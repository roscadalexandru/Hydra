export class Session {
  #queryFn;
  #sdkSessionId;
  #query;
  #config;
  #pmServer;

  /**
   * @param {Function} queryFn
   * @param {object} [pmServer] - MCP server for project management tools
   */
  constructor(queryFn, pmServer) {
    this.#queryFn = queryFn;
    this.#sdkSessionId = null;
    this.#query = null;
    this.#config = null;
    this.#pmServer = pmServer || null;
  }

  async start(config, onEvent) {
    this.#config = config;
    await this.#run(config.prompt, config.resumeSessionId || null, onEvent);
  }

  async sendMessage(message, onEvent) {
    await this.#run(message, this.#sdkSessionId, onEvent);
  }

  async respondToPermission(requestId, approved) {
    const q = this.#query;
    if (!q || typeof q.respondToPermission !== "function") {
      return false;
    }
    await q.respondToPermission(requestId, approved);
    return true;
  }

  async cancel() {
    const q = this.#query;
    this.#query = null;
    if (q) {
      await q.interrupt();
      q.close();
    }
  }

  async #run(prompt, resumeSessionId, onEvent) {
    const mcpServers = {};
    if (this.#pmServer) {
      mcpServers["hydra-pm"] = this.#pmServer;
    }

    const opts = {
      prompt,
      options: {
        cwd: this.#config?.workingDirectory,
        systemPrompt: this.#config?.systemPrompt,
        permissionMode: this.#config?.permissionMode,
        allowedTools: this.#config?.allowedTools,
        ...(Object.keys(mcpServers).length > 0 ? { mcpServers } : {}),
        pathToClaudeCodeExecutable: process.env.CLAUDE_CODE_PATH || undefined,
      },
    };
    if (this.#config?.additionalDirectories?.length) {
      opts.options.addDirs = this.#config.additionalDirectories;
    }
    if (this.#config?.permissionMode === "bypassPermissions") {
      opts.options.allowDangerouslySkipPermissions = true;
    }
    if (resumeSessionId) {
      opts.options.resume = resumeSessionId;
    }

    const q = this.#queryFn(opts);
    this.#query = q;

    try {
      for await (const msg of q) {
        this.#translateMessage(msg, onEvent);
      }
    } catch (err) {
      // If #query is null, cancel() was called — suppress the error.
      // Note: if a real SDK error races with cancel(), it will also be
      // suppressed. This is an acceptable trade-off for the narrow window.
      if (this.#query !== null) {
        onEvent({
          type: "session_error",
          durationMs: 0,
          costUsd: 0,
          error: err.message,
        });
      }
    } finally {
      this.#query = null;
    }
  }

  #translateMessage(msg, onEvent) {
    switch (msg.type) {
      case "system":
        if (msg.subtype === "init") {
          this.#sdkSessionId = msg.session_id;
          onEvent({ type: "session_started", sdkSessionId: msg.session_id });
        } else if (msg.subtype === "permission_request") {
          onEvent({
            type: "permission_request",
            requestId: msg.requestId,
            toolName: msg.toolName,
            description: msg.description,
            affectedPaths: msg.affectedPaths || [],
          });
        }
        break;

      case "assistant":
        if (msg.subtype === "partial") {
          for (const block of msg.message.content) {
            if (block.type === "text") {
              onEvent({ type: "text_delta", delta: block.text });
            }
          }
        } else {
          onEvent({ type: "assistant_message", message: msg.message });
          for (const block of msg.message.content) {
            if (block.type === "tool_use") {
              onEvent({
                type: "tool_use",
                toolUseId: block.id,
                name: block.name,
                input: block.input,
              });
            }
          }
        }
        break;

      case "user":
        for (const block of msg.message.content) {
          if (block.type === "tool_result") {
            onEvent({
              type: "tool_result",
              toolUseId: block.tool_use_id,
              content: block.content,
            });
          }
        }
        break;

      case "result":
        if (msg.is_error) {
          onEvent({
            type: "session_error",
            durationMs: msg.duration_ms,
            costUsd: msg.total_cost_usd,
            error: (msg.errors || []).join("; "),
          });
        } else {
          onEvent({
            type: "session_complete",
            durationMs: msg.duration_ms,
            costUsd: msg.total_cost_usd,
            result: msg.result,
          });
        }
        break;
    }
  }
}
