import XCTest
@testable import hydra

final class SidecarProtocolTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: - RpcRequest encoding

    func testRpcRequestEncodesToCorrectJSON() throws {
        let params = StartSessionParams(
            sessionId: "abc-123",
            prompt: "Hello",
            workingDirectory: "/tmp",
            systemPrompt: nil,
            permissionMode: .default,
            allowedTools: nil,
            resumeSessionId: nil
        )
        let request = RpcRequest(id: 1, method: "start_session", params: params)

        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json["id"] as? Int, 1)
        XCTAssertEqual(json["method"] as? String, "start_session")

        let p = json["params"] as! [String: Any]
        XCTAssertEqual(p["session_id"] as? String, "abc-123")
        XCTAssertEqual(p["prompt"] as? String, "Hello")
        XCTAssertEqual(p["working_directory"] as? String, "/tmp")
        XCTAssertEqual(p["permission_mode"] as? String, "default")
    }

    // MARK: - StartSessionParams encoding

    func testStartSessionParamsEncodesAllFields() throws {
        let params = StartSessionParams(
            sessionId: "s1",
            prompt: "Do something",
            workingDirectory: "/project",
            systemPrompt: "You are helpful",
            permissionMode: .bypassPermissions,
            allowedTools: ["Read", "Write"],
            resumeSessionId: "prev-session"
        )

        let data = try encoder.encode(params)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["session_id"] as? String, "s1")
        XCTAssertEqual(json["prompt"] as? String, "Do something")
        XCTAssertEqual(json["working_directory"] as? String, "/project")
        XCTAssertEqual(json["system_prompt"] as? String, "You are helpful")
        XCTAssertEqual(json["permission_mode"] as? String, "bypassPermissions")
        XCTAssertEqual(json["allowed_tools"] as? [String], ["Read", "Write"])
        XCTAssertEqual(json["resume_session_id"] as? String, "prev-session")
    }

    func testStartSessionParamsOmitsNilFields() throws {
        let params = StartSessionParams(
            sessionId: "s1",
            prompt: "Hello",
            workingDirectory: "/tmp",
            systemPrompt: nil,
            permissionMode: .acceptEdits,
            allowedTools: nil,
            resumeSessionId: nil
        )

        let data = try encoder.encode(params)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNil(json["system_prompt"])
        XCTAssertNil(json["allowed_tools"])
        XCTAssertNil(json["resume_session_id"])
    }

    // MARK: - SendMessageParams encoding

    func testSendMessageParamsEncoding() throws {
        let params = SendMessageParams(sessionId: "s1", message: "Next step")

        let data = try encoder.encode(params)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["session_id"] as? String, "s1")
        XCTAssertEqual(json["message"] as? String, "Next step")
    }

    // MARK: - CancelSessionParams encoding

    func testCancelSessionParamsEncoding() throws {
        let params = CancelSessionParams(sessionId: "s1")

        let data = try encoder.encode(params)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["session_id"] as? String, "s1")
    }

    // MARK: - PermissionMode raw values

    func testPermissionModeRawValues() {
        XCTAssertEqual(PermissionMode.default.rawValue, "default")
        XCTAssertEqual(PermissionMode.acceptEdits.rawValue, "acceptEdits")
        XCTAssertEqual(PermissionMode.bypassPermissions.rawValue, "bypassPermissions")
    }

    // MARK: - RpcResponse decoding

    func testRpcResponseDecodesSuccessResult() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":{"ok":true}}
        """.data(using: .utf8)!

        let response = try decoder.decode(RpcResponse.self, from: json)

        XCTAssertEqual(response.id, 1)
        XCTAssertNotNil(response.result)
        XCTAssertNil(response.error)
    }

    func testRpcResponseDecodesError() throws {
        let json = """
        {"jsonrpc":"2.0","id":2,"error":{"code":-32600,"message":"Invalid request"}}
        """.data(using: .utf8)!

        let response = try decoder.decode(RpcResponse.self, from: json)

        XCTAssertEqual(response.id, 2)
        XCTAssertNil(response.result)
        XCTAssertNotNil(response.error)
        XCTAssertEqual(response.error?.code, -32600)
        XCTAssertEqual(response.error?.message, "Invalid request")
    }

    // MARK: - SidecarMessage discrimination

    func testSidecarMessageDecodesResponse() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":{"ok":true}}
        """.data(using: .utf8)!

        let message = try decoder.decode(SidecarMessage.self, from: json)

        if case .response(let resp) = message {
            XCTAssertEqual(resp.id, 1)
        } else {
            XCTFail("Expected .response, got \(message)")
        }
    }

    func testSidecarMessageDecodesEvent() throws {
        let json = """
        {"jsonrpc":"2.0","method":"event","params":{"session_id":"s1","event":{"type":"session_started","sdk_session_id":"sdk-42"}}}
        """.data(using: .utf8)!

        let message = try decoder.decode(SidecarMessage.self, from: json)

        if case .event(let notif) = message {
            XCTAssertEqual(notif.sessionId, "s1")
            if case .sessionStarted(let sdkId) = notif.event {
                XCTAssertEqual(sdkId, "sdk-42")
            } else {
                XCTFail("Expected .sessionStarted, got \(notif.event)")
            }
        } else {
            XCTFail("Expected .event, got \(message)")
        }
    }

    // MARK: - AgentEvent decoding

    func testAgentEventDecodesAssistantMessage() throws {
        let json = """
        {"type":"assistant_message","content":"Hello world"}
        """.data(using: .utf8)!

        let event = try decoder.decode(AgentEvent.self, from: json)

        if case .assistantMessage(let content) = event {
            XCTAssertEqual(content, "Hello world")
        } else {
            XCTFail("Expected .assistantMessage, got \(event)")
        }
    }

    func testAgentEventDecodesTextDelta() throws {
        let json = """
        {"type":"text_delta","delta":"chunk"}
        """.data(using: .utf8)!

        let event = try decoder.decode(AgentEvent.self, from: json)

        if case .textDelta(let delta) = event {
            XCTAssertEqual(delta, "chunk")
        } else {
            XCTFail("Expected .textDelta, got \(event)")
        }
    }

    func testAgentEventDecodesToolUseWithObjectInput() throws {
        let json = """
        {"type":"tool_use","tool_name":"Read","tool_id":"t1","input":{"file_path":"/tmp/foo.txt"}}
        """.data(using: .utf8)!

        let event = try decoder.decode(AgentEvent.self, from: json)

        if case .toolUse(let name, let id, let input) = event {
            XCTAssertEqual(name, "Read")
            XCTAssertEqual(id, "t1")
            XCTAssertEqual(input, .dictionary(["file_path": .string("/tmp/foo.txt")]))
        } else {
            XCTFail("Expected .toolUse, got \(event)")
        }
    }

    func testAgentEventDecodesToolResultWithStringResult() throws {
        let json = """
        {"type":"tool_result","tool_id":"t1","result":"file contents","is_error":false}
        """.data(using: .utf8)!

        let event = try decoder.decode(AgentEvent.self, from: json)

        if case .toolResult(let id, let result, let isError) = event {
            XCTAssertEqual(id, "t1")
            XCTAssertEqual(result, .string("file contents"))
            XCTAssertFalse(isError)
        } else {
            XCTFail("Expected .toolResult, got \(event)")
        }
    }

    func testAgentEventDecodesToolResultWithObjectResult() throws {
        let json = """
        {"type":"tool_result","tool_id":"t1","result":{"lines":["a","b"]},"is_error":false}
        """.data(using: .utf8)!

        let event = try decoder.decode(AgentEvent.self, from: json)

        if case .toolResult(let id, let result, _) = event {
            XCTAssertEqual(id, "t1")
            XCTAssertEqual(result, .dictionary(["lines": .array([.string("a"), .string("b")])]))
        } else {
            XCTFail("Expected .toolResult, got \(event)")
        }
    }

    func testAgentEventDecodesToolResultWithError() throws {
        let json = """
        {"type":"tool_result","tool_id":"t2","result":"not found","is_error":true}
        """.data(using: .utf8)!

        let event = try decoder.decode(AgentEvent.self, from: json)

        if case .toolResult(_, let result, let isError) = event {
            XCTAssertEqual(result, .string("not found"))
            XCTAssertTrue(isError)
        } else {
            XCTFail("Expected .toolResult, got \(event)")
        }
    }

    func testAgentEventDecodesSessionStarted() throws {
        let json = """
        {"type":"session_started","sdk_session_id":"sdk-99"}
        """.data(using: .utf8)!

        let event = try decoder.decode(AgentEvent.self, from: json)

        if case .sessionStarted(let sdkId) = event {
            XCTAssertEqual(sdkId, "sdk-99")
        } else {
            XCTFail("Expected .sessionStarted, got \(event)")
        }
    }

    func testAgentEventDecodesSessionComplete() throws {
        let json = """
        {"type":"session_complete","duration_ms":1500,"cost_usd":0.03}
        """.data(using: .utf8)!

        let event = try decoder.decode(AgentEvent.self, from: json)

        if case .sessionComplete(let duration, let cost) = event {
            XCTAssertEqual(duration, 1500)
            XCTAssertEqual(cost, 0.03)
        } else {
            XCTFail("Expected .sessionComplete, got \(event)")
        }
    }

    func testAgentEventDecodesSessionCompleteWithNilCost() throws {
        let json = """
        {"type":"session_complete","duration_ms":500}
        """.data(using: .utf8)!

        let event = try decoder.decode(AgentEvent.self, from: json)

        if case .sessionComplete(let duration, let cost) = event {
            XCTAssertEqual(duration, 500)
            XCTAssertNil(cost)
        } else {
            XCTFail("Expected .sessionComplete, got \(event)")
        }
    }

    func testAgentEventDecodesSessionError() throws {
        let json = """
        {"type":"session_error","error":"Something broke"}
        """.data(using: .utf8)!

        let event = try decoder.decode(AgentEvent.self, from: json)

        if case .sessionError(let error) = event {
            XCTAssertEqual(error, "Something broke")
        } else {
            XCTFail("Expected .sessionError, got \(event)")
        }
    }

    // MARK: - AnyCodableValue fidelity

    func testAnyCodableValueDecodesWholeNumberAsNumber() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":1.0}
        """.data(using: .utf8)!

        let response = try decoder.decode(RpcResponse.self, from: json)

        if case .number(let val) = response.result {
            XCTAssertEqual(val, 1.0)
        } else {
            XCTFail("Expected .number(1.0), got \(String(describing: response.result))")
        }
    }

    func testAnyCodableValueDecodesFractionalNumberAsNumber() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":3.14}
        """.data(using: .utf8)!

        let response = try decoder.decode(RpcResponse.self, from: json)

        if case .number(let val) = response.result {
            XCTAssertEqual(val, 3.14)
        } else {
            XCTFail("Expected .number(3.14), got \(String(describing: response.result))")
        }
    }

    func testAnyCodableValueDecodesIntegerAsNumber() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":42}
        """.data(using: .utf8)!

        let response = try decoder.decode(RpcResponse.self, from: json)

        if case .number(let val) = response.result {
            XCTAssertEqual(val, 42.0)
        } else {
            XCTFail("Expected .number(42.0), got \(String(describing: response.result))")
        }
    }

    func testAnyCodableValueDecodesBoolAsBool() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":true}
        """.data(using: .utf8)!

        let response = try decoder.decode(RpcResponse.self, from: json)

        if case .bool(let val) = response.result {
            XCTAssertTrue(val)
        } else {
            XCTFail("Expected .bool(true), got \(String(describing: response.result))")
        }
    }

    // MARK: - SidecarMessage missing params

    func testSidecarMessageEventWithoutParamsThrowsDescriptiveError() {
        let json = """
        {"jsonrpc":"2.0","method":"event"}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(SidecarMessage.self, from: json)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                XCTFail("Expected dataCorrupted, got \(error)")
                return
            }
            XCTAssertTrue(context.debugDescription.contains("params"), "Error should mention missing 'params'")
        }
    }

    // MARK: - SidecarMessage method validation

    func testSidecarMessageRejectsUnknownMethod() {
        let json = """
        {"jsonrpc":"2.0","method":"heartbeat","params":{"session_id":"s1","event":{"type":"session_started","sdk_session_id":"x"}}}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(SidecarMessage.self, from: json)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                XCTFail("Expected dataCorrupted, got \(error)")
                return
            }
            XCTAssertTrue(context.debugDescription.contains("heartbeat"), "Error should mention the unknown method")
        }
    }

    // MARK: - Equatable conformance

    func testAgentEventEquatable() {
        let a = AgentEvent.textDelta(delta: "hi")
        let b = AgentEvent.textDelta(delta: "hi")
        let c = AgentEvent.textDelta(delta: "bye")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testAnyCodableValueEquatable() {
        XCTAssertEqual(AnyCodableValue.string("x"), AnyCodableValue.string("x"))
        XCTAssertNotEqual(AnyCodableValue.string("x"), AnyCodableValue.number(1.0))
        XCTAssertEqual(AnyCodableValue.null, AnyCodableValue.null)
        XCTAssertEqual(
            AnyCodableValue.array([.string("a")]),
            AnyCodableValue.array([.string("a")])
        )
    }

    func testStreamNotificationEquatable() throws {
        let a = StreamNotification(sessionId: "s1", event: .sessionError(error: "x"))
        let b = StreamNotification(sessionId: "s1", event: .sessionError(error: "x"))
        XCTAssertEqual(a, b)
    }

    // MARK: - RpcResponse result accessor

    func testRpcResponseSuccessOutcome() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":{"ok":true}}
        """.data(using: .utf8)!

        let response = try decoder.decode(RpcResponse.self, from: json)
        let outcome = response.outcome

        switch outcome {
        case .success(let val):
            XCTAssertEqual(val, .dictionary(["ok": .bool(true)]))
        case .failure:
            XCTFail("Expected success")
        }
    }

    func testRpcResponseErrorOutcome() throws {
        let json = """
        {"jsonrpc":"2.0","id":2,"error":{"code":-32600,"message":"Bad"}}
        """.data(using: .utf8)!

        let response = try decoder.decode(RpcResponse.self, from: json)
        let outcome = response.outcome

        switch outcome {
        case .success:
            XCTFail("Expected failure")
        case .failure(let err):
            XCTAssertEqual(err.code, -32600)
        }
    }

    // MARK: - AnyCodableValue additional variants

    func testAnyCodableValueDecodesNullResultAsNil() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":null}
        """.data(using: .utf8)!

        let response = try decoder.decode(RpcResponse.self, from: json)
        // JSON null on an optional AnyCodableValue? field decodes as Swift nil
        XCTAssertNil(response.result)
    }

    func testAnyCodableValueDecodesString() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":"hello"}
        """.data(using: .utf8)!

        let response = try decoder.decode(RpcResponse.self, from: json)
        XCTAssertEqual(response.result, .string("hello"))
    }

    func testAnyCodableValueDecodesArray() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":[1,2,3]}
        """.data(using: .utf8)!

        let response = try decoder.decode(RpcResponse.self, from: json)
        XCTAssertEqual(response.result, .array([.number(1), .number(2), .number(3)]))
    }

    func testAnyCodableValueDecodesDictionary() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":{"key":"val"}}
        """.data(using: .utf8)!

        let response = try decoder.decode(RpcResponse.self, from: json)
        XCTAssertEqual(response.result, .dictionary(["key": .string("val")]))
    }

    // MARK: - RpcRequest round-trip with other param types

    func testRpcRequestWithSendMessageParams() throws {
        let request = RpcRequest(id: 2, method: "send_message", params: SendMessageParams(sessionId: "s1", message: "hi"))

        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["method"] as? String, "send_message")
        let p = json["params"] as! [String: Any]
        XCTAssertEqual(p["session_id"] as? String, "s1")
        XCTAssertEqual(p["message"] as? String, "hi")
    }

    func testRpcRequestWithCancelSessionParams() throws {
        let request = RpcRequest(id: 3, method: "cancel_session", params: CancelSessionParams(sessionId: "s2"))

        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["method"] as? String, "cancel_session")
        let p = json["params"] as! [String: Any]
        XCTAssertEqual(p["session_id"] as? String, "s2")
    }

    // MARK: - SidecarMessage with both id and method

    func testSidecarMessageWithBothIdAndMethodDecodesAsResponse() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"method":"event","result":{"ok":true}}
        """.data(using: .utf8)!

        let message = try decoder.decode(SidecarMessage.self, from: json)

        if case .response(let resp) = message {
            XCTAssertEqual(resp.id, 1)
        } else {
            XCTFail("Expected .response when both id and method present, got \(message)")
        }
    }

    // MARK: - AnyCodableValue encoding round-trip

    func testAnyCodableValueEncodesString() throws {
        let value = AnyCodableValue.string("hello")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testAnyCodableValueEncodesNumber() throws {
        let value = AnyCodableValue.number(3.14)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testAnyCodableValueEncodesBool() throws {
        let value = AnyCodableValue.bool(true)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testAnyCodableValueEncodesNestedStructure() throws {
        let value = AnyCodableValue.dictionary([
            "names": .array([.string("a"), .string("b")]),
            "count": .number(2)
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testAnyCodableValueEncodesNull() throws {
        let value = AnyCodableValue.null
        let data = try JSONEncoder().encode(value)
        let str = String(data: data, encoding: .utf8)!
        XCTAssertEqual(str, "null")
    }

    func testAgentEventFailsOnUnknownType() {
        let json = """
        {"type":"unknown_event","data":"foo"}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(AgentEvent.self, from: json))
    }
}
