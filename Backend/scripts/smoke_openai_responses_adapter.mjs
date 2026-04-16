import assert from 'node:assert/strict';
import { createAIProvider } from '../src/ai-provider.mjs';
import { canonicalTraiRequestFixtures } from './trai_ai_contract_fixtures.mjs';
import {
  buildGeminiRequestFromTraiRequest,
  canonicalMessagesFromTraiRequest,
  normalizeIncomingTraiRequest
} from '../src/trai-ai-contract.mjs';

class HttpError extends Error {
  constructor(statusCode, payload) {
    super(payload?.message ?? `HTTP ${statusCode}`);
    this.statusCode = statusCode;
    this.payload = payload;
  }
}

const baseConfig = {
  aiProvider: 'openai',
  openAIApiKey: 'test-openai-key',
  openAIModel: 'gpt-5.4-mini',
  geminiApiKey: '',
  geminiModel: 'gemini-3-flash-preview'
};

await testNonStreamingTextAndRequestShape();
await testNonStreamingToolCallNormalization();
await testStreamingTextNormalization();
await testStreamingToolCallNormalization();
await testToolFollowUpInputMapping();
await testGeminiVisionRequestMapsToOpenAIInput();
await testFoodPhotoAnalysisRequestMapsToStrictOpenAIVisionPayload();
await testGeminiNullableSchemaMapsToOpenAINullTypes();
await testGeminiNullableToolSchemaMapsToOpenAINullTypes();
await testLegacyGeminiCompatRequestBuildsGeminiPayload();
await testCanonicalTraiRequestBuildsGeminiPayload();
await testCanonicalTraiToolMessagesBuildGeminiPayload();
await testLegacyGeminiRequestDerivesCanonicalMessages();
await testGeminiRoundTripPreservesGenerationConfig();
await testGeminiThinkingLevelMapsToOpenAIReasoning();
await testGeminiMinimalThinkingMapsToNoneForGPT54();
await testCanonicalTraiFoodPhotoRequestMapsToOpenAIVisionPayload();
await testOpenAIUsesCanonicalMessagesWhenFlattenedMessagesAreAbsent();
await testCanonicalTraiRequestExecutesAgainstGemini();
await testCanonicalTraiStreamingGeminiNormalization();
await testCanonicalTraiToolMessagesExecuteAgainstGemini();
await testCanonicalFixtureMatrixAcrossProviders();

console.log('Trai AI adapter smoke tests passed.');

async function testNonStreamingTextAndRequestShape() {
  const captured = [];
  const provider = withMockedFetch(async (url, init) => {
    captured.push({ url, body: JSON.parse(init.body) });
    return jsonResponse({
      status: 'completed',
      output: [
        {
          type: 'message',
          content: [
            { type: 'output_text', text: 'Hello from OpenAI.' }
          ]
        }
      ]
    });
  });

  const response = await provider.execute({
    systemText: 'Be concise.',
    messages: [
      {
        role: 'user',
        text: 'Plan my day',
        images: [],
        toolCalls: [],
        toolResponses: []
      }
    ],
    tools: [
      {
        name: 'lookup_food',
        description: 'Look up food macros',
        parameters: {
          type: 'object',
          properties: {
            query: { type: 'string' }
          }
        }
      }
    ],
    output: { kind: 'json_schema', schema: { type: 'object', properties: { ok: { type: 'boolean' } } } },
    generation: {
      temperature: 0.4,
      topP: 0.8,
      maxOutputTokens: 256
    }
  }, { streaming: false });

  assert.equal(response.type, 'single');
  assert.deepEqual(response.response.parts, [{ type: 'text', text: 'Hello from OpenAI.' }]);
  assert.equal(response.response.finishReason, 'STOP');

  assert.equal(captured.length, 1);
  assert.equal(captured[0].url, 'https://api.openai.com/v1/responses');
  assert.equal(captured[0].body.model, 'gpt-5.4-mini');
  assert.equal(captured[0].body.instructions, 'Be concise.');
  assert.equal(captured[0].body.parallel_tool_calls, true);
  assert.equal(captured[0].body.tool_choice, 'auto');
  assert.equal(captured[0].body.text.format.type, 'json_schema');
  assert.equal(captured[0].body.text.format.strict, true);
  assert.equal(captured[0].body.tools[0].strict, true);
}

async function testNonStreamingToolCallNormalization() {
  const provider = withMockedFetch(async () => jsonResponse({
    status: 'completed',
    output: [
      {
        type: 'function_call',
        id: 'fc_1',
        call_id: 'call_1',
        name: 'lookup_food',
        arguments: '{"query":"banana"}'
      }
    ]
  }));

  const response = await provider.execute(emptyRequest(), { streaming: false });

  assert.equal(response.type, 'single');
  assert.deepEqual(response.response.parts, [
    {
      type: 'tool_call',
      id: 'call_1',
      name: 'lookup_food',
      args: { query: 'banana' }
    }
  ]);
}

