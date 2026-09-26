defmodule PortfolixirWeb.Locale do
  @moduledoc false

  import Plug.Conn

  @default_locale "en"
  @supported_locales ~w(en de)

  def init(opts), do: opts

  # A `?locale=` from another site answers that request in the language it
  # names, and neither the cookie nor the session remembers it (E25 S7, F18;
  # the review round's S7E-4, `PortfolixirWeb.FetchSite`): the session keeps
  # the remembered language, and the page reads its own from its address
  # (`PortfolixirWeb.LiveLocale`).
  def call(conn, _opts) do
    conn = fetch_query_params(conn)
    query_locale = normalize_locale(conn.query_params["locale"])

    stored_locale =
      normalize_locale(conn.cookies["portfolixir_locale"]) ||
        preferred_browser_locale(conn) ||
        @default_locale

    locale = query_locale || stored_locale
    remember? = not is_nil(query_locale) and PortfolixirWeb.FetchSite.remember?(conn)
    session_locale = if is_nil(query_locale) or remember?, do: locale, else: stored_locale

    Gettext.put_locale(PortfolixirWeb.Gettext, locale)

    conn
    |> assign(:locale, locale)
    |> put_session("locale", session_locale)
    |> maybe_store_locale(if remember?, do: locale)
  end

  def supported_locales, do: @supported_locales

  @doc """
  The supported locale a raw value names — trimmed, lower-cased, a region
  dropped (`"DE-de"` is `"de"`) — or `nil`.
  """
  @spec normalize(term()) :: String.t() | nil
  def normalize(locale), do: normalize_locale(locale)

  @doc """
  The locale of a page answered outside the router's pipeline, such as an
  error the endpoint refuses before any route runs (E25 S2, F68): the one the
  pipeline chose when it ran, else the locale cookie, then the browser's
  language, then English.
  """
  @spec locale_of(Plug.Conn.t()) :: String.t()
  def locale_of(%Plug.Conn{assigns: %{locale: locale}}) when locale in @supported_locales,
    do: locale

  def locale_of(%Plug.Conn{} = conn) do
    conn = fetch_cookies(conn)

    normalize_locale(conn.cookies["portfolixir_locale"]) || preferred_browser_locale(conn) ||
      @default_locale
  end

  defp maybe_store_locale(conn, nil), do: conn

  defp maybe_store_locale(conn, locale) do
    put_resp_cookie(conn, "portfolixir_locale", locale,
      max_age: 60 * 60 * 24 * 365,
      same_site: "Lax"
    )
  end

  defp preferred_browser_locale(conn) do
    conn
    |> get_req_header("accept-language")
    |> List.first()
    |> case do
      nil ->
        nil

      header ->
        header
        |> String.split(",", trim: true)
        |> Enum.find_value(fn part ->
          part
          |> String.split(";", parts: 2)
          |> hd()
          |> normalize_locale()
        end)
    end
  end

  defp normalize_locale(locale) when is_binary(locale) do
    locale =
      locale
      |> String.trim()
      |> String.downcase()
      |> String.split("-", parts: 2)
      |> hd()

    if locale in @supported_locales, do: locale
  end

  defp normalize_locale(_locale), do: nil
end
