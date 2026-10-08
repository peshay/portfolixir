import { timingSafeEqual } from "node:crypto";
import { STATUS_CODES } from "node:http";

import express, { type Express, type NextFunction, type Request, type Response } from "express";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";

import { createPortfolixirMcpServer } from "./server.js";
import type { ApiClient } from "./api-client.js";
import type { McpProfile } from "./profiles.js";

export interface HttpServerOptions {
  client: ApiClient;
  token?: string;
  host?: string;
  port?: number;
  /** Extra Host names this listener answers under (a reverse-proxy name). */
  extraHosts?: string[];
  /** The tool profile (A1, #992); `full` when absent. */
  profile?: McpProfile;
}

/**
 * The Origin check (#956): a request without an Origin (a client that is not
 * a browser) passes; one with an Origin passes only when that origin, exactly
 * as a browser serializes it (scheme, name and port), is one of
 * `allowedOrigins` (`allowedOriginsFor`). A page on another port of the same
 * machine is another origin, and so is an opaque one (`null`).
 */
export function isAllowedOrigin(origin: string | undefined, allowedOrigins: readonly string[]): boolean {
  if (origin === undefined) {
    return true;
  }

  let parsed: URL;

  try {
    parsed = new URL(origin);
  } catch {
    return false;
  }

  return parsed.origin === origin && allowedOrigins.includes(parsed.origin);
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

export const MCP_DEFAULT_PORT = 4001;

export const MCP_DEFAULT_HOST = "127.0.0.1";

/**
 * The listener's address from `PORTFOLIXIR_MCP_HOST` (#1137), trimmed: unset,
 * empty or blank is 127.0.0.1, as an empty port is 4001 (#1043). An empty
 * address handed to the listener binds every interface, so a line left blank
 * in an `.env` file never opens the companion beyond loopback.
 */
export function mcpHost(configuredHost: string | undefined): string {
  const value = (configuredHost ?? "").trim();

  return value === "" ? MCP_DEFAULT_HOST : value;
}

/**
 * The listener's port from `PORTFOLIXIR_MCP_PORT` (#1043): a whole number
 * from 1 to 65535, trimmed; unset or empty is 4001. Anything else stops the
 * companion with the variable and its value named, as a bad token does,
 * rather than listening on a port nobody chose (`4001x` read as 4001) or
 * reporting `NaN`.
 */
export function requireMcpPort(configuredPort: string | undefined): number {
  const value = (configuredPort ?? "").trim();

  if (value === "") {
    return MCP_DEFAULT_PORT;
  }

  const port = /^[0-9]+$/.test(value) ? Number(value) : Number.NaN;

  if (!(port >= 1 && port <= 65535)) {
    throw new Error(
      "PORTFOLIXIR_MCP_PORT must be a whole number from 1 to 65535, or unset " +
        `(${MCP_DEFAULT_PORT}); it is set to ${JSON.stringify(configuredPort)}`
    );
  }

  return port;
}

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
 * The companion's token gate, the token compared first (#974, the Sprint 20
 * plan's D-11), as the API's is: a correct token passes whether its source is
 * locked out or not, so a stale client sharing the operator's address (every
 * host client behind the Compose port) cannot lock the agent out; it clears
 * the source's count unless the source is locked, so the agent's requests
 * never lift a guesser's lock. A wrong token counts
 * against its source, locked or not, and is answered 429 with the lock its
 * own failure extended while the lock lasts, 401 before. The cost: a locked
 * guesser who guesses right is let in, which the 32-byte floor
 * `requireMcpToken` holds the token to makes infeasible. The source is the
 * connecting address. The Host and Origin guards run ahead of it.
 */
