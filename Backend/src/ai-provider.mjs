import { URLSearchParams } from 'node:url';
import {
  buildGeminiRequestFromTraiRequest,
  canonicalMessagesFromTraiRequest,
  parseGeminiChunkToTraiEvent,
  parseGeminiCompletionToTraiResponse
} from './trai-ai-contract.mjs';

export function createAIProvider(config, HttpError) {
  switch (normalizeAIProviderName(config.aiProvider)) {
    case 'gemini':
      return createGeminiProvider(config, HttpError);
    case 'openai':
      return createOpenAIProvider(config, HttpError);
    default:
      throw new Error(`Unsupported TRAI_AI_PROVIDER value: ${config.aiProvider}`);
  }
}

export function normalizeAIProviderName(value) {
  return String(value ?? '').trim().toLowerCase() === 'openai' ? 'openai' : 'gemini';
}

function createGeminiProvider(config, HttpError) {
  return {
    name: 'gemini',
    model: config.geminiModel,
    capabilities: {
      streaming: true,
      toolCalling: true,
      structuredOutputs: true,
      imageInputs: true
    },
    isConfigured() {
      return Boolean(config.geminiApiKey);
    },
    async execute(request, { streaming }) {
      if (!config.geminiApiKey) {
        throw new HttpError(503, {
          error: 'gemini_not_configured',
          message: 'GEMINI_API_KEY is required for AI proxy requests.'
        });
      }

      const action = streaming ? 'streamGenerateContent' : 'generateContent';
      const query = new URLSearchParams({ key: config.geminiApiKey });
      if (streaming) {
        query.set('alt', 'sse');
      }

      const upstreamURL = `https://generativelanguage.googleapis.com/v1beta/models/${config.geminiModel}:${action}?${query.toString()}`;
      const upstreamResponse = await fetch(upstreamURL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(buildGeminiRequestFromTraiRequest(request))
      });

      if (!upstreamResponse.ok) {
        const errorText = await upstreamResponse.text();
        throw new HttpError(upstreamResponse.status, {
          error: 'gemini_error',
          message: errorText || 'Gemini proxy request failed.'
        });
      }

      if (streaming) {
        const usageState = createUsageState();
        return {
          type: 'stream',
          stream: parseGeminiStreamingResponse(upstreamResponse, usageState),
          getUsageMetadata() {
            return usageState.value;
          }
        };
      }

      const body = await upstreamResponse.json();
      return {
        type: 'single',
        response: parseGeminiCompletionToTraiResponse(body),
        usageMetadata: extractGeminiUsageMetadata(body)
      };
    }
  };
}

function createOpenAIProvider(config, HttpError) {
  return {
    name: 'openai',
    model: config.openAIModel,
    capabilities: {
      streaming: true,
      toolCalling: true,
      structuredOutputs: true,
      imageInputs: true
    },
    isConfigured() {
      return Boolean(config.openAIApiKey);
    },
    async execute(request, { streaming }) {
      if (!config.openAIApiKey) {
        throw new HttpError(503, {
          error: 'openai_not_configured',
          message: 'OPENAI_API_KEY is required when TRAI_AI_PROVIDER=openai.'
        });
      }

      const upstreamResponse = await fetch('https://api.openai.com/v1/responses', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${config.openAIApiKey}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(buildOpenAIResponsesRequest(config, request, { streaming }))
      });

      if (!upstreamResponse.ok) {
        const errorText = await upstreamResponse.text();
        throw new HttpError(upstreamResponse.status, {
          error: 'openai_error',
          message: errorText || 'OpenAI proxy request failed.'
        });
      }

      if (streaming) {
        const usageState = createUsageState();
        return {
          type: 'stream',
          stream: parseOpenAIStreamingResponse(upstreamResponse, usageState),
          getUsageMetadata() {
            return usageState.value;
          }
        };
      }

      const body = await upstreamResponse.json();
      return {
        type: 'single',
        response: normalizeOpenAIResponseToTrai(body),
        usageMetadata: extractOpenAIUsageMetadata(body)
      };
    }
  };
}

