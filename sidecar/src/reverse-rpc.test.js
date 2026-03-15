import { describe, it, mock } from "node:test";
import assert from "node:assert/strict";
import { ReverseRpc } from "./reverse-rpc.js";

describe("ReverseRpc", () => {
  it("sends a JSON-RPC request via writeLine", async () => {
    const lines = [];
    const rpc = new ReverseRpc((obj) => lines.push(obj), { timeoutMs: 100 });

    const promise = rpc.call("db.create_issue", { title: "Bug" });

    assert.equal(lines.length, 1);
    assert.equal(lines[0].jsonrpc, "2.0");
    assert.equal(lines[0].method, "db.create_issue");
    assert.deepEqual(lines[0].params, { title: "Bug" });
    assert.equal(typeof lines[0].id, "number");

    // Resolve to avoid unhandled rejection from timeout
    rpc.handleResponse({ id: lines[0].id, result: {} });
    await promise;
  });

  it("resolves when a matching success response arrives", async () => {
    const lines = [];
    const rpc = new ReverseRpc((obj) => lines.push(obj));

    const promise = rpc.call("db.get_issue", { id: 1 });

    // Simulate Swift sending back a response
    const requestId = lines[0].id;
    rpc.handleResponse({ id: requestId, result: { id: 1, title: "Bug" } });

    const result = await promise;
    assert.deepEqual(result, { id: 1, title: "Bug" });
  });

  it("rejects when a matching error response arrives", async () => {
    const lines = [];
    const rpc = new ReverseRpc((obj) => lines.push(obj));

    const promise = rpc.call("db.get_issue", { id: 999 });

    const requestId = lines[0].id;
    rpc.handleResponse({ id: requestId, error: { code: -1, message: "Not found" } });

    await assert.rejects(promise, { message: "Not found" });
  });

  it("returns false for unrelated messages", () => {
    const rpc = new ReverseRpc(() => {});

    // Message with method (a command, not a response)
    assert.equal(rpc.handleResponse({ id: 1, method: "start_session" }), false);

    // Message without id
    assert.equal(rpc.handleResponse({ method: "event" }), false);

    // Response with unknown id
    assert.equal(rpc.handleResponse({ id: 999, result: {} }), false);
  });

  it("rejects with timeout when no response arrives", async () => {
    const rpc = new ReverseRpc(() => {}, { timeoutMs: 50 });

    const promise = rpc.call("db.slow_method", {});
    await assert.rejects(promise, { message: /timeout/i });
  });

  it("uses incrementing IDs", async () => {
    const lines = [];
    const rpc = new ReverseRpc((obj) => lines.push(obj), { timeoutMs: 100 });

    const promises = [
      rpc.call("db.a", {}),
      rpc.call("db.b", {}),
      rpc.call("db.c", {}),
    ];

    assert.equal(lines[0].id, 1);
    assert.equal(lines[1].id, 2);
    assert.equal(lines[2].id, 3);

    // Resolve all to avoid unhandled rejections
    for (const line of lines) {
      rpc.handleResponse({ id: line.id, result: {} });
    }
    await Promise.all(promises);
  });
});