export function mcpAuthMiddleware(
  token: string,
  throttle: FailureThrottle = createFailureThrottle(),
  clock: () => number = () => Math.floor(Date.now() / 1000)
) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const source = req.socket.remoteAddress ?? "unknown";
    const now = clock();
    const state = throttle.check(source, now);

    if (isAuthorizedMcpRequest(req.get("authorization"), token)) {
      if (!state.locked) {
        throttle.success(source);
      }

      next();
      return;
    }

    throttle.failure(source, now);
    const after = throttle.check(source, now);

    if (state.locked && after.locked) {
      res
        .status(429)
        .set("Retry-After", String(after.retryAfter))
        .json({ errors: { detail: "too many failed attempts; retry later" } });
      return;
    }

    res.status(401).json({ errors: { detail: "unauthorized" } });
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
 * The companion's Origin guard (#956), after the Host guard and before the
 * token: a browser request whose Origin is not one of `allowedOrigins` is
 * answered 403 before its token is read, and counts no failed attempt.
 */
export function originGuard(allowedOrigins: readonly string[]) {
  return (req: Request, res: Response, next: NextFunction): void => {
    if (!isAllowedOrigin(req.get("origin"), allowedOrigins)) {
      res.status(403).json({ errors: { detail: "origin not allowed" } });
      return;
    }

    next();
  };
}

// An address as a Host header and a URL write it: an IPv6 address in
// brackets, once (#1137); one given in brackets already, and any name, as it
// is.
function hostName(host: string): string {
  const bracketed = host.startsWith("[") && host.endsWith("]");

  return host.includes(":") && !bracketed ? `[${host}]` : host;
}

// The names a client reaches the listener itself under (#956): the loopback
// names, the IPv6 one in brackets as a Host header and a URL write it, and
// the bound address, an IPv6 one in brackets too (#1137), unless it is a
// wildcard, which no client sends. Each is answered under the listener's
// port only.
function listenerNames(host: string): string[] {
  const names = ["127.0.0.1", "localhost", "[::1]"];
  const bound = hostName(host);

  if (!["0.0.0.0", "[::]"].includes(bound) && !names.includes(bound)) {
    names.push(bound);
  }

  return names;
}

// A name or a bracketed IPv6 address, then a port: what a Host header with a
// port looks like. A bare IPv6 address is not one, its last group no port.
const HOST_WITH_PORT = /^(\[[^\]]*\]|[^:[\]]+):[0-9]+$/;

// The names the operator adds (PORTFOLIXIR_MCP_ALLOWED_HOSTS), trimmed, as
// the Host values each stands for: an entry that carries its own port
// (`localhost:6274`, a published port `127.0.0.1:14001`) stands for itself;
// a bare name, a bare IPv6 address in brackets (#1137), for itself with the
// listener's port and without one, as a proxy on 80 or 443 passes it.
function extraHostValues(port: number, extraHosts: string[]): string[] {
  return extraHosts
    .map((name) => name.trim())
    .filter(Boolean)
    .flatMap((name) => {
      if (HOST_WITH_PORT.test(name)) {
        return [name];
      }

      const written = hostName(name);
      return [`${written}:${port}`, written];
    });
}

/**
 * The Host values the companion answers under, exact by name and port: the
 * loopback names and the bound address with the listener's port, plus the
 * names the operator adds for a reverse proxy, a published port of another
 * number or a browser client (`extraHostValues`). A wildcard bind (0.0.0.0)
 * is not itself a Host a browser sends, so it is not listed. Both the
 * companion's own guard and the SDK's check read this list.
 */
export function allowedHostsFor(host: string, port: number, ...extraHosts: string[]): string[] {
  return [
    ...listenerNames(host).map((name) => `${name}:${port}`),
    ...extraHostValues(port, extraHosts)
  ];
}

/**
 * The origins the Origin guard admits (#956), built from the configuration
 * the Host guard reads: `http://` with the listener's port for each loopback
 * name and the bound address (the companion itself speaks plain HTTP), and
 * `http://` and `https://` for each Host value the operator added (a proxy
 * that terminates TLS, or a browser client's own origin). Each is written as
 * a browser serializes an origin, a scheme's default port left out.
 */
export function allowedOriginsFor(host: string, port: number, ...extraHosts: string[]): string[] {
  const candidates = [
    ...listenerNames(host).map((name) => `http://${name}:${port}`),
    ...extraHostValues(port, extraHosts).flatMap((value) => [`http://${value}`, `https://${value}`])
  ];
  const origins: string[] = [];

  for (const candidate of candidates) {
    try {
      const { origin } = new URL(candidate);

      if (origin !== "null" && !origins.includes(origin)) {
        origins.push(origin);
      }
    } catch {
      // An entry no URL can carry admits no origin; the Host guard still
      // compares it as written.
    }
  }

  return origins;
}

