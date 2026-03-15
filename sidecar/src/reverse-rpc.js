/**
 * Reverse RPC: allows the sidecar to send requests to Swift and await responses.
 *
 * Swift writes reverse-RPC responses to sidecar stdin (same pipe as commands).
 * The main line handler checks incoming messages and routes reverse-RPC responses here.
 */
export class ReverseRpc {
  #nextId = 1;
  #pending = new Map();
  #writeLine;
  #timeoutMs;

  /**
   * @param {Function} writeLine - writes NDJSON to stdout (same as command responses)
   * @param {object} [options]
   * @param {number} [options.timeoutMs=10000] - timeout for each call in milliseconds
   */
  constructor(writeLine, { timeoutMs = 10000 } = {}) {
    this.#writeLine = writeLine;
    this.#timeoutMs = timeoutMs;
  }

  /**
   * Send a reverse RPC request to Swift and await the response.
   * @param {string} method - e.g. "db.create_issue"
   * @param {object} params - request parameters
   * @returns {Promise<any>} - resolved with result, rejected with error
   */
  call(method, params) {
    const id = this.#nextId++;
    const rpcPromise = new Promise((resolve, reject) => {
      this.#pending.set(id, { resolve, reject });
      this.#writeLine({ jsonrpc: "2.0", id, method, params });
    });

    const timeoutPromise = new Promise((_, reject) => {
      setTimeout(() => {
        if (this.#pending.has(id)) {
          this.#pending.delete(id);
          reject(new Error(`Reverse RPC timeout after ${this.#timeoutMs}ms: ${method}`));
        }
      }, this.#timeoutMs);
    });

    return Promise.race([rpcPromise, timeoutPromise]);
  }

  /**
   * Try to handle an incoming message as a reverse RPC response.
   * @param {object} msg - parsed JSON message from stdin
   * @returns {boolean} true if this was a reverse RPC response, false otherwise
   */
  handleResponse(msg) {
    if (msg.id == null || msg.method != null) return false;
    const entry = this.#pending.get(msg.id);
    if (!entry) return false;
    this.#pending.delete(msg.id);

    if (msg.error) {
      entry.reject(new Error(msg.error.message));
    } else {
      entry.resolve(msg.result);
    }
    return true;
  }
}
