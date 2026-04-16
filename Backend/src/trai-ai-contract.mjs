export function normalizeIncomingTraiRequest(requestBody) {
  if (looksLikeCanonicalTraiRequest(requestBody)) {
    return normalizeCanonicalTraiRequest(requestBody);
  }

  const generationConfig = normalizeObject(requestBody?.generationConfig);
  const normalizedGeneration = normalizeLegacyGeneration(generationConfig);
  const canonicalMessages = normalizeArray(requestBody?.contents).flatMap(convertGeminiContentToCanonicalMessages);

  return {
    requestFormat: 'legacy_gemini_compat',
    systemText: extractTextFromParts(normalizeObject(requestBody?.systemInstruction).parts),
    canonicalMessages,
    tools: convertGeminiToolsToTraiTools(requestBody?.tools),
    output: buildTraiOutputSpec(generationConfig),
    generation: normalizedGeneration,
    backendGenerationConfig: normalizeSchema(generationConfig)
  };
}

export function buildGeminiRequestFromTraiRequest(request) {
  const geminiRequest = {
    contents: canonicalMessagesFromTraiRequest(request).flatMap(convertCanonicalMessageToGeminiContents)
  };

  if (request.systemText) {
    geminiRequest.systemInstruction = {
      parts: [{ text: request.systemText }]
    };
  }

  if (request.tools.length > 0) {
    geminiRequest.tools = [
      {
        function_declarations: request.tools.map((tool) => ({
          name: tool.name,
          description: tool.description,
          parameters: normalizeSchema(tool.parameters)
        }))
      }
    ];
  }

  const generationConfig = normalizeObject(normalizeSchema(request.backendGenerationConfig));
  const reasoningLevel = normalizeReasoningLevel(request?.generation?.reasoning);
  if (reasoningLevel) {
    generationConfig.thinkingConfig = {
      ...normalizeObject(generationConfig.thinkingConfig),
      thinkingLevel: reasoningLevel.toUpperCase()
    };
  }
  const mediaResolution = normalizeImageDetail(request?.generation?.imageDetail);
  if (mediaResolution === 'low') {
    generationConfig.mediaResolution = 'MEDIA_RESOLUTION_LOW';
  } else if (mediaResolution === 'high') {
    generationConfig.mediaResolution = 'MEDIA_RESOLUTION_HIGH';
  }
  if (typeof request.generation.temperature === 'number') {
    generationConfig.temperature = request.generation.temperature;
  }
  if (typeof request.generation.topP === 'number') {
    generationConfig.topP = request.generation.topP;
  }
  if (Number.isFinite(request.generation.maxOutputTokens)) {
    generationConfig.maxOutputTokens = request.generation.maxOutputTokens;
  }

  if (request.output.kind === 'json_object') {
    generationConfig.responseMimeType = 'application/json';
  } else if (request.output.kind === 'json_schema' && request.output.schema) {
    generationConfig.responseMimeType = 'application/json';
    generationConfig.responseSchema = normalizeSchema(request.output.schema);
  }

  if (Object.keys(generationConfig).length > 0) {
    geminiRequest.generationConfig = generationConfig;
  }

  return geminiRequest;
}

export function canonicalMessagesFromTraiRequest(request) {
  const canonicalMessages = normalizeArray(request?.canonicalMessages).flatMap((message) => {
    const normalized = normalizeCanonicalMessage(message);
    return normalized ? [normalized] : [];
  });
  if (canonicalMessages.length > 0) {
    return canonicalMessages;
  }

  return normalizeArray(request?.messages).flatMap(convertNormalizedTraiMessageToCanonicalMessages);
}

export function compatibilityMessagesFromTraiRequest(request) {
  const normalizedMessages = normalizeArray(request?.messages).flatMap(normalizeNormalizedTraiMessage);
  if (normalizedMessages.length > 0) {
    return normalizedMessages;
  }

  return canonicalMessagesFromTraiRequest(request).flatMap(convertCanonicalTraiMessageToNormalizedMessages);
}

