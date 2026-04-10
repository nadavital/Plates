import XCTest
@testable import Trai

final class AIBackendPayloadBuilderTests: XCTestCase {
    func testGenerationConfigIncludesReasoningSchemaAndImageResolution() {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string"]
            ],
            "required": ["name"]
        ]

        let config = AIBackendPayloadBuilder.generationConfig(
            reasoningLevel: .low,
            maxTokens: 512,
            jsonSchema: schema,
            imageResolution: .high
        )

        XCTAssertEqual(config["temperature"] as? Double, 1.0)
        XCTAssertEqual(config["topP"] as? Double, 0.95)
        XCTAssertEqual(config["maxOutputTokens"] as? Int, 512)
        XCTAssertEqual(config["responseMimeType"] as? String, "application/json")
        XCTAssertEqual(config["mediaResolution"] as? String, "MEDIA_RESOLUTION_HIGH")

        let thinkingConfig = config["thinkingConfig"] as? [String: Any]
        XCTAssertEqual(thinkingConfig?["thinkingLevel"] as? String, "LOW")

        let responseSchema = config["responseSchema"] as? [String: Any]
        XCTAssertEqual(responseSchema?["type"] as? String, "object")
    }

    func testRequestBodyBuildsCanonicalTraiPayload() {
        let body = AIBackendPayloadBuilder.requestBody(
            messages: [
                AIBackendPayloadBuilder.message(
                    role: .user,
                    parts: [AIBackendPayloadBuilder.textPart("Analyze this meal")]
                )
            ],
            generationConfig: AIBackendPayloadBuilder.generationConfig(reasoningLevel: .medium),
            toolDeclarations: [
                [
                    "name": "suggest_food_log",
                    "description": "Suggest a food log",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string"]
                        ]
                    ]
                ]
            ],
            systemText: "You are Trai."
        )

        XCTAssertEqual(body["system"] as? String, "You are Trai.")

        let generation = body["generation"] as? [String: Any]
        XCTAssertEqual(generation?["reasoning"] as? String, "medium")

        let messages = body["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 1)
        XCTAssertEqual(messages?.first?["role"] as? String, "user")

        let parts = messages?.first?["parts"] as? [[String: Any]]
        XCTAssertEqual(parts?.first?["type"] as? String, "text")
        XCTAssertEqual(parts?.first?["text"] as? String, "Analyze this meal")

        let tools = body["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.first?["name"] as? String, "suggest_food_log")

        let output = body["output"] as? [String: Any]
        XCTAssertEqual(output?["kind"] as? String, "text")
    }

    func testCanonicalRequestCarriesImageAndStructuredOutput() {
        let generationConfig = AIBackendPayloadBuilder.generationConfig(
            reasoningLevel: .low,
            maxTokens: 512,
            jsonSchema: [
                "type": "object",
                "properties": [
                    "name": ["type": "string"]
                ],
                "required": ["name"]
            ],
            imageResolution: .high
        )

        let body = AIBackendPayloadBuilder.requestBody(
            messages: [
                AIBackendPayloadBuilder.message(
                    role: .user,
                    parts: [
                        AIBackendPayloadBuilder.textPart("What food is this?"),
                        AIBackendPayloadBuilder.jpegImagePart(Data([0x01, 0x02, 0x03]))
                    ]
                )
            ],
            generationConfig: generationConfig
        )

        let generation = body["generation"] as? [String: Any]
        XCTAssertEqual(generation?["reasoning"] as? String, "low")
        XCTAssertEqual(generation?["maxOutputTokens"] as? Int, 512)
        XCTAssertEqual(generation?["imageDetail"] as? String, "high")

        let output = body["output"] as? [String: Any]
        XCTAssertEqual(output?["kind"] as? String, "json_schema")

        let messages = body["messages"] as? [[String: Any]]
        let parts = messages?.first?["parts"] as? [[String: Any]]
        XCTAssertEqual(parts?.count, 2)
        XCTAssertEqual(parts?.last?["type"] as? String, "image")
        XCTAssertEqual(parts?.last?["mimeType"] as? String, "image/jpeg")
        XCTAssertEqual(parts?.last?["data"] as? String, "AQID")
    }

    func testTypedCanonicalRequestEncodesToolCallsAndToolResponses() {
        let request = AIBackendPayloadBuilder.canonicalRequest(
            messages: [
                AIBackendPayloadBuilder.canonicalTextMessage(role: .user, text: "How much protein is in a banana?"),
                AIBackendPayloadBuilder.canonicalMessage(
                    role: .assistant,
                    parts: [
                        AIBackendPayloadBuilder.toolCallPart(
                            id: "call_lookup",
                            name: "lookup_food",
                            arguments: ["query": "banana"]
                        )
                    ]
                ),
                AIBackendPayloadBuilder.canonicalMessage(
                    role: .tool,
                    parts: [
                        AIBackendPayloadBuilder.toolResponsePart(
                            toolCallID: "call_lookup",
                            name: "lookup_food",
                            response: ["protein": 1.3]
                        )
                    ]
                )
            ],
            tools: [
                AIBackendPayloadBuilder.canonicalTool(
                    name: "lookup_food",
                    description: "Look up food macros",
                    parameters: [
                        "type": "object",
                        "properties": [
                            "query": ["type": "string"]
                        ]
                    ]
                )
            ],
            generation: AIBackendPayloadBuilder.canonicalGeneration(reasoningLevel: .low)
        )

        let body = AIBackendPayloadBuilder.requestBody(from: request)
        let messages = body["messages"] as? [[String: Any]]

        XCTAssertEqual(messages?.count, 3)
        XCTAssertEqual(messages?[1]["role"] as? String, "assistant")
        XCTAssertEqual(messages?[2]["role"] as? String, "tool")

        let toolCallPart = (messages?[1]["parts"] as? [[String: Any]])?.first
        XCTAssertEqual(toolCallPart?["type"] as? String, "tool_call")
        XCTAssertEqual(toolCallPart?["id"] as? String, "call_lookup")
        XCTAssertEqual(toolCallPart?["name"] as? String, "lookup_food")
        XCTAssertEqual((toolCallPart?["args"] as? [String: Any])?["query"] as? String, "banana")

        let toolResponsePart = (messages?[2]["parts"] as? [[String: Any]])?.first
        XCTAssertEqual(toolResponsePart?["type"] as? String, "tool_response")
        XCTAssertEqual(toolResponsePart?["toolCallID"] as? String, "call_lookup")
        XCTAssertEqual(toolResponsePart?["name"] as? String, "lookup_food")
        XCTAssertEqual((toolResponsePart?["response"] as? [String: Any])?["protein"] as? Double, 1.3)
    }

    func testSharedCanonicalRequestFixturesRoundTripToCanonicalPayloads() throws {
        for fixture in try loadSharedCanonicalRequestFixtures() {
            let request = try traiRequest(from: fixture.request)
            let body = AIBackendPayloadBuilder.requestBody(from: request)

            XCTAssertEqual(
                try canonicalJSONString(from: body),
                try canonicalJSONString(from: fixture.request),
                "Fixture \(fixture.name) should round-trip through TraiAIRequest serialization."
            )
        }
    }
}

