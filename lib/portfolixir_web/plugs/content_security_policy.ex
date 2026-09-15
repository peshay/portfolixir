defmodule PortfolixirWeb.ContentSecurityPolicy do
  @moduledoc """
  The browser pages' Content-Security-Policy (#382, Sprint 11 Lane C).

  Every browser response carries one policy: scripts only from the instance
  itself plus the root layout's three inline scripts, each admitted by a
  nonce minted for that request; styles from the instance plus inline `style`
  attributes (the data-driven colours and tree indents the pages render —
  an attribute cannot carry a nonce, and CSS is not the injection vector the
  policy exists for); images from the instance plus `data:` URLs (the chart
  export draws its SVG into a canvas through one); connections to the
  instance and to its own WebSocket origin; no plugins, no foreign frames,
  forms only to the instance.

  The router's browser pipelines put the **static** half of this policy
  through `Phoenix.Controller.put_secure_browser_headers/2`: that is the text
  Sobelow checks, and the fail-closed header a page would carry if this plug
  were ever dropped — its inline boot scripts blocked, never a foreign script
  admitted. This plug then mints the nonce, assigns it as `:csp_nonce` for
  the root layout, and replaces the header with the same text plus the nonce
  and the request host's socket origin. `static_policy/0` and `policy/2`
  render the same directive list, so the two cannot drift.

  Deliberately absent: `'unsafe-eval'`, `'unsafe-inline'` for scripts, and
  inline event handlers anywhere in the templates — the controls that used
  to call into `window.Portfolixir` from an `onclick` are wired through data
  attributes and the layout's own listeners, pinned by
  `test/invariants/csp_inline_script_test.exs`.
  """
  @behaviour Plug

  import Plug.Conn

  @nonce_bytes 18

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    nonce = generate_nonce()

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", policy(nonce, socket_host(conn)))
  end

  @doc "A fresh nonce: #{@nonce_bytes} random bytes, base64 — the CSP nonce grammar."
  @spec generate_nonce() :: String.t()
  def generate_nonce, do: @nonce_bytes |> :crypto.strong_rand_bytes() |> Base.encode64()

  @doc "The policy without its per-request parts — the pipelines' static header."
  @spec static_policy() :: String.t()
  def static_policy, do: render(directives(nil, nil))

  @doc """
  The policy for one request: `nonce` admits the root layout's inline scripts,
  `host` (`host` or `host:port`, as the browser addressed the instance) names
  the WebSocket origin the LiveView client connects to.
  """
  @spec policy(String.t(), String.t()) :: String.t()
  def policy(nonce, host) when is_binary(nonce) and is_binary(host),
    do: render(directives(nonce, host))

  defp directives(nonce, host) do
    [
      {"default-src", ["'self'"]},
      {"script-src", ["'self'" | nonce_source(nonce)]},
      {"style-src", ["'self'", "'unsafe-inline'"]},
      {"img-src", ["'self'", "data:"]},
      {"connect-src", ["'self'" | socket_sources(host)]},
      {"font-src", ["'self'"]},
      {"object-src", ["'none'"]},
      {"base-uri", ["'self'"]},
      {"frame-ancestors", ["'self'"]},
      {"form-action", ["'self'"]}
    ]
  end

  defp nonce_source(nil), do: []
  defp nonce_source(nonce), do: ["'nonce-#{nonce}'"]

  # Modern browsers match 'self' against the page's own ws/wss origin; the
  # explicit sources cover the ones that do not.
  defp socket_sources(nil), do: []
  defp socket_sources(host), do: ["ws://#{host}", "wss://#{host}"]

  defp render(directives) do
    Enum.map_join(directives, "; ", fn {name, sources} ->
      name <> " " <> Enum.join(sources, " ")
    end) <> ";"
  end

  # The Host header as the browser sent it (host, or host:port), already
  # validated against the allow-list by PortfolixirWeb.HostGuard ahead of the
  # router. A header that is absent or not a host name falls back to the
  # parsed host and port, so the directive never carries a foreign character.
  defp socket_host(conn) do
    case get_req_header(conn, "host") do
      [host | _] when host != "" ->
        if Regex.match?(~r/^[A-Za-z0-9.\-_\[\]:]+$/, host), do: host, else: parsed_host(conn)

      _ ->
        parsed_host(conn)
    end
  end

  defp parsed_host(%Plug.Conn{host: host, port: port}) when port in [80, 443], do: host
  defp parsed_host(%Plug.Conn{host: host, port: port}), do: "#{host}:#{port}"
end