async function testStreamingTextNormalization() {
  const provider = withMockedFetch(async () => sseResponse([
    { type: 'response.output_text.delta', delta: 'Hello ' },
    { type: 'response.output_text.delta', delta: 'world' },
    { type: 'response.completed', response: { status: 'completed', output: [] } }
  ]));

  const response = await provider.execute(emptyRequest(), { streaming: true });
  assert.equal(response.type, 'stream');

  const events = [];
  for await (const event of response.stream) {
    events.push(event);
  }

  assert.deepEqual(events, [
    { parts: [{ type: 'text', text: 'Hello ' }], finishReason: null },
    { parts: [{ type: 'text', text: 'world' }], finishReason: null },
    { parts: [], finishReason: 'STOP' }
  ]);
}

async function testStreamingToolCallNormalization() {
  const provider = withMockedFetch(async () => sseResponse([
    {
      type: 'response.output_item.added',
      item: {
        type: 'function_call',
        id: 'fc_1',
        call_id: 'call_lookup',
        name: 'lookup_food',
        arguments: ''
      }
    },
    {
      type: 'response.function_call_arguments.delta',
      item_id: 'fc_1',
      delta: '{"query":"'
    },
    {
      type: 'response.function_call_arguments.delta',
      item_id: 'fc_1',
      delta: 'banana"}'
    },
    {
      type: 'response.function_call_arguments.done',
      item: {
        type: 'function_call',
        id: 'fc_1',
        call_id: 'call_lookup',
        name: 'lookup_food'
      }
    },
    { type: 'response.done', response: { status: 'completed', output: [] } }
  ]));

  const response = await provider.execute(emptyRequest(), { streaming: true });
  assert.equal(response.type, 'stream');

  const events = [];
  for await (const event of response.stream) {
    events.push(event);
  }

  assert.deepEqual(events, [
    {
      parts: [
        {
          type: 'tool_call',
          id: 'call_lookup',
          name: 'lookup_food',
          args: { query: 'banana' }
        }
      ],
      finishReason: null
    },
    { parts: [], finishReason: 'STOP' }
  ]);
}

async function testToolFollowUpInputMapping() {
  const captured = [];
  const provider = withMockedFetch(async (url, init) => {
    captured.push(JSON.parse(init.body));
    return jsonResponse({
      status: 'completed',
      output: [
        {
          type: 'message',
          content: [{ type: 'output_text', text: 'Done.' }]
        }
      ]
    });
  });

  await provider.execute({
    systemText: '',
    messages: [
      {
        role: 'user',
        text: 'How much protein is in a banana?',
        images: [],
        toolCalls: [],
        toolResponses: []
      },
      {
        role: 'assistant',
        text: '',
        images: [],
        toolCalls: [
          {
            id: 'call_lookup',
            name: 'lookup_food',
            args: { query: 'banana' }
          }
        ],
        toolResponses: []
      },
      {
        role: 'tool',
        text: '',
        images: [],
        toolCalls: [],
        toolResponses: [
          {
            toolCallID: 'call_lookup',
            name: 'lookup_food',
            response: { protein: 1.3 }
          }
        ]
      }
    ],
    tools: [],
    output: { kind: 'text', schema: null },
    generation: {
      temperature: null,
      topP: null,
      maxOutputTokens: null
    }
  }, { streaming: false });

  assert.equal(captured.length, 1);
  const input = captured[0].input;
  assert.equal(input[1].type, 'function_call');
  assert.equal(input[1].call_id, 'call_lookup');
  assert.equal(input[2].type, 'function_call_output');
  assert.equal(input[2].call_id, 'call_lookup');
  assert.equal(input[2].output, '{"protein":1.3}');
}

async function testGeminiVisionRequestMapsToOpenAIInput() {
  const captured = [];
  const provider = withMockedFetch(async (url, init) => {
    captured.push({ url, body: JSON.parse(init.body) });
    return jsonResponse({
      status: 'completed',
      output: [
        {
          type: 'message',
          content: [{ type: 'output_text', text: 'Vision request handled.' }]
        }
      ]
    });
  });

  const normalizedRequest = normalizeIncomingTraiRequest({
    contents: [
      {
        role: 'user',
        parts: [
          { text: 'What is in this image?' },
          {
            inline_data: {
              mime_type: 'image/jpeg',
              data: 'ZmFrZS1pbWFnZS1ieXRlcw=='
            }
          }
        ]
      }
    ],
    generationConfig: {
      mediaResolution: 'MEDIA_RESOLUTION_HIGH',
      maxOutputTokens: 128
    }
  });

  const response = await provider.execute(normalizedRequest, { streaming: false });
  assert.equal(response.type, 'single');
  assert.equal(captured.length, 1);

  const userInput = captured[0].body.input[0];
  assert.equal(userInput.role, 'user');
  assert.equal(userInput.content[0].type, 'input_text');
  assert.equal(userInput.content[1].type, 'input_image');
  assert.equal(userInput.content[1].image_url, 'data:image/jpeg;base64,ZmFrZS1pbWFnZS1ieXRlcw==');
  assert.equal(userInput.content[1].detail, 'high');
}