function buildOpenAIResponsesRequest(config, request, { streaming }) {
  const state = createToolState();
  const input = [];
  const reasoningEffort = extractOpenAIReasoningEffort(config.openAIModel, request);
  const imageDetail = extractOpenAIImageDetail(request);

  for (const message of canonicalMessagesFromTraiRequest(request)) {
    appendCanonicalMessageAsOpenAIItems(input, message, state, imageDetail);
  }

  const payload = {
    model: config.openAIModel,
    input,
    stream: streaming,
    store: false,
    parallel_tool_calls: true,
    text: buildOpenAITextSpec(request.output)
  };

  if (request.systemText) {
    payload.instructions = request.systemText;
  }

  if (reasoningEffort) {
    payload.reasoning = {
      effort: reasoningEffort
    };
  }

  if (shouldIncludeOpenAISamplingControls(config.openAIModel, reasoningEffort) && typeof request.generation?.temperature === 'number') {
    payload.temperature = request.generation.temperature;
  }

  if (shouldIncludeOpenAISamplingControls(config.openAIModel, reasoningEffort) && typeof request.generation?.topP === 'number') {
    payload.top_p = request.generation.topP;
  }

  if (Number.isFinite(request.generation?.maxOutputTokens)) {
    payload.max_output_tokens = request.generation.maxOutputTokens;
  }

  const tools = convertTraiToolsToOpenAI(request.tools);
  if (tools.length > 0) {
    payload.tools = tools;
    payload.tool_choice = 'auto';
  }

  return payload;
}

function extractOpenAIReasoningEffort(modelName, request) {
  const thinkingLevel = normalizeGeminiThinkingLevel(
    request?.generation?.reasoning ?? request?.backendGenerationConfig?.thinkingConfig?.thinkingLevel
  );
  if (!thinkingLevel) {
    return null;
  }

  switch (thinkingLevel) {
    case 'minimal':
      return openAILowestReasoningEffortForModel(modelName);
    case 'low':
      return 'low';
    case 'medium':
      return 'medium';
    default:
      return null;
  }
}

function shouldIncludeOpenAISamplingControls(modelName, reasoningEffort) {
  const normalizedModelName = String(modelName ?? '').trim().toLowerCase();
  if (!normalizedModelName.startsWith('gpt-5')) {
    return true;
  }

  if (normalizedModelName.startsWith('gpt-5.4') || normalizedModelName.startsWith('gpt-5.2')) {
    return !reasoningEffort || reasoningEffort === 'none';
  }

  return false;
}

function openAILowestReasoningEffortForModel(modelName) {
  const normalizedModelName = String(modelName ?? '').trim().toLowerCase();
  if (
    normalizedModelName.startsWith('gpt-5.4')
    || normalizedModelName.startsWith('gpt-5.2')
    || normalizedModelName.startsWith('gpt-5.1')
  ) {
    return 'none';
  }

  return 'minimal';
}

function normalizeGeminiThinkingLevel(value) {
  if (typeof value !== 'string') {
    return null;
  }

  const normalizedValue = value.trim().toLowerCase();
  if (normalizedValue === 'minimal' || normalizedValue === 'low' || normalizedValue === 'medium') {
    return normalizedValue;
  }

  return null;
}

function extractOpenAIImageDetail(request) {
  const mediaResolution = String(request?.generation?.imageDetail ?? request?.backendGenerationConfig?.mediaResolution ?? '')
    .trim()
    .toUpperCase();

  switch (mediaResolution) {
    case 'LOW':
    case 'MEDIA_RESOLUTION_LOW':
      return 'low';
    case 'HIGH':
    case 'MEDIA_RESOLUTION_HIGH':
      return 'high';
    case 'AUTO':
      return 'auto';
    default:
      return 'auto';
  }
}

