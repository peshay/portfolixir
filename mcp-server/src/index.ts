#!/usr/bin/env node

import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

import { createApiClient } from "./api-client.js";
import { startHttpServer } from "./http.js";
import { createPortfolixirMcpServer } from "./server.js";

const apiBaseUrl = process.env.PORTFOLIXIR_API_BASE_URL ?? "http://127.0.0.1:4000";
const apiToken = process.env.PORTFOLIXIR_API_TOKEN;

if (!apiToken) {
  console.error("PORTFOLIXIR_API_TOKEN is required");
  process.exit(1);
}

const client = createApiClient({ baseUrl: apiBaseUrl, token: apiToken });
const transport = process.env.PORTFOLIXIR_MCP_TRANSPORT ?? "stdio";

if (transport === "http") {
  await startHttpServer({
    client,
    token: process.env.PORTFOLIXIR_MCP_TOKEN,
    host: process.env.PORTFOLIXIR_MCP_HOST ?? "127.0.0.1",
    port: Number.parseInt(process.env.PORTFOLIXIR_MCP_PORT ?? "4001", 10)
  });
} else if (transport === "stdio") {
  const server = createPortfolixirMcpServer(client);
  await server.connect(new StdioServerTransport());
} else {
  console.error(`Unsupported PORTFOLIXIR_MCP_TRANSPORT: ${transport}`);
  process.exit(1);
}