export const normalizeIncomingAIProxyRequest = normalizeIncomingTraiRequest;
export const buildGeminiRequestFromAIProxyRequest = buildGeminiRequestFromTraiRequest;
export const canonicalMessagesFromAIProxyRequest = canonicalMessagesFromTraiRequest;
export const normalizedMessagesFromAIProxyRequest = compatibilityMessagesFromTraiRequest;

function looksLikeCanonicalTraiRequest(requestBody) {
  const body = normalizeObject(requestBody);
  return Array.isArray(body.messages)
    || Object.prototype.hasOwnProperty.call(body, 'system')
    || Object.prototype.hasOwnProperty.call(body, 'generation')
    || Object.prototype.hasOwnProperty.call(body, 'output');
}

function normalizeCanonicalTraiRequest(requestBody) {
  const canonicalMessages = normalizeArray(requestBody?.messages).flatMap((message) => {
    const normalized = normalizeCanonicalMessage(message);
    return normalized ? [normalized] : [];
  });
  const generation = normalizeCanonicalGeneration(normalizeObject(requestBody?.generation));
  return {
    requestFormat: 'trai_v1',
    systemText: typeof requestBody?.system === 'string' ? requestBody.system : '',
    canonicalMessages,
    tools: normalizeCanonicalTools(requestBody?.tools),
    output: normalizeCanonicalOutput(normalizeObject(requestBody?.output)),
    generation,
    backendGenerationConfig: {}
  };
}

export function parseGeminiCompletionToTraiResponse(payload) {
  const choice = normalizeArray(payload?.candidates)[0] ?? {};
  const content = normalizeObject(choice.content);
  return {
    parts: parseGeminiPartsToTraiParts(content.parts),
    finishReason: mapGeminiFinishReason(choice.finishReason)
  };
}

export function parseGeminiChunkToTraiEvent(payload) {
  const choice = normalizeArray(payload?.candidates)[0] ?? {};
  const content = normalizeObject(choice.content);
  return {
    parts: parseGeminiPartsToTraiParts(content.parts),
    finishReason: mapGeminiStreamingFinishReason(choice.finishReason)
  };
}

export function traiResponseToGeminiJSON(response) {
  return {
    candidates: [
      {
        content: {
          role: 'model',
          parts: traiPartsToGeminiParts(response.parts)
        },
        ...(response.finishReason ? { finishReason: mapTraiFinishReasonToGemini(response.finishReason) } : {})
      }
    ]
  };
}

export function traiEventToGeminiSSEChunk(event) {
  return `data: ${JSON.stringify(traiResponseToGeminiJSON(event))}\n\n`;
}

function convertGeminiContentToCanonicalMessages(content) {
  const role = content?.role === 'model' ? 'assistant' : 'user';
  const canonicalParts = normalizeArray(content?.parts).flatMap(convertGeminiPartToCanonicalParts);
  const nonToolResponseParts = canonicalParts.filter((part) => part?.type !== 'tool_response');
  const toolResponseParts = canonicalParts.filter((part) => part?.type === 'tool_response');
  const messages = [];

  if (nonToolResponseParts.length > 0) {
    messages.push({
      role,
      parts: nonToolResponseParts
    });
  }

  if (toolResponseParts.length > 0) {
    messages.push({
      role: 'tool',
      parts: toolResponseParts
    });
  }

  return messages;
}

function convertGeminiToolsToTraiTools(geminiTools) {
  return normalizeArray(geminiTools).flatMap((toolGroup) =>
    normalizeArray(toolGroup?.function_declarations).map((tool) => ({
      name: tool.name,
      description: tool.description ?? '',
      parameters: normalizeSchema(tool.parameters ?? {})
    }))
  ).filter((tool) => typeof tool.name === 'string' && tool.name.length > 0);
}

