//
//  AIBackendPayloadBuilder.swift
//  Trai
//
//  Provider-agnostic helpers for building Trai AI backend requests.
//

import Foundation

enum AIReasoningLevel: String, Sendable {
    case minimal
    case low
    case medium

    nonisolated var backendThinkingLevel: String {
        rawValue.uppercased()
    }

    nonisolated var canonicalValue: String {
        rawValue
    }
}

enum AIImageResolution: String, Sendable {
    case low = "MEDIA_RESOLUTION_LOW"
    case high = "MEDIA_RESOLUTION_HIGH"

    nonisolated var canonicalValue: TraiAIImageDetail {
        switch self {
        case .low:
            return .low
        case .high:
            return .high
        }
    }
}

enum AIBackendMessageRole: Sendable {
    case user
    case assistant

    nonisolated var backendValue: String {
        switch self {
        case .user:
            return "user"
        case .assistant:
            return "model"
        }
    }
}

enum TraiAIImageDetail: String, Equatable, Sendable {
    case low
    case high
    case auto
}

enum TraiAIMessageRole: String, Equatable, Sendable {
    case user
    case assistant
    case tool
}

enum TraiAIJSONValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case bool(Bool)
    case object([String: TraiAIJSONValue])
    case array([TraiAIJSONValue])
    case null

    nonisolated init(any value: Any) throws {
        switch value {
        case let string as String:
            self = .string(string)
        case let bool as Bool:
            self = .bool(bool)
        case let int as Int:
            self = .integer(int)
        case let double as Double:
            self = .double(double)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if number.doubleValue.rounded(.towardZero) == number.doubleValue {
                self = .integer(number.intValue)
            } else {
                self = .double(number.doubleValue)
            }
        case let dictionary as [String: Any]:
            self = .object(try dictionary.mapValues { try TraiAIJSONValue(any: $0) })
        case let array as [Any]:
            self = .array(try array.map { try TraiAIJSONValue(any: $0) })
        case _ as NSNull:
            self = .null
        default:
            throw NSError(domain: "TraiAIJSONValue", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported JSON value: \(type(of: value))"
            ])
        }
    }
}

struct TraiAIImage: Equatable, Sendable {
    let mimeType: String
    let data: String
}

struct TraiAIToolCall: Equatable, Sendable {
    let id: String?
    let name: String
    let args: TraiAIJSONValue
}

struct TraiAIToolResponse: Equatable, Sendable {
    let toolCallID: String?
    let name: String
    let response: TraiAIJSONValue
}

enum TraiAIPart: Equatable, Sendable {
    case text(String)
    case image(TraiAIImage)
    case toolCall(TraiAIToolCall)
    case toolResponse(TraiAIToolResponse)
}

struct TraiAIMessage: Equatable, Sendable {
    let role: TraiAIMessageRole
    let parts: [TraiAIPart]
}

struct TraiAITool: Equatable, Sendable {
    let name: String
    let description: String
    let parameters: TraiAIJSONValue
}

struct TraiAIOutput: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case text
        case jsonObject = "json_object"
        case jsonSchema = "json_schema"
    }

    let kind: Kind
    let schema: TraiAIJSONValue?
}

struct TraiAIGeneration: Equatable, Sendable {
    let reasoning: String?
    let maxOutputTokens: Int?
    let temperature: Double?
    let topP: Double?
    let imageDetail: TraiAIImageDetail?
}

struct TraiAIRequest: Equatable, Sendable {
    let system: String?
    let messages: [TraiAIMessage]
    let tools: [TraiAITool]
    let output: TraiAIOutput
    let generation: TraiAIGeneration
}

enum AIBackendPayloadBuilder {
    typealias JSON = [String: Any]

    nonisolated static func textPart(_ text: String) -> JSON {
        ["text": text]
    }

    nonisolated static func jpegImagePart(_ imageData: Data) -> JSON {
        [
            "inline_data": [
                "mime_type": "image/jpeg",
                "data": imageData.base64EncodedString()
            ]
        ]
    }

    nonisolated static func functionCallPart(name: String, arguments: [String: Any]) -> JSON {
        [
            "functionCall": [
                "name": name,
                "args": arguments
            ]
        ]
    }

