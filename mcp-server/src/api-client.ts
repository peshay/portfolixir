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
 * A write got no answer before its deadline (E25 S7, G31), or its connection
 * failed in a way that does not prove the request never left (#955): a
 * reset, a socket closed while the answer arrived, a TLS failure, a failure
 * with no code. The companion has no answer and cannot tell whether the
 * request was sent, but the server may still commit it, so the outcome is
 * unknown: a retry without a re-read can store a second record. A read that
 * fails changes nothing and is not this error. `cause` is the deadline in
 * milliseconds, or the failure's code (each address's, joined, when a connect
 * failed on several).
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
        : `got no complete answer (${cause.connection}); the request may have been sent`;

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
// retry is safe. Every other failure may have carried the request.
//
// The #955 review round added three, each raised before a byte of the
// request can leave:
// - EAFNOSUPPORT: the kernel refuses a socket of the address's family (an
//   IPv6 address on a host without IPv6), so no socket exists to send on.
// - EADDRNOTAVAIL: connect() finds no local address or port to bind for the
//   destination (::1 in a container without IPv6, ephemeral ports used up)
//   and fails before the handshake's first packet; a TCP socket that has
//   connected never reports it.
// - ERR_INVALID_URL: the base URL does not parse, so the client never resolves a
//   host, let alone connects to one.
const NEVER_SENT = new Set([
  "ECONNREFUSED",
  "ENOTFOUND",
  "EAI_AGAIN",
  "EHOSTUNREACH",
  "ENETUNREACH",
  "EAFNOSUPPORT",
  "EADDRNOTAVAIL",
  "UND_ERR_CONNECT_TIMEOUT",
  "ERR_INVALID_URL"
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

function codeOf(candidate: unknown): string | undefined {
  const code =
    typeof candidate === "object" && candidate !== null
      ? (candidate as { code?: unknown }).code
      : undefined;

  return typeof code === "string" ? code : undefined;
}

// The failed connection's codes, on the error or on its cause (where the
// Fetch API puts the socket's), "unknown" standing for one that carries none.
// One code, except for a connect that failed on every address a name
// resolves to (Node's happy eyeballs): its AggregateError carries one member
// per address and copies only the first member's code onto itself, which
// speaks for the first address alone. Its members' codes are read instead
// (#955 review round), so a later address that may have carried the request
// is never hidden behind a first one that was refused.
function connectionCodes(error: unknown): string[] {
  for (const candidate of [error, (error as { cause?: unknown } | null)?.cause]) {
    const members =
      typeof candidate === "object" && candidate !== null
        ? (candidate as { errors?: unknown }).errors
        : undefined;

    if (Array.isArray(members) && members.length > 0) {
      return members.map((member) => codeOf(member) ?? "unknown");
    }

    const code = codeOf(candidate);

    if (code !== undefined) {
      return [code];
    }
  }

  return ["unknown"];
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

        // A write whose connection failed once it may have been sent
        // (#955): the same unknown outcome as a timeout. A connect tried on
        // several addresses was never sent only if no address carried it.
        if (failure instanceof TransportFailure && !read) {
          const codes = connectionCodes(error);

          if (!codes.every((code) => NEVER_SENT.has(code))) {
            const connection = [...new Set(codes)].join(", ");
            throw new ApiOutcomeUnknownError(method, path, { connection });
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