async function testFoodPhotoAnalysisRequestMapsToStrictOpenAIVisionPayload() {
  const captured = [];
  const provider = withMockedFetch(async (url, init) => {
    captured.push({ url, body: JSON.parse(init.body) });
    return jsonResponse({
      status: 'completed',
      output: [
        {
          type: 'message',
          content: [{
            type: 'output_text',
            text: '{"name":"Plain water","calories":0,"proteinGrams":0,"carbsGrams":0,"fatGrams":0,"fiberGrams":null,"servingSize":"1 glass","confidence":"high","notes":"Clear glass of water.","emoji":"💧"}'
          }]
        }
      ]
    });
  });

  const normalizedRequest = normalizeIncomingTraiRequest({
    contents: [
      {
        role: 'user',
        parts: [
          { text: 'Analyze this food and provide accurate nutritional information.' },
          {
            inline_data: {
              mime_type: 'image/jpeg',
              data: 'Zm9vZC1pbWFnZS1ieXRlcy0xMjM='
            }
          }
        ]
      }
    ],
    generationConfig: {
      responseMimeType: 'application/json',
      responseSchema: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          calories: { type: 'integer' },
          proteinGrams: { type: 'number' },
          carbsGrams: { type: 'number' },
          fatGrams: { type: 'number' },
          fiberGrams: { type: 'number', nullable: true },
          servingSize: { type: 'string', nullable: true },
          confidence: {
            type: 'string',
            enum: ['high', 'medium', 'low'],
            nullable: true
          },
          notes: { type: 'string', nullable: true },
          emoji: { type: 'string', nullable: true }
        },
        required: ['name', 'calories', 'proteinGrams', 'carbsGrams', 'fatGrams']
      },
      mediaResolution: 'MEDIA_RESOLUTION_HIGH',
      maxOutputTokens: 512,
      thinkingConfig: {
        thinkingLevel: 'MEDIUM'
      }
    }
  });

  const response = await provider.execute(normalizedRequest, { streaming: false });
  assert.equal(response.type, 'single');
  assert.equal(captured.length, 1);

  const requestBody = captured[0].body;
  assert.equal(requestBody.model, 'gpt-5.4-mini');
  assert.deepEqual(requestBody.reasoning, { effort: 'medium' });
  assert.equal(requestBody.max_output_tokens, 512);

  const userInput = requestBody.input[0];
  assert.equal(userInput.role, 'user');
  assert.equal(userInput.content[0].type, 'input_text');
  assert.equal(userInput.content[0].text, 'Analyze this food and provide accurate nutritional information.');
  assert.equal(userInput.content[1].type, 'input_image');
  assert.equal(userInput.content[1].image_url, 'data:image/jpeg;base64,Zm9vZC1pbWFnZS1ieXRlcy0xMjM=');
  assert.equal(userInput.content[1].detail, 'high');

  const schema = requestBody.text.format.schema;
  assert.equal(requestBody.text.format.type, 'json_schema');
  assert.equal(requestBody.text.format.strict, true);
  assert.deepEqual(schema.required, [
    'name',
    'calories',
    'proteinGrams',
    'carbsGrams',
    'fatGrams',
    'fiberGrams',
    'servingSize',
    'confidence',
    'notes',
    'emoji'
  ]);
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.properties.fiberGrams.type, ['number', 'null']);
  assert.deepEqual(schema.properties.servingSize.type, ['string', 'null']);
  assert.deepEqual(schema.properties.confidence.type, ['string', 'null']);
  assert.deepEqual(schema.properties.confidence.enum, ['high', 'medium', 'low', null]);
  assert.deepEqual(schema.properties.notes.type, ['string', 'null']);
  assert.deepEqual(schema.properties.emoji.type, ['string', 'null']);
}

async function testGeminiNullableSchemaMapsToOpenAINullTypes() {
  const captured = [];
  const provider = withMockedFetch(async (url, init) => {
    captured.push({ url, body: JSON.parse(init.body) });
    return jsonResponse({
      status: 'completed',
      output: [
        {
          type: 'message',
          content: [{ type: 'output_text', text: '{"name":"Eggs","notes":null,"details":{"servingSize":null}}' }]
        }
      ]
    });
  });

  const normalizedRequest = normalizeIncomingTraiRequest({
    contents: [
      {
        role: 'user',
        parts: [{ text: 'Analyze this meal' }]
      }
    ],
    generationConfig: {
      responseMimeType: 'application/json',
      responseSchema: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          notes: { type: 'string', nullable: true },
          details: {
            type: 'object',
            properties: {
              servingSize: { type: 'string', nullable: true }
            }
          }
        },
        required: ['name']
      }
    }
  });

  const response = await provider.execute(normalizedRequest, { streaming: false });
  assert.equal(response.type, 'single');
  assert.equal(captured.length, 1);

  const schema = captured[0].body.text.format.schema;
  assert.equal(captured[0].body.text.format.strict, true);
  assert.deepEqual(schema.properties.notes.type, ['string', 'null']);
  assert.deepEqual(schema.properties.details.type, ['object', 'null']);
  assert.deepEqual(schema.properties.details.properties.servingSize.type, ['string', 'null']);
  assert.equal('nullable' in schema.properties.notes, false);
  assert.equal('nullable' in schema.properties.details.properties.servingSize, false);
  assert.deepEqual(schema.required, ['name', 'notes', 'details']);
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.properties.details.required, ['servingSize']);
  assert.equal(schema.properties.details.additionalProperties, false);
}

