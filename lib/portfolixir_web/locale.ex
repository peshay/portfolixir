defmodule PortfolixirWeb.Locale do
  @moduledoc false

  import Plug.Conn

  @default_locale "en"
  @supported_locales ~w(en de)

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)
    query_locale = normalize_locale(conn.query_params["locale"])

    locale =
      query_locale ||
        normalize_locale(conn.cookies["portfolixir_locale"]) ||
        preferred_browser_locale(conn) ||
        @default_locale

    Gettext.put_locale(PortfolixirWeb.Gettext, locale)

    conn
    |> assign(:locale, locale)
    |> put_session("locale", locale)
    |> maybe_store_locale(query_locale)
  end

  def supported_locales, do: @supported_locales

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