function appendCanonicalMessageAsOpenAIItems(items, message, state, imageDetail) {
  const parts = normalizeArray(message?.parts);

  if (message.role === 'tool') {
    for (const toolResponse of parts
      .filter((part) => part?.type === 'tool_response')
      .map((response) => convertToolResponseToOpenAIItem(response, state))) {
      if (toolResponse) {
        items.push(toolResponse);
      }
    }
    return;
  }

  if (message.role === 'assistant') {
    const textItem = buildOpenAIMessageItem('assistant', parts, imageDetail);
    if (textItem) {
      items.push(textItem);
    }
    for (const toolCall of parts
      .filter((part) => part?.type === 'tool_call')
      .map((entry) => convertToolCallToOpenAIItem(entry, state))) {
      if (toolCall) {
        items.push(toolCall);
      }
    }
    return;
  }

  const userItem = buildOpenAIMessageItem('user', parts, imageDetail);
  if (userItem) {
    items.push(userItem);
  }
}

function buildOpenAIMessageItem(role, parts, imageDetail) {
  const content = [];

  for (const part of normalizeArray(parts)) {
    if (part?.type === 'text' && typeof part?.text === 'string' && part.text.length > 0) {
      content.push({
        type: role === 'assistant' ? 'output_text' : 'input_text',
        text: part.text
      });
      continue;
    }

    if (role === 'user' && part?.type === 'image') {
      const imagePart = convertTraiImageToOpenAIContentPart(part, imageDetail);
      if (imagePart) {
        content.push(imagePart);
      }
    }
  }

  if (content.length === 0) {
    return null;
  }

  return {
    role,
    content: content.length === 1 && content[0].type.endsWith('_text')
      ? content[0].text
      : content
  };
}

function convertTraiImageToOpenAIContentPart(image, imageDetail) {
  const mimeType = typeof image?.mimeType === 'string' ? image.mimeType : null;
  const data = typeof image?.data === 'string' ? image.data : null;
  if (!mimeType || !data) {
    return null;
  }

  return {
    type: 'input_image',
    image_url: `data:${mimeType};base64,${data}`,
    detail: imageDetail ?? 'auto'
  };
}

function convertToolCallToOpenAIItem(toolCall, state) {
  const name = typeof toolCall?.name === 'string' ? toolCall.name : null;
  if (!name) {
    return null;
  }

  const callID = typeof toolCall?.id === 'string' && toolCall.id.length > 0
    ? toolCall.id
    : `call_${state.nextCallID++}_${slugify(name)}`;
  state.pendingToolCallIDsByName.set(name, [...(state.pendingToolCallIDsByName.get(name) ?? []), callID]);

  return {
    type: 'function_call',
    call_id: callID,
    name,
    arguments: JSON.stringify(normalizeObject(toolCall.args))
  };
}

function convertToolResponseToOpenAIItem(functionResponse, state) {
  const name = typeof functionResponse?.name === 'string' ? functionResponse.name : null;
  if (!name) {
    return null;
  }

  const toolCallID = resolveToolCallID(functionResponse, state);

  return {
    type: 'function_call_output',
    call_id: toolCallID,
    output: stringifyToolOutput(functionResponse.response)
  };
}

function resolveToolCallID(functionResponse, state) {
  if (typeof functionResponse?.toolCallID === 'string' && functionResponse.toolCallID.length > 0) {
    return functionResponse.toolCallID;
  }

  const queuedCallIDs = state.pendingToolCallIDsByName.get(functionResponse.name) ?? [];
  const resolved = queuedCallIDs.shift() ?? `call_${state.nextCallID++}_${slugify(functionResponse.name)}_response`;
  if (queuedCallIDs.length > 0) {
    state.pendingToolCallIDsByName.set(functionResponse.name, queuedCallIDs);
  } else {
    state.pendingToolCallIDsByName.delete(functionResponse.name);
  }
  return resolved;
}

