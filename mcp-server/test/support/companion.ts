import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";

import type { ApiClient } from "../../src/api-client.js";
import { createPortfolixirMcpServer } from "../../src/server.js";

/**
 * An MCP client connected to the companion's real server over an in-memory
 * transport (E25 S7, F21): what it lists and answers is what an MCP host
 * receives, not what the tool definitions say before the SDK publishes them.
 */
export interface ConnectedCompanion {
  mcp: Client;
  close(): Promise<void>;
}

export interface CompanionOptions {
  readOnly?: boolean;
}

const unreachableApi: ApiClient = {
  request: async () => {
    throw new Error("the API is not reached by this test");
  }
};

export async function connectCompanion(
  client: ApiClient = unreachableApi,
  options: CompanionOptions = {}
): Promise<ConnectedCompanion> {
  const server = createPortfolixirMcpServer(client, options);
  const [serverSide, clientSide] = InMemoryTransport.createLinkedPair();
  const mcp = new Client({ name: "portfolixir-test-host", version: "0.0.0" });

  await Promise.all([server.connect(serverSide), mcp.connect(clientSide)]);

  return {
    mcp,
    close: async () => {
      await mcp.close();
      await server.close();
    }
  };
}

/** The tool list an MCP host receives from `tools/list`. */
export async function publishedTools(options: CompanionOptions = {}) {
  const companion = await connectCompanion(unreachableApi, options);

  try {
    return (await companion.mcp.listTools()).tools;
  } finally {
    await companion.close();
  }
}
