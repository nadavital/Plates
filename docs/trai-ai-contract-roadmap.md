# Trai AI Contract Roadmap

## Goal

Move Trai to a true provider-agnostic AI architecture where:

- app and feature logic speak one Trai-native contract
- backend core validates one Trai-native contract
- Gemini/OpenAI adapters own all provider-specific translation
- tests prove that the same Trai request maps correctly to every provider

## Current State

Today the app layer is renamed to `AI*`, but the request wire shape is still partially Gemini-shaped:

- app request assembly still thinks in terms like `contents`, `inline_data`, and `function_declarations`
- backend normalization still accepts Gemini-compatible request bodies as the default path
- OpenAI translation is good, but it still derives some behavior from Gemini-style generation config

## Target Contract

Canonical request shape:

```json
{
  "system": "You are Trai.",
  "messages": [
    {
      "role": "user",
      "parts": [
        { "type": "text", "text": "Analyze this meal" },
        { "type": "image", "mimeType": "image/jpeg", "data": "..." }
      ]
    }
  ],
  "tools": [
    {
      "name": "suggest_food_log",
      "description": "Suggest a food log",
      "parameters": { "type": "object", "properties": {} }
    }
  ],
  "output": {
    "kind": "json_schema",
    "schema": { "type": "object", "properties": {} }
  },
  "generation": {
    "reasoning": "low",
    "maxOutputTokens": 512,
    "temperature": 1,
    "topP": 0.95,
    "imageDetail": "high"
  }
}
```

Canonical response shape:

```json
{
  "parts": [
    { "type": "text", "text": "..." },
    { "type": "tool_call", "id": "call_1", "name": "lookup_food", "args": {} }
  ],
  "finishReason": "STOP"
}
```

## Principles

1. App code never writes provider field names.
2. Backend core never assumes Gemini or OpenAI field names.
3. Adapters are responsible for provider compatibility only.
4. One canonical fixture should be testable against every provider adapter.
5. Migration should stay backward compatible until parity is proven.

## Phases

### Phase 1: Canonical Contract Foundation

- Introduce typed Trai-native request models in the app.
- Add canonical request serialization on the app side.
- Add canonical request normalization on the backend.
- Keep backward compatibility with existing Gemini-shaped payloads.

Exit criteria:

- app can emit canonical request JSON
- backend accepts canonical JSON and legacy JSON
- canonical tests exist for app serialization and backend normalization

### Phase 2: App Migration

- Refactor `AIService+*` feature flows to build `TraiAIRequest` directly.
- Remove feature-level `[String: Any]` payload assembly where practical.
- Keep feature logic provider-agnostic.

Exit criteria:

- food, exercise, chat, and function-calling flows build canonical requests
- only one serializer turns models into JSON

### Phase 3: Provider Adapter Isolation

- Refactor Gemini adapter to map from canonical internal request only.
- Refactor OpenAI adapter to map from canonical internal request only.
- Remove reliance on Gemini-shaped generation config as an internal source of truth.

Exit criteria:

- provider adapters are the only place where provider field names appear
- backend core talks only in canonical Trai types

### Phase 4: Coverage Expansion

- Add adapter fixture tests for:
  - text
  - structured output
  - image input
  - tool calls
  - tool responses
  - streaming chunks
- Add feature fixtures for:
  - food photo
  - exercise photo
  - coach chat
  - function-calling chat
  - memory extraction
  - plan generation

Exit criteria:

- the same canonical request fixture is asserted against Gemini and OpenAI payload mapping
- adapter regressions fail in test before they reach production

### Phase 5: Cleanup and Removal

- Remove legacy Gemini-shaped request support once telemetry confirms parity.
- Replace remaining dictionary-based request APIs with typed models.
- Remove compatibility helpers that only exist for the migration.

Exit criteria:

- no app feature assembles Gemini wire payloads
- no backend route treats Gemini shape as primary

## Test Matrix

### App Tests

- canonical serialization from typed models
- backward-compatible conversion from legacy builder helpers
- schema and tool parameter encoding
- image encoding

### Backend Contract Tests

- canonical request normalization
- legacy request normalization
- canonical to Gemini request mapping
- canonical to OpenAI request mapping

### Provider Adapter Tests

- reasoning mapping
- image detail mapping
- structured output mapping
- nullable schema handling
- tool call and response round-trips
- streaming parsing

### Feature Regression Fixtures

- food photo analysis
- exercise photo analysis
- normal chat
- structured chat
- tool-calling chat

## Rollout Notes

- keep dual-shape compatibility during migration
- instrument canonical vs legacy request counts
- compare latency, token usage, and failures by provider
- remove legacy support only after feature parity is proven
