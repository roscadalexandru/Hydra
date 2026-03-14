import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { parseCommand, formatResponse, formatError, formatEvent } from "./protocol.js";

describe("parseCommand", () => {
  it("parses a valid shutdown command", () => {
    const line = '{"jsonrpc":"2.0","id":1,"method":"shutdown","params":{}}';
    const result = parseCommand(line);
    assert.deepStrictEqual(result, {
      jsonrpc: "2.0",
      id: 1,
      method: "shutdown",
      params: {},
    });
  });

  it("parses a valid start_session command", () => {
    const line = JSON.stringify({
      jsonrpc: "2.0",
      id: 2,
      method: "start_session",
      params: {
        sessionId: "abc-123",
        prompt: "Hello",
        workingDirectory: "/tmp",
        permissionMode: "default",
      },
    });
    const result = parseCommand(line);
    assert.equal(result.method, "start_session");
    assert.equal(result.params.sessionId, "abc-123");
  });

  it("throws on malformed JSON", () => {
    assert.throws(() => parseCommand("not json{"), {
      message: /Invalid JSON/,
    });
  });

  it("throws when jsonrpc field is missing", () => {
    const line = JSON.stringify({ id: 1, method: "shutdown", params: {} });
    assert.throws(() => parseCommand(line), {
      message: /jsonrpc/,
    });
  });

  it("throws when method field is missing", () => {
    const line = JSON.stringify({ jsonrpc: "2.0", id: 1, params: {} });
    assert.throws(() => parseCommand(line), {
      message: /method/,
    });
  });

  it("throws when id field is missing", () => {
    const line = JSON.stringify({
      jsonrpc: "2.0",
      method: "shutdown",
      params: {},
    });
    assert.throws(() => parseCommand(line), {
      message: /id/,
    });
  });
});

describe("formatResponse", () => {
  it("formats a success response", () => {
    const result = formatResponse(1, { status: "ok" });
    assert.deepStrictEqual(result, {
      jsonrpc: "2.0",
      id: 1,
      result: { status: "ok" },
    });
  });
});

describe("formatError", () => {
  it("formats an error response", () => {
    const result = formatError(1, -32601, "Method not found");
    assert.deepStrictEqual(result, {
      jsonrpc: "2.0",
      id: 1,
      error: { code: -32601, message: "Method not found" },
    });
  });
});

describe("formatEvent", () => {
  it("formats a stream event notification", () => {
    const event = { type: "session_started", sdkSessionId: "sdk-123" };
    const result = formatEvent("session-1", event);
    assert.deepStrictEqual(result, {
      jsonrpc: "2.0",
      method: "stream_event",
      params: {
        sessionId: "session-1",
        event: { type: "session_started", sdkSessionId: "sdk-123" },
      },
    });
  });

  it("has no id field (notification)", () => {
    const result = formatEvent("s1", { type: "text_delta", delta: "hi" });
    assert.equal(result.id, undefined);
  });
});
