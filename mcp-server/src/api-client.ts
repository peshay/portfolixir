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

export function createApiClient(options: ApiClientOptions): ApiClient {
  const fetchImpl = options.fetch ?? globalThis.fetch.bind(globalThis);
  const baseUrl = options.baseUrl.replace(/\/+$/, "");
  const timeoutMs = options.timeoutMs ?? 30_000;

  return {
    async request(method: string, path: string, body?: unknown): Promise<unknown> {
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