async function testGeminiNullableToolSchemaMapsToOpenAINullTypes() {
  const captured = [];
  const provider = withMockedFetch(async (url, init) => {
    captured.push({ url, body: JSON.parse(init.body) });
    return jsonResponse({
      status: 'completed',
      output: [
        {
          type: 'message',
          content: [{ type: 'output_text', text: 'Tool schema handled.' }]
        }
      ]
    });
  });

  const response = await provider.execute({
    systemText: '',
    messages: [
      {
        role: 'user',
        text: 'Help me log this meal',
        images: [],
        toolCalls: [],
        toolResponses: []
      }
    ],
    tools: [
      {
        name: 'suggest_meal_log',
        description: 'Suggest a meal log for the user',
        parameters: {
          type: 'object',
          properties: {
            name: { type: 'string' },
            servingSize: { type: 'string', nullable: true },
            notes: {
              anyOf: [
                { type: 'string' }
              ],
              nullable: true
            }
          },
          required: ['name']
        }
      }
    ],
    output: { kind: 'text', schema: null },
    generation: {
      temperature: null,
      topP: null,
      maxOutputTokens: null
    }
  }, { streaming: false });

  assert.equal(response.type, 'single');
  assert.equal(captured.length, 1);

  const toolSchema = captured[0].body.tools[0].parameters;
  assert.equal(captured[0].body.tools[0].strict, true);
  assert.deepEqual(toolSchema.properties.servingSize.type, ['string', 'null']);
  assert.deepEqual(toolSchema.properties.notes.anyOf, [
    { type: 'string' },
    { type: 'null' }
  ]);
  assert.equal('nullable' in toolSchema.properties.servingSize, false);
  assert.equal('nullable' in toolSchema.properties.notes, false);
  assert.deepEqual(toolSchema.required, ['name', 'servingSize', 'notes']);
  assert.equal(toolSchema.additionalProperties, false);
}

async function testLegacyGeminiCompatRequestBuildsGeminiPayload() {
  const request = normalizeIncomingTraiRequest({
    contents: [
      {
        role: 'user',
        parts: [
          { text: 'Analyze this image' },
          {
            inline_data: {
              mime_type: 'image/jpeg',
              data: 'ZmFrZS1pbWFnZS1ieXRlcw=='
            }
          }
        ]
      }
    ],
    tools: [
      {
        function_declarations: [
          {
            name: 'lookup_food',
            description: 'Look up food macros',
            parameters: {
              type: 'object',
              properties: {
                query: { type: 'string' }
              }
            }
          }
        ]
      }
    ],
    generationConfig: {
      responseMimeType: 'application/json',
      responseSchema: {
        type: 'object',
        properties: {
          ok: { type: 'boolean' }
        },
        required: ['ok']
      },
      mediaResolution: 'MEDIA_RESOLUTION_HIGH',
      thinkingConfig: {
        thinkingLevel: 'LOW'
      }
    }
  });

  const rebuiltRequest = buildGeminiRequestFromTraiRequest(request);
  assert.equal('messages' in request, false);
  assert.equal(request.requestFormat, 'legacy_gemini_compat');
  assert.equal(rebuiltRequest.contents[0].parts[0].text, 'Analyze this image');
  assert.equal(rebuiltRequest.contents[0].parts[1].inlineData.mimeType, 'image/jpeg');
  assert.equal(rebuiltRequest.contents[0].parts[1].inlineData.data, 'ZmFrZS1pbWFnZS1ieXRlcw==');
  assert.equal(rebuiltRequest.tools[0].function_declarations[0].name, 'lookup_food');
  assert.equal(rebuiltRequest.generationConfig.responseMimeType, 'application/json');
  assert.equal(rebuiltRequest.generationConfig.mediaResolution, 'MEDIA_RESOLUTION_HIGH');
  assert.deepEqual(rebuiltRequest.generationConfig.thinkingConfig, {
    thinkingLevel: 'LOW'
  });
}

async function testCanonicalTraiRequestBuildsGeminiPayload() {
  const request = normalizeIncomingTraiRequest({
    system: 'You are Trai.',
    messages: [
      {
        role: 'user',
        parts: [
          { type: 'text', text: 'Analyze this image' },
          {
            type: 'image',
            mimeType: 'image/jpeg',
            data: 'ZmFrZS1pbWFnZS1ieXRlcw=='
          }
        ]
      }
    ],
    tools: [
      {
        name: 'lookup_food',
        description: 'Look up food macros',
        parameters: {
          type: 'object',
          properties: {
            query: { type: 'string' }
          }
        }
      }
    ],
    output: {
      kind: 'json_schema',
      schema: {
        type: 'object',
        properties: {
          ok: { type: 'boolean' }
        },
        required: ['ok']
      }
    },
    generation: {
      reasoning: 'low',
      imageDetail: 'high',
      maxOutputTokens: 256
    }
  });

  const rebuiltRequest = buildGeminiRequestFromTraiRequest(request);
  assert.equal('messages' in request, false);
  assert.equal(request.requestFormat, 'trai_v1');
  assert.equal(rebuiltRequest.systemInstruction.parts[0].text, 'You are Trai.');
  assert.equal(rebuiltRequest.contents[0].parts[0].text, 'Analyze this image');
  assert.equal(rebuiltRequest.contents[0].parts[1].inlineData.mimeType, 'image/jpeg');
  assert.equal(rebuiltRequest.tools[0].function_declarations[0].name, 'lookup_food');
  assert.equal(rebuiltRequest.generationConfig.responseMimeType, 'application/json');
  assert.equal(rebuiltRequest.generationConfig.mediaResolution, 'MEDIA_RESOLUTION_HIGH');
  assert.deepEqual(rebuiltRequest.generationConfig.thinkingConfig, {
    thinkingLevel: 'LOW'
  });
  assert.equal(rebuiltRequest.generationConfig.maxOutputTokens, 256);
}

