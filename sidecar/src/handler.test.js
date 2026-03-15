import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { createHandler } from "./handler.js";
import { fakeQuery, makeInitMsg, makeResultMsg, createBlockingQuery } from "./test-helpers.js";

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

  it("send_message returns ack with accepted status and streams events", async () => {
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
    assert.equal(ack.result.status, "accepted");
    assert.equal(callCount, 2, "should have called queryFn twice");
  });

  it("send_message with mismatched sessionId returns error", async () => {
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

    output.length = 0;

    await handler({
      jsonrpc: "2.0",
      id: 2,
      method: "send_message",
      params: { sessionId: "wrong-id", message: "Hi" },
    });

    const errResp = output.find((o) => o.id === 2);
    assert.ok(errResp.error, "should return error for mismatched sessionId");
    assert.equal(errResp.error.code, -32602);
    assert.match(errResp.error.message, /mismatch/i);
  });

  it("cancel_session returns ack and cancels active session", async () => {
    const blocking = createBlockingQuery();

    const output = [];
    const writeLine = (obj) => output.push(obj);
    const handler = createHandler(blocking.queryFn, writeLine);

    // Start a long-running session (don't await — it would block)
    const startPromise = handler({
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

    // Wait for the init message to be yielded
    await new Promise(setImmediate);

    await handler({
      jsonrpc: "2.0",
      id: 2,
      method: "cancel_session",
      params: { sessionId: "hydra-1" },
    });

    const ack = output.find((o) => o.id === 2);
    assert.ok(ack);
    assert.equal(ack.result.status, "cancelled");
    assert.ok(blocking.interruptCalled, "should have called interrupt");
    assert.ok(blocking.closeCalled, "should have called close");
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

  it("start_session cancels existing session before starting new one", async () => {
    let callCount = 0;
    let firstInterruptCalled = false;
    let firstCloseCalled = false;
    let resolveFirst;

    const queryFn = (_opts) => {
      callCount++;
      if (callCount === 1) {
        // First call: blocks until resolved externally
        const gen = (async function* () {
          yield makeInitMsg();
          await new Promise((resolve) => { resolveFirst = resolve; });
        })();
        gen.interrupt = async () => { firstInterruptCalled = true; };
        gen.close = () => { firstCloseCalled = true; };
        return gen;
      }
      // Second call: completes immediately
      const gen = (async function* () {
        yield makeInitMsg("sdk-2");
        yield makeResultMsg("sdk-2");
      })();
      gen.interrupt = async () => {};
      gen.close = () => {};
      return gen;
    };

    const output = [];
    const writeLine = (obj) => output.push(obj);
    const handler = createHandler(queryFn, writeLine);

    // Start first session (don't await — it blocks)
    handler({
      jsonrpc: "2.0",
      id: 1,
      method: "start_session",
      params: {
        sessionId: "hydra-1",
        prompt: "First",
        workingDirectory: "/tmp",
        permissionMode: "default",
      },
    });

    await new Promise(setImmediate);
    assert.ok(!firstInterruptCalled, "should not have interrupted yet");

    // Start second session — should cancel the first
    await handler({
      jsonrpc: "2.0",
      id: 2,
      method: "start_session",
      params: {
        sessionId: "hydra-2",
        prompt: "Second",
        workingDirectory: "/tmp",
        permissionMode: "default",
      },
    });

    assert.ok(firstInterruptCalled, "should have cancelled first session");
    assert.ok(firstCloseCalled, "should have closed first session");
    assert.equal(callCount, 2);
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
    const blocking = createBlockingQuery();

    const output = [];
    const writeLine = (obj) => output.push(obj);
    const handler = createHandler(blocking.queryFn, writeLine);

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

    await new Promise(setImmediate);

    await handler({
      jsonrpc: "2.0",
      id: 99,
      method: "shutdown",
      params: {},
    });

    assert.ok(blocking.closeCalled, "shutdown should cancel active session");
    const shutdownAck = output.find((o) => o.id === 99);
    assert.equal(shutdownAck.result.status, "shutting_down");
  });

  it("permission_response forwards to active session", async () => {
    const blocking = createBlockingQuery();

    const output = [];
    const writeLine = (obj) => output.push(obj);
    const handler = createHandler(blocking.queryFn, writeLine);

    // Start a session
    handler({
      jsonrpc: "2.0",
      id: 1,
      method: "start_session",
      params: {
        sessionId: "hydra-1",
        prompt: "Write something",
        workingDirectory: "/tmp",
        permissionMode: "default",
      },
    });

    await new Promise(setImmediate);

    await handler({
      jsonrpc: "2.0",
      id: 2,
      method: "permission_response",
      params: {
        sessionId: "hydra-1",
        requestId: "req-1",
        approved: true,
      },
    });

    const ack = output.find((o) => o.id === 2);
    assert.ok(ack, "should have ack for permission_response");
    assert.equal(ack.result.status, "accepted");
  });

  it("permission_response without active session returns error", async () => {
    const output = [];
    const writeLine = (obj) => output.push(obj);
    const handler = createHandler(fakeQuery([]), writeLine);

    await handler({
      jsonrpc: "2.0",
      id: 1,
      method: "permission_response",
      params: {
        sessionId: "hydra-1",
        requestId: "req-1",
        approved: true,
      },
    });

    const errResp = output.find((o) => o.id === 1);
    assert.ok(errResp.error, "should return error when no active session");
  });

  it("start_session passes additionalDirectories to session config", async () => {
    let capturedConfig = null;

    const queryFn = (opts) => {
      capturedConfig = opts;
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

    await handler({
      jsonrpc: "2.0",
      id: 1,
      method: "start_session",
      params: {
        sessionId: "hydra-1",
        prompt: "Hello",
        workingDirectory: "/project-a",
        permissionMode: "default",
        additionalDirectories: ["/project-b"],
      },
    });

    assert.deepStrictEqual(capturedConfig.options.addDirs, ["/project-b"]);
  });
});
