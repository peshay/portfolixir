import { createApiClient, type ApiClient } from "../../src/api-client.js";

/**
 * A single fetch call captured by the recording client.
 *
 * Every field the MCP tool tests assert on is always recorded, so individual
 * tests only need to read the parts they care about (method/path/body/token).
 */
export interface RecordedRequest {
  method: string;
  path: string;
  body?: unknown;
  token: string;
}

export interface RecordingClient {
  client: ApiClient;
  requests: RecordedRequest[];
}

export interface RecordingClientOptions {
  /** JSON payload returned to the tool for every request (default `{ data: {} }`). */
  data?: unknown;
  /** HTTP status of the stubbed response (default `200`). */
  status?: number;
}

/**
 * Builds an {@link ApiClient} backed by a fake `fetch` that records each
 * request and replies with a fixed JSON body. This consolidates the
 * arrange-a-client-and-capture-requests boilerplate that every MCP tool test
 * otherwise repeats verbatim.
 */
export function createRecordingClient(options: RecordingClientOptions = {}): RecordingClient {
  const { data = {}, status = 200 } = options;
  const requests: RecordedRequest[] = [];

  const client = createApiClient({
    baseUrl: "http://portfolixir.test",
    token: "api-token",
    fetch: async (url, init) => {
      const parsed = new URL(url);
      requests.push({
        method: init?.method ?? "GET",
        path: `${parsed.pathname}${parsed.search}`,
        body: init?.body ? JSON.parse(String(init.body)) : undefined,
        token: String(init?.headers?.["authorization"])
      });

      return new Response(JSON.stringify({ data }), {
        status,
        headers: { "content-type": "application/json" }
      });
    }
  });

  return { client, requests };
}
