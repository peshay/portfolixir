defmodule PortfolixirWeb.LayoutView do
  use Phoenix.Component

  def render("root.html", assigns) do
    conn = assigns[:conn]
    locale = assigns[:locale] || (conn && conn.assigns[:locale]) || "en"
    assigns = assign(assigns, :locale, locale)

    ~H"""
    <!DOCTYPE html>
    <html lang={@locale}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>Portfolixir</title>
      </head>
      <body>
        <%= @inner_content %>
        <script src="/vendor/phoenix.min.js">
        </script>
        <script src="/vendor/phoenix_live_view.min.js">
        </script>
        <script id="live-view-client-script">
          (function () {
            var csrfTokenElement = document.querySelector("meta[name='csrf-token']");
            var csrfToken = csrfTokenElement && csrfTokenElement.getAttribute("content");

            if (!window.Phoenix || !window.LiveView || !csrfToken) {
              return;
            }

            var liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
              params: { _csrf_token: csrfToken }
            });

            liveSocket.connect();
            window.liveSocket = liveSocket;
          })();
        </script>
      </body>
    </html>
    """
  end
end
