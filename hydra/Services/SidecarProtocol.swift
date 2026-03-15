import Foundation

// MARK: - Permission Mode

enum PermissionMode: String, Codable {
    case `default`
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

struct RpcError: Codable, Equatable, Error {
    let code: Int
    let message: String
}

struct RpcResponse: Decodable, Equatable {
    let id: Int
    let result: AnyCodableValue?
    let error: RpcError?

    var outcome: Result<AnyCodableValue, RpcError> {
        if let error = error {
            return .failure(error)
        }
        return .success(result ?? .null)
    }
}

struct StreamNotification: Decodable, Equatable {
    let sessionId: String
    let event: AgentEvent
}

enum SidecarMessage: Decodable, Equatable {
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
            let method = try container.decode(String.self, forKey: .method)
            guard method == "stream_event" else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Unknown notification method: '\(method)'"
                    )
                )
            }
            guard container.contains(.params) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Event notification is missing required 'params' field"
                    )
                )
            }
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

enum AgentEvent: Decodable, Equatable {
    case assistantMessage(content: String)
    case textDelta(delta: String)
    case toolUse(toolName: String, toolId: String, input: AnyCodableValue)
    case toolResult(toolId: String, result: AnyCodableValue, isError: Bool)
    case sessionStarted(sdkSessionId: String)
    case sessionComplete(durationMs: Int, costUsd: Double?)
    case sessionError(error: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case content
        case delta
        case toolName
        case toolId
        case toolUseId
        case input
        case result
        case isError
        case sdkSessionId
        case durationMs
        case costUsd
        case error
        case errors
        case message
        case name
    }

    private struct SdkMessage: Decodable {
        let content: [SdkContentBlock]
    }

    private struct SdkContentBlock: Decodable {
        let type: String
        let text: String?
        let id: String?
        let name: String?
        let input: AnyCodableValue?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "assistant_message":
            let message = try container.decode(SdkMessage.self, forKey: .message)
            let text = message.content
                .filter { $0.type == "text" }
                .compactMap { $0.text }
                .joined()
            self = .assistantMessage(content: text)
        case "text_delta":
            let delta = try container.decode(String.self, forKey: .delta)
            self = .textDelta(delta: delta)
        case "tool_use":
            let toolName = try (container.decodeIfPresent(String.self, forKey: .toolName)
                ?? container.decode(String.self, forKey: .name))
            let toolId = try (container.decodeIfPresent(String.self, forKey: .toolId)
                ?? container.decode(String.self, forKey: .toolUseId))
            let input = try container.decode(AnyCodableValue.self, forKey: .input)
            self = .toolUse(toolName: toolName, toolId: toolId, input: input)
        case "tool_result":
            let toolId = try (container.decodeIfPresent(String.self, forKey: .toolId)
                ?? container.decode(String.self, forKey: .toolUseId))
            let result = try (container.decodeIfPresent(AnyCodableValue.self, forKey: .result)
                ?? container.decode(AnyCodableValue.self, forKey: .content))
            let isError = (try? container.decode(Bool.self, forKey: .isError)) ?? false
            self = .toolResult(toolId: toolId, result: result, isError: isError)
        case "session_started":
            let sdkSessionId = try container.decode(String.self, forKey: .sdkSessionId)
            self = .sessionStarted(sdkSessionId: sdkSessionId)
        case "session_complete":
            let durationMs = try container.decode(Int.self, forKey: .durationMs)
            let costUsd = try container.decodeIfPresent(Double.self, forKey: .costUsd)
            self = .sessionComplete(durationMs: durationMs, costUsd: costUsd)
        case "session_error":
            if let error = try? container.decode(String.self, forKey: .error) {
                self = .sessionError(error: error)
            } else if let errors = try? container.decode([String].self, forKey: .errors) {
                self = .sessionError(error: errors.joined(separator: "; "))
            } else {
                self = .sessionError(error: "Unknown error")
            }
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

enum AnyCodableValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case dictionary([String: AnyCodableValue])
    case array([AnyCodableValue])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let val): try container.encode(val)
        case .number(let val): try container.encode(val)
        case .bool(let val): try container.encode(val)
        case .dictionary(let val): try container.encode(val)
        case .array(let val): try container.encode(val)
        case .null: try container.encodeNil()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let val = try? container.decode(Bool.self) {
            self = .bool(val)
        } else if let val = try? container.decode(Double.self) {
            // JSON numbers are IEEE 754 doubles — decode as Double to preserve
            // fidelity for values like 1.0 vs 1 (indistinguishable to JSONDecoder)
            self = .number(val)
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