async function testCanonicalTraiToolMessagesBuildGeminiPayload() {
  const request = normalizeIncomingTraiRequest({
    messages: [
      {
        role: 'user',
        parts: [
          { type: 'text', text: 'How much protein is in a banana?' }
        ]
      },
      {
        role: 'assistant',
        parts: [
          {
            type: 'tool_call',
            id: 'call_lookup',
            name: 'lookup_food',
            args: { query: 'banana' }
          }
        ]
      },
      {
        role: 'tool',
        parts: [
          {
            type: 'tool_response',
            toolCallID: 'call_lookup',
            name: 'lookup_food',
            response: { protein: 1.3 }
          }
        ]
      }
    ],
    generation: {
      reasoning: 'low'
    }
  });

  const rebuiltRequest = buildGeminiRequestFromTraiRequest(request);
  assert.equal(rebuiltRequest.contents[1].role, 'model');
  assert.deepEqual(rebuiltRequest.contents[1].parts[0].functionCall, {
    id: 'call_lookup',
    name: 'lookup_food',
    args: { query: 'banana' }
  });
  assert.equal(rebuiltRequest.contents[2].role, 'user');
  assert.deepEqual(rebuiltRequest.contents[2].parts[0].functionResponse, {
    toolCallID: 'call_lookup',
    name: 'lookup_food',
    response: { protein: 1.3 }
  });
}

async function testLegacyGeminiRequestDerivesCanonicalMessages() {
  const request = normalizeIncomingTraiRequest({
    contents: [
      {
        role: 'user',
        parts: [
          { text: 'Analyze this image' },
          {
            inline_data: {
              mime_type: 'image/jpeg',
              data: 'ZmFrZS1pbWFnZS1ieXRlcw=='
            }
          }
        ]
      },
      {
        role: 'model',
        parts: [
          {
            functionCall: {
              id: 'call_lookup',
              name: 'lookup_food',
              args: { query: 'banana' }
            }
          }
        ]
      },
      {
        role: 'user',
        parts: [
          {
            functionResponse: {
              toolCallID: 'call_lookup',
              name: 'lookup_food',
              response: { protein: 1.3 }
            }
          }
        ]
      }
    ]
  });

  const canonicalMessages = canonicalMessagesFromTraiRequest(request);
  assert.equal(canonicalMessages.length, 3);
  assert.equal(canonicalMessages[0].parts[0].type, 'text');
  assert.equal(canonicalMessages[0].parts[1].type, 'image');
  assert.equal(canonicalMessages[1].parts[0].type, 'tool_call');
  assert.equal(canonicalMessages[1].parts[0].id, 'call_lookup');
  assert.equal(canonicalMessages[2].role, 'tool');
  assert.equal(canonicalMessages[2].parts[0].type, 'tool_response');
  assert.equal(canonicalMessages[2].parts[0].toolCallID, 'call_lookup');
}

async function testGeminiRoundTripPreservesGenerationConfig() {
  const request = normalizeIncomingTraiRequest({
    contents: [
      {
        role: 'user',
        parts: [{ text: 'Analyze this photo' }]
      }
    ],
    generationConfig: {
      temperature: 0.2,
      topP: 0.7,
      maxOutputTokens: 256,
      mediaResolution: 'MEDIA_RESOLUTION_HIGH',
      thinkingConfig: {
        thinkingLevel: 'MEDIUM'
      }
    }
  });

  const rebuiltRequest = buildGeminiRequestFromTraiRequest(request);
  assert.equal(rebuiltRequest.generationConfig.temperature, 0.2);
  assert.equal(rebuiltRequest.generationConfig.topP, 0.7);
  assert.equal(rebuiltRequest.generationConfig.maxOutputTokens, 256);
  assert.equal(rebuiltRequest.generationConfig.mediaResolution, 'MEDIA_RESOLUTION_HIGH');
  assert.deepEqual(rebuiltRequest.generationConfig.thinkingConfig, {
    thinkingLevel: 'MEDIUM'
  });
}

