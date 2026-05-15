export type FetchLike = (url: string, init?: RequestInit) => Promise<Response>;

export interface ApiClientOptions {
  baseUrl: string;
  token: string;
  fetch?: FetchLike;
}

export interface ApiClient {
  request(method: string, path: string, body?: unknown): Promise<unknown>;
}

export function createApiClient(options: ApiClientOptions): ApiClient {
  const fetchImpl = options.fetch ?? globalThis.fetch.bind(globalThis);
  const baseUrl = options.baseUrl.replace(/\/+$/, "");

  return {
    async request(method: string, path: string, body?: unknown): Promise<unknown> {
      const response = await fetchImpl(`${baseUrl}${path}`, {
        method,
        headers: {
          accept: "application/json",
          "content-type": "application/json",
          authorization: `Bearer ${options.token}`
        },
        body: body === undefined ? undefined : JSON.stringify(body)
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
