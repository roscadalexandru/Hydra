import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { createHandler } from "./handler.js";

function fakeQuery(messages) {
  return (_opts) => {
    const gen = (async function* () {
      for (const msg of messages) {
        yield msg;
      }
    })();
    gen.interrupt = async () => {};
    gen.close = () => {};
    return gen;
  };
}

function makeInitMsg(sessionId = "sdk-1") {
  return {
    type: "system",
    subtype: "init",
    session_id: sessionId,
    uuid: "u1",
    tools: [],
    model: "claude-opus-4-6",
    permissionMode: "default",
    claude_code_version: "1.0.0",
    cwd: "/tmp",
    mcp_servers: [],
    apiKeySource: "env",
    slash_commands: [],
    output_style: "default",
    skills: [],
    plugins: [],
  };
}

function makeResultMsg(sessionId = "sdk-1") {
  return {
    type: "result",
    subtype: "success",
    uuid: "u2",
    session_id: sessionId,
    is_error: false,
    duration_ms: 100,
    duration_api_ms: 80,
    total_cost_usd: 0.01,
    num_turns: 1,
    result: "Done",
    usage: {},
  };
}

describe("handler", () => {
  it("start_session returns ack and streams events via writeLine", async () => {
    const queryFn = fakeQuery([makeInitMsg(), makeResultMsg()]);
    const output = [];
    const writeLine = (obj) => output.push(obj);

    const handler = createHandler(queryFn, writeLine);

    await handler({
      jsonrpc: "2.0",
      id: 1,
      method: "start_session",
      params: {
        sessionId: "hydra-1",
        prompt: "Hello",
        workingDirectory: "/tmp",
        permissionMode: "default",
      },
    });

    // Should have: ack response + stream events
    const ack = output.find((o) => o.id === 1);
    assert.ok(ack, "should have an ack response");
    assert.equal(ack.result.sessionId, "hydra-1");
    assert.equal(ack.result.status, "started");

    const streamEvents = output.filter((o) => o.method === "stream_event");
    const sessionStarted = streamEvents.find(
      (e) => e.params.event.type === "session_started",
    );
    assert.ok(sessionStarted, "should have session_started event");
    assert.equal(
      sessionStarted.params.event.sdkSessionId,
      "sdk-1",
    );

    const sessionComplete = streamEvents.find(
      (e) => e.params.event.type === "session_complete",
    );
    assert.ok(sessionComplete, "should have session_complete event");
  });

  it("send_message returns ack and streams events", async () => {
    let callCount = 0;
    const queryFn = (_opts) => {
      callCount++;
      const gen = (async function* () {
        yield makeInitMsg();
        yield makeResultMsg();
      })();
      gen.interrupt = async () => {};
      gen.close = () => {};
      return gen;
    };

    const output = [];
    const writeLine = (obj) => output.push(obj);
    const handler = createHandler(queryFn, writeLine);

    // Start session first
    await handler({
      jsonrpc: "2.0",
      id: 1,
      method: "start_session",
      params: {
        sessionId: "hydra-1",
        prompt: "Hello",
        workingDirectory: "/tmp",
        permissionMode: "default",
      },
    });

    output.length = 0;

    // Now send_message
    await handler({
      jsonrpc: "2.0",
      id: 2,
      method: "send_message",
      params: {
        sessionId: "hydra-1",
        message: "Follow up",
      },
    });

    const ack = output.find((o) => o.id === 2);
    assert.ok(ack, "should have ack for send_message");
    assert.equal(ack.result.sessionId, "hydra-1");
    assert.equal(ack.result.status, "started");
    assert.equal(callCount, 2, "should have called queryFn twice");
  });

  it("cancel_session returns ack and cancels active session", async () => {
    let interruptCalled = false;
    let closeCalled = false;

    const queryFn = (_opts) => {
      const gen = (async function* () {
        yield makeInitMsg();
        await new Promise((resolve) => setTimeout(resolve, 5000));
      })();
      gen.interrupt = async () => {
        interruptCalled = true;
      };
      gen.close = () => {
        closeCalled = true;
      };
      return gen;
    };

    const output = [];
    const writeLine = (obj) => output.push(obj);
    const handler = createHandler(queryFn, writeLine);

    // Start a long-running session (don't await — it would hang)
    handler({
      jsonrpc: "2.0",
      id: 1,
      method: "start_session",
      params: {
        sessionId: "hydra-1",
        prompt: "Long task",
        workingDirectory: "/tmp",
        permissionMode: "default",
      },
    });

    await new Promise((resolve) => setTimeout(resolve, 20));

    await handler({
      jsonrpc: "2.0",
      id: 2,
      method: "cancel_session",
      params: { sessionId: "hydra-1" },
    });

    const ack = output.find((o) => o.id === 2);
    assert.ok(ack);
    assert.equal(ack.result.status, "cancelled");
    assert.ok(interruptCalled, "should have called interrupt");
    assert.ok(closeCalled, "should have called close");
  });

  it("send_message after cancel_session returns no active session error", async () => {
    const queryFn = fakeQuery([makeInitMsg(), makeResultMsg()]);
    const output = [];
    const writeLine = (obj) => output.push(obj);
    const handler = createHandler(queryFn, writeLine);

    await handler({
      jsonrpc: "2.0",
      id: 1,
      method: "start_session",
      params: {
        sessionId: "hydra-1",
        prompt: "Hello",
        workingDirectory: "/tmp",
        permissionMode: "default",
      },
    });

    await handler({
      jsonrpc: "2.0",
      id: 2,
      method: "cancel_session",
      params: { sessionId: "hydra-1" },
    });

    output.length = 0;

    await handler({
      jsonrpc: "2.0",
      id: 3,
      method: "send_message",
      params: { sessionId: "hydra-1", message: "Follow up" },
    });

    const errResp = output.find((o) => o.id === 3);
    assert.ok(errResp.error, "should return error after cancel");
    assert.equal(errResp.error.code, -32602);
    assert.match(errResp.error.message, /no active session/i);
  });

  it("returns error for missing sessionId", async () => {
    const output = [];
    const writeLine = (obj) => output.push(obj);
    const handler = createHandler(fakeQuery([]), writeLine);

    await handler({
      jsonrpc: "2.0",
      id: 1,
      method: "start_session",
      params: {},
    });

    assert.ok(output[0].error);
    assert.equal(output[0].error.code, -32602);
  });

  it("shutdown cancels active session", async () => {
    let closeCalled = false;
    const queryFn = (_opts) => {
      const gen = (async function* () {
        yield makeInitMsg();
        await new Promise((resolve) => setTimeout(resolve, 5000));
      })();
      gen.interrupt = async () => {};
      gen.close = () => {
        closeCalled = true;
      };
      return gen;
    };

    const output = [];
    const writeLine = (obj) => output.push(obj);
    const handler = createHandler(queryFn, writeLine);

    handler({
      jsonrpc: "2.0",
      id: 1,
      method: "start_session",
      params: {
        sessionId: "hydra-1",
        prompt: "Long task",
        workingDirectory: "/tmp",
        permissionMode: "default",
      },
    });

    await new Promise((resolve) => setTimeout(resolve, 20));

    const result = await handler({
      jsonrpc: "2.0",
      id: 99,
      method: "shutdown",
      params: {},
    });

    assert.ok(closeCalled, "shutdown should cancel active session");
    const shutdownAck = output.find((o) => o.id === 99);
    assert.equal(shutdownAck.result.status, "shutting_down");
  });
});
