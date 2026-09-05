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

export function createApiClient(options: ApiClientOptions): ApiClient {
  const fetchImpl = options.fetch ?? globalThis.fetch.bind(globalThis);
  const baseUrl = options.baseUrl.replace(/\/+$/, "");
  const timeoutMs = options.timeoutMs ?? 30_000;

  return {
    async request(method: string, path: string, body?: unknown): Promise<unknown> {
      // A hung upstream must not hang the tool call: every request carries a
      // deadline (#761).
      const response = await fetchImpl(`${baseUrl}${path}`, {
        method,
        headers: {
          accept: "application/json",
          "content-type": "application/json",
          authorization: `Bearer ${options.token}`
        },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(timeoutMs)
      });

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