function buildTraiOutputSpec(generationConfig) {
  if (generationConfig.responseMimeType !== 'application/json') {
    return { kind: 'text', schema: null };
  }

  if (generationConfig.responseSchema && typeof generationConfig.responseSchema === 'object') {
    return {
      kind: 'json_schema',
      schema: normalizeSchema(generationConfig.responseSchema)
    };
  }

  return { kind: 'json_object', schema: null };
}

function normalizeCanonicalOutput(output) {
  const kind = output.kind;
  if (kind === 'json_schema' && output.schema && typeof output.schema === 'object') {
    return {
      kind: 'json_schema',
      schema: normalizeSchema(output.schema)
    };
  }

  if (kind === 'json_object') {
    return { kind: 'json_object', schema: null };
  }

  return { kind: 'text', schema: null };
}

function normalizeLegacyGeneration(generationConfig) {
  return {
    temperature: typeof generationConfig.temperature === 'number' ? generationConfig.temperature : null,
    topP: typeof generationConfig.topP === 'number' ? generationConfig.topP : null,
    maxOutputTokens: Number.isFinite(generationConfig.maxOutputTokens) ? generationConfig.maxOutputTokens : null,
    reasoning: normalizeReasoningLevel(generationConfig?.thinkingConfig?.thinkingLevel),
    imageDetail: normalizeImageDetail(generationConfig?.mediaResolution)
  };
}

function normalizeCanonicalGeneration(generation) {
  return {
    temperature: typeof generation.temperature === 'number' ? generation.temperature : null,
    topP: typeof generation.topP === 'number' ? generation.topP : null,
    maxOutputTokens: Number.isFinite(generation.maxOutputTokens) ? generation.maxOutputTokens : null,
    reasoning: normalizeReasoningLevel(generation.reasoning),
    imageDetail: normalizeImageDetail(generation.imageDetail)
  };
}

function normalizeReasoningLevel(value) {
  if (typeof value !== 'string') {
    return null;
  }

  const normalized = value.trim().toLowerCase();
  if (normalized === 'minimal' || normalized === 'low' || normalized === 'medium') {
    return normalized;
  }

  return null;
}

function normalizeImageDetail(value) {
  if (typeof value !== 'string') {
    return null;
  }

  const normalized = value.trim().toLowerCase();
  switch (normalized) {
    case 'low':
    case 'media_resolution_low':
      return 'low';
    case 'high':
    case 'media_resolution_high':
      return 'high';
    case 'auto':
      return 'auto';
    default:
      return null;
  }
}

function normalizeCanonicalTools(tools) {
  return normalizeArray(tools).map((tool) => ({
    name: tool.name,
    description: tool.description ?? '',
    parameters: normalizeSchema(tool.parameters ?? {})
  })).filter((tool) => typeof tool.name === 'string' && tool.name.length > 0);
}

function normalizeCanonicalMessage(message) {
  const parts = normalizeArray(message?.parts).flatMap(normalizeCanonicalPart);
  if (parts.length === 0) {
    return null;
  }

  return {
    role: normalizeCanonicalRole(message?.role),
    parts
  };
}

function normalizeNormalizedTraiMessage(message) {
  const role = normalizeCanonicalRole(message?.role);
  const text = typeof message?.text === 'string' ? message.text : '';
  const images = normalizeArray(message?.images)
    .filter((image) => typeof image?.mimeType === 'string' && typeof image?.data === 'string')
    .map((image) => ({ mimeType: image.mimeType, data: image.data }));
  const toolCalls = normalizeArray(message?.toolCalls)
    .filter((toolCall) => typeof toolCall?.name === 'string' && toolCall.name.length > 0)
    .map((toolCall) => ({
      id: typeof toolCall.id === 'string' ? toolCall.id : null,
      name: toolCall.name,
      args: normalizeObject(toolCall.args)
    }));
  const toolResponses = normalizeArray(message?.toolResponses)
    .filter((toolResponse) => typeof toolResponse?.name === 'string' && toolResponse.name.length > 0)
    .map((toolResponse) => ({
      toolCallID: typeof toolResponse.toolCallID === 'string' ? toolResponse.toolCallID : null,
      name: toolResponse.name,
      response: normalizeObject(toolResponse.response)
    }));

  if (role === 'tool') {
    return toolResponses.length > 0
      ? [{
        role: 'tool',
        text: '',
        images: [],
        toolCalls: [],
        toolResponses
      }]
      : [];
  }

  const messages = [];
  if (text.length > 0 || images.length > 0 || toolCalls.length > 0) {
    messages.push({
      role,
      text,
      images,
      toolCalls,
      toolResponses: []
    });
  }
  if (toolResponses.length > 0) {
    messages.push({
      role: 'tool',
      text: '',
      images: [],
      toolCalls: [],
      toolResponses
    });
  }
  return messages;
}