function convertTraiToolsToOpenAI(tools) {
  return normalizeArray(tools).map((tool) => ({
    type: 'function',
    name: tool.name,
    description: tool.description,
    parameters: normalizeOpenAISchema(tool.parameters, { strict: true }),
    strict: true
  })).filter((tool) => typeof tool.name === 'string' && tool.name.length > 0);
}

function buildOpenAITextSpec(output) {
  if (output.kind === 'text') {
    return {
      format: {
        type: 'text'
      }
    };
  }

  if (output.kind === 'json_schema' && output.schema) {
    return {
      format: {
        type: 'json_schema',
        name: 'structured_response',
        strict: true,
        schema: normalizeOpenAISchema(output.schema, { strict: true })
      }
    };
  }

  return {
    format: {
      type: 'json_object'
    }
  };
}

function normalizeOpenAIResponseToTrai(openAIResponse) {
  const parts = [];

  for (const item of normalizeArray(openAIResponse?.output)) {
    const text = extractAssistantText(item);
    if (text) {
      parts.push({ type: 'text', text });
    }

    const toolCall = normalizeOpenAIFunctionCallItem(item);
    if (toolCall) {
      parts.push(toolCall);
    }
  }

  return {
    parts,
    finishReason: mapOpenAIResponseFinishReason(openAIResponse)
  };
}

async function* parseGeminiStreamingResponse(upstreamResponse, usageState) {
  const decoder = new TextDecoder();
  let buffer = '';

  for await (const chunk of upstreamResponse.body) {
    buffer += decoder.decode(chunk, { stream: true });
    const result = takeSSEEvents(buffer);
    buffer = result.remainder;
    for (const eventPayload of result.events) {
      if (eventPayload === '[DONE]') {
        continue;
      }

      let payload;
      try {
        payload = JSON.parse(eventPayload);
      } catch {
        continue;
      }

      maybeStoreUsageMetadata(usageState, extractGeminiUsageMetadata(payload));

      yield parseGeminiChunkToTraiEvent(payload);
    }
  }

  if (buffer.trim().length > 0) {
    const result = takeSSEEvents(`${buffer}\n\n`);
    for (const eventPayload of result.events) {
      if (eventPayload === '[DONE]') {
        continue;
      }

      let payload;
      try {
        payload = JSON.parse(eventPayload);
      } catch {
        continue;
      }

      maybeStoreUsageMetadata(usageState, extractGeminiUsageMetadata(payload));

      yield parseGeminiChunkToTraiEvent(payload);
    }
  }
}

async function* parseOpenAIStreamingResponse(upstreamResponse, usageState) {
  const decoder = new TextDecoder();
  let buffer = '';
  const state = {
    functionCallsByItemID: new Map(),
    emittedCallIDs: new Set(),
    emittedTerminalEvent: false
  };

  for await (const chunk of upstreamResponse.body) {
    buffer += decoder.decode(chunk, { stream: true });
    const result = takeSSEEvents(buffer);
    buffer = result.remainder;
    for (const payloadText of result.events) {
      if (payloadText === '[DONE]') {
        continue;
      }

      let payload;
      try {
        payload = JSON.parse(payloadText);
      } catch {
        continue;
      }

      const event = parseOpenAIStreamingEvent(payload, state, usageState);
      if (event) {
        yield event;
      }
    }
  }

  if (buffer.trim().length > 0) {
    const result = takeSSEEvents(`${buffer}\n\n`);
    for (const payloadText of result.events) {
      if (payloadText === '[DONE]') {
        continue;
      }

      let payload;
      try {
        payload = JSON.parse(payloadText);
      } catch {
        continue;
      }

      const event = parseOpenAIStreamingEvent(payload, state, usageState);
      if (event) {
        yield event;
      }
    }
  }
}

