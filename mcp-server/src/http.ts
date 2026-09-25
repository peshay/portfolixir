import { timingSafeEqual } from "node:crypto";
import { STATUS_CODES } from "node:http";

import express, { type Express, type NextFunction, type Request, type Response } from "express";
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
  /** The opt-in read-only switch (E25 S7, G26). */
  readOnly?: boolean;
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
 * The companion's token meets the API token's policy (#761, E25 S1 F01): at
 * least 32 bytes and not one of the placeholders the example files ship. The
 * list mirrors `Portfolixir.RuntimeConfig`; an Elixir test pins the parity.
 */
export const MCP_TOKEN_MIN_BYTES = 32;

export const MCP_TOKEN_PLACEHOLDER_PREFIXES = [
  "dev-api-token",
  "dev-mcp-token",
  "test-api-token",
  "replace",
  "change",
  "secret",
  "token",
  "password",
  "example"
];

/**
 * HTTP mode needs a token to authenticate anything at all; without one the
 * listener would start and answer 401 forever, which is a misconfiguration
 * that should stop the process with the variable's name (#761). A short or
 * placeholder token stops it the same way (F01).
 */
export function requireMcpToken(configuredToken: string | undefined): string {
  const token = configuredToken?.trim();

  if (!token) {
    throw new Error("PORTFOLIXIR_MCP_TOKEN is required when PORTFOLIXIR_MCP_TRANSPORT=http");
  }

  const bytes = Buffer.byteLength(token, "utf8");

  if (bytes < MCP_TOKEN_MIN_BYTES) {
    throw new Error(
      `PORTFOLIXIR_MCP_TOKEN must be at least ${MCP_TOKEN_MIN_BYTES} bytes (got ${bytes}); ` +
        "generate one with `openssl rand -base64 48`"
    );
  }

  const lowered = token.toLowerCase();

  if (MCP_TOKEN_PLACEHOLDER_PREFIXES.some((prefix) => lowered.startsWith(prefix))) {
    throw new Error(
      "PORTFOLIXIR_MCP_TOKEN is a placeholder value; generate a real token with `openssl rand -base64 48`"
    );
  }

  return token;
}

export interface FailureThrottle {
  readonly maxFailures: number;
  readonly baseLockSeconds: number;
  readonly maxLockSeconds: number;
  check(source: string, now: number): { locked: false } | { locked: true; retryAfter: number };
  failure(source: string, now: number): void;
  success(source: string): void;
}

interface FailureRecord {
  count: number;
  lockedUntil: number;
  lastFailure: number;
}

/**
 * Per-source lockout for the companion's bearer check (E25 S1, F01), the same
 * arithmetic as the application's `Portfolixir.Auth.Throttle`: from the tenth
 * failure a source is locked for two seconds, doubling per further failure up
 * to five minutes; a success clears it. A source's count is kept for an hour
 * after its last failure, so waiting out a lock does not reset the escalation,
 * and older records are pruned so the map stays bounded by that window.
 */
export function createFailureThrottle(): FailureThrottle {
  const maxFailures = 10;
  const baseLockSeconds = 2;
  const maxLockSeconds = 300;
  const retentionSeconds = 60 * 60;
  const records = new Map<string, FailureRecord>();
  let lastPrune = 0;

  const prune = (now: number): void => {
    if (now - lastPrune < maxLockSeconds) {
      return;
    }

    lastPrune = now;

    for (const [source, record] of records) {
      if (now - record.lastFailure > retentionSeconds) {
        records.delete(source);
      }
    }
  };

  return {
    maxFailures,
    baseLockSeconds,
    maxLockSeconds,
    check(source, now) {
      const record = records.get(source);

      return record && record.lockedUntil > now
        ? { locked: true, retryAfter: record.lockedUntil - now }
        : { locked: false };
    },
    failure(source, now) {
      prune(now);
      const record = records.get(source) ?? { count: 0, lockedUntil: 0, lastFailure: now };
      record.count += 1;
      record.lastFailure = now;

      if (record.count >= maxFailures) {
        const exponent = Math.min(record.count - maxFailures, 30);
        record.lockedUntil = now + Math.min(baseLockSeconds * 2 ** exponent, maxLockSeconds);
      }

      records.set(source, record);
    },
    success(source) {
      records.delete(source);
    }
  };
}

/**
 * The companion's gate: the origin check, then a locked-out source answered
 * 429 before the token is compared (right token or wrong), then the
 * constant-time bearer check, which counts a failure against the source and
 * clears it on success. The source is the connecting address.
 */
export function mcpAuthMiddleware(
  token: string,
  throttle: FailureThrottle = createFailureThrottle(),
  clock: () => number = () => Math.floor(Date.now() / 1000)
) {
  return (req: Request, res: Response, next: NextFunction): void => {
    if (!isAllowedOrigin(req.get("origin"))) {
      res.status(403).json({ errors: { detail: "origin not allowed" } });
      return;
    }

    const source = req.socket.remoteAddress ?? "unknown";
    const now = clock();
    const state = throttle.check(source, now);

    if (state.locked) {
      res
        .status(429)
        .set("Retry-After", String(state.retryAfter))
        .json({ errors: { detail: "too many failed attempts; retry later" } });
      return;
    }

    if (!isAuthorizedMcpRequest(req.get("authorization"), token)) {
      throttle.failure(source, now);
      res.status(401).json({ errors: { detail: "unauthorized" } });
      return;
    }

    throttle.success(source);
    next();
  };
}

/**
 * The companion's own DNS-rebinding guard (E25 S7, F22), the first check a
 * request meets: its Host must be one of the allowed values exactly, name and
 * port together (a name compared without its case), or it is answered 403
 * before its origin, its token or its body is read, and it counts no failed
 * token attempt. The SDK transport's Host check stays behind it as a second
 * layer.
 */
export function hostGuard(allowedHosts: string[]) {
  const allowed = new Set(allowedHosts.map((host) => host.toLowerCase()));

  return (req: Request, res: Response, next: NextFunction): void => {
    const host = req.headers.host;

    if (host === undefined || !allowed.has(host.toLowerCase())) {
      res.status(403).json({ errors: { detail: "host not allowed" } });
      return;
    }

    next();
  };
}

/**
 * The Host values the companion answers under: the loopback names with and
 * without the port, plus any name the operator adds for a reverse proxy. A
 * wildcard bind (0.0.0.0) is not itself a Host a browser sends, so it is not
 * listed. Both the companion's own guard and the SDK's check read this list.
 */
export function allowedHostsFor(host: string, port: number, ...extraHosts: string[]): string[] {
  const names = ["127.0.0.1", "localhost", ...extraHosts.map((name) => name.trim()).filter(Boolean)];

  if (host !== "0.0.0.0" && host !== "::" && !names.includes(host)) {
    names.push(host);
  }

  return names.flatMap((name) => [`${name}:${port}`, name]);
}

export interface HttpAppOptions {
  client: ApiClient;
  /** A token `requireMcpToken` has accepted. */
  token: string;
  /** The Host values the companion answers under (its guard and the SDK's). */
  allowedHosts: string[];
  /** The opt-in read-only switch (E25 S7, G26). */
  readOnly?: boolean;
}

/**
 * The terminal error handler (E25 S2, F19): every error that reaches it is
 * answered in the API's error shape with the status's reason phrase, and
 * nothing of the error itself (no message, no stack, no path) reaches the
 * client. A 4xx is the client's own doing and is not logged; anything else
 * is logged by its stack, never with the request. The refusals the MCP SDK's
 * transport answers itself on /mcp (a Host outside the allow-list, a method
 * the protocol does not take) never reach it: they keep the protocol's
 * JSON-RPC error shape.
 */
export function mcpErrorHandler(
  error: unknown,
  _req: Request,
  res: Response,
  next: NextFunction
): void {
  if (res.headersSent) {
    next(error);
    return;
  }

  const status = errorStatus(error);

  if (status >= 500) {
    console.error(error instanceof Error ? error.stack : "unexpected non-error thrown");
  }

  res.status(status).json({ errors: { detail: STATUS_CODES[status] ?? "Error" } });
}

function errorStatus(error: unknown): number {
  if (typeof error === "object" && error !== null) {
    const candidate =
      (error as { status?: unknown }).status ?? (error as { statusCode?: unknown }).statusCode;

    if (typeof candidate === "number" && candidate >= 400 && candidate <= 599) {
      return candidate;
    }
  }

  return 500;
}

/**
 * The companion's HTTP app, without a listener. The Host guard runs first
 * (E25 S7, F22), then the gate, both before any body is read (E25 S2, F19):
 * an unauthenticated request is refused without being parsed. Express runs in
 * production mode whatever NODE_ENV says, so its own last-resort handler never
 * renders a stack trace either.
 */
export function createHttpApp(options: HttpAppOptions): Express {
  const app = express();
  app.set("env", "production");

  app.use(hostGuard(options.allowedHosts));
  app.use(mcpAuthMiddleware(options.token));
  app.use(express.json({ limit: "1mb" }));

  app.all("/mcp", async (req: Request, res: Response) => {
    const server = createPortfolixirMcpServer(options.client, { readOnly: options.readOnly });
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined,
      enableDnsRebindingProtection: true,
      allowedHosts: options.allowedHosts
    });

    res.on("close", () => {
      void transport.close();
      void server.close();
    });

    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
  });

  // Any other path: Express's own 404 is an HTML page, so the companion
  // answers it in the same shape as its other errors.
  app.use((_req: Request, res: Response) => {
    res.status(404).json({ errors: { detail: STATUS_CODES[404] } });
  });

  app.use(mcpErrorHandler);

  return app;
}

export async function startHttpServer(options: HttpServerOptions): Promise<void> {
  const host = options.host ?? "127.0.0.1";
  const port = options.port ?? 4001;
  const token = requireMcpToken(options.token);
  const allowedHosts = allowedHostsFor(host, port, ...(options.extraHosts ?? []));
  const app = createHttpApp({
    client: options.client,
    token,
    allowedHosts,
    readOnly: options.readOnly
  });

  await new Promise<void>((resolve) => {
    app.listen(port, host, () => resolve());
  });

  console.error(`Portfolixir MCP server listening on http://${host}:${port}/mcp`);
}
