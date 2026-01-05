# Gemini API Reference

This document defines the correct Gemini API usage for this project. Always reference before modifying Gemini-related code.

## Official Documentation

- **Function Calling**: https://ai.google.dev/gemini-api/docs/function-calling
- **Structured Output**: https://ai.google.dev/gemini-api/docs/structured-output

## Function Calling

### Function Declaration Format

```json
{
  "name": "function_name",
  "description": "Clear description of what this function does",
  "parameters": {
    "type": "object",
    "properties": {
      "param1": {
        "type": "string",
        "description": "What this parameter is for"
      },
      "param2": {
        "type": "integer",
        "enum": [1, 2, 3]
      }
    },
    "required": ["param1"]
  }
}
```

### Key Points

- Uses OpenAPI schema subset
- **Types are lowercase**: `object`, `string`, `array`, `integer`, `number`, `boolean`
- Response contains `functionCall` with `name` and `args`
- Send results back via `functionResponse` with `name` and `response` fields
- Supports parallel function calling (multiple independent calls at once)
- Supports compositional function calling (chained calls where output feeds next call)
- Keep temperature at 1.0 for Gemini 3 models
- Limit to 10-20 functions max for best accuracy

### Sending Function Results Back

Single function:
```json
{
  "role": "user",
  "parts": [{
    "functionResponse": {
      "name": "function_name",
      "response": { "result": "value" }
    }
  }]
}
```

Multiple functions (parallel):
```json
{
  "role": "user",
  "parts": [
    {"functionResponse": {"name": "func1", "response": {...}}},
    {"functionResponse": {"name": "func2", "response": {...}}}
  ]
}
```

**Important**: When Gemini returns multiple function calls, collect ALL of them first, execute all, then send ALL results back in ONE request. This ensures Gemini can give a unified response considering all data.

## Structured Output

### Configuration

```swift
config["responseMimeType"] = "application/json"
config["responseSchema"] = schema
```

### Schema Format

```json
{
  "type": "object",
  "properties": {
    "field1": {
      "type": "string",
      "description": "Description guides model behavior"
    },
    "field2": {
      "type": "array",
      "items": { "type": "string" }
    }
  },
  "required": ["field1"]
}
```

### Key Points

- **Types are lowercase**: `string`, `object`, `array`, `integer`, `number`, `boolean`, `null`
- Supports `enum` for limited value sets
- Supports `format` for strings: `date-time`, `date`, `time`
- Supports `minimum`, `maximum` for numbers
- Use `description` fields to guide model behavior
- Output is syntactically correct JSON but values need semantic validation in app code

## Model Configuration

For Gemini 3 models:
- Temperature: 1.0 (recommended default)
- Use `thinkingConfig` with `thinkingLevel`: `MINIMAL`, `LOW`, `MEDIUM`
- For images: `mediaResolution`: `MEDIA_RESOLUTION_HIGH`
