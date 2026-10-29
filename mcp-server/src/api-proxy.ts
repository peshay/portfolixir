// Security review 2026-10-12, K16: Node's opt-in environment proxy
// (NODE_USE_ENV_PROXY=1, NODE_OPTIONS=--use-env-proxy or the --use-env-proxy
// flag) routes every request Node makes through HTTP_PROXY, the companion's
// API calls included, and those carry the API token and the instance's
// records. The companion keeps them off any proxy: when that proxy would
// carry them, it refuses to start, naming NO_PROXY and the host to add. It
// never reconfigures the proxy itself, so an operator whose API is reachable
// only through a proxy decides that knowingly.

export type ApiProxyDecision = { kind: "direct" } | { kind: "refuse"; message: string };

function present(value: string | undefined): value is string {
  return value !== undefined && value.trim() !== "";
}

function envProxyInEffect(env: NodeJS.ProcessEnv, execArgv: readonly string[]): boolean {
  const flag = env.NODE_USE_ENV_PROXY?.trim();
  const options = (env.NODE_OPTIONS ?? "").split(/\s+/);

  return (
    (present(flag) && flag !== "0") ||
    options.includes("--use-env-proxy") ||
    execArgv.includes("--use-env-proxy")
  );
}

// The proxy Node would use for the base URL's scheme; an https URL falls back
// to the http proxy, as Node's environment proxy does.
function proxyFor(protocol: string, env: NodeJS.ProcessEnv): string | undefined {
  const httpProxy = [env.http_proxy, env.HTTP_PROXY].find(present);

  if (protocol === "https:") {
    return [env.https_proxy, env.HTTPS_PROXY].find(present) ?? httpProxy;
  }

  return httpProxy;
}

// Whether NO_PROXY exempts the host, read the way Node's HTTP client reads it
// (undici's EnvHttpProxyAgent): entries split on commas and spaces, an entry
// with a port covers that port only, a plain entry covers that exact host and
// never its subdomains, an entry starting with "." or "*" covers what ends
// with the rest (subdomains only; "*" alone covers everything).
function excluded(noProxy: string, hostname: string, port: number): boolean {
  return noProxy
    .split(/[,\s]/)
    .filter((entry) => entry !== "")
    .some((entry) => {
      const parsed = /^(.+):(\d+)$/.exec(entry);
      const host = (parsed ? parsed[1]! : entry).toLowerCase();
      const entryPort = parsed ? Number.parseInt(parsed[2]!, 10) : 0;

      if (entryPort !== 0 && entryPort !== port) return false;
      if (!/^[.*]/.test(host)) return hostname === host;
      return hostname.endsWith(host.replace(/^\*/, ""));
    });
}

export function apiProxyDecision(
  baseUrl: string,
  env: NodeJS.ProcessEnv,
  execArgv: readonly string[]
): ApiProxyDecision {
  const url = new URL(baseUrl);

  if (!envProxyInEffect(env, execArgv) || proxyFor(url.protocol, env) === undefined) {
    return { kind: "direct" };
  }

  const hostname = url.hostname.toLowerCase();
  const port = Number.parseInt(url.port, 10) || (url.protocol === "https:" ? 443 : 80);
  // As Node reads it: the lower-case variable wins whenever it is set, even
  // blank, which then exempts nothing.
  const noProxy = env.no_proxy ?? env.NO_PROXY ?? "";

  if (excluded(noProxy, hostname, port)) {
    return { kind: "direct" };
  }

  return {
    kind: "refuse",
    message:
      "Node's environment proxy is on (NODE_USE_ENV_PROXY or --use-env-proxy) and NO_PROXY " +
      `does not name the API host ${hostname}: the API calls, with the API token, would go ` +
      `through the proxy. Add ${hostname} to NO_PROXY, or turn the environment proxy off.`
  };
}

/**
 * Applies `apiProxyDecision` to this process at start-up; throws with the
 * refusal's message when the companion must not start.
 */
export function keepApiOffProxy(baseUrl: string): void {
  // Each name read by itself, so the repository's environment scan names
  // every variable the companion reads (NFR-9 B2).
  const env: NodeJS.ProcessEnv = {
    NODE_USE_ENV_PROXY: process.env.NODE_USE_ENV_PROXY,
    NODE_OPTIONS: process.env.NODE_OPTIONS,
    HTTP_PROXY: process.env.HTTP_PROXY,
    http_proxy: process.env.http_proxy,
    HTTPS_PROXY: process.env.HTTPS_PROXY,
    https_proxy: process.env.https_proxy,
    NO_PROXY: process.env.NO_PROXY,
    no_proxy: process.env.no_proxy
  };
  const decision = apiProxyDecision(baseUrl, env, process.execArgv);

  if (decision.kind === "refuse") {
    throw new Error(decision.message);
  }
}