function normalizeCanonicalPart(part) {
  switch (part?.type) {
    case 'text':
      return typeof part.text === 'string' && part.text.length > 0
        ? [{ type: 'text', text: part.text }]
        : [];
    case 'image':
      return (typeof part.mimeType === 'string' && typeof part.data === 'string')
        ? [{ type: 'image', mimeType: part.mimeType, data: part.data }]
        : [];
    case 'tool_call':
      return typeof part.name === 'string' && part.name.length > 0
        ? [{
          type: 'tool_call',
          ...(typeof part.id === 'string' && part.id.length > 0 ? { id: part.id } : {}),
          name: part.name,
          args: normalizeObject(part.args)
        }]
        : [];
    case 'tool_response':
      return typeof part.name === 'string' && part.name.length > 0
        ? [{
          type: 'tool_response',
          ...(typeof part.toolCallID === 'string' && part.toolCallID.length > 0 ? { toolCallID: part.toolCallID } : {}),
          name: part.name,
          response: normalizeObject(part.response)
        }]
        : [];
    default:
      return [];
  }
}

function convertCanonicalTraiMessageToNormalizedMessages(message) {
  const role = normalizeCanonicalRole(message?.role);
  const parts = normalizeArray(message?.parts);
  const text = [];
  const images = [];
  const toolCalls = [];
  const toolResponses = [];

  for (const part of parts) {
    switch (part?.type) {
      case 'text':
        if (typeof part.text === 'string' && part.text.length > 0) {
          text.push(part.text);
        }
        break;
      case 'image':
        if (typeof part.mimeType === 'string' && typeof part.data === 'string') {
          images.push({ mimeType: part.mimeType, data: part.data });
        }
        break;
      case 'tool_call':
        if (typeof part.name === 'string' && part.name.length > 0) {
          toolCalls.push({
            id: typeof part.id === 'string' ? part.id : null,
            name: part.name,
            args: normalizeObject(part.args)
          });
        }
        break;
      case 'tool_response':
        if (typeof part.name === 'string' && part.name.length > 0) {
          toolResponses.push({
            toolCallID: typeof part.toolCallID === 'string' ? part.toolCallID : null,
            name: part.name,
            response: normalizeObject(part.response)
          });
        }
        break;
      default:
        break;
    }
  }

  if (role === 'tool') {
    return toolResponses.length > 0 ? [{
      role: 'tool',
      text: '',
      images: [],
      toolCalls: [],
      toolResponses
    }] : [];
  }

  const messages = [];
  if (text.length > 0 || images.length > 0 || toolCalls.length > 0) {
    messages.push({
      role,
      text: text.join('\n'),
      images,
      toolCalls,
      toolResponses: []
    });
  }

  if (toolResponses.length > 0) {
    messages.push({
      role: 'tool',
      text: '',
      images: [],
      toolCalls: [],
      toolResponses
    });
  }

  return messages;
}

function normalizeCanonicalRole(role) {
  switch (String(role ?? '').trim().toLowerCase()) {
    case 'assistant':
      return 'assistant';
    case 'tool':
      return 'tool';
    default:
      return 'user';
  }
}