function parseOpenAIStreamingEvent(payload, state, usageState) {
  switch (payload?.type) {
    case 'response.output_text.delta':
      if (typeof payload.delta === 'string' && payload.delta.length > 0) {
        return {
          parts: [{ type: 'text', text: payload.delta }],
          finishReason: null
        };
      }
      return null;
    case 'response.output_item.added':
      trackOpenAIFunctionCallItem(payload.item, state);
      return null;
    case 'response.function_call_arguments.delta':
      appendOpenAIFunctionCallDelta(payload, state);
      return null;
    case 'response.function_call_arguments.done':
      return buildOpenAIFunctionCallEvent(payload.item, state);
    case 'response.output_item.done':
      if (payload?.item?.type === 'function_call') {
        return buildOpenAIFunctionCallEvent(payload.item, state);
      }
      return null;
    case 'response.completed':
    case 'response.done':
      maybeStoreUsageMetadata(usageState, extractOpenAIUsageMetadata(payload.response));
      return buildOpenAICompletionEvent(payload.response, state);
    case 'response.incomplete': {
      maybeStoreUsageMetadata(usageState, extractOpenAIUsageMetadata(payload.response));
      const finishReason = mapOpenAIIncompleteReason(payload?.response?.incomplete_details?.reason);
      if (!finishReason || finishReason === 'STOP') {
        return null;
      }
      return {
        parts: [],
        finishReason
      };
    }
    default:
      return null;
  }
}

function trackOpenAIFunctionCallItem(item, state) {
  if (item?.type !== 'function_call' || typeof item?.id !== 'string' || item.id.length === 0) {
    return;
  }

  state.functionCallsByItemID.set(item.id, {
    type: 'function_call',
    id: item.id,
    call_id: typeof item.call_id === 'string' && item.call_id.length > 0 ? item.call_id : item.id,
    name: typeof item.name === 'string' ? item.name : '',
    argumentsBuffer: typeof item.arguments === 'string' ? item.arguments : ''
  });
}

function appendOpenAIFunctionCallDelta(payload, state) {
  const itemID = typeof payload?.item_id === 'string' ? payload.item_id : null;
  if (!itemID) {
    return;
  }

  const existing = state.functionCallsByItemID.get(itemID) ?? {
    type: 'function_call',
    id: itemID,
    call_id: itemID,
    name: '',
    argumentsBuffer: ''
  };
  if (typeof payload?.delta === 'string') {
    existing.argumentsBuffer += payload.delta;
  }
  state.functionCallsByItemID.set(itemID, existing);
}

function buildOpenAIFunctionCallEvent(item, state) {
  const bufferedItem = state.functionCallsByItemID.get(item?.id);
  const directToolCall = normalizeOpenAIFunctionCallItem(item);
  const bufferedToolCall = normalizeOpenAIFunctionCallItem(bufferedItem);
  const toolCall =
    (directToolCall && Object.keys(directToolCall.args ?? {}).length > 0)
      ? directToolCall
      : bufferedToolCall ?? directToolCall;
  if (!toolCall || !toolCall.id || state.emittedCallIDs.has(toolCall.id)) {
    return null;
  }

  state.emittedCallIDs.add(toolCall.id);
  if (typeof item?.id === 'string' && item.id.length > 0) {
    state.functionCallsByItemID.delete(item.id);
  }

  return {
    parts: [toolCall],
    finishReason: null
  };
}

function buildOpenAICompletionEvent(response, state) {
  if (state.emittedTerminalEvent) {
    return null;
  }

  state.emittedTerminalEvent = true;
  return {
    parts: [],
    finishReason: mapOpenAIResponseFinishReason(response)
  };
}

function extractAssistantText(item) {
  if (typeof item?.content === 'string' && item.content.length > 0) {
    return item.content;
  }

  if (item?.type !== 'message') {
    return '';
  }

  return normalizeArray(item.content)
    .map((part) => {
      if (typeof part?.text === 'string' && part.text.length > 0) {
        return part.text;
      }
      if (typeof part?.refusal === 'string' && part.refusal.length > 0) {
        return part.refusal;
      }
      return null;
    })
    .filter(Boolean)
    .join('\n');
}

