export type FetchLike = (url: string, init?: RequestInit) => Promise<Response>;

export interface ApiClientOptions {
  baseUrl: string;
  token: string;
  fetch?: FetchLike;
  /** Upstream deadline per request in milliseconds (#761); default 30 s. */
  timeoutMs?: number;
}

export interface ApiClient {
  request(method: string, path: string, body?: unknown): Promise<unknown>;
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
 * A write got no answer before its deadline (E25 S7, G31). The companion
 * stopped waiting, but the server may still commit the request, so the
 * outcome is unknown: a retry without a re-read can store a second record.
 * A read that times out changes nothing and is not this error.
 */
export class ApiOutcomeUnknownError extends Error {
  override readonly name = "ApiOutcomeUnknownError";

  constructor(
    readonly method: string,
    readonly path: string,
    timeoutMs: number
  ) {
    super(
      `Portfolixir API outcome unknown: ${method} ${path} got no answer within ` +
        `${timeoutMs / 1000} s, and the server may still have committed it. Re-read the ` +
        "records it would have changed before retrying: a blind retry can store a duplicate."
    );
  }
}

// The deadline's abort, or any other abort of the request.
function isAbort(error: unknown): boolean {
  const name = typeof error === "object" && error !== null ? (error as { name?: unknown }).name : undefined;
  return name === "TimeoutError" || name === "AbortError";
}

export function createApiClient(options: ApiClientOptions): ApiClient {
  const fetchImpl = options.fetch ?? globalThis.fetch.bind(globalThis);
  const baseUrl = options.baseUrl.replace(/\/+$/, "");
  const timeoutMs = options.timeoutMs ?? 30_000;

  const send = async (method: string, path: string, body?: unknown): Promise<unknown> => {
    // A hung upstream must not hang the tool call: every request carries a
    // deadline (#761). A redirect is answered, never followed (F23).
    const response = await fetchImpl(`${baseUrl}${path}`, {
      method,
      headers: {
        accept: "application/json",
        "content-type": "application/json",
        authorization: `Bearer ${options.token}`
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      redirect: "manual",
      signal: AbortSignal.timeout(timeoutMs)
    });

    if (response.status >= 300 && response.status < 400) {
      await response.body?.cancel().catch(() => undefined);
      throw new ApiRedirectError(method, path, response.status);
    }

    const payload = await parseJson(response);

    if (!response.ok) {
      throw new Error(
        `Portfolixir API request failed: ${response.status} ${JSON.stringify(payload)}`
      );
    }

    return payload;
  };

  return {
    async request(method: string, path: string, body?: unknown): Promise<unknown> {
      try {
        return await send(method, path, body);
      } catch (error) {
        // A write the deadline cut off may still commit on the server (G31).
        if (method !== "GET" && isAbort(error)) {
          throw new ApiOutcomeUnknownError(method, path, timeoutMs);
        }

        throw error;
      }
    }
  };
}

async function parseJson(response: Response): Promise<unknown> {
  const text = await response.text();

  if (text.trim() === "") {
    return null;
  }

  return JSON.parse(text);
}