async function testGeminiThinkingLevelMapsToOpenAIReasoning() {
  const captured = [];
  const provider = withMockedFetch(async (url, init) => {
    captured.push({ url, body: JSON.parse(init.body) });
    return jsonResponse({
      status: 'completed',
      output: [
        {
          type: 'message',
          content: [{ type: 'output_text', text: 'Reasoning request handled.' }]
        }
      ]
    });
  });

  const normalizedRequest = normalizeIncomingTraiRequest({
    contents: [
      {
        role: 'user',
        parts: [{ text: 'Think through this meal plan.' }]
      }
    ],
    generationConfig: {
      temperature: 0.4,
      topP: 0.8,
      thinkingConfig: {
        thinkingLevel: 'LOW'
      }
    }
  });

  const response = await provider.execute(normalizedRequest, { streaming: false });
  assert.equal(response.type, 'single');
  assert.equal(captured.length, 1);

  const requestBody = captured[0].body;
  assert.deepEqual(requestBody.reasoning, { effort: 'low' });
  assert.equal('temperature' in requestBody, false);
  assert.equal('top_p' in requestBody, false);
}

async function testGeminiMinimalThinkingMapsToNoneForGPT54() {
  const captured = [];
  const provider = withMockedFetch(async (url, init) => {
    captured.push({ url, body: JSON.parse(init.body) });
    return jsonResponse({
      status: 'completed',
      output: [
        {
          type: 'message',
          content: [{ type: 'output_text', text: 'Minimal reasoning request handled.' }]
        }
      ]
    });
  });

  const normalizedRequest = normalizeIncomingTraiRequest({
    contents: [
      {
        role: 'user',
        parts: [{ text: 'Classify this quickly.' }]
      }
    ],
    generationConfig: {
      temperature: 0.15,
      topP: 0.55,
      thinkingConfig: {
        thinkingLevel: 'MINIMAL'
      }
    }
  });

  const response = await provider.execute(normalizedRequest, { streaming: false });
  assert.equal(response.type, 'single');
  assert.equal(captured.length, 1);

  const requestBody = captured[0].body;
  assert.deepEqual(requestBody.reasoning, { effort: 'none' });
  assert.equal(requestBody.temperature, 0.15);
  assert.equal(requestBody.top_p, 0.55);
}

async function testCanonicalTraiFoodPhotoRequestMapsToOpenAIVisionPayload() {
  const captured = [];
  const provider = withMockedFetch(async (url, init) => {
    captured.push({ url, body: JSON.parse(init.body) });
    return jsonResponse({
      status: 'completed',
      output: [
        {
          type: 'message',
          content: [{ type: 'output_text', text: '{"name":"Water"}' }]
        }
      ]
    });
  });

  const normalizedRequest = normalizeIncomingTraiRequest({
    system: 'You are Trai.',
    messages: [
      {
        role: 'user',
        parts: [
          { type: 'text', text: 'Analyze this food and provide accurate nutritional information.' },
          {
            type: 'image',
            mimeType: 'image/jpeg',
            data: 'Zm9vZC1pbWFnZS1ieXRlcy0xMjM='
          }
        ]
      }
    ],
    output: {
      kind: 'json_schema',
      schema: {
        type: 'object',
        properties: {
          name: { type: 'string' }
        },
        required: ['name']
      }
    },
    generation: {
      reasoning: 'medium',
      imageDetail: 'high',
      maxOutputTokens: 512
    }
  });

  const response = await provider.execute(normalizedRequest, { streaming: false });
  assert.equal(response.type, 'single');
  assert.equal(captured.length, 1);

  const requestBody = captured[0].body;
  assert.equal(requestBody.instructions, 'You are Trai.');
  assert.deepEqual(requestBody.reasoning, { effort: 'medium' });
  assert.equal(requestBody.max_output_tokens, 512);
  assert.equal(requestBody.input[0].content[1].type, 'input_image');
  assert.equal(requestBody.input[0].content[1].image_url, 'data:image/jpeg;base64,Zm9vZC1pbWFnZS1ieXRlcy0xMjM=');
  assert.equal(requestBody.input[0].content[1].detail, 'high');
  assert.equal(requestBody.text.format.type, 'json_schema');
}

async function testOpenAIUsesCanonicalMessagesWhenFlattenedMessagesAreAbsent() {
  const captured = [];
  const provider = withMockedFetch(async (url, init) => {
    captured.push({ url, body: JSON.parse(init.body) });
    return jsonResponse({
      status: 'completed',
      output: [
        {
          type: 'message',
          content: [{ type: 'output_text', text: 'Handled canonical-only request.' }]
        }
      ]
    });
  });

  const response = await provider.execute({
    systemText: 'You are Trai.',
    messages: [],
    canonicalMessages: [
      {
        role: 'user',
        parts: [
          { type: 'text', text: 'Analyze this' },
          { type: 'image', mimeType: 'image/jpeg', data: 'ZmFrZS1pbWFnZQ==' }
        ]
      }
    ],
    tools: [],
    output: { kind: 'text', schema: null },
    generation: {
      reasoning: 'low',
      imageDetail: 'high',
      temperature: null,
      topP: null,
      maxOutputTokens: null
    }
  }, { streaming: false });

  assert.equal(response.type, 'single');
  assert.equal(captured.length, 1);
  assert.equal(captured[0].body.input[0].role, 'user');
  assert.equal(captured[0].body.input[0].content[0].text, 'Analyze this');
  assert.equal(captured[0].body.input[0].content[1].type, 'input_image');
}

