import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const fixtureURL = new URL('../../SharedFixtures/trai_ai_contract_request_fixtures.json', import.meta.url);
const rawFixtures = JSON.parse(readFileSync(fixtureURL, 'utf8'));
const requestsByName = new Map(rawFixtures.map((fixture) => [fixture.name, fixture.request]));

export const canonicalTraiRequestFixtures = [
  {
    name: 'coach_text_low_reasoning',
    request: requestFixtureNamed('coach_text_low_reasoning'),
    assertOpenAIBody(body) {
      assert.equal(body.instructions, 'You are Trai.');
      assert.equal(body.text.format.type, 'text');
      assert.deepEqual(body.reasoning, { effort: 'low' });
      assert.equal(body.max_output_tokens, 180);
      assert.equal(body.input.length, 1);
      assert.equal(body.input[0].role, 'user');
      assert.equal(body.input[0].content, 'Plan my meals for today.');
      assert.equal('temperature' in body, false);
      assert.equal('top_p' in body, false);
    },
    assertGeminiBody(body) {
      assert.equal(body.systemInstruction.parts[0].text, 'You are Trai.');
      assert.equal(body.contents.length, 1);
      assert.equal(body.contents[0].parts[0].text, 'Plan my meals for today.');
      assert.deepEqual(body.generationConfig.thinkingConfig, {
        thinkingLevel: 'LOW'
      });
      assert.equal(body.generationConfig.maxOutputTokens, 180);
      assert.equal(body.generationConfig.temperature, 0.3);
      assert.equal(body.generationConfig.topP, 0.85);
      assert.equal('responseMimeType' in body.generationConfig, false);
    }
  },
  {
    name: 'food_photo_structured',
    request: requestFixtureNamed('food_photo_structured'),
    assertOpenAIBody(body) {
      assert.equal(body.instructions, 'You are Trai.');
      assert.deepEqual(body.reasoning, { effort: 'medium' });
      assert.equal(body.max_output_tokens, 512);
      assert.equal(body.text.format.type, 'json_schema');
      assert.equal(body.text.format.strict, true);
      assert.equal(body.input[0].role, 'user');
      assert.equal(body.input[0].content[0].type, 'input_text');
      assert.equal(body.input[0].content[1].type, 'input_image');
      assert.equal(body.input[0].content[1].detail, 'high');
      assert.equal(body.input[0].content[1].image_url, 'data:image/jpeg;base64,Zm9vZC1pbWFnZS1ieXRlcy0xMjM=');
      assert.deepEqual(body.text.format.schema.required, ['name', 'calories']);
    },
    assertGeminiBody(body) {
      assert.equal(body.systemInstruction.parts[0].text, 'You are Trai.');
      assert.equal(body.contents[0].parts[0].text, 'Analyze this food and provide accurate nutritional information.');
      assert.equal(body.contents[0].parts[1].inlineData.mimeType, 'image/jpeg');
      assert.equal(body.contents[0].parts[1].inlineData.data, 'Zm9vZC1pbWFnZS1ieXRlcy0xMjM=');
      assert.equal(body.generationConfig.responseMimeType, 'application/json');
      assert.equal(body.generationConfig.mediaResolution, 'MEDIA_RESOLUTION_HIGH');
      assert.deepEqual(body.generationConfig.thinkingConfig, {
        thinkingLevel: 'MEDIUM'
      });
      assert.equal(body.generationConfig.maxOutputTokens, 512);
      assert.deepEqual(body.generationConfig.responseSchema.required, ['name', 'calories']);
    }
  },
  {
    name: 'exercise_photo_minimal_reasoning',
    request: requestFixtureNamed('exercise_photo_minimal_reasoning'),
    assertOpenAIBody(body) {
      assert.deepEqual(body.reasoning, { effort: 'none' });
      assert.equal(body.max_output_tokens, 320);
      assert.equal(body.input[0].content[0].text, 'Identify this gym equipment and suggest exercises.');
      assert.equal(body.input[0].content[1].type, 'input_image');
      assert.equal(body.input[0].content[1].detail, 'high');
      assert.equal(body.temperature, 0.1);
      assert.equal(body.top_p, 0.5);
      assert.equal(body.text.format.type, 'json_schema');
    },
    assertGeminiBody(body) {
      assert.equal(body.contents[0].parts[0].text, 'Identify this gym equipment and suggest exercises.');
      assert.equal(body.contents[0].parts[1].inlineData.mimeType, 'image/jpeg');
      assert.equal(body.generationConfig.responseMimeType, 'application/json');
      assert.equal(body.generationConfig.mediaResolution, 'MEDIA_RESOLUTION_HIGH');
      assert.deepEqual(body.generationConfig.thinkingConfig, {
        thinkingLevel: 'MINIMAL'
      });
      assert.equal(body.generationConfig.maxOutputTokens, 320);
      assert.equal(body.generationConfig.temperature, 0.1);
      assert.equal(body.generationConfig.topP, 0.5);
    }
  },
  {
    name: 'tool_follow_up',
    request: requestFixtureNamed('tool_follow_up'),
    assertOpenAIBody(body) {
      assert.equal(body.tool_choice, 'auto');
      assert.equal(body.tools[0].name, 'lookup_food');
      assert.equal(body.tools[0].strict, true);
      assert.equal(body.input[0].role, 'user');
      assert.equal(body.input[0].content, 'How much protein is in a banana?');
      assert.equal(body.input[1].type, 'function_call');
      assert.equal(body.input[1].call_id, 'call_lookup');
      assert.equal(body.input[2].type, 'function_call_output');
      assert.equal(body.input[2].call_id, 'call_lookup');
      assert.equal(body.input[2].output, '{"protein":1.3}');
      assert.deepEqual(body.reasoning, { effort: 'low' });
      assert.equal(body.max_output_tokens, 120);
    },
    assertGeminiBody(body) {
      assert.equal(body.tools[0].function_declarations[0].name, 'lookup_food');
      assert.equal(body.contents[0].parts[0].text, 'How much protein is in a banana?');
      assert.equal(body.contents[1].role, 'model');
      assert.deepEqual(body.contents[1].parts[0].functionCall, {
        id: 'call_lookup',
        name: 'lookup_food',
        args: { query: 'banana' }
      });
      assert.equal(body.contents[2].role, 'user');
      assert.deepEqual(body.contents[2].parts[0].functionResponse, {
        toolCallID: 'call_lookup',
        name: 'lookup_food',
        response: { protein: 1.3 }
      });
      assert.deepEqual(body.generationConfig.thinkingConfig, {
        thinkingLevel: 'LOW'
      });
      assert.equal(body.generationConfig.maxOutputTokens, 120);
    }
  },
  {
    name: 'structured_optional_fields',
    request: requestFixtureNamed('structured_optional_fields'),
    assertOpenAIBody(body) {
      assert.equal(body.text.format.type, 'json_schema');
      assert.equal(body.text.format.strict, true);
      assert.deepEqual(body.reasoning, { effort: 'low' });
      assert.equal(body.max_output_tokens, 220);
      assert.deepEqual(body.text.format.schema.required, ['name', 'servingSize', 'notes']);
      assert.deepEqual(body.text.format.schema.properties.servingSize.type, ['string', 'null']);
      assert.deepEqual(body.text.format.schema.properties.notes.anyOf, [
        { type: 'string' },
        { type: 'null' }
      ]);
      assert.equal(body.text.format.schema.additionalProperties, false);
    },
    assertGeminiBody(body) {
      assert.equal(body.contents[0].parts[0].text, 'Extract the meal name and any optional serving details.');
      assert.equal(body.generationConfig.responseMimeType, 'application/json');
      assert.deepEqual(body.generationConfig.responseSchema.required, ['name']);
      assert.deepEqual(body.generationConfig.responseSchema.properties.servingSize.type, ['string', 'null']);
      assert.deepEqual(body.generationConfig.responseSchema.properties.notes.anyOf, [
        { type: 'string' },
        { type: 'null' }
      ]);
      assert.deepEqual(body.generationConfig.thinkingConfig, {
        thinkingLevel: 'LOW'
      });
      assert.equal(body.generationConfig.maxOutputTokens, 220);
    }
  },
  {
    name: 'multi_image_text_analysis',
    request: requestFixtureNamed('multi_image_text_analysis'),
    assertOpenAIBody(body) {
      assert.equal(body.instructions, 'You are Trai.');
      assert.equal(body.text.format.type, 'text');
      assert.deepEqual(body.reasoning, { effort: 'low' });
      assert.equal(body.max_output_tokens, 240);
      assert.equal(body.input.length, 1);
      assert.equal(body.input[0].role, 'user');
      assert.equal(body.input[0].content[0].type, 'input_text');
      assert.equal(body.input[0].content[0].text, 'Compare these two meal photos.');
      assert.equal(body.input[0].content[1].type, 'input_image');
      assert.equal(body.input[0].content[1].image_url, 'data:image/jpeg;base64,aW1hZ2UtMQ==');
      assert.equal(body.input[0].content[1].detail, 'high');
      assert.equal(body.input[0].content[2].type, 'input_image');
      assert.equal(body.input[0].content[2].image_url, 'data:image/png;base64,aW1hZ2UtMg==');
      assert.equal(body.input[0].content[2].detail, 'high');
    },
    assertGeminiBody(body) {
      assert.equal(body.systemInstruction.parts[0].text, 'You are Trai.');
      assert.equal(body.contents[0].parts[0].text, 'Compare these two meal photos.');
      assert.equal(body.contents[0].parts[1].inlineData.mimeType, 'image/jpeg');
      assert.equal(body.contents[0].parts[1].inlineData.data, 'aW1hZ2UtMQ==');
      assert.equal(body.contents[0].parts[2].inlineData.mimeType, 'image/png');
      assert.equal(body.contents[0].parts[2].inlineData.data, 'aW1hZ2UtMg==');
      assert.deepEqual(body.generationConfig.thinkingConfig, {
        thinkingLevel: 'LOW'
      });
      assert.equal(body.generationConfig.mediaResolution, 'MEDIA_RESOLUTION_HIGH');
      assert.equal(body.generationConfig.maxOutputTokens, 240);
    }
  }
];

function requestFixtureNamed(name) {
  const request = requestsByName.get(name);
  assert.ok(request, `Missing canonical Trai request fixture named ${name}.`);
  return request;
}
