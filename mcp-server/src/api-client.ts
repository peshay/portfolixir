import { escapeInvisible, escapeInvisibleText } from "./invisible-text.js";

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
 * timeout, or a gateway's error (#1045), is answered as a read's.
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
 * Why a write's outcome is unknown: the deadline in milliseconds; the failed
 * connection's code (each address's, joined, when a connect failed on
 * several); the status a gateway answered in the server's place (#1045); or
 * the 2xx status of an answer that is not JSON (#1045). The last two carry
 * the answer's excerpt, quoted as `excerptOf` quotes it, when it had a body.
 */
export type OutcomeUnknownCause =
  | number
  | { connection: string }
  | { gateway: number; excerpt?: string }
  | { unreadable: number; excerpt: string };

/**
 * A write got no answer before its deadline (E25 S7, G31), or its connection
 * failed in a way that does not prove the request never left (#955): a
 * reset, a socket closed while the answer arrived, a TLS failure, a failure
 * with no code. A gateway answering 502, 504, 520 or 524 in the server's
 * place is the same situation reported by the proxy instead of the socket,
 * and so is a 2xx
 * whose body is not JSON (#1045): the server may have committed the write,
 * and its answer cannot be read. The companion cannot tell whether the write
 * took effect, so the outcome is unknown: a retry without a re-read can store
 * a second record. A read that fails changes nothing and is not this error.
 */
export class ApiOutcomeUnknownError extends Error {
  override readonly name = "ApiOutcomeUnknownError";

  constructor(
    readonly method: string,
    readonly path: string,
    cause: OutcomeUnknownCause
  ) {
    let what: string;
    let quoted = "";

    if (typeof cause === "number") {
      what = `got no answer within ${cause / 1000} s`;
    } else if ("connection" in cause) {
      what = `got no complete answer (${cause.connection}); the request may have been sent`;
    } else if ("gateway" in cause) {
      what = `was not answered by the server: the gateway answered ${cause.gateway} instead`;
      quoted = cause.excerpt === undefined ? "" : ` The gateway's answer: ${cause.excerpt}.`;
    } else {
      what = `was answered ${cause.unreadable} with a body that is not JSON`;
      quoted = ` The answer: ${cause.excerpt}.`;
    }

    super(
      `Portfolixir API outcome unknown: ${method} ${path} ${what}, and the server may still ` +
        "have committed it. Re-read the records it would have changed before retrying: a " +
        `blind retry can store a duplicate.${quoted}`
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
 * request it sends says so, so a timeout, or a gateway's error (#1045), is
 * answered as a read's.
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

  const send = async (method: string, path: string, body: unknown, read: boolean): Promise<unknown> => {
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

    // The status is read before the body (#1045). The body is read as bytes,
    // so an excerpt can state its length, and decoded as text() decodes it.
    const { status } = response;
    const bytes = new Uint8Array(await transport(() => response.arrayBuffer()));
    const text = new TextDecoder().decode(bytes);
    const blank = isBlank(text);
    const quote = (): string => excerptOf(redact(text, options.token), bytes.byteLength);

    const parsed = parseJson(text);

    // A gateway status is a gateway answering in the server's place: like a
    // lost connection (#955), it says nothing of whether the server committed
    // the write. The one exception is a 502 in the API's own error envelope:
    // the API answers that itself when the rate sync's provider fails
    // (exchange_rate_controller.ex), so the server answered, and nothing is
    // unknown. A read's gateway status is a plain error, safe to retry. A 503
    // is none of them, by the spec's decision: a proxy that answers 503
    // usually did not forward the request, but some (Envoy, Istio) answer it
    // after forwarding, so the docs tell the agent to re-read before retrying
    // a write that got one.
    const failedUpstream = GATEWAY_STATUSES.has(status);
    const apiOwn = status === 502 && parsed.json && isApiErrorEnvelope(parsed.value);
    const gateway = failedUpstream && !apiOwn;

    if (gateway && !read) {
      throw new ApiOutcomeUnknownError(method, path, {
        gateway: status,
        excerpt: blank ? undefined : quote()
      });
    }

    const retrySafe =
      failedUpstream && read
        ? gateway
          ? ` The gateway answered ${status} instead of the server; the call changes nothing, ` +
            "so it can be retried."
          : " The call changes nothing, so it can be retried."
        : "";

    // An answer that is not JSON is named by its status and quoted, never
    // passed on as a parse failure (#1045). A write the server answered 2xx
    // may have committed, and its answer cannot be read.
    if (!parsed.json) {
      if (response.ok && !read) {
        throw new ApiOutcomeUnknownError(method, path, { unreadable: status, excerpt: quote() });
      }

      throw new Error(
        `Portfolixir API request failed: ${method} ${path} answered ${status} with a body that ` +
          `is not JSON: ${quote()}.${retrySafe}`
      );
    }

    if (!response.ok) {
      // A read's gateway status with nothing in it: no `null` to quote.
      if (blank && retrySafe !== "") {
        throw new Error(
          `Portfolixir API request failed: ${method} ${path} answered ${status} with no body.${retrySafe}`
        );
      }

      throw new Error(
        `Portfolixir API request failed: ${status} ${redact(JSON.stringify(parsed.value), options.token)}` +
          (retrySafe === "" ? "" : `.${retrySafe}`)
      );
    }

    return parsed.value;
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
        return await send(method, path, body, read);
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

// The statuses a gateway answers once it has forwarded the request and got
// no usable answer back (#1045): 502 and 504, and Cloudflare's 520 (the
// origin's answer was unusable) and 524 (the origin took the request and did
// not answer in time).
const GATEWAY_STATUSES = new Set([502, 504, 520, 524]);

// A body of JSON whitespace only (space, tab, line feed, carriage return): an
// empty answer. Any other blank character, a no-break space among them, is a
// body that is not JSON (#1045).
function isBlank(text: string): boolean {
  return /^[ \t\n\r]*$/.test(text);
}

// Every answer reaches the agent with the characters an operator cannot see
// spelled out (E25 S7, G20): the one place the companion escapes them. A
// blank body is null; a body that is not JSON says so instead of throwing
// (#1045), so the caller can name the status that came with it.
function parseJson(text: string): { json: true; value: unknown } | { json: false } {
  if (isBlank(text)) {
    return { json: true, value: null };
  }

  let value: unknown;

  try {
    value = JSON.parse(text);
  } catch {
    return { json: false };
  }

  return { json: true, value: escapeInvisible(value) };
}

// The API's JSON error envelope (#1045): exactly one key, `errors`, holding
// an object with something in it, the shape every error the API answers
// carries. An empty `errors`, or one beside other keys, is not the API's
// (review round): a proxy answering 502 in that shape must not make a write
// the server may have committed read as a refusal.
function isApiErrorEnvelope(value: unknown): boolean {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return false;
  }

  const keys = Object.keys(value);

  if (keys.length !== 1 || keys[0] !== "errors") {
    return false;
  }

  const { errors } = value as { errors: unknown };

  return (
    typeof errors === "object" &&
    errors !== null &&
    !Array.isArray(errors) &&
    Object.keys(errors).length > 0
  );
}

const REDACTED = "[redacted]";

// A bearer credential as a header, a page or a JSON string carries it: the
// scheme word, then its value up to a space, a quote or a tag.
const BEARER = /\b(bearer)\s+[^\s"'<>]+/gi;

/**
 * `text` with the companion's own API token, and any bearer credential's
 * value, replaced by `[redacted]` (#1045 review round). A proxy's page can
 * echo the request's headers, `Authorization: Bearer …` among them; quoted
 * to the agent, it would hand a read-only profile the token that writes.
 * The token is replaced as written and as JSON-quoting writes it.
 */
function redact(text: string, token: string): string {
  let redacted = text;

  if (token !== "") {
    for (const form of new Set([token, JSON.stringify(token).slice(1, -1)])) {
      redacted = redacted.replaceAll(form, REDACTED);
    }
  }

  return redacted.replace(BEARER, `$1 ${REDACTED}`);
}

const EXCERPT_LIMIT = 120;

// How much of a body an excerpt reads, in UTF-16 code units: enough for 120
// characters once whitespace is collapsed, never the whole of a large body.
const EXCERPT_SCAN = 4096;

// DEL and the C1 controls, U+007F to U+009F, spelled as the invisible
// characters are: neither the escape nor the JSON quote touches them. So is
// every blank character but JSON's whitespace (a form feed, a no-break or an
// ideographic space, a line separator): collapsed, a body of them quoted as
// `""`, which reads as no body at all (#1045 review round).
const SPELLED = /[\u007F-\u009F]|[^\S \t\n\r]/gu;

function spellControlsAndBlanks(text: string): string {
  return text.replace(
    SPELLED,
    (character) => `[U+${(character.codePointAt(0) as number).toString(16).toUpperCase().padStart(4, "0")}]`
  );
}

// A character's length once JSON-quoted: two for a quote or a backslash, six
// for a C0 control written `\u00XX`, one for any other, a surrogate pair
// included.
function quotedLength(character: string): number {
  return character.length === 1 ? JSON.stringify(character).length - 2 : 1;
}

/**
 * A body quoted for an error message (#1045): the first few thousand code
 * units of it, escaped as every answer is (`escapeInvisibleText`) with DEL,
 * the C1 controls and the blank characters other than JSON's whitespace
 * spelled out too, JSON's whitespace collapsed, and JSON-quoted, so a quote
 * or a control character in it reads as the letters it is. At most 120
 * characters as quoted, JSON's escapes counted (review round), never cut
 * inside a `[U+XXXX]` or a JSON escape. When cut, the whole body's length in
 * bytes follows. The caller redacts the body first (`redact`).
 */
function excerptOf(text: string, byteLength: number): string {
  let scanned = text.length > EXCERPT_SCAN ? text.slice(0, EXCERPT_SCAN) : text;
  const last = scanned.charCodeAt(scanned.length - 1);

  // Never half a surrogate pair at the end of what was read.
  if (scanned.length < text.length && last >= 0xd800 && last <= 0xdbff) {
    scanned = scanned.slice(0, -1);
  }

  const collapsed = spellControlsAndBlanks(escapeInvisibleText(scanned))
    .replace(/[ \t\n\r]+/g, " ")
    .trim();
  const characters = Array.from(collapsed);

  // How many characters fit in the limit as quoted, and how many beside the
  // ellipsis a cut adds.
  let length = 0;
  let fit = 0;
  let kept = 0;

  for (const character of characters) {
    length += quotedLength(character);

    if (length > EXCERPT_LIMIT) {
      break;
    }

    fit += 1;

    if (length < EXCERPT_LIMIT) {
      kept = fit;
    }
  }

  if (scanned.length === text.length && fit === characters.length) {
    return JSON.stringify(collapsed);
  }

  let head = characters.slice(0, kept).join("");

  // A cut that lands inside an escape drops what it kept of it: `[`, `[U`,
  // `[U+`, or `[U+` and some of its digits.
  if (kept < characters.length) {
    head = head.replace(/\[(?:U(?:\+[0-9A-F]{0,6})?)?$/, "");
  }

  return `${JSON.stringify(`${head}…`)} (cut from ${byteLength} bytes)`;
}