async function testCanonicalTraiRequestExecutesAgainstGemini() {
  const captured = [];
  const provider = withGeminiMockedFetch(async (url, init) => {
    captured.push({ url, body: JSON.parse(init.body) });
    return jsonResponse({
      candidates: [
        {
          content: {
            role: 'model',
            parts: [{ text: 'Hello from Gemini.' }]
          },
          finishReason: 'STOP'
        }
      ],
      usageMetadata: {
        promptTokenCount: 123,
        candidatesTokenCount: 17,
        totalTokenCount: 140,
        cachedContentTokenCount: 9,
        thoughtsTokenCount: 4
      }
    });
  });

  const response = await provider.execute({
    systemText: 'You are Trai.',
    canonicalMessages: [
      {
        role: 'user',
        parts: [
          { type: 'text', text: 'Analyze this image' },
          { type: 'image', mimeType: 'image/jpeg', data: 'ZmFrZS1pbWFnZS1ieXRlcw==' }
        ]
      }
    ],
    tools: [
      {
        name: 'lookup_food',
        description: 'Look up food macros',
        parameters: {
          type: 'object',
          properties: {
            query: { type: 'string' }
          }
        }
      }
    ],
    output: {
      kind: 'json_schema',
      schema: {
        type: 'object',
        properties: {
          ok: { type: 'boolean' }
        },
        required: ['ok']
      }
    },
    generation: {
      reasoning: 'low',
      imageDetail: 'high',
      maxOutputTokens: 256,
      temperature: 0.25,
      topP: 0.75
    }
  }, { streaming: false });

  assert.equal(response.type, 'single');
  assert.deepEqual(response.response.parts, [{ type: 'text', text: 'Hello from Gemini.' }]);
  assert.equal(response.response.finishReason, 'stop');
  assert.deepEqual(response.usageMetadata, {
    provider: 'gemini',
    inputTokens: 123,
    outputTokens: 17,
    totalTokens: 140,
    cachedInputTokens: 9,
    reasoningTokens: 4,
    raw: {
      promptTokenCount: 123,
      candidatesTokenCount: 17,
      totalTokenCount: 140,
      cachedContentTokenCount: 9,
      thoughtsTokenCount: 4
    }
  });

  assert.equal(captured.length, 1);
  assert.match(captured[0].url, /^https:\/\/generativelanguage\.googleapis\.com\/v1beta\/models\/gemini-3-flash-preview:generateContent\?/);
  assert.equal(captured[0].body.systemInstruction.parts[0].text, 'You are Trai.');
  assert.equal(captured[0].body.contents[0].parts[0].text, 'Analyze this image');
  assert.equal(captured[0].body.contents[0].parts[1].inlineData.mimeType, 'image/jpeg');
  assert.equal(captured[0].body.generationConfig.mediaResolution, 'MEDIA_RESOLUTION_HIGH');
  assert.deepEqual(captured[0].body.generationConfig.thinkingConfig, {
    thinkingLevel: 'LOW'
  });
  assert.equal(captured[0].body.generationConfig.maxOutputTokens, 256);
  assert.equal(captured[0].body.generationConfig.temperature, 0.25);
  assert.equal(captured[0].body.generationConfig.topP, 0.75);
  assert.equal(captured[0].body.generationConfig.responseMimeType, 'application/json');
}

async function testCanonicalTraiStreamingGeminiNormalization() {
  const captured = [];
  const provider = withGeminiMockedFetch(async (url) => {
    captured.push(url);
    return sseResponse([
      {
        candidates: [
          {
            content: {
              role: 'model',
              parts: [{ text: 'Hello ' }]
            }
          }
        ]
      },
      {
        candidates: [
          {
            content: {
              role: 'model',
              parts: [{ text: 'world' }]
            },
            finishReason: 'STOP'
          }
        ],
        usageMetadata: {
          promptTokenCount: 11,
          candidatesTokenCount: 7,
          totalTokenCount: 18
        }
      }
    ]);
  });

  const response = await provider.execute({
    canonicalMessages: [
      {
        role: 'user',
        parts: [{ type: 'text', text: 'Say hello.' }]
      }
    ],
    tools: [],
    output: { kind: 'text', schema: null },
    generation: {
      reasoning: 'minimal',
      imageDetail: null,
      maxOutputTokens: null,
      temperature: null,
      topP: null
    }
  }, { streaming: true });

  assert.equal(response.type, 'stream');
  const events = [];
  for await (const event of response.stream) {
    events.push(event);
  }

  assert.deepEqual(events, [
    { parts: [{ type: 'text', text: 'Hello ' }], finishReason: null },
    { parts: [{ type: 'text', text: 'world' }], finishReason: 'stop' }
  ]);
  assert.deepEqual(response.getUsageMetadata(), {
    provider: 'gemini',
    inputTokens: 11,
    outputTokens: 7,
    totalTokens: 18,
    cachedInputTokens: null,
    reasoningTokens: null,
    raw: {
      promptTokenCount: 11,
      candidatesTokenCount: 7,
      totalTokenCount: 18
    }
  });
  assert.equal(captured.length, 1);
  assert.match(captured[0], /:streamGenerateContent\?.*alt=sse/);
}

