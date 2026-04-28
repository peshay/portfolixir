defmodule PortfolixirWeb.Locale do
  @behaviour Plug

  @cookie "portfolixir_locale"
  @default_locale "en"
  @supported_locales ["en", "de"]

  import Phoenix.Component, only: [assign: 3]

  def init(opts), do: opts

  def call(conn, _opts) do
    conn =
      conn
      |> Plug.Conn.fetch_query_params()
      |> Plug.Conn.fetch_cookies()

    locale = resolve_locale(conn)
    Gettext.put_locale(PortfolixirWeb.Gettext, locale)

    conn
    |> Plug.Conn.assign(:locale, locale)
    |> Plug.Conn.put_session("locale", locale)
    |> maybe_put_locale_cookie(conn.query_params["locale"], locale)
  end

  def live_session(conn) do
    %{"locale" => Map.get(conn.assigns, :locale) || resolve_locale(conn)}
  end

  def on_mount(:default, _params, session, socket) do
    locale = normalize_locale(session["locale"])
    Gettext.put_locale(PortfolixirWeb.Gettext, locale)

    {:cont, assign(socket, :locale, locale)}
  end

  def supported_locale?(locale), do: locale in @supported_locales

  def normalize_locale(locale) when locale in @supported_locales, do: locale
  def normalize_locale(_locale), do: @default_locale

  defp resolve_locale(conn) do
    selected_locale = normalize_selected_locale(conn.query_params["locale"])

    selected_locale ||
      cookie_locale(conn) ||
      accept_language_locale(conn) ||
      @default_locale
  end

  defp normalize_selected_locale(locale) do
    if supported_locale?(locale), do: locale
  end

  defp cookie_locale(conn) do
    conn.req_cookies
    |> Map.get(@cookie)
    |> normalize_selected_locale()
  end

  defp accept_language_locale(conn) do
    conn
    |> Plug.Conn.get_req_header("accept-language")
    |> List.first()
    |> parse_accept_language()
  end

  defp parse_accept_language(nil), do: nil

  defp parse_accept_language(header) do
    header
    |> String.split(",")
    |> Enum.map(&language_tag/1)
    |> Enum.find(&supported_locale?/1)
  end

  defp language_tag(value) do
    value
    |> String.split(";")
    |> List.first()
    |> String.trim()
    |> String.split(["-", "_"])
    |> List.first()
    |> String.downcase()
  end

  defp maybe_put_locale_cookie(conn, selected_locale, locale) do
    if supported_locale?(selected_locale) do
      Plug.Conn.put_resp_cookie(conn, @cookie, locale,
        max_age: 31_536_000,
        same_site: "Lax"
      )
    else
      conn
    end
  end
end