function normalizeOpenAIFunctionCallItem(item) {
  if (item?.type !== 'function_call') {
    return null;
  }

  const name = typeof item?.name === 'string' ? item.name : null;
  if (!name) {
    return null;
  }

  return {
    type: 'tool_call',
    id: typeof item?.call_id === 'string' && item.call_id.length > 0
      ? item.call_id
      : (typeof item?.id === 'string' ? item.id : null),
    name,
    args: parseJSONObject(
      typeof item?.arguments === 'string' && item.arguments.length > 0
        ? item.arguments
        : item?.argumentsBuffer
    )
  };
}

function normalizeSchema(schema) {
  if (Array.isArray(schema)) {
    return schema.map((item) => normalizeSchema(item));
  }

  if (!schema || typeof schema !== 'object') {
    return schema;
  }

  const result = {};
  for (const [key, value] of Object.entries(schema)) {
    result[key] = normalizeSchema(value);
  }
  return result;
}

function normalizeOpenAISchema(schema, options = {}) {
  if (Array.isArray(schema)) {
    return schema.map((item) => normalizeOpenAISchema(item, options));
  }

  if (!schema || typeof schema !== 'object') {
    return schema;
  }

  const result = {};
  for (const [key, value] of Object.entries(schema)) {
    if (key === 'nullable') {
      continue;
    }
    result[key] = normalizeOpenAISchema(value, options);
  }

  if (schema.nullable === true) {
    makeOpenAISchemaNullable(result);
  }

  if (options.strict === true) {
    enforceOpenAIStrictObjectSchema(result, schema, options);
  }

  return result;
}

function enforceOpenAIStrictObjectSchema(result, originalSchema, options) {
  const properties = result?.properties;
  if (!properties || typeof properties !== 'object' || Array.isArray(properties)) {
    return;
  }

  const propertyNames = Object.keys(properties);
  const originallyRequired = new Set(
    Array.isArray(originalSchema?.required)
      ? originalSchema.required.filter((value) => typeof value === 'string')
      : []
  );

  for (const propertyName of propertyNames) {
    if (!originallyRequired.has(propertyName)) {
      makeOpenAISchemaNullable(properties[propertyName]);
    }
  }

  result.required = propertyNames;
  result.additionalProperties = false;
}

function makeOpenAISchemaNullable(schema) {
  if (!schema || typeof schema !== 'object' || Array.isArray(schema)) {
    return schema;
  }

  if (typeof schema.type === 'string' && schema.type !== 'null') {
    schema.type = [schema.type, 'null'];
  } else if (Array.isArray(schema.type) && !schema.type.includes('null')) {
    schema.type = [...schema.type, 'null'];
  } else if (Array.isArray(schema.anyOf) && !schema.anyOf.some((entry) => entry?.type === 'null')) {
    schema.anyOf = [...schema.anyOf, { type: 'null' }];
  }

  if (Array.isArray(schema.enum) && !schema.enum.includes(null)) {
    schema.enum = [...schema.enum, null];
  }

  return schema;
}

function takeSSEEvents(buffer) {
  const events = [];
  let remaining = buffer;
  let separatorIndex = remaining.indexOf('\n\n');

  while (separatorIndex >= 0) {
    const rawEvent = remaining.slice(0, separatorIndex);
    remaining = remaining.slice(separatorIndex + 2);
    const payload = rawEvent
      .split('\n')
      .filter((line) => line.startsWith('data: '))
      .map((line) => line.slice(6).trim())
      .filter(Boolean)
      .join('\n');
    if (payload) {
      events.push(payload);
    }
    separatorIndex = remaining.indexOf('\n\n');
  }

  return { events, remainder: remaining };
}

function parseJSONObject(value) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    return {};
  }

  try {
    const parsed = JSON.parse(value);
    return normalizeObject(parsed);
  } catch {
    return {};
  }
}

