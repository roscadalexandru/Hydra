import { createInterface } from "node:readline";
import {
  parseCommand,
  formatResponse,
  formatError,
  ParseError,
  InvalidRequestError,
} from "./protocol.js";

const rl = createInterface({ input: process.stdin });

function writeLine(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

function requireParam(cmd, name) {
  if (!cmd.params || cmd.params[name] == null) {
    writeLine(
      formatError(cmd.id, -32602, `Missing required param: ${name}`)
    );
    return false;
  }
  return true;
}

function handleCommand(cmd) {
  switch (cmd.method) {
    case "start_session":
      if (!requireParam(cmd, "sessionId")) return;
      writeLine(
        formatResponse(cmd.id, {
          sessionId: cmd.params.sessionId,
          status: "echo_mode",
        })
      );
      break;

    case "send_message":
      if (!requireParam(cmd, "sessionId")) return;
      writeLine(
        formatResponse(cmd.id, {
          sessionId: cmd.params.sessionId,
          status: "echo_mode",
        })
      );
      break;

    case "cancel_session":
      if (!requireParam(cmd, "sessionId")) return;
      writeLine(
        formatResponse(cmd.id, {
          sessionId: cmd.params.sessionId,
          status: "cancelled",
        })
      );
      break;

    case "shutdown":
      writeLine(formatResponse(cmd.id, { status: "shutting_down" }));
      rl.close();
      break;

    default:
      writeLine(
        formatError(cmd.id, -32601, `Unknown method: ${cmd.method}`)
      );
      break;
  }
}

rl.on("line", (line) => {
  try {
    const cmd = parseCommand(line);
    handleCommand(cmd);
  } catch (err) {
    if (err instanceof InvalidRequestError) {
      writeLine(formatError(null, -32600, err.message));
    } else {
      writeLine(formatError(null, -32700, err.message));
    }
  }
});

rl.on("close", () => {
  process.exit(0);
});
