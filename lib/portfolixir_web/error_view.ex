defmodule PortfolixirWeb.ErrorView do
  @moduledoc """
  The body of every error the endpoint renders (`render_errors`, layout off).

  One clause per format carries every status (E25 S2, F68). With a clause per
  status, any status without one crashed the rendering itself: the client got a
  bodyless 500, and what reached the log was the rendering crash, holding the
  request, instead of the original error.

  - HTML is the status and its reason in the page's language, the same line for
    every status: `403 · Forbidden`, `403 · Zugriff verweigert`. The reason
    phrases are runtime msgids of the `errors` gettext domain. The line stands
    alone in a document that follows the theme like every other page (the
    closing act, board 11 part 4): both colour schemes declared, the app's
    stylesheet for the tokens, and the root layout's theme script for the
    stored light, dark and accent choice, loaded from `/theme-boot.js` because
    an error page may carry the static policy, which admits no inline script.
  - JSON is the API's error shape, in English: `{"errors": {"detail": ...}}`.

  Neither body carries anything from the request.
  """

  use Phoenix.Component

  alias PortfolixirWeb.Locale

  def render(<<_status::binary-size(3), ".json">> = template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end

  def render(<<status::binary-size(3), ".", _format::binary>> = template, assigns) do
    locale = locale(assigns)
    reason = Phoenix.Controller.status_message_from_template(template)

    translated =
      Gettext.with_locale(PortfolixirWeb.Gettext, locale, fn ->
        Gettext.dgettext(PortfolixirWeb.Gettext, "errors", reason)
      end)

    document(locale, status <> " · " <> translated)
  end

  # HEEx escapes the language and the line, like every page's template.
  defp document(locale, line) do
    assigns = %{lang: locale, line: line}

    ~H"""
    <!DOCTYPE html>
    <html lang={@lang}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="color-scheme" content="light dark" />
        <script src="/theme-boot.js">
        </script>
        <link rel="stylesheet" href="/app.css" />
        <title><%= @line %></title>
      </head>
      <body>
        <main class="error-page" data-role="error-status"><%= @line %></main>
      </body>
    </html>
    """
  end

  defp locale(%{conn: %Plug.Conn{} = conn}), do: Locale.locale_of(conn)
  defp locale(_assigns), do: "en"
end
