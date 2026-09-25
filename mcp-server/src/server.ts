import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  type CallToolResult,
  type Tool
} from "@modelcontextprotocol/sdk/types.js";
import { ZodError } from "zod";

import type { ApiClient } from "./api-client.js";
import { callTool, listTools } from "./tools.js";

/**
 * The companion's MCP server. It publishes each tool's own definition (E25
 * S7, F21): the JSON Schema the tests pin, its property descriptions and
 * closed objects included, rather than the schema the SDK would derive from
 * the validator, which carries neither. The validator still runs before any
 * API request (`callTool`), and a test holds it to the properties the
 * published schema names.
 */
export function createPortfolixirMcpServer(client: ApiClient): McpServer {
  const server = new McpServer(
    { name: "portfolixir", version: "0.1.0" },
    { capabilities: { tools: {} } }
  );

  server.server.setRequestHandler(ListToolsRequestSchema, () => ({
    tools: listTools().map(
      (tool): Tool => ({
        name: tool.name,
        title: tool.title,
        description: tool.description,
        inputSchema: tool.inputSchema as Tool["inputSchema"]
      })
    )
  }));

  server.server.setRequestHandler(CallToolRequestSchema, (request) =>
    answer(client, request.params.name, request.params.arguments ?? {})
  );

  return server;
}

/**
 * One call, answered as a tool result whatever happens: a refused argument, an
 * unknown tool and an API error are tool errors the agent reads, and an API
 * answer without a JSON object (a delete's empty 204) is a result without
 * structured content, which the protocol only admits as an object.
 */
async function answer(
  client: ApiClient,
  name: string,
  args: Record<string, unknown>
): Promise<CallToolResult> {
  if (!listTools().some((tool) => tool.name === name)) {
    return toolError(`Tool ${name} not found`);
  }

  try {
    const result = await callTool(client, name, args);

    return isObject(result.structuredContent)
      ? { content: result.content, structuredContent: result.structuredContent }
      : { content: result.content };
  } catch (error) {
    return toolError(errorText(name, error));
  }
}

function toolError(text: string): CallToolResult {
  return { content: [{ type: "text", text }], isError: true };
}

function errorText(name: string, error: unknown): string {
  if (error instanceof ZodError) {
    const issues = error.issues.map((issue) =>
      issue.path.length > 0 ? `${issue.message} at ${issue.path.join(".")}` : issue.message
    );

    return `Input validation error: Invalid arguments for tool ${name}: ${issues.join("; ")}`;
  }

  return error instanceof Error ? error.message : String(error);
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
