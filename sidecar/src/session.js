export class Session {
  #queryFn;
  #sdkSessionId;
  #query;
  #config;

  constructor(queryFn) {
    this.#queryFn = queryFn;
    this.#sdkSessionId = null;
    this.#query = null;
    this.#config = null;
  }

  async start(config, onEvent) {
    this.#config = config;
    await this.#run(config.prompt, null, onEvent);
  }

  async sendMessage(message, onEvent) {
    await this.#run(message, this.#sdkSessionId, onEvent);
  }

  async cancel() {
    if (this.#query) {
      await this.#query.interrupt();
      this.#query.close();
    }
  }

  async #run(prompt, resumeSessionId, onEvent) {
    const opts = {
      prompt,
      options: {
        cwd: this.#config?.workingDirectory,
        systemPrompt: this.#config?.systemPrompt,
        permissionMode: this.#config?.permissionMode,
        allowedTools: this.#config?.allowedTools,
        allowDangerouslySkipPermissions:
          this.#config?.permissionMode === "bypassPermissions",
      },
    };
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
      onEvent({
        type: "session_error",
        durationMs: 0,
        costUsd: 0,
        errors: [err.message],
      });
    }
  }

  #translateMessage(msg, onEvent) {
    switch (msg.type) {
      case "system":
        if (msg.subtype === "init") {
          this.#sdkSessionId = msg.session_id;
          onEvent({ type: "session_started", sdkSessionId: msg.session_id });
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
            errors: msg.errors || [],
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
