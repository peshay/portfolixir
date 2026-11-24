// Security review 2026-11, N-93: every API call carries the API token, and
// over plain http it travels unencrypted. That is the documented design on
// the machine itself and on a container network, where the Compose file
// names the API `app`; beyond them the operator is told once, at start. A
// warning, never a refusal, and never a credential: this module is handed
// the base URL only, and names its host alone.

// This machine: the loopback names and addresses.
function onThisMachine(hostname: string): boolean {
  return (
    hostname === "localhost" ||
    hostname.endsWith(".localhost") ||
    hostname === "[::1]" ||
    /^127(?:\.\d{1,3}){3}$/.test(hostname)
  );
}

// A name without a dot is how a container network names a neighbour (the
// Compose service `app`); an address is never such a name.
function containerNetworkName(hostname: string): boolean {
  return !hostname.includes(".") && !hostname.startsWith("[");
}

/**
 * The line to print at start when the API token would cross a link beyond
 * this machine over plain http, naming the variable, the host and the
 * remedy; `undefined` when there is nothing to say: an https base, a base on
 * this machine, a container network's name, or a base that does not parse
 * (which the checks that refuse a start judge, not this one).
 */
export function apiLinkWarning(baseUrl: string): string | undefined {
  let url: URL;

  try {
    url = new URL(baseUrl);
  } catch {
    return undefined;
  }

  const hostname = url.hostname.toLowerCase().replace(/\.$/, "");

  if (url.protocol !== "http:" || hostname === "" || onThisMachine(hostname) || containerNetworkName(hostname)) {
    return undefined;
  }

  return (
    `PORTFOLIXIR_API_BASE_URL is plain http to ${hostname}, which is neither this machine ` +
    "nor a container network's name: every API call carries PORTFOLIXIR_API_TOKEN " +
    "unencrypted over that link, readable by whoever can read it. Use an https base URL, " +
    "or run the companion on the API's own host or container network."
  );
}