    nonisolated static func functionResponsePart(name: String, response: [String: Any]) -> JSON {
        [
            "functionResponse": [
                "name": name,
                "response": response
            ]
        ]
    }

    nonisolated static func message(role: AIBackendMessageRole, parts: [JSON]) -> JSON {
        [
            "role": role.backendValue,
            "parts": parts
        ]
    }

    nonisolated static func toolDeclarations(_ declarations: [JSON]) -> [JSON] {
        guard !declarations.isEmpty else { return [] }
        return [["function_declarations": declarations]]
    }

    nonisolated static func generationConfig(
        reasoningLevel: AIReasoningLevel,
        maxTokens: Int = 16384,
        jsonSchema: JSON? = nil,
        imageResolution: AIImageResolution? = nil,
        temperature: Double = 1.0,
        topP: Double = 0.95
    ) -> JSON {
        var config: JSON = [
            "temperature": temperature,
            "topP": topP,
            "maxOutputTokens": maxTokens,
            "thinkingConfig": [
                "thinkingLevel": reasoningLevel.backendThinkingLevel
            ]
        ]

        if let jsonSchema {
            config["responseMimeType"] = "application/json"
            config["responseSchema"] = jsonSchema
        }

        if let imageResolution {
            config["mediaResolution"] = imageResolution.rawValue
        }

        return config
    }

    nonisolated static func requestBody(from request: TraiAIRequest) -> JSON {
        var body: JSON = [
            "messages": request.messages.map(messageJSONObject),
            "tools": request.tools.map(toolJSONObject),
            "output": outputJSONObject(request.output),
            "generation": generationJSONObject(request.generation)
        ]
        if let system = request.system, !system.isEmpty {
            body["system"] = system
        }
        return body
    }

    nonisolated static func jsonValue(_ value: Any) -> TraiAIJSONValue {
        ((try? TraiAIJSONValue(any: value)) ?? .null)
    }

    nonisolated static func imagePart(_ imageData: Data, mimeType: String = "image/jpeg") -> TraiAIPart {
        .image(.init(mimeType: mimeType, data: imageData.base64EncodedString()))
    }

    nonisolated static func toolCallPart(id: String? = nil, name: String, arguments: [String: Any]) -> TraiAIPart {
        .toolCall(.init(id: id, name: name, args: jsonValue(arguments)))
    }

    nonisolated static func toolResponsePart(toolCallID: String? = nil, name: String, response: [String: Any]) -> TraiAIPart {
        .toolResponse(.init(toolCallID: toolCallID, name: name, response: jsonValue(response)))
    }

    nonisolated static func canonicalMessage(role: TraiAIMessageRole, parts: [TraiAIPart]) -> TraiAIMessage {
        TraiAIMessage(role: role, parts: parts)
    }

    nonisolated static func canonicalTextMessage(role: TraiAIMessageRole, text: String) -> TraiAIMessage {
        canonicalMessage(role: role, parts: [.text(text)])
    }

    nonisolated static func canonicalTool(name: String, description: String, parameters: [String: Any]) -> TraiAITool {
        TraiAITool(name: name, description: description, parameters: jsonValue(parameters))
    }

    nonisolated static func canonicalOutput(kind: TraiAIOutput.Kind = .text, schema: [String: Any]? = nil) -> TraiAIOutput {
        TraiAIOutput(kind: kind, schema: schema.map(jsonValue))
    }

    nonisolated static func canonicalGeneration(
        reasoningLevel: AIReasoningLevel,
        maxTokens: Int? = 16384,
        imageResolution: AIImageResolution? = nil,
        temperature: Double? = 1.0,
        topP: Double? = 0.95
    ) -> TraiAIGeneration {
        TraiAIGeneration(
            reasoning: reasoningLevel.canonicalValue,
            maxOutputTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            imageDetail: imageResolution?.canonicalValue
        )
    }

