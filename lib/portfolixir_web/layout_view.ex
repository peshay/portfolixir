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
        <meta name="color-scheme" content="light dark" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <link rel="icon" href="/favicon.svg" type="image/svg+xml" />
        <link rel="alternate icon" href="/favicon.ico" />
        <script id="theme-boot">
          (function () {
            var mode = window.localStorage && window.localStorage.getItem("portfolixir-theme");
            if (["system", "light", "dark"].indexOf(mode) === -1) {
              mode = "system";
            }
            document.documentElement.dataset.theme = mode;
          })();
        </script>
        <link rel="stylesheet" href="/app.css" />
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
        <script id="theme-control-script">
          (function () {
            var allowedModes = ["system", "light", "dark"];

            function currentMode() {
              var stored = window.localStorage && window.localStorage.getItem("portfolixir-theme");
              return allowedModes.indexOf(stored) === -1 ? "system" : stored;
            }

            function applyTheme(mode) {
              if (allowedModes.indexOf(mode) === -1) {
                mode = "system";
              }

              if (window.localStorage) {
                window.localStorage.setItem("portfolixir-theme", mode);
              }

              document.documentElement.dataset.theme = mode;
              syncControls(mode);
            }

            function syncControls(mode) {
              document.querySelectorAll("[data-theme-control]").forEach(function (container) {
                container.dataset.currentTheme = mode;
              });

              document.querySelectorAll("[data-theme-control] [data-theme-choice]").forEach(function (control) {
                var active = control.dataset.themeChoice === mode;
                control.classList.toggle("is-active", active);
                control.setAttribute("aria-pressed", active ? "true" : "false");
              });
            }

            document.addEventListener("click", function (event) {
              var control = event.target && event.target.closest("[data-theme-choice]");

              if (control) {
                applyTheme(control.dataset.themeChoice);

                var menu = control.closest("details");
                if (menu) {
                  menu.removeAttribute("open");
                }

                return;
              }

              if (event.target && !event.target.closest("[data-theme-control]")) {
                document.querySelectorAll("[data-theme-control][open]").forEach(function (menu) {
                  menu.removeAttribute("open");
                });
              }
            });

            document.addEventListener("DOMContentLoaded", function () {
              syncControls(currentMode());
            });
            document.addEventListener("phx:update", function () {
              syncControls(currentMode());
            });
          })();
        </script>
      </body>
    </html>
    """
  end
end
