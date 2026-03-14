/**
 * Parse a JSON-RPC command from a line of text.
 * @param {string} line - Raw JSON string
 * @returns {object} Parsed command with jsonrpc, id, method, params
 */
export function parseCommand(line) {
  let parsed;
  try {
    parsed = JSON.parse(line);
  } catch {
    throw new Error("Invalid JSON: could not parse input");
  }

  if (parsed.jsonrpc !== "2.0") {
    throw new Error('Missing or invalid "jsonrpc" field');
  }
  if (typeof parsed.id !== "number") {
    throw new Error('Missing or invalid "id" field');
  }
  if (typeof parsed.method !== "string") {
    throw new Error('Missing or invalid "method" field');
  }

  return parsed;
}

/**
 * Format a success response.
 * @param {number} id - Request ID to correlate with
 * @param {*} result - Result payload
 */
export function formatResponse(id, result) {
  return { jsonrpc: "2.0", id, result };
}

/**
 * Format an error response.
 * @param {number} id - Request ID to correlate with
 * @param {number} code - JSON-RPC error code
 * @param {string} message - Error description
 */
export function formatError(id, code, message) {
  return { jsonrpc: "2.0", id, error: { code, message } };
}

/**
 * Format a streaming event notification (no id).
 * @param {string} sessionId - Session this event belongs to
 * @param {object} event - Event payload with type field
 */
export function formatEvent(sessionId, event) {
  return {
    jsonrpc: "2.0",
    method: "stream_event",
    params: { sessionId, event },
  };
}
