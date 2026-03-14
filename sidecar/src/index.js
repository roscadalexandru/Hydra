import { createInterface } from "node:readline";
import { parseCommand, formatError, InvalidRequestError } from "./protocol.js";
import { createHandler } from "./handler.js";
import { createQueryFn } from "./query-factory.js";

const rl = createInterface({ input: process.stdin });

function writeLine(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

const handleCommand = createHandler(createQueryFn(), writeLine);

rl.on("line", async (line) => {
  try {
    const cmd = parseCommand(line);
    const result = await handleCommand(cmd);
    if (result === "shutdown") {
      rl.close();
    }
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