function mapOpenAIResponseFinishReason(response) {
  if (normalizeArray(response?.output).some((item) => item?.type === 'function_call')) {
    return 'STOP';
  }

  if (response?.status === 'incomplete') {
    return mapOpenAIIncompleteReason(response?.incomplete_details?.reason);
  }

  return mapOpenAIIncompleteReason(response?.incomplete_details?.reason);
}

function mapOpenAIIncompleteReason(reason) {
  switch (reason) {
    case 'max_output_tokens':
    case 'length':
      return 'MAX_TOKENS';
    case 'content_filter':
    case 'safety':
      return 'SAFETY';
    default:
      return 'STOP';
  }
}

function stringifyToolOutput(output) {
  if (typeof output === 'string') {
    return output;
  }

  return JSON.stringify(normalizeObject(output));
}

function createToolState() {
  return {
    nextCallID: 1,
    pendingToolCallIDsByName: new Map()
  };
}

function createUsageState() {
  return {
    value: null
  };
}

function maybeStoreUsageMetadata(state, usageMetadata) {
  if (!state || !usageMetadata) {
    return;
  }

  state.value = usageMetadata;
}

function extractGeminiUsageMetadata(payload) {
  const usageMetadata = normalizeObject(payload?.usageMetadata);
  const inputTokens = firstFiniteNumber(
    usageMetadata.promptTokenCount,
    usageMetadata.prompt_token_count
  );
  const outputTokens = firstFiniteNumber(
    usageMetadata.candidatesTokenCount,
    usageMetadata.candidates_token_count
  );
  const totalTokens = firstFiniteNumber(
    usageMetadata.totalTokenCount,
    usageMetadata.total_token_count
  );
  const cachedInputTokens = firstFiniteNumber(
    usageMetadata.cachedContentTokenCount,
    usageMetadata.cached_content_token_count
  );
  const reasoningTokens = firstFiniteNumber(
    usageMetadata.thoughtsTokenCount,
    usageMetadata.thoughts_token_count
  );

  if (
    inputTokens == null
    && outputTokens == null
    && totalTokens == null
    && cachedInputTokens == null
    && reasoningTokens == null
  ) {
    return null;
  }

  return {
    provider: 'gemini',
    inputTokens,
    outputTokens,
    totalTokens,
    cachedInputTokens,
    reasoningTokens,
    raw: usageMetadata
  };
}

function extractOpenAIUsageMetadata(payload) {
  const usage = normalizeObject(payload?.usage);
  const inputDetails = normalizeObject(usage.input_tokens_details);
  const outputDetails = normalizeObject(usage.output_tokens_details);
  const inputTokens = firstFiniteNumber(usage.input_tokens, usage.inputTokens);
  const outputTokens = firstFiniteNumber(usage.output_tokens, usage.outputTokens);
  const totalTokens = firstFiniteNumber(usage.total_tokens, usage.totalTokens);
  const cachedInputTokens = firstFiniteNumber(
    inputDetails.cached_tokens,
    inputDetails.cachedTokens
  );
  const reasoningTokens = firstFiniteNumber(
    outputDetails.reasoning_tokens,
    outputDetails.reasoningTokens
  );

  if (
    inputTokens == null
    && outputTokens == null
    && totalTokens == null
    && cachedInputTokens == null
    && reasoningTokens == null
  ) {
    return null;
  }

  return {
    provider: 'openai',
    inputTokens,
    outputTokens,
    totalTokens,
    cachedInputTokens,
    reasoningTokens,
    raw: usage
  };
}

function firstFiniteNumber(...values) {
  for (const value of values) {
    if (Number.isFinite(value)) {
      return Math.max(0, Math.round(value));
    }
  }
  return null;
}

function normalizeArray(value) {
  return Array.isArray(value) ? value : [];
}

function normalizeObject(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function slugify(value) {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}