async function testCanonicalTraiToolMessagesExecuteAgainstGemini() {
  const provider = withGeminiMockedFetch(async () => jsonResponse({
    candidates: [
      {
        content: {
          role: 'model',
          parts: [
            {
              functionCall: {
                id: 'call_lookup',
                name: 'lookup_food',
                args: { query: 'banana' }
              }
            }
          ]
        },
        finishReason: 'STOP'
      }
    ]
  }));

  const response = await provider.execute({
    canonicalMessages: [
      {
        role: 'user',
        parts: [{ type: 'text', text: 'How much protein is in a banana?' }]
      }
    ],
    tools: [
      {
        name: 'lookup_food',
        description: 'Look up food macros',
        parameters: {
          type: 'object',
          properties: {
            query: { type: 'string' }
          }
        }
      }
    ],
    output: { kind: 'text', schema: null },
    generation: {
      reasoning: 'low',
      imageDetail: null,
      maxOutputTokens: null,
      temperature: null,
      topP: null
    }
  }, { streaming: false });

  assert.equal(response.type, 'single');
  assert.deepEqual(response.response.parts, [
    {
      type: 'tool_call',
      id: 'call_lookup',
      name: 'lookup_food',
      args: { query: 'banana' }
    }
  ]);
  assert.equal(response.response.finishReason, 'stop');
}

async function testCanonicalFixtureMatrixAcrossProviders() {
  for (const fixture of canonicalTraiRequestFixtures) {
    const openAIBody = await captureOpenAIRequestBodyForFixture(fixture);
    fixture.assertOpenAIBody(openAIBody);

    const geminiBody = await captureGeminiRequestBodyForFixture(fixture);
    fixture.assertGeminiBody(geminiBody);
  }
}

async function captureOpenAIRequestBodyForFixture(fixture) {
  const captured = [];
  const provider = withMockedFetch(async (url, init) => {
    captured.push({ url, body: JSON.parse(init.body) });
    return jsonResponse({
      status: 'completed',
      output: [
        {
          type: 'message',
          content: [{ type: 'output_text', text: `Handled ${fixture.name}.` }]
        }
      ]
    });
  });

  const normalizedRequest = normalizeIncomingTraiRequest(cloneValue(fixture.request));
  assert.equal(normalizedRequest.requestFormat, 'trai_v1');

  const response = await provider.execute(normalizedRequest, { streaming: false });
  assert.equal(response.type, 'single');
  assert.equal(captured.length, 1);
  assert.equal(captured[0].url, 'https://api.openai.com/v1/responses');
  return captured[0].body;
}

async function captureGeminiRequestBodyForFixture(fixture) {
  const captured = [];
  const provider = withGeminiMockedFetch(async (url, init) => {
    captured.push({ url, body: JSON.parse(init.body) });
    return jsonResponse({
      candidates: [
        {
          content: {
            role: 'model',
            parts: [{ text: `Handled ${fixture.name}.` }]
          },
          finishReason: 'STOP'
        }
      ]
    });
  });

  const normalizedRequest = normalizeIncomingTraiRequest(cloneValue(fixture.request));
  assert.equal(normalizedRequest.requestFormat, 'trai_v1');

  const response = await provider.execute(normalizedRequest, { streaming: false });
  assert.equal(response.type, 'single');
  assert.equal(response.response.finishReason, 'stop');
  assert.equal(captured.length, 1);
  assert.match(captured[0].url, /^https:\/\/generativelanguage\.googleapis\.com\/v1beta\/models\/gemini-3-flash-preview:generateContent\?/);
  return captured[0].body;
}

function withMockedFetch(handler, configOverrides = {}) {
  const provider = createAIProvider({
    ...baseConfig,
    ...configOverrides
  }, HttpError);
  globalThis.fetch = handler;
  return provider;
}

function withGeminiMockedFetch(handler) {
  return withMockedFetch(handler, {
    aiProvider: 'gemini',
    geminiApiKey: 'test-gemini-key'
  });
}

function jsonResponse(payload) {
  return {
    ok: true,
    async json() {
      return payload;
    },
    async text() {
      return JSON.stringify(payload);
    }
  };
}

function sseResponse(events) {
  const payload = `${events.map((event) => `data: ${JSON.stringify(event)}\n\n`).join('')}data: [DONE]\n\n`;
  return {
    ok: true,
    body: streamChunks([payload]),
    async text() {
      return payload;
    }
  };
}

async function* streamChunks(chunks) {
  const encoder = new TextEncoder();
  for (const chunk of chunks) {
    yield encoder.encode(chunk);
  }
}

function emptyRequest() {
  return {
    systemText: '',
    messages: [
      {
        role: 'user',
        text: 'Hello',
        images: [],
        toolCalls: [],
        toolResponses: []
      }
    ],
    tools: [],
    output: { kind: 'text', schema: null },
    generation: {
      temperature: null,
      topP: null,
      maxOutputTokens: null
    }
  };
}

function cloneValue(value) {
  return JSON.parse(JSON.stringify(value));
}
