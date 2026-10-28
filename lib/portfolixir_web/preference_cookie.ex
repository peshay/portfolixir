defmodule PortfolixirWeb.PreferenceCookie do
  @moduledoc """
  The cookies that remember the view, benchmark and language choices
  (`PortfolixirWeb.ViewScope`, `PortfolixirWeb.BenchmarkScope`,
  `PortfolixirWeb.Locale`), read and written in one place (security review
  2026-10-12, K02).

  A preference is taken only when this server wrote it:

  - **Signed.** Every value is signed with a key derived from
    `SECRET_KEY_BASE` and the cookie's name, so a cookie another origin of the
    same host name planted (another port, a sibling subdomain) does not
    verify and is read as no choice at all.
  - **One of a name.** When the Cookie header carries a preference cookie's
    name more than once — a twin with a longer `Path` or a `Domain`, which the
    browser lists first — the choice is dropped rather than resolved in
    favour of whichever came first: a signed value can be copied, the order
    of twins is the planter's.
  - **`__Host-` on HTTPS.** Over HTTPS the cookie is named with the `__Host-`
    prefix, which the browser accepts only as `Secure`, host-only and
    `Path=/`, so no `Domain` or `Path` variant of it can be set; a cookie
    without the prefix is not read there.

  A cookie written before this rule, unsigned, does not verify: the page
  falls back to the default view, no benchmark and the browser's language
  until the operator chooses again, and that choice replaces it (on HTTPS the
  old cookie is no longer read and expires on its own).
  """

  import Plug.Conn

  alias Plug.Conn.Cookies

  @host_prefix "__Host-"
  # One year, the horizon every preference cookie has had.
  @max_age 60 * 60 * 24 * 365

  @doc """
  The name the cookie `base` carries on this request: `base` over plain HTTP,
  `"__Host-" <> base` over HTTPS.
  """
  @spec name(Plug.Conn.t(), String.t()) :: String.t()
  def name(%Plug.Conn{scheme: :https}, base), do: @host_prefix <> base
  def name(%Plug.Conn{}, base), do: base

  @doc """
  The value this server wrote under `base`, or `nil`: for no cookie, a value
  that does not verify, or a name the Cookie header carries more than once.
  """
  @spec read(Plug.Conn.t(), String.t()) :: String.t() | nil
  def read(%Plug.Conn{} = conn, base) do
    name = name(conn, base)

    case request_values(conn, name) do
      [signed] -> verify(conn, name, signed)
      _none_or_twins -> nil
    end
  end

  @doc "Remembers `value` under `base` for a year, signed."
  @spec put(Plug.Conn.t(), String.t(), String.t()) :: Plug.Conn.t()
  def put(%Plug.Conn{} = conn, base, value) when is_binary(value) do
    put_resp_cookie(conn, name(conn, base), value,
      sign: true,
      max_age: @max_age,
      same_site: "Lax",
      path: "/"
    )
  end

  @doc "Forgets the choice remembered under `base`."
  @spec delete(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def delete(%Plug.Conn{} = conn, base) do
    delete_resp_cookie(conn, name(conn, base), same_site: "Lax", path: "/")
  end

  # Every value the request's Cookie headers carry under `name`, in order;
  # Plug's own decoding keeps the first of a duplicated name and so cannot
  # tell a twin from a single cookie.
  defp request_values(conn, name) do
    for {"cookie", header} <- conn.req_headers,
        pair <- :binary.split(header, ";", [:global]),
        {^name, value} <- Cookies.decode(pair),
        do: value
  end

  defp verify(%Plug.Conn{secret_key_base: secret}, name, signed) when is_binary(secret) do
    case Plug.Crypto.verify(secret, name <> "_cookie", signed, keys: Plug.Keys) do
      {:ok, value} when is_binary(value) -> value
      _invalid -> nil
    end
  end

  defp verify(_conn, _name, _signed), do: nil
end
