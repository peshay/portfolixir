#!/usr/bin/env node

import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

import { createApiClient } from "./api-client.js";
import { requireMcpToken, startHttpServer } from "./http.js";
import { createPortfolixirMcpServer, readOnlySwitch } from "./server.js";

const apiBaseUrl = process.env.PORTFOLIXIR_API_BASE_URL ?? "http://127.0.0.1:4000";
const apiToken = process.env.PORTFOLIXIR_API_TOKEN;

if (!apiToken) {
  console.error("PORTFOLIXIR_API_TOKEN is required");
  process.exit(1);
}

// The opt-in read-only switch (E25 S7, G26): a value it cannot read stops the
// companion with the variable named rather than running it with writes open.
let readOnly: boolean;

try {
  readOnly = readOnlySwitch(process.env.PORTFOLIXIR_MCP_READ_ONLY);
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}

const client = createApiClient({ baseUrl: apiBaseUrl, token: apiToken });
const transport = process.env.PORTFOLIXIR_MCP_TRANSPORT ?? "stdio";

if (transport === "http") {
  // HTTP mode refuses to start without a sound token (#761, E25 S1 F01): a
  // listener that answers 401 forever is a misconfiguration, and a short or
  // placeholder token is not a credential. The message names the variable.
  let token: string;

  try {
    token = requireMcpToken(process.env.PORTFOLIXIR_MCP_TOKEN);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }

  await startHttpServer({
    client,
    token,
    host: process.env.PORTFOLIXIR_MCP_HOST ?? "127.0.0.1",
    port: Number.parseInt(process.env.PORTFOLIXIR_MCP_PORT ?? "4001", 10),
    extraHosts: (process.env.PORTFOLIXIR_MCP_ALLOWED_HOSTS ?? "").split(","),
    readOnly
  });
} else if (transport === "stdio") {
  const server = createPortfolixirMcpServer(client, { readOnly });
  await server.connect(new StdioServerTransport());
} else {
  console.error(`Unsupported PORTFOLIXIR_MCP_TRANSPORT: ${transport}`);
  process.exit(1);
}