export interface HttpAppOptions {
  client: ApiClient;
  /** A token `requireMcpToken` has accepted. */
  token: string;
  /** The Host values the companion answers under (its guard and the SDK's). */
  allowedHosts: string[];
  /** The origins a browser request may come from (#956). */
  allowedOrigins: string[];
  /** The tool profile (A1, #992); `full` when absent. */
  profile?: McpProfile;
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
 * (E25 S7, F22), then the Origin guard (#956), then the token gate, all
 * before any body is read (E25 S2, F19): an unauthenticated request is
 * refused without being parsed. Express runs in production mode whatever
 * NODE_ENV says, so its own last-resort handler never renders a stack trace
 * either.
 */
export function createHttpApp(options: HttpAppOptions): Express {
  const app = express();
  app.set("env", "production");

  app.use(hostGuard(options.allowedHosts));
  app.use(originGuard(options.allowedOrigins));
  app.use(mcpAuthMiddleware(options.token));
  app.use(express.json({ limit: "1mb" }));

  app.all("/mcp", async (req: Request, res: Response) => {
    const server = createPortfolixirMcpServer(options.client, { profile: options.profile });
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
  const host = mcpHost(options.host);
  const port = options.port ?? MCP_DEFAULT_PORT;
  const token = requireMcpToken(options.token);
  const allowedHosts = allowedHostsFor(host, port, ...(options.extraHosts ?? []));
  const allowedOrigins = allowedOriginsFor(host, port, ...(options.extraHosts ?? []));
  const app = createHttpApp({
    client: options.client,
    token,
    allowedHosts,
    allowedOrigins,
    profile: options.profile
  });

  // A listen that fails rejects (#1043), so a port that is taken never reads
  // as listening. No callback goes to app.listen, which would leave Express's
  // own error listener on the server for good: one listener hears the bind's
  // failure, and it is removed once the server listens, so a later server
  // error is not swallowed.
  await new Promise<void>((resolve, reject) => {
    let server: ReturnType<typeof app.listen>;

    try {
      server = app.listen(port, host);
    } catch (error) {
      reject(listenFailure(host, port, error));
      return;
    }

    const failed = (error: Error): void => {
      server.off("listening", listening);
      reject(listenFailure(host, port, error));
    };
    const listening = (): void => {
      server.off("error", failed);
      resolve();
    };

    server.once("error", failed);
    server.once("listening", listening);
  });

  console.error(`Portfolixir MCP server listening on ${mcpUrl(host, port)}`);
}

// The listener's address as a URL: an IPv6 host goes in brackets, once; a
// host given already bracketed (`[::1]`) is left as it is (#1043 review round).
// Its Host is one the allowed hosts list (#1137).
export function mcpUrl(host: string, port: number): string {
  return `http://${hostName(host)}:${port}/mcp`;
}

// What a listen most often fails with, in the operator's words.
const LISTEN_CAUSES = new Map([
  ["EADDRINUSE", "the port is in use"],
  ["EACCES", "no permission to listen on the port"],
  ["EADDRNOTAVAIL", "the host is not an address of this machine"],
  ["ENOTFOUND", "the host name does not resolve"]
]);

/**
 * The one line an operator reads when the listener cannot start (#1043): the
 * address it tried, and the cause by its code (or its message, when it
 * carries none). It never says "listening".
 */
function listenFailure(host: string, port: number, error: unknown): Error {
  const code =
    typeof error === "object" && error !== null ? (error as { code?: unknown }).code : undefined;
  const gloss = typeof code === "string" ? LISTEN_CAUSES.get(code) : undefined;
  const cause =
    typeof code === "string"
      ? gloss === undefined
        ? code
        : `${code} (${gloss})`
      : error instanceof Error
        ? error.message
        : String(error);

  return new Error(`Portfolixir MCP server could not listen on ${mcpUrl(host, port)}: ${cause}`, {
    cause: error
  });
}