function convertCanonicalMessageToGeminiContents(message) {
  if (message.role === 'tool') {
    const toolResponseParts = normalizeArray(message.parts)
      .filter((part) => part?.type === 'tool_response')
      .map((part) => ({
        functionResponse: {
          ...(part.toolCallID ? { toolCallID: part.toolCallID } : {}),
          name: part.name,
          response: normalizeObject(part.response)
        }
      }));

    return toolResponseParts.length > 0
      ? [{
        role: 'user',
        parts: toolResponseParts
      }]
      : [];
  }

  const parts = normalizeArray(message.parts).flatMap((part) => {
    switch (part?.type) {
      case 'text':
        return typeof part.text === 'string' && part.text.length > 0
          ? [{ text: part.text }]
          : [];
      case 'image':
        return (typeof part.mimeType === 'string' && typeof part.data === 'string')
          ? [{
            inlineData: {
              mimeType: part.mimeType,
              data: part.data
            }
          }]
          : [];
      case 'tool_call':
        return typeof part.name === 'string' && part.name.length > 0
          ? [{
            functionCall: {
              ...(part.id ? { id: part.id } : {}),
              name: part.name,
              args: normalizeObject(part.args)
            }
          }]
          : [];
      default:
        return [];
    }
  });

  return parts.length > 0
    ? [{
      role: message.role === 'assistant' ? 'model' : 'user',
      parts
    }]
    : [];
}

function parseGeminiPartsToTraiParts(parts) {
  return normalizeArray(parts).flatMap((part) => {
    if (typeof part?.text === 'string' && part.text.length > 0) {
      return [{ type: 'text', text: part.text }];
    }

    if (part?.functionCall && typeof part.functionCall?.name === 'string') {
      return [{
        type: 'tool_call',
        id: typeof part.functionCall?.id === 'string' ? part.functionCall.id : null,
        name: part.functionCall.name,
        args: normalizeObject(part.functionCall.args)
      }];
    }

    if (part?.functionResponse && typeof part.functionResponse?.name === 'string') {
      return [{
        type: 'tool_response',
        toolCallID: typeof part.functionResponse?.toolCallID === 'string'
          ? part.functionResponse.toolCallID
          : (typeof part.functionResponse?.tool_call_id === 'string' ? part.functionResponse.tool_call_id : null),
        name: part.functionResponse.name,
        response: normalizeObject(part.functionResponse.response)
      }];
    }

    return [];
  });
}

function traiPartsToGeminiParts(parts) {
  return normalizeArray(parts).flatMap((part) => {
    if (part?.type === 'text' && typeof part?.text === 'string' && part.text.length > 0) {
      return [{ text: part.text }];
    }

    if (part?.type === 'tool_call' && typeof part?.name === 'string' && part.name.length > 0) {
      return [{
        functionCall: {
          ...(part.id ? { id: part.id } : {}),
          name: part.name,
          args: normalizeObject(part.args)
        }
      }];
    }

    if (part?.type === 'tool_response' && typeof part?.name === 'string' && part.name.length > 0) {
      return [{
        functionResponse: {
          ...(part.toolCallID ? { toolCallID: part.toolCallID } : {}),
          name: part.name,
          response: normalizeObject(part.response)
        }
      }];
    }

    return [];
  });
}

function convertGeminiInlineDataToTraiImage(inlineData) {
  const mimeType =
    typeof inlineData?.mimeType === 'string'
      ? inlineData.mimeType
      : (typeof inlineData?.mime_type === 'string' ? inlineData.mime_type : null);
  const data = typeof inlineData?.data === 'string' ? inlineData.data : null;
  if (!mimeType || !data) {
    return null;
  }

  return { mimeType, data };
}

