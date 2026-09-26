defmodule PortfolixirWeb.LiveLocale do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  # A `?locale=` in the page's own address wins over the session (E25 S7
  # review round, S7E-4): a language from another site is kept out of the
  # session (`PortfolixirWeb.Locale`), so the page it opened reads it from
  # there, and a live navigation reads the remembered one.
  def on_mount(:default, params, session, socket) do
    locale =
      (address_locale(params) || Map.get(session, "locale"))
      |> normalize_locale()

    Gettext.put_locale(PortfolixirWeb.Gettext, locale)

    {:cont, assign(socket, :locale, locale)}
  end

  defp address_locale(%{"locale" => raw}), do: PortfolixirWeb.Locale.normalize(raw)
  defp address_locale(_params), do: nil

  defp normalize_locale(locale) when locale in ["en", "de"], do: locale
  defp normalize_locale(_locale), do: "en"
end
