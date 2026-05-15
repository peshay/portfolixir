import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";

import type { ApiClient } from "./api-client.js";
import { callTool, listTools } from "./tools.js";

export function createPortfolixirMcpServer(client: ApiClient): McpServer {
  const server = new McpServer({
    name: "portfolixir",
    version: "0.1.0"
  });

  for (const tool of listTools()) {
    server.registerTool(
      tool.name,
      {
        title: tool.title,
        description: tool.description,
        inputSchema: tool.zodSchema
      },
      async (args) => callTool(client, tool.name, args as Record<string, unknown>) as any
    );
  }

  return server;
}
