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
            var accent = window.localStorage && window.localStorage.getItem("portfolixir-accent");
            if (["violet", "teal", "coral"].indexOf(accent) === -1) {
              accent = "violet";
            }
            document.documentElement.dataset.theme = mode;
            document.documentElement.dataset.accent = accent;
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

            var Hooks = {};

            Hooks.ColumnPrefs = {
              mounted: function () {
                var key = this.el.dataset.storageKey || "securities.columns";
                var raw = null;
                try { raw = window.localStorage && window.localStorage.getItem(key); } catch (_) {}

                if (raw) {
                  try {
                    var stored = JSON.parse(raw);
                    if (Array.isArray(stored) && stored.length > 0) {
                      this.pushEvent("set_columns", { columns: stored });
                    }
                  } catch (_) {}
                }

                this.handleEvent("column-prefs-changed", function (payload) {
                  try {
                    if (window.localStorage && payload && Array.isArray(payload.columns)) {
                      window.localStorage.setItem(key, JSON.stringify(payload.columns));
                    }
                  } catch (_) {}
                });
              }
            };

            Hooks.ChartCrosshair = {
              mounted: function () {
                this.payload = this.readPayload();
                this.svg = this.el.querySelector("svg.security-chart");

                if (!this.svg) {
                  return;
                }

                this.crosshair = document.createElement("div");
                this.crosshair.className = "chart-crosshair";
                this.crosshair.hidden = true;
                this.el.appendChild(this.crosshair);

                this.tooltip = document.createElement("div");
                this.tooltip.className = "chart-tooltip";
                this.tooltip.hidden = true;
                this.tooltip.setAttribute("role", "status");
                this.el.appendChild(this.tooltip);

                var self = this;
                this.onMove = function (event) { self.handleMove(event); };
                this.onLeave = function () { self.hide(); };

                this.svg.addEventListener("pointermove", this.onMove);
                this.svg.addEventListener("pointerdown", this.onMove);
                this.svg.addEventListener("pointerleave", this.onLeave);
                this.svg.addEventListener("pointercancel", this.onLeave);
              },
              updated: function () {
                this.payload = this.readPayload();
                this.hide();
              },
              destroyed: function () {
                if (this.svg) {
                  this.svg.removeEventListener("pointermove", this.onMove);
                  this.svg.removeEventListener("pointerdown", this.onMove);
                  this.svg.removeEventListener("pointerleave", this.onLeave);
                  this.svg.removeEventListener("pointercancel", this.onLeave);
                }
              },
              readPayload: function () {
                var node = this.el.querySelector("script[data-chart-payload]");
                if (!node) return { points: [], txs: [], view: { width: 960, height: 320 }, currency: "" };
                try {
                  return JSON.parse(node.textContent);
                } catch (_) {
                  return { points: [], txs: [], view: { width: 960, height: 320 }, currency: "" };
                }
              },
              handleMove: function (event) {
                var payload = this.payload;
                if (!payload || !payload.points || payload.points.length === 0) {
                  return;
                }

                var svgRect = this.svg.getBoundingClientRect();
                var frameRect = this.el.getBoundingClientRect();
                if (svgRect.width === 0 || svgRect.height === 0) return;

                var view = payload.view || { width: 960, height: 320 };
                var pointerSvgX = (event.clientX - svgRect.left) * (view.width / svgRect.width);

                var idx = this.nearestIndex(payload.points, pointerSvgX);
                var point = payload.points[idx];
                var iso = point[0];
                var close = point[1];
                var px = point[2];
                var py = point[3];

                var svgOffsetX = svgRect.left - frameRect.left;
                var svgOffsetY = svgRect.top - frameRect.top;
                var cssX = svgOffsetX + px * (svgRect.width / view.width);
                var cssY = svgOffsetY + py * (svgRect.height / view.height);

                this.crosshair.style.left = cssX + "px";
                this.crosshair.style.top = svgOffsetY + "px";
                this.crosshair.style.height = svgRect.height + "px";
                this.crosshair.hidden = false;

                var tx = this.transactionAt(payload.txs, px);
                this.renderTooltip(iso, close, payload.currency, tx);

                this.positionTooltip(cssX, cssY, frameRect.width);
              },
              nearestIndex: function (points, x) {
                var lo = 0;
                var hi = points.length - 1;
                while (lo < hi) {
                  var mid = (lo + hi) >> 1;
                  if (points[mid][2] < x) lo = mid + 1; else hi = mid;
                }
                if (lo > 0 && Math.abs(points[lo - 1][2] - x) < Math.abs(points[lo][2] - x)) {
                  return lo - 1;
                }
                return lo;
              },
              transactionAt: function (txs, x) {
                if (!txs || txs.length === 0) return null;
                for (var i = 0; i < txs.length; i++) {
                  if (Math.abs(txs[i].x - x) <= 3) return txs[i];
                }
                return null;
              },
              renderTooltip: function (iso, close, currency, tx) {
                var parts = [
                  '<div class="chart-tooltip__date">' + iso + "</div>",
                  '<div class="chart-tooltip__price">' + close + (currency ? " " + currency : "") + "</div>"
                ];
                if (tx) {
                  parts.push(
                    '<div class="chart-tooltip__tx chart-tooltip__tx--' + tx.type + '">' +
                      tx.type + " " + tx.quantity + " @ " + tx.price +
                    "</div>"
                  );
                }
                this.tooltip.innerHTML = parts.join("");
                this.tooltip.hidden = false;
              },
              positionTooltip: function (cssX, cssY, frameWidth) {
                var tipWidth = this.tooltip.offsetWidth || 120;
                var pad = 8;
                var x = cssX + 12;
                if (x + tipWidth + pad > frameWidth) {
                  x = cssX - tipWidth - 12;
                  if (x < pad) x = pad;
                }
                this.tooltip.style.left = x + "px";
                this.tooltip.style.top = Math.max(pad, cssY - 16) + "px";
              },
              hide: function () {
                if (this.crosshair) this.crosshair.hidden = true;
                if (this.tooltip) this.tooltip.hidden = true;
              }
            };

            var liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
              hooks: Hooks,
              params: { _csrf_token: csrfToken }
            });

            liveSocket.connect();
            window.liveSocket = liveSocket;
          })();
        </script>
        <script id="theme-control-script">
          (function () {
            var allowedModes = ["system", "light", "dark"];
            var allowedAccents = ["violet", "teal", "coral"];

            function currentMode() {
              var stored = window.localStorage && window.localStorage.getItem("portfolixir-theme");
              return allowedModes.indexOf(stored) === -1 ? "system" : stored;
            }

            function currentAccent() {
              var stored = window.localStorage && window.localStorage.getItem("portfolixir-accent");
              return allowedAccents.indexOf(stored) === -1 ? "violet" : stored;
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

            function applyAccent(accent) {
              if (allowedAccents.indexOf(accent) === -1) {
                accent = "violet";
              }

              if (window.localStorage) {
                window.localStorage.setItem("portfolixir-accent", accent);
              }

              document.documentElement.dataset.accent = accent;
              syncAccentControls(accent);
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

            function syncAccentControls(accent) {
              document.querySelectorAll("[data-accent-control]").forEach(function (container) {
                container.dataset.currentAccent = accent;
              });

              document.querySelectorAll("[data-accent-control] [data-accent-choice]").forEach(function (control) {
                var active = control.dataset.accentChoice === accent;
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

              var accentControl = event.target && event.target.closest("[data-accent-choice]");

              if (accentControl) {
                applyAccent(accentControl.dataset.accentChoice);

                var accentMenu = accentControl.closest("details");
                if (accentMenu) {
                  accentMenu.removeAttribute("open");
                }

                return;
              }

              if (event.target && !event.target.closest("[data-theme-control]")) {
                document.querySelectorAll("[data-theme-control][open]").forEach(function (menu) {
                  menu.removeAttribute("open");
                });
              }

              if (event.target && !event.target.closest("[data-accent-control]")) {
                document.querySelectorAll("[data-accent-control][open]").forEach(function (menu) {
                  menu.removeAttribute("open");
                });
              }
            });

            document.addEventListener("DOMContentLoaded", function () {
              syncControls(currentMode());
              syncAccentControls(currentAccent());
            });
            document.addEventListener("phx:update", function () {
              syncControls(currentMode());
              syncAccentControls(currentAccent());
            });
          })();
        </script>
      </body>
    </html>
    """
  end
end