    nonisolated static func canonicalRequest(
        system: String? = nil,
        messages: [TraiAIMessage],
        tools: [TraiAITool] = [],
        output: TraiAIOutput = .init(kind: .text, schema: nil),
        generation: TraiAIGeneration
    ) -> TraiAIRequest {
        TraiAIRequest(
            system: system?.isEmpty == true ? nil : system,
            messages: messages,
            tools: tools,
            output: output,
            generation: generation
        )
    }

    nonisolated static func canonicalRequest(
        messages: [JSON],
        generationConfig: JSON,
        toolDeclarations declarations: [JSON] = [],
        systemText: String? = nil
    ) -> TraiAIRequest {
        let generation = canonicalGeneration(from: generationConfig)
        let output = canonicalOutput(from: generationConfig)
        let traiMessages = messages.compactMap(canonicalMessage(from:))
        let traiTools = declarations.compactMap(canonicalTool(from:))

        return TraiAIRequest(
            system: systemText?.isEmpty == true ? nil : systemText,
            messages: traiMessages,
            tools: traiTools,
            output: output,
            generation: generation
        )
    }

    nonisolated static func requestBody(
        messages: [JSON],
        generationConfig: JSON,
        toolDeclarations declarations: [JSON] = [],
        systemText: String? = nil
    ) -> JSON {
        requestBody(from: canonicalRequest(
            messages: messages,
            generationConfig: generationConfig,
            toolDeclarations: declarations,
            systemText: systemText
        ))
    }

    nonisolated private static func canonicalTool(from declaration: JSON) -> TraiAITool? {
        guard let name = declaration["name"] as? String, !name.isEmpty else { return nil }

        let description = declaration["description"] as? String ?? ""
        let parameters = (try? TraiAIJSONValue(any: declaration["parameters"] ?? [:])) ?? .object([:])

        return TraiAITool(
            name: name,
            description: description,
            parameters: parameters
        )
    }

    nonisolated private static func canonicalMessage(from legacyMessage: JSON) -> TraiAIMessage? {
        guard let parts = legacyMessage["parts"] as? [JSON] else { return nil }
        let canonicalParts = parts.compactMap(canonicalPart(from:))
        guard !canonicalParts.isEmpty else { return nil }

        let rawRole = (legacyMessage["role"] as? String ?? "user").lowercased()
        let containsOnlyToolResponses = canonicalParts.allSatisfy {
            if case .toolResponse = $0 { return true }
            return false
        }

        let role: TraiAIMessageRole
        if containsOnlyToolResponses {
            role = .tool
        } else {
            switch rawRole {
            case "model", "assistant":
                role = .assistant
            case "tool":
                role = .tool
            default:
                role = .user
            }
        }

        return TraiAIMessage(role: role, parts: canonicalParts)
    }

    nonisolated private static func canonicalPart(from legacyPart: JSON) -> TraiAIPart? {
        if let text = legacyPart["text"] as? String {
            return .text(text)
        }

        if let inlineData = (legacyPart["inline_data"] as? JSON) ?? (legacyPart["inlineData"] as? JSON),
           let mimeType = inlineData["mime_type"] as? String ?? inlineData["mimeType"] as? String,
           let data = inlineData["data"] as? String {
            return .image(.init(mimeType: mimeType, data: data))
        }

        if let functionCall = legacyPart["functionCall"] as? JSON,
           let name = functionCall["name"] as? String {
            let args = (try? TraiAIJSONValue(any: functionCall["args"] ?? [:])) ?? .object([:])
            return .toolCall(.init(
                id: functionCall["id"] as? String,
                name: name,
                args: args
            ))
        }

        if let functionResponse = legacyPart["functionResponse"] as? JSON,
           let name = functionResponse["name"] as? String {
            let response = (try? TraiAIJSONValue(any: functionResponse["response"] ?? [:])) ?? .object([:])
            return .toolResponse(.init(
                toolCallID: functionResponse["toolCallID"] as? String ?? functionResponse["tool_call_id"] as? String,
                name: name,
                response: response
            ))
        }

        return nil
    }