private extension AIBackendPayloadBuilderTests {
    struct SharedFixture {
        let name: String
        let request: [String: Any]
    }

    func loadSharedCanonicalRequestFixtures() throws -> [SharedFixture] {
        let fileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SharedFixtures/trai_ai_contract_request_fixtures.json")

        let data = try Data(contentsOf: fileURL)
        let rawFixtures = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        return try rawFixtures.map { fixture in
            let name = try XCTUnwrap(fixture["name"] as? String)
            let request = try XCTUnwrap(fixture["request"] as? [String: Any])
            return SharedFixture(name: name, request: request)
        }
    }

    func canonicalJSONString(from jsonObject: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    func traiRequest(from json: [String: Any]) throws -> TraiAIRequest {
        let system = json["system"] as? String
        let messages = try (json["messages"] as? [[String: Any]] ?? []).map(traiMessage(from:))
        let tools = try (json["tools"] as? [[String: Any]] ?? []).map(traiTool(from:))
        let output = try traiOutput(from: try XCTUnwrap(json["output"] as? [String: Any]))
        let generation = try traiGeneration(from: try XCTUnwrap(json["generation"] as? [String: Any]))

        return TraiAIRequest(
            system: system,
            messages: messages,
            tools: tools,
            output: output,
            generation: generation
        )
    }

    func traiMessage(from json: [String: Any]) throws -> TraiAIMessage {
        let rawRole = try XCTUnwrap(json["role"] as? String)
        let role: TraiAIMessageRole
        switch rawRole {
        case "user":
            role = .user
        case "assistant":
            role = .assistant
        case "tool":
            role = .tool
        default:
            XCTFail("Unsupported message role: \(rawRole)")
            role = .user
        }

        let parts = try (json["parts"] as? [[String: Any]] ?? []).map(traiPart(from:))
        return TraiAIMessage(role: role, parts: parts)
    }

    func traiPart(from json: [String: Any]) throws -> TraiAIPart {
        switch try XCTUnwrap(json["type"] as? String) {
        case "text":
            return .text(try XCTUnwrap(json["text"] as? String))
        case "image":
            return .image(.init(
                mimeType: try XCTUnwrap(json["mimeType"] as? String),
                data: try XCTUnwrap(json["data"] as? String)
            ))
        case "tool_call":
            return .toolCall(.init(
                id: json["id"] as? String,
                name: try XCTUnwrap(json["name"] as? String),
                args: try TraiAIJSONValue(any: json["args"] ?? [:])
            ))
        case "tool_response":
            return .toolResponse(.init(
                toolCallID: json["toolCallID"] as? String,
                name: try XCTUnwrap(json["name"] as? String),
                response: try TraiAIJSONValue(any: json["response"] ?? [:])
            ))
        default:
            XCTFail("Unsupported part type: \(json)")
            return .text("")
        }
    }

    func traiTool(from json: [String: Any]) throws -> TraiAITool {
        TraiAITool(
            name: try XCTUnwrap(json["name"] as? String),
            description: try XCTUnwrap(json["description"] as? String),
            parameters: try TraiAIJSONValue(any: json["parameters"] ?? [:])
        )
    }

    func traiOutput(from json: [String: Any]) throws -> TraiAIOutput {
        let rawKind = try XCTUnwrap(json["kind"] as? String)
        let kind: TraiAIOutput.Kind
        switch rawKind {
        case "text":
            kind = .text
        case "json_object":
            kind = .jsonObject
        case "json_schema":
            kind = .jsonSchema
        default:
            XCTFail("Unsupported output kind: \(rawKind)")
            kind = .text
        }

        let schema = try json["schema"].map { try TraiAIJSONValue(any: $0) }
        return TraiAIOutput(kind: kind, schema: schema)
    }

    func traiGeneration(from json: [String: Any]) throws -> TraiAIGeneration {
        let imageDetail: TraiAIImageDetail?
        switch json["imageDetail"] as? String {
        case "low":
            imageDetail = .low
        case "high":
            imageDetail = .high
        case "auto":
            imageDetail = .auto
        case nil:
            imageDetail = nil
        default:
            XCTFail("Unsupported image detail: \(String(describing: json["imageDetail"]))")
            imageDetail = nil
        }

        return TraiAIGeneration(
            reasoning: json["reasoning"] as? String,
            maxOutputTokens: json["maxOutputTokens"] as? Int,
            temperature: json["temperature"] as? Double,
            topP: json["topP"] as? Double,
            imageDetail: imageDetail
        )
    }
}
