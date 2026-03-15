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

  /**
   * @param {Function} writeLine - writes NDJSON to stdout (same as command responses)
   */
  constructor(writeLine) {
    this.#writeLine = writeLine;
  }

  /**
   * Send a reverse RPC request to Swift and await the response.
   * @param {string} method - e.g. "db.create_issue"
   * @param {object} params - request parameters
   * @returns {Promise<any>} - resolved with result, rejected with error
   */
  call(method, params) {
    const id = this.#nextId++;
    return new Promise((resolve, reject) => {
      this.#pending.set(id, { resolve, reject });
      this.#writeLine({ jsonrpc: "2.0", id, method, params });
    });
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
