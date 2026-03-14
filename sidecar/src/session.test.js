import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { Session } from "./session.js";
import { fakeQuery, makeInitMsg } from "./test-helpers.js";

describe("Session", () => {
  describe("start()", () => {
    it("emits session_started when SDK sends system init message", async () => {
      const initMsg = {
        type: "system",
        subtype: "init",
        session_id: "sdk-session-abc",
        uuid: "uuid-1",
        tools: ["Read", "Write"],
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

      const queryFn = fakeQuery([initMsg]);
      const session = new Session(queryFn);

      const events = [];
      await session.start(
        {
          sessionId: "hydra-123",
          prompt: "Hello",
          workingDirectory: "/tmp",
          permissionMode: "default",
        },
        (event) => events.push(event),
      );

      assert.equal(events.length, 1);
      assert.equal(events[0].type, "session_started");
      assert.equal(events[0].sdkSessionId, "sdk-session-abc");
    });

    it("passes resumeSessionId to query options", async () => {
      let capturedOpts = null;

      const queryFn = (opts) => {
        capturedOpts = opts;
        const gen = (async function* () {
          yield makeInitMsg();
        })();
        gen.interrupt = async () => {};
        gen.close = () => {};
        return gen;
      };

      const session = new Session(queryFn);
      await session.start(
        {
          sessionId: "h-1",
          prompt: "Resume",
          workingDirectory: "/tmp",
          permissionMode: "default",
          resumeSessionId: "prev-sdk-session",
        },
        () => {},
      );

      assert.equal(capturedOpts.options.resume, "prev-sdk-session");
    });

    it("does not set allowDangerouslySkipPermissions when not bypass mode", async () => {
      let capturedOpts = null;

      const queryFn = (opts) => {
        capturedOpts = opts;
        const gen = (async function* () {
          yield makeInitMsg();
        })();
        gen.interrupt = async () => {};
        gen.close = () => {};
        return gen;
      };

      const session = new Session(queryFn);
      await session.start(
        {
          sessionId: "h-1",
          prompt: "Hi",
          workingDirectory: "/tmp",
          permissionMode: "default",
        },
        () => {},
      );

      assert.equal(capturedOpts.options.allowDangerouslySkipPermissions, undefined);
    });

    it("emits assistant_message for assistant type messages", async () => {
      const messages = [
        makeInitMsg(),
        {
          type: "assistant",
          uuid: "u2",
          session_id: "sdk-1",
          message: {
            content: [{ type: "text", text: "Hello there!" }],
          },
          parent_tool_use_id: null,
        },
      ];

      const queryFn = fakeQuery(messages);
      const session = new Session(queryFn);

      const events = [];
      await session.start(
        {
          sessionId: "h-1",
          prompt: "Hi",
          workingDirectory: "/tmp",
          permissionMode: "default",
        },
        (event) => events.push(event),
      );

      const assistantEvents = events.filter(
        (e) => e.type === "assistant_message",
      );
      assert.equal(assistantEvents.length, 1);
      assert.deepStrictEqual(assistantEvents[0].message.content, [
        { type: "text", text: "Hello there!" },
      ]);
    });

    it("emits tool_use and tool_result for tool content blocks", async () => {
      const messages = [
        makeInitMsg(),
        {
          type: "assistant",
          uuid: "u2",
          session_id: "sdk-1",
          message: {
            content: [
              {
                type: "tool_use",
                id: "tool-1",
                name: "Read",
                input: { file_path: "/tmp/foo.txt" },
              },
            ],
          },
          parent_tool_use_id: null,
        },
        {
          type: "user",
          uuid: "u3",
          session_id: "sdk-1",
          message: {
            content: [
              {
                type: "tool_result",
                tool_use_id: "tool-1",
                content: "file contents here",
              },
            ],
          },
          parent_tool_use_id: null,
          tool_use_result: "file contents here",
        },
      ];

      const queryFn = fakeQuery(messages);
      const session = new Session(queryFn);

      const events = [];
      await session.start(
        {
          sessionId: "h-1",
          prompt: "Read a file",
          workingDirectory: "/tmp",
          permissionMode: "default",
        },
        (event) => events.push(event),
      );

      const toolUseEvents = events.filter((e) => e.type === "tool_use");
      assert.equal(toolUseEvents.length, 1);
      assert.equal(toolUseEvents[0].toolUseId, "tool-1");
      assert.equal(toolUseEvents[0].name, "Read");

      const toolResultEvents = events.filter((e) => e.type === "tool_result");
      assert.equal(toolResultEvents.length, 1);
      assert.equal(toolResultEvents[0].toolUseId, "tool-1");
    });

    it("emits text_delta for partial assistant messages", async () => {
      const messages = [
        makeInitMsg(),
        {
          type: "assistant",
          subtype: "partial",
          uuid: "u2",
          session_id: "sdk-1",
          message: {
            content: [{ type: "text", text: "Hel" }],
          },
          parent_tool_use_id: null,
        },
      ];

      const queryFn = fakeQuery(messages);
      const session = new Session(queryFn);

      const events = [];
      await session.start(
        {
          sessionId: "h-1",
          prompt: "Hi",
          workingDirectory: "/tmp",
          permissionMode: "default",
        },
        (event) => events.push(event),
      );

      const deltas = events.filter((e) => e.type === "text_delta");
      assert.equal(deltas.length, 1);
      assert.equal(deltas[0].delta, "Hel");
    });

    it("emits session_complete on successful result message", async () => {
      const messages = [
        makeInitMsg(),
        {
          type: "result",
          subtype: "success",
          uuid: "u2",
          session_id: "sdk-1",
          is_error: false,
          duration_ms: 1500,
          duration_api_ms: 1200,
          total_cost_usd: 0.05,
          num_turns: 3,
          result: "Done!",
          usage: { input_tokens: 100, output_tokens: 50 },
        },
      ];

      const queryFn = fakeQuery(messages);
      const session = new Session(queryFn);

      const events = [];
      await session.start(
        {
          sessionId: "h-1",
          prompt: "Do stuff",
          workingDirectory: "/tmp",
          permissionMode: "default",
        },
        (event) => events.push(event),
      );

      const complete = events.find((e) => e.type === "session_complete");
      assert.ok(complete, "should emit session_complete");
      assert.equal(complete.durationMs, 1500);
      assert.equal(complete.costUsd, 0.05);
      assert.equal(complete.result, "Done!");
    });

    it("emits session_error on error result message", async () => {
      const messages = [
        makeInitMsg(),
        {
          type: "result",
          subtype: "error_during_execution",
          uuid: "u2",
          session_id: "sdk-1",
          is_error: true,
          duration_ms: 500,
          duration_api_ms: 400,
          total_cost_usd: 0.01,
          num_turns: 1,
          errors: ["Something went wrong"],
          usage: { input_tokens: 50, output_tokens: 10 },
        },
      ];

      const queryFn = fakeQuery(messages);
      const session = new Session(queryFn);

      const events = [];
      await session.start(
        {
          sessionId: "h-1",
          prompt: "Fail",
          workingDirectory: "/tmp",
          permissionMode: "default",
        },
        (event) => events.push(event),
      );

      const errEvent = events.find((e) => e.type === "session_error");
      assert.ok(errEvent, "should emit session_error");
      assert.equal(errEvent.durationMs, 500);
      assert.equal(errEvent.costUsd, 0.01);
      assert.deepStrictEqual(errEvent.errors, ["Something went wrong"]);
    });

    it("emits session_error when SDK throws an exception", async () => {
      const queryFn = (_opts) => {
        const gen = (async function* () {
          throw new Error("SDK crashed");
        })();
        gen.interrupt = async () => {};
        gen.close = () => {};
        return gen;
      };

      const session = new Session(queryFn);

      const events = [];
      await session.start(
        {
          sessionId: "h-1",
          prompt: "Crash",
          workingDirectory: "/tmp",
          permissionMode: "default",
        },
        (event) => events.push(event),
      );

      const errEvent = events.find((e) => e.type === "session_error");
      assert.ok(errEvent, "should emit session_error on exception");
      assert.match(errEvent.errors[0], /SDK crashed/);
    });
  });

  describe("sendMessage()", () => {
    it("calls query with resume option using captured sdkSessionId", async () => {
      let capturedOpts = null;

      const queryFn = (opts) => {
        capturedOpts = opts;
        const gen = (async function* () {
          yield makeInitMsg();
          yield {
            type: "result",
            subtype: "success",
            uuid: "u2",
            session_id: "sdk-1",
            is_error: false,
            duration_ms: 100,
            duration_api_ms: 80,
            total_cost_usd: 0.01,
            num_turns: 1,
            result: "OK",
            usage: {},
          };
        })();
        gen.interrupt = async () => {};
        gen.close = () => {};
        return gen;
      };

      const session = new Session(queryFn);
      const events = [];
      const onEvent = (event) => events.push(event);

      // First call: start session to capture sdkSessionId
      await session.start(
        {
          sessionId: "h-1",
          prompt: "Hello",
          workingDirectory: "/tmp",
          permissionMode: "default",
        },
        onEvent,
      );

      // Reset to track second call
      capturedOpts = null;
      events.length = 0;

      await session.sendMessage("Follow up question", onEvent);

      assert.ok(capturedOpts, "should have called queryFn again");
      assert.equal(capturedOpts.prompt, "Follow up question");
      assert.equal(capturedOpts.options.resume, "sdk-1");
    });
  });

  describe("cancel()", () => {
    it("calls interrupt() and close() on the active query", async () => {
      let interruptCalled = false;
      let closeCalled = false;
      let resolveBlock;

      const queryFn = (_opts) => {
        const gen = (async function* () {
          yield makeInitMsg();
          await new Promise((resolve) => { resolveBlock = resolve; });
        })();
        gen.interrupt = async () => { interruptCalled = true; };
        gen.close = () => { closeCalled = true; };
        return gen;
      };

      const session = new Session(queryFn);
      const events = [];

      // Start session but don't await it (it would block)
      const startPromise = session.start(
        {
          sessionId: "h-1",
          prompt: "Long task",
          workingDirectory: "/tmp",
          permissionMode: "default",
        },
        (event) => events.push(event),
      );

      // Wait for the generator to yield the init message
      await new Promise(setImmediate);

      await session.cancel();

      assert.ok(interruptCalled, "should have called interrupt()");
      assert.ok(closeCalled, "should have called close()");
    });

    it("is safe to call after session completes", async () => {
      const queryFn = fakeQuery([makeInitMsg()]);
      const session = new Session(queryFn);

      await session.start(
        {
          sessionId: "h-1",
          prompt: "Quick",
          workingDirectory: "/tmp",
          permissionMode: "default",
        },
        () => {},
      );

      // Should not throw — #query is cleared after run completes
      await session.cancel();
    });
  });
});
