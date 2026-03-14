import Foundation

// MARK: - Permission Mode

enum PermissionMode: String, Codable {
    case `default` = "default"
    case acceptEdits = "acceptEdits"
    case bypassPermissions = "bypassPermissions"
}

// MARK: - Commands (Swift → Node)

struct RpcRequest<P: Encodable>: Encodable {
    let jsonrpc: String = "2.0"
    let id: Int
    let method: String
    let params: P
}

struct StartSessionParams: Codable {
    let sessionId: String
    let prompt: String
    let workingDirectory: String
    let systemPrompt: String?
    let permissionMode: PermissionMode
    let allowedTools: [String]?
    let resumeSessionId: String?
}

struct SendMessageParams: Codable {
    let sessionId: String
    let message: String
}

struct CancelSessionParams: Codable {
    let sessionId: String
}

// MARK: - Incoming messages (Node → Swift)

struct RpcError: Codable, Equatable {
    let code: Int
    let message: String
}

struct RpcResponse: Decodable {
    let id: Int
    let result: AnyCodableValue?
    let error: RpcError?
}

struct StreamNotification: Decodable {
    let sessionId: String
    let event: AgentEvent
}

enum SidecarMessage: Decodable {
    case response(RpcResponse)
    case event(StreamNotification)

    private enum CodingKeys: String, CodingKey {
        case id
        case method
        case params
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.id) {
            let response = try RpcResponse(from: decoder)
            self = .response(response)
        } else if container.contains(.method) {
            let params = try container.decode(StreamNotification.self, forKey: .params)
            self = .event(params)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "SidecarMessage must contain either 'id' (response) or 'method' (event)"
                )
            )
        }
    }
}

// MARK: - Agent Events

enum AgentEvent: Decodable {
    case assistantMessage(content: String)
    case textDelta(delta: String)
    case toolUse(toolName: String, toolId: String, input: String)
    case toolResult(toolId: String, result: String, isError: Bool)
    case sessionStarted(sdkSessionId: String)
    case sessionComplete(durationMs: Int, costUsd: Double?)
    case sessionError(error: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case content
        case delta
        case toolName
        case toolId
        case input
        case result
        case isError
        case sdkSessionId
        case durationMs
        case costUsd
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "assistant_message":
            let content = try container.decode(String.self, forKey: .content)
            self = .assistantMessage(content: content)
        case "text_delta":
            let delta = try container.decode(String.self, forKey: .delta)
            self = .textDelta(delta: delta)
        case "tool_use":
            let toolName = try container.decode(String.self, forKey: .toolName)
            let toolId = try container.decode(String.self, forKey: .toolId)
            let input = try container.decode(String.self, forKey: .input)
            self = .toolUse(toolName: toolName, toolId: toolId, input: input)
        case "tool_result":
            let toolId = try container.decode(String.self, forKey: .toolId)
            let result = try container.decode(String.self, forKey: .result)
            let isError = try container.decode(Bool.self, forKey: .isError)
            self = .toolResult(toolId: toolId, result: result, isError: isError)
        case "session_started":
            let sdkSessionId = try container.decode(String.self, forKey: .sdkSessionId)
            self = .sessionStarted(sdkSessionId: sdkSessionId)
        case "session_complete":
            let durationMs = try container.decode(Int.self, forKey: .durationMs)
            let costUsd = try container.decodeIfPresent(Double.self, forKey: .costUsd)
            self = .sessionComplete(durationMs: durationMs, costUsd: costUsd)
        case "session_error":
            let error = try container.decode(String.self, forKey: .error)
            self = .sessionError(error: error)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown AgentEvent type: \(type)"
                )
            )
        }
    }
}

// MARK: - AnyCodableValue (for untyped JSON results)

enum AnyCodableValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case dictionary([String: AnyCodableValue])
    case array([AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let val = try? container.decode(Bool.self) {
            self = .bool(val)
        } else if let val = try? container.decode(Int.self) {
            self = .int(val)
        } else if let val = try? container.decode(Double.self) {
            self = .double(val)
        } else if let val = try? container.decode(String.self) {
            self = .string(val)
        } else if let val = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(val)
        } else if let val = try? container.decode([AnyCodableValue].self) {
            self = .array(val)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
            )
        }
    }
}