    nonisolated private static func canonicalGeneration(from legacyGenerationConfig: JSON) -> TraiAIGeneration {
        let thinkingConfig = legacyGenerationConfig["thinkingConfig"] as? JSON
        let rawThinkingLevel = (thinkingConfig?["thinkingLevel"] as? String)?.lowercased()
        let reasoning: String?
        switch rawThinkingLevel {
        case "minimal", "low", "medium":
            reasoning = rawThinkingLevel
        default:
            reasoning = nil
        }

        let imageDetail: TraiAIImageDetail?
        switch legacyGenerationConfig["mediaResolution"] as? String {
        case AIImageResolution.low.rawValue:
            imageDetail = .low
        case AIImageResolution.high.rawValue:
            imageDetail = .high
        default:
            imageDetail = nil
        }

        return TraiAIGeneration(
            reasoning: reasoning,
            maxOutputTokens: legacyGenerationConfig["maxOutputTokens"] as? Int,
            temperature: legacyGenerationConfig["temperature"] as? Double,
            topP: legacyGenerationConfig["topP"] as? Double,
            imageDetail: imageDetail
        )
    }

    nonisolated private static func canonicalOutput(from legacyGenerationConfig: JSON) -> TraiAIOutput {
        guard legacyGenerationConfig["responseMimeType"] as? String == "application/json" else {
            return TraiAIOutput(kind: .text, schema: nil)
        }

        if let responseSchema = legacyGenerationConfig["responseSchema"] {
            return TraiAIOutput(
                kind: .jsonSchema,
                schema: try? TraiAIJSONValue(any: responseSchema)
            )
        }

        return TraiAIOutput(kind: .jsonObject, schema: nil)
    }

    nonisolated private static func messageJSONObject(_ message: TraiAIMessage) -> JSON {
        [
            "role": message.role.rawValue,
            "parts": message.parts.map(partJSONObject)
        ]
    }

    nonisolated private static func partJSONObject(_ part: TraiAIPart) -> JSON {
        switch part {
        case let .text(value):
            return [
                "type": "text",
                "text": value
            ]
        case let .image(image):
            return [
                "type": "image",
                "mimeType": image.mimeType,
                "data": image.data
            ]
        case let .toolCall(toolCall):
            var object: JSON = [
                "type": "tool_call",
                "name": toolCall.name,
                "args": jsonObject(from: toolCall.args)
            ]
            if let id = toolCall.id, !id.isEmpty {
                object["id"] = id
            }
            return object
        case let .toolResponse(toolResponse):
            var object: JSON = [
                "type": "tool_response",
                "name": toolResponse.name,
                "response": jsonObject(from: toolResponse.response)
            ]
            if let toolCallID = toolResponse.toolCallID, !toolCallID.isEmpty {
                object["toolCallID"] = toolCallID
            }
            return object
        }
    }

    nonisolated private static func toolJSONObject(_ tool: TraiAITool) -> JSON {
        [
            "name": tool.name,
            "description": tool.description,
            "parameters": jsonObject(from: tool.parameters)
        ]
    }

    nonisolated private static func outputJSONObject(_ output: TraiAIOutput) -> JSON {
        var object: JSON = ["kind": output.kind.rawValue]
        if let schema = output.schema {
            object["schema"] = jsonObject(from: schema)
        }
        return object
    }

    nonisolated private static func generationJSONObject(_ generation: TraiAIGeneration) -> JSON {
        var object: JSON = [:]
        if let reasoning = generation.reasoning {
            object["reasoning"] = reasoning
        }
        if let maxOutputTokens = generation.maxOutputTokens {
            object["maxOutputTokens"] = maxOutputTokens
        }
        if let temperature = generation.temperature {
            object["temperature"] = temperature
        }
        if let topP = generation.topP {
            object["topP"] = topP
        }
        if let imageDetail = generation.imageDetail {
            object["imageDetail"] = imageDetail.rawValue
        }
        return object
    }

    nonisolated private static func jsonObject(from value: TraiAIJSONValue) -> Any {
        switch value {
        case let .string(string):
            return string
        case let .integer(integer):
            return integer
        case let .double(double):
            return double
        case let .bool(bool):
            return bool
        case let .object(object):
            return object.mapValues(jsonObject)
        case let .array(array):
            return array.map(jsonObject)
        case .null:
            return NSNull()
        }
    }
}
