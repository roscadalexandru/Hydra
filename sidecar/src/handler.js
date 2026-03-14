import { formatResponse, formatError, formatEvent } from "./protocol.js";
import { Session } from "./session.js";

/**
 * Creates a command handler with injected dependencies.
 * @param {Function} queryFn - The SDK query function (or fake for testing)
 * @param {Function} writeLine - Function to write NDJSON output
 * @returns {Function} Async command handler
 */
export function createHandler(queryFn, writeLine) {
  let activeSession = null;

  function requireParam(cmd, name) {
    if (!cmd.params || cmd.params[name] == null) {
      writeLine(
        formatError(cmd.id, -32602, `Missing required param: ${name}`),
      );
      return false;
    }
    return true;
  }

  return async function handleCommand(cmd) {
    switch (cmd.method) {
      case "start_session": {
        if (!requireParam(cmd, "sessionId")) return;

        const { sessionId, prompt, workingDirectory, permissionMode,
          systemPrompt, allowedTools, resumeSessionId } = cmd.params;

        activeSession = new Session(queryFn);

        writeLine(
          formatResponse(cmd.id, { sessionId, status: "started" }),
        );

        const onEvent = (event) => {
          writeLine(formatEvent(sessionId, event));
        };

        await activeSession.start(
          { sessionId, prompt, workingDirectory, permissionMode,
            systemPrompt, allowedTools, resumeSessionId },
          onEvent,
        );
        break;
      }

      case "send_message": {
        if (!requireParam(cmd, "sessionId")) return;

        const { sessionId, message } = cmd.params;

        if (!activeSession) {
          writeLine(
            formatError(cmd.id, -32602, "No active session"),
          );
          return;
        }

        writeLine(
          formatResponse(cmd.id, { sessionId, status: "started" }),
        );

        const onEvent = (event) => {
          writeLine(formatEvent(sessionId, event));
        };

        await activeSession.sendMessage(message, onEvent);
        break;
      }

      case "cancel_session": {
        if (!requireParam(cmd, "sessionId")) return;

        if (activeSession) {
          await activeSession.cancel();
        }

        writeLine(
          formatResponse(cmd.id, {
            sessionId: cmd.params.sessionId,
            status: "cancelled",
          }),
        );
        break;
      }

      case "shutdown": {
        if (activeSession) {
          await activeSession.cancel();
          activeSession = null;
        }
        writeLine(formatResponse(cmd.id, { status: "shutting_down" }));
        return "shutdown";
      }

      default:
        writeLine(
          formatError(cmd.id, -32601, `Unknown method: ${cmd.method}`),
        );
        break;
    }
  };
}
