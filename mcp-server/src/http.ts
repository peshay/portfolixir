import express, { type Request, type Response } from "express";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";

import { createPortfolixirMcpServer } from "./server.js";
import type { ApiClient } from "./api-client.js";

export interface HttpServerOptions {
  client: ApiClient;
  token?: string;
  host?: string;
  port?: number;
}

export function isAllowedOrigin(origin: string | undefined): boolean {
  if (origin === undefined) {
    return true;
  }

  try {
    const parsed = new URL(origin);
    return ["localhost", "127.0.0.1", "::1"].includes(parsed.hostname);
  } catch {
    return false;
  }
}

export function isAuthorizedMcpRequest(
  authorization: string | undefined,
  configuredToken: string | undefined
): boolean {
  const token = configuredToken?.trim();

  if (!token) {
    return false;
  }

  return authorization === `Bearer ${token}`;
}

export async function startHttpServer(options: HttpServerOptions): Promise<void> {
  const app = express();
  const host = options.host ?? "127.0.0.1";
  const port = options.port ?? 4001;

  app.use(express.json({ limit: "1mb" }));

  app.use((req, res, next) => {
    if (!isAllowedOrigin(req.get("origin"))) {
      res.status(403).json({ errors: { detail: "origin not allowed" } });
      return;
    }

    if (!isAuthorizedMcpRequest(req.get("authorization"), options.token)) {
      res.status(401).json({ errors: { detail: "unauthorized" } });
      return;
    }

    next();
  });

  app.all("/mcp", async (req: Request, res: Response) => {
    const server = createPortfolixirMcpServer(options.client);
    const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });

    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
  });

  await new Promise<void>((resolve) => {
    app.listen(port, host, () => resolve());
  });

  console.error(`Portfolixir MCP server listening on http://${host}:${port}/mcp`);
}
