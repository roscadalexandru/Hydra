import { createInterface } from "node:readline";
import { parseCommand, formatResponse, formatError } from "./protocol.js";

const rl = createInterface({ input: process.stdin });

function writeLine(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

function handleCommand(cmd) {
  switch (cmd.method) {
    case "start_session":
      writeLine(
        formatResponse(cmd.id, {
          sessionId: cmd.params.sessionId,
          status: "echo_mode",
        })
      );
      break;

    case "send_message":
      writeLine(
        formatResponse(cmd.id, {
          sessionId: cmd.params.sessionId,
          status: "echo_mode",
        })
      );
      break;

    case "cancel_session":
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
    writeLine(formatError(null, -32700, err.message));
  }
});

rl.on("close", () => {
  process.exit(0);
});
