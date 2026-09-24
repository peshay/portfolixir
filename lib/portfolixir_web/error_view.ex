defmodule PortfolixirWeb.ErrorView do
  @moduledoc """
  The body of every error the endpoint renders (`render_errors`, layout off).

  One clause per format carries every status (E25 S2, F68). With a clause per
  status, any status without one crashed the rendering itself: the client got a
  bodyless 500, and what reached the log was the rendering crash, holding the
  request, instead of the original error.

  - HTML is the status and its reason in the page's language, the same line for
    every status: `403 · Forbidden`, `403 · Zugriff verweigert`. The reason
    phrases are runtime msgids of the `errors` gettext domain.
  - JSON is the API's error shape, in English: `{"errors": {"detail": ...}}`.

  Neither body carries anything from the request.
  """

  alias PortfolixirWeb.Locale

  def render(<<_status::binary-size(3), ".json">> = template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end

  def render(<<status::binary-size(3), ".", _format::binary>> = template, assigns) do
    reason = Phoenix.Controller.status_message_from_template(template)

    translated =
      Gettext.with_locale(PortfolixirWeb.Gettext, locale(assigns), fn ->
        Gettext.dgettext(PortfolixirWeb.Gettext, "errors", reason)
      end)

    status <> " · " <> translated
  end

  defp locale(%{conn: %Plug.Conn{} = conn}), do: Locale.locale_of(conn)
  defp locale(_assigns), do: "en"
end
