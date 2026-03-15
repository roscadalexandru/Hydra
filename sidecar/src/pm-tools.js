import { tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";

/**
 * Creates the project management MCP server with tools backed by reverse RPC.
 * @param {import('./reverse-rpc.js').ReverseRpc} reverseRpc
 * @param {number} workspaceId - scopes all operations to this workspace
 * @returns MCP server instance to pass to Agent SDK session options
 */
export function createPmServer(reverseRpc, workspaceId) {
  const listIssues = tool(
    "list_issues",
    "List issues in the project board. Filter by status, priority, epic, or assignee.",
    {
      status: z.enum(["backlog", "in_progress", "in_review", "done"]).optional()
        .describe("Filter by issue status"),
      priority: z.enum(["urgent", "high", "medium", "low"]).optional()
        .describe("Filter by priority"),
      epicId: z.number().optional()
        .describe("Filter by epic ID"),
      assigneeType: z.enum(["human", "agent"]).optional()
        .describe("Filter by assignee type"),
    },
    async (args) => {
      const result = await reverseRpc.call("db.list_issues", {
        workspaceId,
        ...args,
      });
      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    },
  );

  const getIssue = tool(
    "get_issue",
    "Get full details of a specific issue by its ID.",
    {
      id: z.number().describe("Issue ID"),
    },
    async (args) => {
      const result = await reverseRpc.call("db.get_issue", { workspaceId, ...args });
      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    },
  );

  const createIssue = tool(
    "create_issue",
    "Create a new issue on the project board.",
    {
      title: z.string().describe("Issue title"),
      description: z.string().optional().describe("Issue description"),
      status: z.enum(["backlog", "in_progress", "in_review", "done"]).optional()
        .describe("Initial status (default: backlog)"),
      priority: z.enum(["urgent", "high", "medium", "low"]).optional()
        .describe("Priority (default: medium)"),
      epicId: z.number().optional()
        .describe("Epic ID to associate the issue with"),
      assigneeType: z.enum(["human", "agent"]).optional()
        .describe("Assignee type (default: human)"),
      assigneeName: z.string().optional()
        .describe("Name of the assignee"),
    },
    async (args) => {
      const result = await reverseRpc.call("db.create_issue", {
        workspaceId,
        ...args,
      });
      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    },
  );

  const updateIssue = tool(
    "update_issue",
    "Update an existing issue. Only provided fields are changed.",
    {
      id: z.number().describe("Issue ID to update"),
      title: z.string().optional().describe("New title"),
      description: z.string().optional().describe("New description"),
      status: z.enum(["backlog", "in_progress", "in_review", "done"]).optional()
        .describe("New status"),
      priority: z.enum(["urgent", "high", "medium", "low"]).optional()
        .describe("New priority"),
      epicId: z.number().optional()
        .describe("New epic ID"),
      assigneeType: z.enum(["human", "agent"]).optional()
        .describe("New assignee type"),
      assigneeName: z.string().optional()
        .describe("New assignee name"),
    },
    async (args) => {
      const result = await reverseRpc.call("db.update_issue", { workspaceId, ...args });
      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    },
  );

  const deleteIssue = tool(
    "delete_issue",
    "Delete an issue from the project board.",
    {
      id: z.number().describe("Issue ID to delete"),
    },
    async (args) => {
      const result = await reverseRpc.call("db.delete_issue", { workspaceId, ...args });
      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    },
  );

  const listEpics = tool(
    "list_epics",
    "List all epics in the workspace.",
    {},
    async () => {
      const result = await reverseRpc.call("db.list_epics", { workspaceId });
      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    },
  );

  const createEpic = tool(
    "create_epic",
    "Create a new epic to group related issues.",
    {
      title: z.string().describe("Epic title"),
      description: z.string().optional().describe("Epic description"),
    },
    async (args) => {
      const result = await reverseRpc.call("db.create_epic", {
        workspaceId,
        ...args,
      });
      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    },
  );

  const updateEpic = tool(
    "update_epic",
    "Update an existing epic. Only provided fields are changed.",
    {
      id: z.number().describe("Epic ID to update"),
      title: z.string().optional().describe("New title"),
      description: z.string().optional().describe("New description"),
    },
    async (args) => {
      const result = await reverseRpc.call("db.update_epic", { workspaceId, ...args });
      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    },
  );

  const deleteEpic = tool(
    "delete_epic",
    "Delete an epic from the workspace.",
    {
      id: z.number().describe("Epic ID to delete"),
    },
    async (args) => {
      const result = await reverseRpc.call("db.delete_epic", { workspaceId, ...args });
      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    },
  );

  return createSdkMcpServer("hydra-pm", {
    tools: [
      listIssues, getIssue, createIssue, updateIssue, deleteIssue,
      listEpics, createEpic, updateEpic, deleteEpic,
    ],
  });
}