function convertGeminiPartToCanonicalParts(part) {
  if (typeof part?.text === 'string' && part.text.length > 0) {
    return [{ type: 'text', text: part.text }];
  }

  const inlineData = part?.inlineData ?? part?.inline_data;
  if (inlineData) {
    const image = convertGeminiInlineDataToTraiImage(inlineData);
    return image ? [{ type: 'image', mimeType: image.mimeType, data: image.data }] : [];
  }

  if (part?.functionCall) {
    const toolCall = convertGeminiFunctionCallToTrai(part.functionCall);
    return toolCall ? [{
      type: 'tool_call',
      ...(toolCall.id ? { id: toolCall.id } : {}),
      name: toolCall.name,
      args: normalizeObject(toolCall.args)
    }] : [];
  }

  if (part?.functionResponse) {
    const toolResponse = convertGeminiFunctionResponseToTrai(part.functionResponse);
    return toolResponse ? [{
      type: 'tool_response',
      ...(toolResponse.toolCallID ? { toolCallID: toolResponse.toolCallID } : {}),
      name: toolResponse.name,
      response: normalizeObject(toolResponse.response)
    }] : [];
  }

  return [];
}

function convertNormalizedTraiMessageToCanonicalMessages(message) {
  const parts = [];
  if (typeof message?.text === 'string' && message.text.length > 0) {
    parts.push({ type: 'text', text: message.text });
  }
  for (const image of normalizeArray(message?.images)) {
    if (typeof image?.mimeType === 'string' && typeof image?.data === 'string') {
      parts.push({ type: 'image', mimeType: image.mimeType, data: image.data });
    }
  }
  for (const toolCall of normalizeArray(message?.toolCalls)) {
    if (typeof toolCall?.name === 'string' && toolCall.name.length > 0) {
      parts.push({
        type: 'tool_call',
        ...(typeof toolCall.id === 'string' && toolCall.id.length > 0 ? { id: toolCall.id } : {}),
        name: toolCall.name,
        args: normalizeObject(toolCall.args)
      });
    }
  }
  for (const toolResponse of normalizeArray(message?.toolResponses)) {
    if (typeof toolResponse?.name === 'string' && toolResponse.name.length > 0) {
      parts.push({
        type: 'tool_response',
        ...(typeof toolResponse.toolCallID === 'string' && toolResponse.toolCallID.length > 0 ? { toolCallID: toolResponse.toolCallID } : {}),
        name: toolResponse.name,
        response: normalizeObject(toolResponse.response)
      });
    }
  }

  return parts.length > 0
    ? [{
      role: normalizeCanonicalRole(message?.role),
      parts
    }]
    : [];
}

function convertGeminiFunctionCallToTrai(functionCall) {
  const name = typeof functionCall?.name === 'string' ? functionCall.name : null;
  if (!name) {
    return null;
  }

  return {
    id: typeof functionCall?.id === 'string' ? functionCall.id : null,
    name,
    args: normalizeObject(functionCall.args)
  };
}

function convertGeminiFunctionResponseToTrai(functionResponse) {
  const name = typeof functionResponse?.name === 'string' ? functionResponse.name : null;
  if (!name) {
    return null;
  }

  return {
    toolCallID: typeof functionResponse?.toolCallID === 'string'
      ? functionResponse.toolCallID
      : (typeof functionResponse?.tool_call_id === 'string' ? functionResponse.tool_call_id : null),
    name,
    response: normalizeObject(functionResponse.response)
  };
}

function extractTextFromParts(parts) {
  return normalizeArray(parts)
    .map((part) => (typeof part?.text === 'string' ? part.text : null))
    .filter(Boolean)
    .join('\n')
    .trim();
}

function mapGeminiFinishReason(reason) {
  switch (reason) {
    case 'MAX_TOKENS':
      return 'max_tokens';
    case 'SAFETY':
      return 'safety';
    default:
      return 'stop';
  }
}

function mapGeminiStreamingFinishReason(reason) {
  if (typeof reason !== 'string' || reason.length === 0) {
    return null;
  }

  return mapGeminiFinishReason(reason);
}

function mapTraiFinishReasonToGemini(reason) {
  switch (reason) {
    case 'max_tokens':
      return 'MAX_TOKENS';
    case 'safety':
      return 'SAFETY';
    default:
      return 'STOP';
  }
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

function normalizeArray(value) {
  return Array.isArray(value) ? value : [];
}

function normalizeObject(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}
