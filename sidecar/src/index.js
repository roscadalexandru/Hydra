import { createInterface } from "node:readline";
import { parseCommand, formatError, InvalidRequestError } from "./protocol.js";
import { createHandler } from "./handler.js";
import { createQueryFn } from "./query-factory.js";
import { ReverseRpc } from "./reverse-rpc.js";
import { createPmServer } from "./pm-tools.js";

function writeLine(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

const reverseRpc = new ReverseRpc(writeLine);

// workspaceId is passed via HYDRA_WORKSPACE_ID env var, set by Swift before spawning
const workspaceId = Number(process.env.HYDRA_WORKSPACE_ID) || 0;
const pmServer = workspaceId > 0 ? createPmServer(reverseRpc, workspaceId) : null;

const handleCommand = createHandler(createQueryFn(), writeLine, pmServer);

const rl = createInterface({ input: process.stdin });

// Protocol assumes the Swift caller sends commands sequentially and waits
// for each ack before sending the next. No command queue or mutex is used.
rl.on("line", async (line) => {
  try {
    // Check if this is a reverse RPC response (has id but no method)
    const parsed = JSON.parse(line);
    if (parsed.id != null && !parsed.method) {
      reverseRpc.handleResponse(parsed);
      return;
    }

    const cmd = parseCommand(line);
    const result = await handleCommand(cmd);
    if (result === "shutdown") {
      rl.close();
    }
  } catch (err) {
    if (err instanceof InvalidRequestError) {
      writeLine(formatError(null, -32600, err.message));
    } else if (err instanceof SyntaxError) {
      writeLine(formatError(null, -32700, err.message));
    } else {
      writeLine(formatError(null, -32700, err.message));
    }
  }
});

rl.on("close", () => {
  process.exit(0);
});
