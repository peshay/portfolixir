import { timingSafeEqual } from "node:crypto";

import express, { type Request, type Response } from "express";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";

import { createPortfolixirMcpServer } from "./server.js";
import type { ApiClient } from "./api-client.js";

export interface HttpServerOptions {
  client: ApiClient;
  token?: string;
  host?: string;
  port?: number;
  /** Extra Host names this listener answers under (a reverse-proxy name). */
  extraHosts?: string[];
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

/**
 * Constant-time bearer check (#761). Both sides are compared as bytes of equal
 * length; a header of another length is refused before the compare, and a
 * header of the same length is refused without leaking where it diverged.
 */
export function isAuthorizedMcpRequest(
  authorization: string | undefined,
  configuredToken: string | undefined
): boolean {
  const token = configuredToken?.trim();

  if (!token || authorization === undefined) {
    return false;
  }

  const expected = Buffer.from(`Bearer ${token}`, "utf8");
  const provided = Buffer.from(authorization, "utf8");

  if (expected.length !== provided.length) {
    return false;
  }

  return timingSafeEqual(expected, provided);
}

/**
 * HTTP mode needs a token to authenticate anything at all; without one the
 * listener would start and answer 401 forever, which is a misconfiguration
 * that should stop the process with the variable's name (#761).
 */
export function requireMcpToken(configuredToken: string | undefined): string {
  const token = configuredToken?.trim();

  if (!token) {
    throw new Error("PORTFOLIXIR_MCP_TOKEN is required when PORTFOLIXIR_MCP_TRANSPORT=http");
  }

  return token;
}

/**
 * The Host values the SDK's DNS-rebinding protection accepts: the loopback
 * names with and without the port, plus any name the operator adds for a
 * reverse proxy. A wildcard bind (0.0.0.0) is not itself a Host a browser
 * sends, so it is not listed.
 */
export function allowedHostsFor(host: string, port: number, ...extraHosts: string[]): string[] {
  const names = ["127.0.0.1", "localhost", ...extraHosts.map((name) => name.trim()).filter(Boolean)];

  if (host !== "0.0.0.0" && host !== "::" && !names.includes(host)) {
    names.push(host);
  }

  return names.flatMap((name) => [`${name}:${port}`, name]);
}

export async function startHttpServer(options: HttpServerOptions): Promise<void> {
  const app = express();
  const host = options.host ?? "127.0.0.1";
  const port = options.port ?? 4001;
  const token = requireMcpToken(options.token);
  const allowedHosts = allowedHostsFor(host, port, ...(options.extraHosts ?? []));

  app.use(express.json({ limit: "1mb" }));

  app.use((req, res, next) => {
    if (!isAllowedOrigin(req.get("origin"))) {
      res.status(403).json({ errors: { detail: "origin not allowed" } });
      return;
    }

    if (!isAuthorizedMcpRequest(req.get("authorization"), token)) {
      res.status(401).json({ errors: { detail: "unauthorized" } });
      return;
    }

    next();
  });

  app.all("/mcp", async (req: Request, res: Response) => {
    const server = createPortfolixirMcpServer(options.client);
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined,
      enableDnsRebindingProtection: true,
      allowedHosts
    });

    res.on("close", () => {
      void transport.close();
      void server.close();
    });

    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
  });

  await new Promise<void>((resolve) => {
    app.listen(port, host, () => resolve());
  });

  console.error(`Portfolixir MCP server listening on http://${host}:${port}/mcp`);
}
