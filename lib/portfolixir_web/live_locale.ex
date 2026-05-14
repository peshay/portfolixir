defmodule PortfolixirWeb.LiveLocale do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, session, socket) do
    locale =
      session
      |> Map.get("locale")
      |> normalize_locale()

    Gettext.put_locale(PortfolixirWeb.Gettext, locale)

    {:cont, assign(socket, :locale, locale)}
  end

  defp normalize_locale(locale) when locale in ["en", "de"], do: locale
  defp normalize_locale(_locale), do: "en"
end
