/**
 * Creates a fake query function that yields the given messages.
 * Returns an async generator with interrupt() and close() methods.
 */
export function fakeQuery(messages) {
  return (_opts) => {
    const gen = (async function* () {
      for (const msg of messages) {
        yield msg;
      }
    })();
    gen.interrupt = async () => {};
    gen.close = () => {};
    gen.respondToPermission = async () => {};
    return gen;
  };
}

export function makeInitMsg(sessionId = "sdk-1") {
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

export function makeResultMsg(sessionId = "sdk-1") {
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

/**
 * Creates a fake query that yields init, then blocks until resolved externally.
 * Returns { queryFn, resolve, interruptCalled, closeCalled } for test synchronization.
 */
export function createBlockingQuery() {
  let resolveBlock;
  let interruptCalled = false;
  let closeCalled = false;
  let lastPermissionResponse = null;

  const queryFn = (_opts) => {
    const gen = (async function* () {
      yield makeInitMsg();
      await new Promise((resolve) => { resolveBlock = resolve; });
    })();
    gen.interrupt = async () => { interruptCalled = true; };
    gen.close = () => { closeCalled = true; };
    gen.respondToPermission = async (requestId, approved) => {
      lastPermissionResponse = { requestId, approved };
    };
    return gen;
  };

  return {
    queryFn,
    unblock: () => resolveBlock?.(),
    get interruptCalled() { return interruptCalled; },
    get closeCalled() { return closeCalled; },
    get lastPermissionResponse() { return lastPermissionResponse; },
  };
}
