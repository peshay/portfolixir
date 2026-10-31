defmodule PortfolixirWeb.PreferenceCookieHelpers do
  @moduledoc """
  Preference cookies as the browser holds them once this server wrote them:
  signed (`PortfolixirWeb.PreferenceCookie`, K02). A test that wants a page in
  German, or a remembered view or benchmark, puts the cookie the server would
  have set rather than a plain value, which the server no longer reads.
  """

  @max_age 60 * 60 * 24 * 365

  @doc "Puts the preference cookie `name` with `value`, signed as the server signs it."
  @spec put_preference_cookie(Plug.Conn.t(), String.t(), String.t()) :: Plug.Conn.t()
  def put_preference_cookie(conn, name, value) do
    Plug.Test.put_req_cookie(conn, name, sign(name, value))
  end

  @doc "The value `name` carries signed, as a `Cookie` header pair `name=signed`."
  @spec cookie_pair(String.t(), String.t()) :: String.t()
  def cookie_pair(name, value), do: name <> "=" <> sign(name, value)

  @doc """
  The value a response remembered under `name`: the verified value, `:deleted`
  for a deleted cookie, `nil` when the response wrote none.
  """
  @spec remembered(Plug.Conn.t(), String.t()) :: String.t() | :deleted | nil
  def remembered(%Plug.Conn{resp_cookies: cookies}, name) do
    case cookies[name] do
      %{max_age: 0} ->
        :deleted

      %{value: signed} ->
        {:ok, value} = Plug.Crypto.verify(secret(), name <> "_cookie", signed, keys: Plug.Keys)
        value

      nil ->
        nil
    end
  end

  defp sign(name, value),
    do: Plug.Crypto.sign(secret(), name <> "_cookie", value, keys: Plug.Keys, max_age: @max_age)

  defp secret, do: PortfolixirWeb.Endpoint.config(:secret_key_base)
end
