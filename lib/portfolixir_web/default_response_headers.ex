defmodule PortfolixirWeb.DefaultResponseHeaders do
  @moduledoc """
  The headers every response of the instance carries, whoever builds it
  (E25 S7, F07; closing-act finding SR-1):

    * `Cross-Origin-Resource-Policy: same-origin` on every response — only
      this origin reads it, so a page on another site open in the same
      browser can neither embed nor probe one;
    * the **static** `Content-Security-Policy`
      (`PortfolixirWeb.ContentSecurityPolicy.static_policy/0`), the
      fail-closed policy with no inline script admitted, on every response
      that is not JSON — the JSON API carries no browser policy, as before.

  The router's browser pipelines and `Plug.Static` set these themselves, and
  a page's per-request nonce policy is never replaced: a header already on
  the response when it is sent is left as it is. What they never reached are
  the responses built outside them: the error page of an unknown path, the
  Host guard's refusal, and the answer to a request an endpoint plug refuses
  (a body the parser cannot read). Phoenix renders the last kind from the
  connection as it entered the endpoint, so the check is registered there —
  on the way in, before any plug — by wrapping the endpoint's own `call/2`:

      use Phoenix.Endpoint, otp_app: :portfolixir
      @before_compile PortfolixirWeb.DefaultResponseHeaders

  Registered after `use Phoenix.Endpoint`, the hook runs after Phoenix's own
  and so wraps the `call/2` that renders the error pages.
  """

  import Plug.Conn

  @doc "Registers the default headers on `conn`, added when it is sent unless already set."
  @spec register(Plug.Conn.t()) :: Plug.Conn.t()
  def register(%Plug.Conn{} = conn), do: register_before_send(conn, &put_defaults/1)

  @doc false
  @spec put_defaults(Plug.Conn.t()) :: Plug.Conn.t()
  def put_defaults(%Plug.Conn{} = conn) do
    conn
    |> put_new("cross-origin-resource-policy", "same-origin")
    |> then(fn conn ->
      if json?(conn),
        do: conn,
        else:
          put_new(
            conn,
            "content-security-policy",
            PortfolixirWeb.ContentSecurityPolicy.static_policy()
          )
    end)
  end

  defp put_new(conn, name, value) do
    case get_resp_header(conn, name) do
      [] -> put_resp_header(conn, name, value)
      _set -> conn
    end
  end

  defp json?(conn) do
    case get_resp_header(conn, "content-type") do
      [type | _] -> String.starts_with?(type, "application/json")
      [] -> false
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      defoverridable call: 2

      def call(conn, opts), do: super(PortfolixirWeb.DefaultResponseHeaders.register(conn), opts)
    end
  end
end
