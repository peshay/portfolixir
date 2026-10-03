import { escapeInvisible } from "./invisible-text.js";

export type FetchLike = (url: string, init?: RequestInit) => Promise<Response>;

export interface ApiClientOptions {
  baseUrl: string;
  token: string;
  fetch?: FetchLike;
  /** Upstream deadline per request in milliseconds (#761); default 30 s. */
  timeoutMs?: number;
}

/**
 * What a call tells the client about itself (E25 S7 review round, R3):
 * `readOnly` for a tool that changes nothing whatever its method, so a
 * timeout is answered as a read's.
 */
export interface RequestOptions {
  readOnly?: boolean;
}

export interface ApiClient {
  request(method: string, path: string, body?: unknown, options?: RequestOptions): Promise<unknown>;
}

/**
 * The API answered a redirect, which the companion never follows (E25 S7,
 * F23): following one would resend the request, its body and its bearer
 * token to wherever the redirect points. The message names the request and
 * the variable to correct, never the redirect's target.
 */
export class ApiRedirectError extends Error {
  override readonly name = "ApiRedirectError";

  constructor(
    readonly method: string,
    readonly path: string,
    readonly status: number
  ) {
    super(
      `Portfolixir API redirect refused: ${method} ${path} answered ${status}. ` +
        "The companion follows no redirect; point PORTFOLIXIR_API_BASE_URL at the address " +
        "the API answers on directly."
    );
  }
}

/**
 * A write got no answer before its deadline (E25 S7, G31), or lost its
 * connection after the request was sent (#955): a reset, a socket closed
 * while the answer arrived. The companion has no answer, but the server may
 * still commit the request, so the outcome is unknown: a retry without a
 * re-read can store a second record. A read that fails changes nothing and
 * is not this error. `cause` is the deadline in milliseconds, or the lost
 * connection's code.
 */
export class ApiOutcomeUnknownError extends Error {
  override readonly name = "ApiOutcomeUnknownError";

  constructor(
    readonly method: string,
    readonly path: string,
    cause: number | { connection: string }
  ) {
    const what =
      typeof cause === "number"
        ? `got no answer within ${cause / 1000} s`
        : `lost its connection after the request was sent (${cause.connection})`;

    super(
      `Portfolixir API outcome unknown: ${method} ${path} ${what}, and the server may still ` +
        "have committed it. Re-read the records it would have changed before retrying: a " +
        "blind retry can store a duplicate."
    );
  }
}

/**
 * A read got no answer before its deadline: a GET, or a tool that changes
 * nothing routed through POST (E25 S7 review round, R3). Nothing was
 * changed, so retrying is safe.
 */
export class ApiReadTimeoutError extends Error {
  override readonly name = "ApiReadTimeoutError";

  constructor(
    readonly method: string,
    readonly path: string,
    timeoutMs: number
  ) {
    super(
      `Portfolixir API timeout: ${method} ${path} got no answer within ${timeoutMs / 1000} s. ` +
        "The call changes nothing, so it can be retried."
    );
  }
}

/**
 * `client` for a tool that changes nothing (E25 S7 review round, R3): every
 * request it sends says so, so a timeout is answered as a read's.
 */
export function readOnlyClient(client: ApiClient): ApiClient {
  return {
    request: (method, path, body) => client.request(method, path, body, { readOnly: true })
  };
}

// The deadline's abort, or any other abort of the request.
function isAbort(error: unknown): boolean {
  const name = typeof error === "object" && error !== null ? (error as { name?: unknown }).name : undefined;
  return name === "TimeoutError" || name === "AbortError";
}

// #955: the failures that prove the request never reached the server. The
// connection was refused, the name did not resolve, the host or network was
// unreachable, or the connect itself timed out. Nothing was sent, so a
// retry is safe. Every other lost connection may have carried the request.
const NEVER_SENT = new Set([
  "ECONNREFUSED",
  "ENOTFOUND",
  "EAI_AGAIN",
  "EHOSTUNREACH",
  "ENETUNREACH",
  "UND_ERR_CONNECT_TIMEOUT"
]);

// A failure of the transport itself (#955): the request on its way out, or
// the answer's body on its way in. Only these two steps are wrapped, so an
// error the companion raises about an answer it did receive never reads as
// a lost connection.
class TransportFailure {
  constructor(readonly error: unknown) {}
}

async function transport<T>(step: () => Promise<T>): Promise<T> {
  try {
    return await step();
  } catch (error) {
    throw new TransportFailure(error);
  }
}

// The lost connection's code, on the error or on its cause (where the Fetch
// API puts the socket's), or "unknown" when neither carries one.
function connectionCode(error: unknown): string {
  for (const candidate of [error, (error as { cause?: unknown } | null)?.cause]) {
    const code =
      typeof candidate === "object" && candidate !== null
        ? (candidate as { code?: unknown }).code
        : undefined;

    if (typeof code === "string") {
      return code;
    }
  }

  return "unknown";
}

export function createApiClient(options: ApiClientOptions): ApiClient {
  const fetchImpl = options.fetch ?? globalThis.fetch.bind(globalThis);
  const baseUrl = options.baseUrl.replace(/\/+$/, "");
  const timeoutMs = options.timeoutMs ?? 30_000;

  const send = async (method: string, path: string, body?: unknown): Promise<unknown> => {
    const encoded = body === undefined ? undefined : JSON.stringify(body);

    // A hung upstream must not hang the tool call: every request carries a
    // deadline (#761). A redirect is answered, never followed (F23).
    const response = await transport(() =>
      fetchImpl(`${baseUrl}${path}`, {
        method,
        headers: {
          accept: "application/json",
          "content-type": "application/json",
          authorization: `Bearer ${options.token}`
        },
        body: encoded,
        redirect: "manual",
        signal: AbortSignal.timeout(timeoutMs)
      })
    );

    if (response.status >= 300 && response.status < 400) {
      await response.body?.cancel().catch(() => undefined);
      throw new ApiRedirectError(method, path, response.status);
    }

    const payload = parseJson(await transport(() => response.text()));

    if (!response.ok) {
      throw new Error(
        `Portfolixir API request failed: ${response.status} ${JSON.stringify(payload)}`
      );
    }

    return payload;
  };

  return {
    async request(
      method: string,
      path: string,
      body?: unknown,
      requestOptions: RequestOptions = {}
    ): Promise<unknown> {
      const read = method === "GET" || requestOptions.readOnly === true;

      try {
        return await send(method, path, body);
      } catch (failure) {
        const error = failure instanceof TransportFailure ? failure.error : failure;

        if (isAbort(error)) {
          // A write the deadline cut off may still commit on the server
          // (G31); a read changes nothing, whatever its method (R3).
          if (read) {
            throw new ApiReadTimeoutError(method, path, timeoutMs);
          }

          throw new ApiOutcomeUnknownError(method, path, timeoutMs);
        }

        // A write whose connection was lost once it may have been sent
        // (#955): the same unknown outcome as a timeout.
        if (failure instanceof TransportFailure && !read) {
          const code = connectionCode(error);

          if (!NEVER_SENT.has(code)) {
            throw new ApiOutcomeUnknownError(method, path, { connection: code });
          }
        }

        throw error;
      }
    }
  };
}

// Every answer reaches the agent with the characters an operator cannot see
// spelled out (E25 S7, G20): the one place the companion escapes them.
function parseJson(text: string): unknown {
  if (text.trim() === "") {
    return null;
  }

  return escapeInvisible(JSON.parse(text));
}
