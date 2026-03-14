import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const INDEX_PATH = join(__dirname, "index.js");

/**
 * Send NDJSON commands to sidecar process and collect responses.
 * @param {object[]} commands - Array of command objects to send
 * @param {number} [timeoutMs=3000] - Timeout in milliseconds
 * @returns {Promise<object[]>} Array of parsed response objects
 */
function sendCommands(commands, timeoutMs = 3000) {
  return new Promise((resolve, reject) => {
    const proc = spawn("node", [INDEX_PATH], {
      stdio: ["pipe", "pipe", "pipe"],
    });

    let stdout = "";
    proc.stdout.on("data", (data) => {
      stdout += data.toString();
    });

    let stderr = "";
    proc.stderr.on("data", (data) => {
      stderr += data.toString();
    });

    const timeout = setTimeout(() => {
      proc.kill();
      reject(new Error(`Timed out after ${timeoutMs}ms. stdout: ${stdout}, stderr: ${stderr}`));
    }, timeoutMs);

    proc.on("close", () => {
      clearTimeout(timeout);
      try {
        const lines = stdout.trim().split("\n").filter(Boolean);
        const responses = lines.map((line) => JSON.parse(line));
        resolve(responses);
      } catch (err) {
        reject(new Error(`Failed to parse stdout as JSON: ${err.message}\nstdout: ${stdout}`));
      }
    });

    for (const cmd of commands) {
      proc.stdin.write(JSON.stringify(cmd) + "\n");
    }
    proc.stdin.end();
  });
}

describe("sidecar index", () => {
  it("responds to shutdown with success and exits", async () => {
    const responses = await sendCommands([
      { jsonrpc: "2.0", id: 1, method: "shutdown", params: {} },
    ]);
    assert.equal(responses.length, 1);
    assert.equal(responses[0].jsonrpc, "2.0");
    assert.equal(responses[0].id, 1);
    assert.deepStrictEqual(responses[0].result, { status: "shutting_down" });
  });

  it("returns error for unknown method", async () => {
    const responses = await sendCommands([
      { jsonrpc: "2.0", id: 1, method: "nonexistent", params: {} },
      { jsonrpc: "2.0", id: 2, method: "shutdown", params: {} },
    ]);
    const errResp = responses.find((r) => r.id === 1);
    assert.ok(errResp.error);
    assert.equal(errResp.error.code, -32601);
    assert.match(errResp.error.message, /unknown method/i);
  });

  it("returns error for malformed JSON", async () => {
    const proc = spawn("node", [INDEX_PATH], {
      stdio: ["pipe", "pipe", "pipe"],
    });

    let stdout = "";
    proc.stdout.on("data", (data) => {
      stdout += data.toString();
    });

    const done = new Promise((resolve) => proc.on("close", resolve));

    proc.stdin.write("not valid json\n");
    proc.stdin.write(
      JSON.stringify({ jsonrpc: "2.0", id: 99, method: "shutdown", params: {} }) + "\n"
    );
    proc.stdin.end();

    await done;

    const lines = stdout.trim().split("\n").filter(Boolean);
    const responses = lines.map((l) => JSON.parse(l));

    const errResp = responses.find((r) => r.error && r.id === null);
    assert.ok(errResp, "should have an error response for malformed JSON");
    assert.equal(errResp.error.code, -32700);
  });

  it("acknowledges start_session in echo mode", async () => {
    const responses = await sendCommands([
      {
        jsonrpc: "2.0",
        id: 1,
        method: "start_session",
        params: {
          sessionId: "test-123",
          prompt: "Hello",
          workingDirectory: "/tmp",
          permissionMode: "default",
        },
      },
      { jsonrpc: "2.0", id: 2, method: "shutdown", params: {} },
    ]);
    const ack = responses.find((r) => r.id === 1);
    assert.ok(ack.result, "start_session should return a result");
    assert.equal(ack.result.sessionId, "test-123");
  });

  it("acknowledges send_message in echo mode", async () => {
    const responses = await sendCommands([
      {
        jsonrpc: "2.0",
        id: 1,
        method: "send_message",
        params: { sessionId: "test-123", message: "Hi there" },
      },
      { jsonrpc: "2.0", id: 2, method: "shutdown", params: {} },
    ]);
    const ack = responses.find((r) => r.id === 1);
    assert.ok(ack.result);
    assert.equal(ack.result.sessionId, "test-123");
  });

  it("acknowledges cancel_session in echo mode", async () => {
    const responses = await sendCommands([
      {
        jsonrpc: "2.0",
        id: 1,
        method: "cancel_session",
        params: { sessionId: "test-123" },
      },
      { jsonrpc: "2.0", id: 2, method: "shutdown", params: {} },
    ]);
    const ack = responses.find((r) => r.id === 1);
    assert.ok(ack.result);
    assert.equal(ack.result.sessionId, "test-123");
  });

  it("returns -32600 for valid JSON with missing required fields", async () => {
    const responses = await sendCommands([
      { jsonrpc: "2.0", id: 1, method: "start_session", params: {} },
      { jsonrpc: "2.0", id: 2, method: "shutdown", params: {} },
    ]);
    const errResp = responses.find((r) => r.id === 1);
    assert.ok(errResp.error);
    assert.equal(errResp.error.code, -32602);
    assert.match(errResp.error.message, /sessionId/i);
  });

  it("returns -32602 for send_message with missing sessionId", async () => {
    const responses = await sendCommands([
      { jsonrpc: "2.0", id: 1, method: "send_message", params: { message: "hi" } },
      { jsonrpc: "2.0", id: 2, method: "shutdown", params: {} },
    ]);
    const errResp = responses.find((r) => r.id === 1);
    assert.ok(errResp.error);
    assert.equal(errResp.error.code, -32602);
  });

  it("returns -32602 for cancel_session with null params", async () => {
    const responses = await sendCommands([
      { jsonrpc: "2.0", id: 1, method: "cancel_session", params: null },
      { jsonrpc: "2.0", id: 2, method: "shutdown", params: {} },
    ]);
    const errResp = responses.find((r) => r.id === 1);
    assert.ok(errResp.error);
    assert.equal(errResp.error.code, -32602);
  });

  it("returns -32600 for valid JSON missing jsonrpc field", async () => {
    const proc = spawn("node", [INDEX_PATH], {
      stdio: ["pipe", "pipe", "pipe"],
    });

    let stdout = "";
    proc.stdout.on("data", (data) => {
      stdout += data.toString();
    });

    const done = new Promise((resolve) => proc.on("close", resolve));

    // Valid JSON but missing jsonrpc - should be -32600, not -32700
    proc.stdin.write(JSON.stringify({ id: 1, method: "shutdown", params: {} }) + "\n");
    proc.stdin.write(
      JSON.stringify({ jsonrpc: "2.0", id: 99, method: "shutdown", params: {} }) + "\n"
    );
    proc.stdin.end();

    await done;

    const lines = stdout.trim().split("\n").filter(Boolean);
    const responses = lines.map((l) => JSON.parse(l));

    // parseCommand throws before extracting id, so id is null
    const errResp = responses.find((r) => r.error && r.error.code === -32600);
    assert.ok(errResp, "should have an error response with code -32600");
    assert.equal(errResp.id, null);
  });

  it("exits cleanly when stdin closes without shutdown", async () => {
    const proc = spawn("node", [INDEX_PATH], {
      stdio: ["pipe", "pipe", "pipe"],
    });

    const exitCode = await new Promise((resolve) => {
      proc.on("close", (code) => resolve(code));
      proc.stdin.end();
    });

    assert.equal(exitCode, 0);
  });
});
