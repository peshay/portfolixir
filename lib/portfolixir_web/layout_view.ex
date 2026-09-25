defmodule PortfolixirWeb.LayoutView do
  use Phoenix.Component

  def render("root.html", assigns) do
    conn = assigns[:conn]
    locale = assigns[:locale] || (conn && conn.assigns[:locale]) || "en"
    # The request's CSP nonce (#382) reaches the layout the same two ways the
    # locale does; PortfolixirWeb.ContentSecurityPolicy assigns it.
    csp_nonce = assigns[:csp_nonce] || (conn && conn.assigns[:csp_nonce])
    # A plain Map.put: the root layout is rendered both by LiveView (tracked
    # assigns) and by the session controller (a plain map, #764).
    assigns = assigns |> Map.put(:locale, locale) |> Map.put(:csp_nonce, csp_nonce)

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
        <script id="theme-boot" nonce={@csp_nonce}>
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
        <script id="live-view-client-script" nonce={@csp_nonce}>
          (function () {
            // Every destructive control carries data-confirm (#765). The page
            // loads no phoenix_html script, so the attribute is honoured here:
            // one capture-phase listener ahead of LiveView's own, cancelling
            // the click before phx-click can see it.
            document.addEventListener("click", function (event) {
              var target = event.target && event.target.closest && event.target.closest("[data-confirm]");
              if (!target) { return; }
              if (!window.confirm(target.getAttribute("data-confirm"))) {
                event.preventDefault();
                event.stopImmediatePropagation();
              }
            }, true);

            var csrfTokenElement = document.querySelector("meta[name='csrf-token']");
            var csrfToken = csrfTokenElement && csrfTokenElement.getAttribute("content");

            if (!window.Phoenix || !window.LiveView || !csrfToken) {
              return;
            }

            var Hooks = {};

            window.Portfolixir = window.Portfolixir || {};

            // CSS properties we need to bake into the exported SVG so the
            // file renders the same as on-screen without our stylesheet.
            window.Portfolixir._CHART_EXPORT_PROPS = [
              "fill", "fill-opacity", "stroke", "stroke-opacity",
              "stroke-width", "stroke-dasharray", "stroke-linecap",
              "stroke-linejoin", "opacity",
              "font-family", "font-size", "font-weight", "color"
            ];

            window.Portfolixir._inlineStyles = function (sourceEl, cloneEl) {
              var props = window.Portfolixir._CHART_EXPORT_PROPS;
              var srcStyle = window.getComputedStyle(sourceEl);
              var decls = [];
              for (var i = 0; i < props.length; i++) {
                var name = props[i];
                var value = srcStyle.getPropertyValue(name);
                if (value && value !== "" && value !== "normal") {
                  decls.push(name + ":" + value);
                }
              }
              if (decls.length > 0) {
                cloneEl.setAttribute("style", decls.join(";"));
              }

              var sourceChildren = sourceEl.children;
              var cloneChildren = cloneEl.children;
              for (var j = 0; j < sourceChildren.length; j++) {
                window.Portfolixir._inlineStyles(sourceChildren[j], cloneChildren[j]);
              }
            };

            window.Portfolixir.exportChart = function (button, format) {
              var frame = button.closest(".chart-frame") ||
                button.closest(".detail-pane").querySelector(".chart-frame");
              if (!frame) return;
              var svg = frame.querySelector("svg.security-chart");
              if (!svg) return;

              var clone = svg.cloneNode(true);
              clone.setAttribute("xmlns", "http://www.w3.org/2000/svg");

              // Bake the document background color into the export so dark
              // themes don't end up with transparent (visually black) areas.
              var bodyBg = window.getComputedStyle(document.body).backgroundColor || "#ffffff";
              clone.setAttribute("style", "background:" + bodyBg);

              // Bake the on-screen computed styles into the clone — without
              // this the exported SVG opens as a black-and-white skeleton
              // because none of our chart styling lives inline.
              window.Portfolixir._inlineStyles(svg, clone);

              // Pin the rendered dimensions so the export keeps its on-screen
              // size and isn't reflowed by the consumer.
              var rect = svg.getBoundingClientRect();
              var exportW = Math.max(640, Math.floor(rect.width || 960));
              var exportH = Math.max(240, Math.floor(rect.height || 320));
              clone.setAttribute("width", exportW);
              clone.setAttribute("height", exportH);

              var serializer = new XMLSerializer();
              var source = '<?xml version="1.0" encoding="UTF-8"?>\n' + serializer.serializeToString(clone);

              if (format === "svg") {
                var blob = new Blob([source], { type: "image/svg+xml;charset=utf-8" });
                var url = URL.createObjectURL(blob);
                window.Portfolixir._download(url, "chart.svg");
                setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
                return;
              }

              var img = new Image();
              var encoded = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(source);
              img.onload = function () {
                var canvas = document.createElement("canvas");
                canvas.width = exportW;
                canvas.height = exportH;
                var ctx = canvas.getContext("2d");
                ctx.fillStyle = bodyBg;
                ctx.fillRect(0, 0, canvas.width, canvas.height);
                ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
                canvas.toBlob(function (blob) {
                  if (!blob) return;
                  var url = URL.createObjectURL(blob);
                  window.Portfolixir._download(url, "chart.png");
                  setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
                }, "image/png");
              };
              img.src = encoded;
            };

            window.Portfolixir._download = function (url, filename) {
              var a = document.createElement("a");
              a.href = url;
              a.download = filename;
              document.body.appendChild(a);
              a.click();
              document.body.removeChild(a);
            };

            Hooks.ColumnPrefs = {
              mounted: function () {
                var key = this.el.dataset.storageKey || "securities.columns";
                var restoreEvent = this.el.dataset.restoreEvent || "set_columns";
                var raw = null;
                try { raw = window.localStorage && window.localStorage.getItem(key); } catch (_) {}

                if (raw) {
                  try {
                    var stored = JSON.parse(raw);
                    if (Array.isArray(stored) && stored.length > 0) {
                      this.pushEvent(restoreEvent, { columns: stored });
                    }
                  } catch (_) {}
                }

                // handleEvent listens page-wide, so on a page with more than
                // one picked table (#732: transactions) the payload names its
                // storage key and each hook stores only its own set. A
                // payload without a key keeps the pre-#732 behavior.
                this.handleEvent("column-prefs-changed", function (payload) {
                  if (payload && payload.key && payload.key !== key) { return; }
                  try {
                    if (window.localStorage && payload && Array.isArray(payload.columns)) {
                      window.localStorage.setItem(key, JSON.stringify(payload.columns));
                    }
                  } catch (_) {}
                });
              }
            };

            Hooks.SecuritySplitPane = {
              mounted: function () {
                this.workspace = this.el.closest("#securities-workspace");
                this.target = document.getElementById(this.el.dataset.target || "securities-list-pane");
                this.key = this.el.dataset.storageKey || "securities.detailSplitHeight";
                this.min = parseInt(this.el.dataset.minHeight || "220", 10);
                this.max = parseInt(this.el.dataset.maxHeight || "720", 10);
                this.drag = null;

                var stored = null;
                try { stored = window.localStorage && window.localStorage.getItem(this.key); } catch (_) {}
                if (stored) {
                  this.applyHeight(parseInt(stored, 10), false);
                } else if (this.target) {
                  this.applyHeight(this.target.getBoundingClientRect().height || 360, false);
                }

                var self = this;
                this.onPointerDown = function (event) { self.startDrag(event); };
                this.onPointerMove = function (event) { self.moveDrag(event); };
                this.onPointerUp = function (event) { self.endDrag(event); };
                this.onKeyDown = function (event) { self.handleKey(event); };

                this.el.addEventListener("pointerdown", this.onPointerDown);
                this.el.addEventListener("keydown", this.onKeyDown);
              },
              destroyed: function () {
                this.el.removeEventListener("pointerdown", this.onPointerDown);
                this.el.removeEventListener("keydown", this.onKeyDown);
                window.removeEventListener("pointermove", this.onPointerMove);
                window.removeEventListener("pointerup", this.onPointerUp);
              },
              startDrag: function (event) {
                if (!this.target) return;
                event.preventDefault();
                this.drag = {
                  y: event.clientY,
                  height: this.target.getBoundingClientRect().height || 360
                };
                window.addEventListener("pointermove", this.onPointerMove);
                window.addEventListener("pointerup", this.onPointerUp);
              },
              moveDrag: function (event) {
                if (!this.drag) return;
                this.applyHeight(this.drag.height + (event.clientY - this.drag.y), true);
              },
              endDrag: function () {
                this.drag = null;
                window.removeEventListener("pointermove", this.onPointerMove);
                window.removeEventListener("pointerup", this.onPointerUp);
              },
              handleKey: function (event) {
                if (!this.target) return;
                var current = this.target.getBoundingClientRect().height || 360;
                var next = current;

                if (event.key === "ArrowUp") next = current - 24;
                else if (event.key === "ArrowDown") next = current + 24;
                else if (event.key === "Home") next = this.min;
                else if (event.key === "End") next = this.max;
                else return;

                event.preventDefault();
                this.applyHeight(next, true);
              },
              applyHeight: function (height, persist) {
                if (!this.workspace || !Number.isFinite(height)) return;
                var clamped = Math.max(this.min, Math.min(this.max, Math.round(height)));
                this.workspace.style.setProperty("--securities-list-height", clamped + "px");
                this.el.setAttribute("aria-valuenow", String(clamped));

                if (persist) {
                  try {
                    if (window.localStorage) window.localStorage.setItem(this.key, String(clamped));
                  } catch (_) {}
                }
              }
            };

            // The detail pane's tab row (issue 837, plan D-3, pick E4-A): the
            // keyboard half of the tablist pattern. The server renders the
            // roving tabindex (0 on the selected tab, -1 on the rest); this
            // hook moves focus along the row with Arrow Left/Right (wrapping)
            // and Home/End, and activates the focused tab, so the tab stop and
            // the selection never disagree after the patch.
            Hooks.DetailTabs = {
              mounted: function () {
                var self = this;
                this.onKeydown = function (e) { self.keydown(e); };
                this.el.addEventListener("keydown", this.onKeydown);
              },
              destroyed: function () {
                this.el.removeEventListener("keydown", this.onKeydown);
              },
              keydown: function (e) {
                var tabs = Array.prototype.slice.call(
                  this.el.querySelectorAll('[role="tab"]')
                );
                var index = tabs.indexOf(e.target);
                if (index < 0 || tabs.length === 0) return;

                var next;
                if (e.key === "ArrowRight") next = (index + 1) % tabs.length;
                else if (e.key === "ArrowLeft") next = (index - 1 + tabs.length) % tabs.length;
                else if (e.key === "Home") next = 0;
                else if (e.key === "End") next = tabs.length - 1;
                else return;

                e.preventDefault();
                var target = tabs[next];
                target.focus();
                if (target.getAttribute("aria-selected") !== "true") target.click();
              }
            };

            // The area tab row (#857): on a phone the row overflows, and it
            // opened at scrollLeft 0 on every page, so on Risk, Tax or
            // Snapshots the tab the operator was on sat off-screen. On mount
            // the aria-current tab is scrolled into the row's view — the row
            // only, never the page, which is why this is a scrollTo on the nav
            // and not a scrollIntoView. No animation under
            // prefers-reduced-motion. The hook also marks which edges the row
            // rests on, so the stylesheet can fade exactly the edges that have
            // tabs beyond them (board 04): otherwise the repair only moves the
            // active tab under the right-edge mask.
            //
            // The row's end is a tab boundary (#876, pick G10 = A of board
            // ux-design-2026-09-24/10-area-tab-end). The browser clamps a
            // centring target past the row's maximum scroll, and the maximum
            // scroll lay mid-tab, so Tax and Risk came to rest with a fragment
            // of "Cashflow" under the left fade. When the row overflows, the
            // hook gives it a trailing inset (--area-tabs-tail, read by
            // app.css) as wide as the distance from its maximum scroll to the
            // next tab start, and the active tab comes to rest on a tab
            // start — never on the raw centring target.
            Hooks.AreaTabs = {
              mounted: function () {
                var self = this;
                this.lastLeft = 0;
                this.onScroll = function () {
                  self.lastLeft = self.el.scrollLeft;
                  self.markEdges();
                };
                this.onResize = function () {
                  self.fitTail();
                  self.markEdges();
                };
                this.el.addEventListener("scroll", this.onScroll, { passive: true });
                window.addEventListener("resize", this.onResize);
                this.fitTail();
                this.reveal();
                this.markEdges();
              },
              // A patch may drop what the hook wrote on the row: the inset and
              // the edge marks are restored, and a rest the browser clamped to
              // the row's end while the inset was gone is put back.
              updated: function () {
                var nav = this.el;
                var left = this.lastLeft;
                var clamped = left > nav.scrollLeft + 1 &&
                  nav.scrollLeft + nav.clientWidth >= nav.scrollWidth - 2;

                this.fitTail();
                if (clamped) nav.scrollLeft = left;
                this.markEdges();
              },
              destroyed: function () {
                window.removeEventListener("resize", this.onResize);
              },
              tabStarts: function () {
                var nav = this.el;
                var origin = nav.getBoundingClientRect().left - nav.scrollLeft;
                return Array.prototype.map.call(nav.querySelectorAll(".area-tab"), function (tab) {
                  var rect = tab.getBoundingClientRect();
                  return { left: rect.left - origin, width: rect.width };
                });
              },
              // Measured against the row without the inset it carries now, so
              // re-measuring never shrinks the scroll range under the current
              // rest. Rounded up, so the maximum scroll reaches the tab start.
              fitTail: function () {
                var nav = this.el;
                var inset = parseFloat(window.getComputedStyle(nav).paddingInlineEnd) || 0;
                var max = nav.scrollWidth - inset - nav.clientWidth;
                var tail = 0;

                if (max > 0) {
                  var next = this.tabStarts().find(function (tab) { return tab.left >= max - 0.5; });
                  if (next) tail = Math.ceil(next.left - max);
                }

                nav.style.setProperty("--area-tabs-tail", tail + "px");
              },
              // The last tab start at or before the centring target at which
              // the active tab is whole; else the first one after it.
              restingLeft: function (index) {
                var width = this.el.clientWidth;
                var tabs = this.tabStarts();
                var active = tabs[index];
                var target = active.left - (width - active.width) / 2;
                var whole = function (tab) {
                  return tab.left <= active.left + 0.5 &&
                    active.left + active.width <= tab.left + width + 0.5;
                };
                var fits = tabs.filter(whole);
                var before = fits.filter(function (tab) { return tab.left <= target; }).pop();
                var after = fits.find(function (tab) { return tab.left > target; });
                var rest = before || after;

                return rest ? Math.max(0, rest.left) : 0;
              },
              reveal: function () {
                var nav = this.el;
                var tab = nav.querySelector('[aria-current="page"]');
                if (!tab || nav.scrollWidth <= nav.clientWidth) return;

                var index = Array.prototype.indexOf.call(nav.querySelectorAll(".area-tab"), tab);
                if (index < 0) return;
                var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

                nav.scrollTo({ left: this.restingLeft(index), behavior: reduce ? "auto" : "smooth" });
              },
              markEdges: function () {
                var nav = this.el;
                var slack = 2;
                var atStart = nav.scrollLeft <= slack;
                var atEnd = nav.scrollLeft + nav.clientWidth >= nav.scrollWidth - slack;

                nav.toggleAttribute("data-scroll-start", atStart);
                nav.toggleAttribute("data-scroll-end", atEnd);
              }
            };

            // Every row menu mounts this hook (role="menu" with data-trigger
            // naming its kebab), so the keyboard pattern lives here once
            // (#858, WAI-ARIA menu): opening focuses the first enabled item;
            // ArrowDown/ArrowUp walk the enabled items and wrap, Home/End
            // jump; Tab closes through the same close_row_menu event that
            // Escape and click-away send, onto the kebab. When
            // the menu goes away while it held the focus and nothing else
            // took it — Escape, or an item that only closed the menu — the
            // focus returns to the kebab, instead of falling to the page.
            Hooks.PositionedMenu = {
              mounted: function () {
                // The control that opened the menu: the phone rows open it
                // from their own kebab, while data-trigger names the desktop
                // one, hidden below 720 px.
                this.opener = document.activeElement;
                this.reposition();

                var self = this;
                this.onWindow = function () { self.reposition(); };
                window.addEventListener("resize", this.onWindow);
                window.addEventListener("scroll", this.onWindow, true);

                this.onKey = function (event) { self.navigate(event); };
                this.el.addEventListener("keydown", this.onKey);

                var first = this.items()[0];
                if (first) first.focus();
              },
              updated: function () {
                this.reposition();
              },
              destroyed: function () {
                window.removeEventListener("resize", this.onWindow);
                window.removeEventListener("scroll", this.onWindow, true);

                var active = document.activeElement;
                if (!active || active === document.body || !active.isConnected) {
                  this.focusTrigger();
                }
              },
              focusTrigger: function () {
                var opener = this.opener;
                if (opener && opener !== document.body && opener.isConnected && opener.offsetParent !== null) {
                  opener.focus();
                  return;
                }

                var id = this.el.dataset.trigger;
                var trigger = id && document.getElementById(id);
                if (trigger) trigger.focus();
              },
              items: function () {
                return Array.prototype.slice.call(
                  this.el.querySelectorAll('[role="menuitem"]:not([disabled])')
                );
              },
              navigate: function (event) {
                var items = this.items();
                if (items.length === 0) return;

                var index = items.indexOf(document.activeElement);
                var next = null;

                switch (event.key) {
                  case "ArrowDown":
                    next = items[(index + 1) % items.length];
                    break;
                  case "ArrowUp":
                    next = items[index <= 0 ? items.length - 1 : index - 1];
                    break;
                  case "Home":
                    next = items[0];
                    break;
                  case "End":
                    next = items[items.length - 1];
                    break;
                  case "Tab":
                    // The menus render after their table (so the popover is
                    // never clipped), which makes the browser's own next stop
                    // the first control past the whole list. Tab therefore
                    // closes onto the kebab, and the next Tab moves on from
                    // the row the operator was in.
                    event.preventDefault();
                    this.focusTrigger();
                    this.pushEvent("close_row_menu", {});
                    return;
                  default:
                    return;
                }

                event.preventDefault();
                next.focus();
              },
              reposition: function () {
                if (window.matchMedia("(max-width: 720px)").matches) {
                  // Mobile bottom sheet uses CSS, no positioning needed
                  this.el.style.top = "";
                  this.el.style.left = "";
                  this.el.style.right = "";
                  return;
                }

                var triggerId = this.el.dataset.trigger;
                var trigger = triggerId && document.getElementById(triggerId);
                if (!trigger) return;

                var rect = trigger.getBoundingClientRect();
                var menuWidth = this.el.offsetWidth || 220;
                var menuHeight = this.el.offsetHeight || 320;
                var pad = 8;

                var top = rect.bottom + 4;
                var left = rect.right - menuWidth;

                if (left < pad) left = pad;
                if (left + menuWidth + pad > window.innerWidth) {
                  left = window.innerWidth - menuWidth - pad;
                }

                if (top + menuHeight + pad > window.innerHeight) {
                  // Not enough space below — flip above
                  top = rect.top - menuHeight - 4;
                  if (top < pad) top = pad;
                }

                this.el.style.top = top + "px";
                this.el.style.left = left + "px";
                this.el.style.right = "auto";
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

                this.zoomRect = document.createElement("div");
                this.zoomRect.className = "chart-zoom-rect";
                this.zoomRect.hidden = true;
                this.el.appendChild(this.zoomRect);

                this.zoom = null;

                var self = this;
                this.onMove = function (event) { self.handleMove(event); };
                this.onLeave = function () { self.hide(); };
                this.onDown = function (event) { self.beginZoom(event); };
                this.onUp = function (event) { self.endZoom(event); };
                this.onCancel = function (event) { self.cancelZoom(); self.hide(); };
                this.onDbl = function () { self.resetZoom(); };

                this.svg.addEventListener("pointermove", this.onMove);
                this.svg.addEventListener("pointerdown", this.onDown);
                this.svg.addEventListener("pointerup", this.onUp);
                this.svg.addEventListener("pointerleave", this.onLeave);
                this.svg.addEventListener("pointercancel", this.onCancel);
                this.svg.addEventListener("lostpointercapture", this.onCancel);
                this.svg.addEventListener("dblclick", this.onDbl);
              },
              updated: function () {
                this.payload = this.readPayload();
                this.hide();
              },
              destroyed: function () {
                if (this.svg) {
                  this.svg.removeEventListener("pointermove", this.onMove);
                  this.svg.removeEventListener("pointerdown", this.onDown);
                  this.svg.removeEventListener("pointerup", this.onUp);
                  this.svg.removeEventListener("pointerleave", this.onLeave);
                  this.svg.removeEventListener("pointercancel", this.onCancel);
                  this.svg.removeEventListener("lostpointercapture", this.onCancel);
                  this.svg.removeEventListener("dblclick", this.onDbl);
                }
              },
              beginZoom: function (event) {
                if (!this.payload || !this.payload.points || this.payload.points.length < 2) return;
                this.zoom = { startX: event.clientX, pointerId: event.pointerId };
                // Capture the pointer so pointerup still fires on the SVG
                // even when the user drags outside and releases.
                if (event.pointerId != null && this.svg.setPointerCapture) {
                  try { this.svg.setPointerCapture(event.pointerId); } catch (_) {}
                }
              },
              cancelZoom: function () {
                if (!this.zoom) return;
                if (this.zoom.pointerId != null && this.svg.releasePointerCapture) {
                  try { this.svg.releasePointerCapture(this.zoom.pointerId); } catch (_) {}
                }
                this.zoom = null;
                this.zoomRect.hidden = true;
              },
              endZoom: function (event) {
                if (!this.zoom) return;
                var startX = this.zoom.startX;
                var endX = event.clientX;
                var pointerId = this.zoom.pointerId;
                this.zoom = null;
                this.zoomRect.hidden = true;
                if (pointerId != null && this.svg.releasePointerCapture) {
                  try { this.svg.releasePointerCapture(pointerId); } catch (_) {}
                }

                if (Math.abs(endX - startX) < 8) return;

                var svgRect = this.svg.getBoundingClientRect();
                var view = this.payload.view || { width: 960, height: 320 };
                var scale = view.width / svgRect.width;
                var a = (Math.min(startX, endX) - svgRect.left) * scale;
                var b = (Math.max(startX, endX) - svgRect.left) * scale;

                var fromIdx = this.nearestIndex(this.payload.points, a);
                var toIdx = this.nearestIndex(this.payload.points, b);
                if (fromIdx === toIdx) return;

                var fromIso = this.payload.points[fromIdx][0];
                var toIso = this.payload.points[toIdx][0];

                this.pushEvent("set_detail_custom_range", { from: fromIso, to: toIso });
              },
              resetZoom: function () {
                this.pushEvent("clear_detail_custom_range", {});
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

                if (this.zoom) {
                  var left = Math.min(this.zoom.startX, event.clientX) - frameRect.left;
                  var width = Math.abs(event.clientX - this.zoom.startX);
                  this.zoomRect.style.left = left + "px";
                  this.zoomRect.style.top = (svgRect.top - frameRect.top) + "px";
                  this.zoomRect.style.width = width + "px";
                  this.zoomRect.style.height = svgRect.height + "px";
                  this.zoomRect.hidden = false;
                }

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
                // Built through the DOM API (#770): every value is text, never markup.
                var tooltip = this.tooltip;
                tooltip.textContent = "";
                var line = function (className, text) {
                  var node = document.createElement("div");
                  node.className = className;
                  node.textContent = text;
                  tooltip.appendChild(node);
                };
                line("chart-tooltip__date", String(iso));
                line("chart-tooltip__price", String(close) + (currency ? " " + currency : ""));
                if (tx) {
                  line(
                    "chart-tooltip__tx chart-tooltip__tx--" + String(tx.type).replace(/[^a-z_]/g, ""),
                    tx.type + " " + tx.quantity + " @ " + tx.price
                  );
                }
                tooltip.hidden = false;
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

            // Hover/touch crosshair for the portfolio performance chart
            // (#336/#411). Deliberately minimal — a vertical line plus a
            // date/%/€ tooltip, no zoom and no pushEvents — so it never fires
            // an event the portfolio LiveView does not handle. The data table
            // in the figure is the accessible fallback; everything here is a
            // defensively-guarded enhancement.

            // Instant custom hover tooltip for the allocation sunburst. The
            // native SVG <title> has a browser-imposed delay; this hook reads
            // each slice's data-label/data-value/data-percent attributes and
            // shows a div immediately on hover. The <title> stays in the
            // markup as a no-JS fallback. Position is fixed to the pointer so
            // it works regardless of the chart's layout context.
            Hooks.SunburstTooltip = {
              mounted: function () {
                this.tooltip = document.createElement("div");
                this.tooltip.className = "sunburst-tooltip";
                this.tooltip.hidden = true;
                this.tooltip.setAttribute("role", "status");
                document.body.appendChild(this.tooltip);

                var self = this;
                this.onOver = function (event) { self.handleOver(event); };
                this.onMove = function (event) { self.handleMove(event); };
                this.onOut = function (event) { self.handleOut(event); };

                this.el.addEventListener("mouseover", this.onOver);
                this.el.addEventListener("mousemove", this.onMove);
                this.el.addEventListener("mouseout", this.onOut);
              },
              updated: function () {
                this.hide();
              },
              destroyed: function () {
                this.el.removeEventListener("mouseover", this.onOver);
                this.el.removeEventListener("mousemove", this.onMove);
                this.el.removeEventListener("mouseout", this.onOut);
                if (this.tooltip && this.tooltip.parentNode) {
                  this.tooltip.parentNode.removeChild(this.tooltip);
                }
              },
              segmentFrom: function (target) {
                if (!target || !target.closest) return null;
                return target.closest(".sunburst-seg");
              },
              handleOver: function (event) {
                var seg = this.segmentFrom(event.target);
                if (!seg) return;
                this.render(seg);
                this.position(event.clientX, event.clientY);
              },
              handleMove: function (event) {
                var seg = this.segmentFrom(event.target);
                if (!seg) {
                  this.hide();
                  return;
                }
                if (this.tooltip.hidden) this.render(seg);
                this.position(event.clientX, event.clientY);
              },
              handleOut: function (event) {
                // Hide only when the pointer leaves the slice entirely, not
                // when moving between child nodes of the same <path>.
                var to = event.relatedTarget;
                if (to && this.segmentFrom(to)) return;
                this.hide();
              },
              centre: function () {
                var figure = this.el.closest(".sunburst-figure");
                return figure ? figure.querySelector("[data-role='sunburst-centre']") : null;
              },
              // Issue 793: the hovered slice reads in the centre too — the
              // touch device's tooltip — and the server's text comes back
              // from the centre's own data attributes on leave.
              paintCentre: function (label, value, percent, target) {
                var centre = this.centre();
                if (!centre) return;
                var currency = centre.getAttribute("data-currency") || "";
                var word = centre.getAttribute("data-target-word") || "target";
                var sub = percent + " %" + (target ? " · " + word + " " + target + " %" : "");
                this.writeCentre(centre, label, value + (currency ? " " + currency : ""), sub);
              },
              restoreCentre: function () {
                var centre = this.centre();
                if (!centre) return;
                this.writeCentre(
                  centre,
                  centre.getAttribute("data-label") || "",
                  centre.getAttribute("data-value") || "",
                  centre.getAttribute("data-sub") || ""
                );
              },
              writeCentre: function (centre, label, value, sub) {
                var l = centre.querySelector(".sunburst-centre__label");
                var v = centre.querySelector(".sunburst-centre__value");
                var s = centre.querySelector(".sunburst-centre__sub");
                if (l) l.textContent = label;
                if (v) v.textContent = value;
                if (s) s.textContent = sub;
              },
              render: function (seg) {
                var label = seg.getAttribute("data-label") || "";
                var value = seg.getAttribute("data-value") || "";
                var percent = seg.getAttribute("data-percent") || "";
                var target = seg.getAttribute("data-target") || "";
                this.paintCentre(label, value, percent, target);
                this.tooltip.textContent = "";

                var name = document.createElement("div");
                name.className = "sunburst-tooltip__name";
                name.textContent = label;
                this.tooltip.appendChild(name);

                var meta = document.createElement("div");
                meta.className = "sunburst-tooltip__meta";
                meta.textContent = percent + "%" + (value ? " · " + value : "");
                this.tooltip.appendChild(meta);

                this.tooltip.hidden = false;
              },
              position: function (clientX, clientY) {
                var pad = 12;
                var tipWidth = this.tooltip.offsetWidth || 120;
                var tipHeight = this.tooltip.offsetHeight || 32;
                var x = clientX + pad;
                var y = clientY + pad;
                if (x + tipWidth + pad > window.innerWidth) {
                  x = clientX - tipWidth - pad;
                }
                if (x < pad) x = pad;
                if (y + tipHeight + pad > window.innerHeight) {
                  y = clientY - tipHeight - pad;
                }
                if (y < pad) y = pad;
                this.tooltip.style.left = x + "px";
                this.tooltip.style.top = y + "px";
              },
              hide: function () {
                if (this.tooltip) this.tooltip.hidden = true;
                this.restoreCentre();
              }
            };

            // Native dialog modals (UX-DR9, issue 646): showModal() supplies
            // the focus trap, background inertness and Esc handling the old
            // div-based modals only asserted. The cancel event (Esc) is
            // prevented so LiveView owns the close — the server removes the
            // dialog from the DOM.
            Hooks.ModalDialog = {
              mounted: function () {
                // The trigger that had focus when the dialog opened; restored
                // on close because the server removes the dialog from the DOM,
                // which forfeits the native focus-restore (UX-DR9).
                this.opener = document.activeElement;
                // A dialog that is a sheet only on the phone (#803, the
                // booking drawer): `data-sheet-below="720"` opens it modally
                // up to that width and non-modally — in flow, beside the
                // content — above it. Esc closes both; the non-modal branch
                // handles the key itself, because only showModal() fires
                // `cancel`.
                this.sheetBelow = parseInt(this.el.getAttribute("data-sheet-below") || "0", 10);
                this.showModal();
                var self = this;
                this.onCancel = function (e) {
                  e.preventDefault();
                  self.close();
                };
                this.onKeydown = function (e) {
                  if (e.key === "Escape" && !self.modal()) {
                    e.preventDefault();
                    self.close();
                  }
                };
                // A browser may force-close a modal without a cancelable
                // cancel (Chromium CloseWatcher). Tell the server, so client
                // and assigns cannot desync.
                this.onClose = function () {
                  if (self.el.isConnected && !self.el.open) {
                    self.close();
                  }
                };
                this.el.addEventListener("cancel", this.onCancel);
                this.el.addEventListener("close", this.onClose);
                this.el.addEventListener("keydown", this.onKeydown);
              },
              // morphdom strips the client-set `open` attribute on every
              // server patch (the template never renders it), which would
              // silently hide the dialog mid-interaction — re-assert it.
              updated: function () {
                this.showModal();
              },
              destroyed: function () {
                this.el.removeEventListener("cancel", this.onCancel);
                this.el.removeEventListener("close", this.onClose);
                this.el.removeEventListener("keydown", this.onKeydown);
                if (this.el.open && typeof this.el.close === "function") {
                  this.el.close();
                }
                if (this.opener && this.opener.isConnected &&
                    typeof this.opener.focus === "function") {
                  this.opener.focus();
                }
              },
              modal: function () {
                return !this.sheetBelow ||
                  window.matchMedia("(max-width: " + this.sheetBelow + "px)").matches;
              },
              showModal: function () {
                if (this.el.open) return;
                if (this.modal()) {
                  if (typeof this.el.showModal === "function") this.el.showModal();
                } else if (typeof this.el.show === "function") {
                  this.el.show();
                }
              },
              close: function () {
                var event = this.el.getAttribute("data-close-event");
                if (event) {
                  this.pushEventTo(this.el, event, {});
                }
              }
            };

            // #801: a <details> popover on its trigger. Esc closes it and
            // returns focus to the summary; the server closes it with
            // "close-popover" (naming the details id) once a choice applied.
            Hooks.PopoverDisclosure = {
              mounted: function () {
                var self = this;
                this.open = this.el.open;
                // The native summary toggle is the user's choice; a server
                // patch of the popover's body (a refused range reporting
                // its violation) must not close it. LiveView removes every
                // attribute the server did not render — `open` included —
                // so the hook remembers the toggle and restores it after
                // each patch.
                this.onToggle = function () {
                  self.open = self.el.open;
                };
                this.onKeydown = function (e) {
                  if (e.key === "Escape" && self.el.open) {
                    e.preventDefault();
                    self.closeAndFocus();
                  }
                };
                this.el.addEventListener("toggle", this.onToggle);
                this.el.addEventListener("keydown", this.onKeydown);
                this.handleEvent("close-popover", function (payload) {
                  if (payload && payload.id === self.el.id && self.el.open) {
                    self.closeAndFocus();
                  }
                });
              },
              updated: function () {
                if (this.open && !this.el.open) this.el.setAttribute("open", "");
              },
              destroyed: function () {
                this.el.removeEventListener("toggle", this.onToggle);
                this.el.removeEventListener("keydown", this.onKeydown);
              },
              closeAndFocus: function () {
                this.open = false;
                this.el.removeAttribute("open");
                var summary = this.el.querySelector("summary");
                if (summary && typeof summary.focus === "function") summary.focus();
              }
            };

            // The ninth inline hook (owner decision 2026-08-05, DESIGN.md →
            // Motion): a cosmetic count-up to an already-known final value.
            // requestAnimationFrame drives the count, Intl.NumberFormat
            // formats each frame, and the accent bar beneath reports the
            // count's real progress. The hook reads prefers-reduced-motion
            // before the first frame: under `reduce` the settling state does
            // not occur — the final value renders immediately.
            Hooks.CountUp = {
              mounted: function () {
                this.lastValue = null;
                this.frame = null;
                // A preference flip mid-count cancels the animation and snaps
                // to the final value (the settling state must not occur under
                // reduce).
                this.mq = window.matchMedia
                  ? window.matchMedia("(prefers-reduced-motion: reduce)")
                  : null;
                var self = this;
                this.onMqChange = function (e) {
                  if (e.matches) self.finish();
                };
                if (this.mq && this.mq.addEventListener) {
                  this.mq.addEventListener("change", this.onMqChange);
                }
                this.animate();
              },
              updated: function () { this.animate(); },
              destroyed: function () {
                if (this.frame) cancelAnimationFrame(this.frame);
                if (this.mq && this.mq.removeEventListener) {
                  this.mq.removeEventListener("change", this.onMqChange);
                }
              },
              reduceMotion: function () {
                return this.mq ? this.mq.matches : false;
              },
              finish: function () {
                if (this.frame) cancelAnimationFrame(this.frame);
                this.frame = null;
                if (this.settle) this.settle();
              },
              animate: function () {
                var el = this.el;
                var digits = el.querySelector("[data-count-digits]");
                if (!digits) return;

                var target = parseFloat(el.getAttribute("data-count-to"));
                if (isNaN(target)) return;

                var from = this.lastValue === null ? 0 : this.lastValue;
                this.lastValue = target;
                if (from === target || this.reduceMotion()) return;

                // The server-rendered text is the value of record; frames
                // approximate it and the last frame restores it exactly. The
                // slot's final footprint is pinned before the first frame so
                // a growing digit count cannot reflow the neighbours
                // (UX-DR20 reserved footprint).
                var finalText = digits.textContent;
                digits.style.display = "inline-block";
                digits.style.minWidth = digits.offsetWidth + "px";
                var decimals = parseInt(el.getAttribute("data-decimals") || "2", 10);
                var lang = document.documentElement.lang || "en";
                var fmt = null;
                try {
                  fmt = new Intl.NumberFormat(lang, {
                    minimumFractionDigits: decimals,
                    maximumFractionDigits: decimals
                  });
                } catch (e) { fmt = null; }

                if (this.frame) cancelAnimationFrame(this.frame);

                var bar = el.querySelector(".count-up__bar");
                if (!bar) {
                  bar = document.createElement("span");
                  bar.className = "count-up__bar";
                  bar.setAttribute("aria-hidden", "true");
                  el.appendChild(bar);
                }

                el.classList.add("is-settling");
                el.setAttribute("aria-busy", "true");

                var duration = 600;
                var start = null;
                var self = this;

                this.settle = function () {
                  self.settle = null;
                  digits.textContent = finalText;
                  digits.style.minWidth = "";
                  el.classList.remove("is-settling");
                  el.setAttribute("aria-busy", "false");
                  bar.classList.add("is-done");
                  setTimeout(function () {
                    if (bar.parentNode) bar.parentNode.removeChild(bar);
                  }, 300);
                };

                function step(ts) {
                  if (start === null) start = ts;
                  var t = Math.min((ts - start) / duration, 1);
                  var eased = 1 - Math.pow(1 - t, 3);
                  var current = from + (target - from) * eased;
                  digits.textContent = fmt ? fmt.format(current) : current.toFixed(decimals);
                  bar.style.width = (t * 100).toFixed(1) + "%";
                  if (t < 1) {
                    self.frame = requestAnimationFrame(step);
                  } else {
                    self.frame = null;
                    if (self.settle) self.settle();
                  }
                }

                this.frame = requestAnimationFrame(step);
              }
            };

            Hooks.PPImportDrop = {
              mounted: function () {
                var container = this.el;
                var input = container.querySelector("input[type='file']");
                var button = container.querySelector("[data-import-file-button]");

                if (button && input) {
                  button.addEventListener("click", function (e) {
                    e.preventDefault();
                    input.click();
                  });
                }

                function setDragging(active) {
                  if (active) {
                    container.classList.add("is-dragging");
                  } else {
                    container.classList.remove("is-dragging");
                  }
                }

                function hasFiles(event) {
                  var dt = event.dataTransfer;
                  if (!dt || !dt.types) return false;
                  for (var i = 0; i < dt.types.length; i++) {
                    if (dt.types[i] === "Files") return true;
                  }
                  return false;
                }

                this._onDragOver = function (event) {
                  if (!hasFiles(event)) return;
                  event.preventDefault();
                  setDragging(true);
                };
                this._onDragLeave = function (event) {
                  if (event.target !== container) return;
                  setDragging(false);
                };
                this._onDrop = function () { setDragging(false); };

                container.addEventListener("dragover", this._onDragOver);
                container.addEventListener("dragleave", this._onDragLeave);
                container.addEventListener("dragend", this._onDrop);
                container.addEventListener("drop", this._onDrop);
              },
              destroyed: function () {
                var container = this.el;
                if (this._onDragOver) container.removeEventListener("dragover", this._onDragOver);
                if (this._onDragLeave) container.removeEventListener("dragleave", this._onDragLeave);
                if (this._onDrop) {
                  container.removeEventListener("dragend", this._onDrop);
                  container.removeEventListener("drop", this._onDrop);
                }
              }
            };

            Hooks.ClassificationDnD = {
              mounted: function () {
                var self = this;
                var el = this.el;
                var selected = {};
                var anchor = null;
                var anchorList = null;

                function rows() { return el.querySelectorAll("[data-drag-security]"); }
                function selectedIds() {
                  var ids = [];
                  for (var k in selected) { if (selected[k]) ids.push(parseInt(k, 10)); }
                  return ids;
                }
                function clearSelection() { selected = {}; anchor = null; anchorList = null; }
                function classificationId() {
                  return parseInt(el.getAttribute("data-classification"), 10);
                }
                function prune() {
                  var present = {};
                  var r = rows();
                  for (var i = 0; i < r.length; i++) {
                    present[r[i].getAttribute("data-drag-security")] = true;
                  }
                  for (var k in selected) { if (!present[k]) delete selected[k]; }
                }
                function refresh() {
                  var r = rows();
                  for (var i = 0; i < r.length; i++) {
                    var id = r[i].getAttribute("data-drag-security");
                    if (selected[id]) r[i].classList.add("is-selected");
                    else r[i].classList.remove("is-selected");
                  }
                  var count = selectedIds().length;
                  var bar = el.querySelector("[data-select-toolbar]");
                  if (bar) {
                    var label = bar.querySelector("[data-selected-count]");
                    if (label) label.textContent = String(count);
                    if (count > 0) bar.removeAttribute("hidden");
                    else bar.setAttribute("hidden", "");
                  }
                }
                function selectRange(list, fromId, toId) {
                  var r = list.querySelectorAll("[data-drag-security]");
                  var ids = [];
                  for (var i = 0; i < r.length; i++) {
                    ids.push(r[i].getAttribute("data-drag-security"));
                  }
                  var a = ids.indexOf(String(fromId));
                  var b = ids.indexOf(String(toId));
                  if (a === -1 || b === -1) { selected[toId] = true; return; }
                  var lo = Math.min(a, b);
                  var hi = Math.max(a, b);
                  for (var j = lo; j <= hi; j++) selected[ids[j]] = true;
                }
                function dispatch(zone, ids) {
                  var cid = parseInt(zone.getAttribute("data-classification"), 10);
                  if (zone.getAttribute("data-drop-kind") === "unassign") {
                    self.pushEvent("unassign_many", { security_ids: ids, classification_id: cid });
                  } else {
                    self.pushEvent("assign_securities", {
                      security_ids: ids,
                      classification_id: cid,
                      category_id: parseInt(zone.getAttribute("data-category"), 10)
                    });
                  }
                }

                this._refreshState = function () { prune(); refresh(); };

                this._onClick = function (event) {
                  if (!event.target.closest) return;
                  if (event.target.closest("[data-no-toggle]")) {
                    // Keep summary action buttons from toggling the <details> folder.
                    event.preventDefault();
                  }
                  if (event.target.closest("[data-move-selected]")) {
                    var sel = el.querySelector("[data-move-target]");
                    var categoryId = sel ? parseInt(sel.value, 10) : NaN;
                    var ids = selectedIds();
                    if (ids.length && !isNaN(categoryId)) {
                      self.pushEvent("assign_securities", {
                        security_ids: ids,
                        classification_id: classificationId(),
                        category_id: categoryId
                      });
                      clearSelection();
                      refresh();
                    }
                    return;
                  }
                  var unassignButton = event.target.closest("[data-unassign-selected]");
                  if (unassignButton) {
                    var uids = selectedIds();
                    if (uids.length) {
                      self.pushEvent("unassign_many", {
                        security_ids: uids,
                        classification_id: classificationId()
                      });
                      clearSelection();
                      refresh();
                    }
                    return;
                  }
                  if (event.target.closest("[data-clear-selection]")) {
                    clearSelection();
                    refresh();
                    return;
                  }

                  var row = event.target.closest("[data-drag-security]");
                  if (!row || !el.contains(row)) return;
                  if (event.target.closest("a, input, select")) return;
                  var rid = row.getAttribute("data-drag-security");
                  var list = row.parentNode;
                  if (event.shiftKey && anchor && anchorList === list) {
                    selectRange(list, anchor, rid);
                  } else {
                    if (selected[rid]) delete selected[rid];
                    else selected[rid] = true;
                    anchor = rid;
                    anchorList = list;
                  }
                  refresh();
                };

                this._onDragStart = function (event) {
                  var row = event.target.closest
                    ? event.target.closest("[data-drag-security]")
                    : null;
                  if (!row) return;
                  var rid = row.getAttribute("data-drag-security");
                  if (!selected[rid]) {
                    selected[rid] = true;
                    anchor = rid;
                    anchorList = row.parentNode;
                    refresh();
                  }
                  event.dataTransfer.setData("text/plain", selectedIds().join(","));
                  event.dataTransfer.effectAllowed = "move";
                };
                this._onDragOver = function (event) {
                  var zone = event.target.closest
                    ? event.target.closest("[data-dropzone]")
                    : null;
                  if (!zone) return;
                  event.preventDefault();
                  event.dataTransfer.dropEffect = "move";
                  zone.classList.add("is-dropping");
                };
                this._onDragLeave = function (event) {
                  var zone = event.target.closest
                    ? event.target.closest("[data-dropzone]")
                    : null;
                  if (zone) zone.classList.remove("is-dropping");
                };
                this._onDrop = function (event) {
                  var zone = event.target.closest
                    ? event.target.closest("[data-dropzone]")
                    : null;
                  if (!zone) return;
                  event.preventDefault();
                  zone.classList.remove("is-dropping");
                  var ids = selectedIds();
                  if (!ids.length) return;
                  dispatch(zone, ids);
                  clearSelection();
                  refresh();
                };

                el.addEventListener("click", this._onClick);
                el.addEventListener("dragstart", this._onDragStart);
                el.addEventListener("dragover", this._onDragOver);
                el.addEventListener("dragleave", this._onDragLeave);
                el.addEventListener("drop", this._onDrop);
                refresh();
              },
              updated: function () {
                if (this._refreshState) this._refreshState();
              },
              destroyed: function () {
                var el = this.el;
                el.removeEventListener("click", this._onClick);
                el.removeEventListener("dragstart", this._onDragStart);
                el.removeEventListener("dragover", this._onDragOver);
                el.removeEventListener("dragleave", this._onDragLeave);
                el.removeEventListener("drop", this._onDrop);
              }
            };

            var liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
              hooks: Hooks,
              params: { _csrf_token: csrfToken }
            });

            window.addEventListener("phx:copy-to-clipboard", function (event) {
              var text = event.detail && event.detail.text;
              if (!text) return;

              function fallbackCopy() {
                try {
                  var area = document.createElement("textarea");
                  area.value = text;
                  area.setAttribute("readonly", "");
                  area.style.position = "absolute";
                  area.style.left = "-9999px";
                  document.body.appendChild(area);
                  area.select();
                  document.execCommand("copy");
                  document.body.removeChild(area);
                } catch (_) {}
              }

              if (navigator.clipboard && navigator.clipboard.writeText) {
                try {
                  var promise = navigator.clipboard.writeText(text);
                  if (promise && typeof promise.then === "function") {
                    promise.then(function () {}, fallbackCopy);
                    return;
                  }
                } catch (_) {}
              }

              fallbackCopy();
            });

            // Long background actions (price sync, logo lookup) ask the OS to
            // notify when they finish — but only if the tab is in the
            // background, since the on-page feedback covers the visible case.
            window.Portfolixir.ensureNotifyPermission = function () {
              try {
                if ("Notification" in window && Notification.permission === "default") {
                  Notification.requestPermission();
                }
              } catch (_) {}
            };

            window.Portfolixir.osNotify = function (detail) {
              try {
                if (!("Notification" in window)) return;
                if (Notification.permission !== "granted") return;
                if (!document.hidden) return;
                var title = (detail && detail.title) || "Portfolixir";
                var note = new Notification(title, {
                  body: (detail && detail.body) || "",
                  tag: (detail && detail.tag) || "portfolixir"
                });
                note.onclick = function () {
                  window.focus();
                  note.close();
                };
              } catch (_) {}
            };

            window.addEventListener("phx:os-notify", function (event) {
              window.Portfolixir.osNotify(event.detail || {});
            });

            // Content-Security-Policy (#382): the pages carry no inline event
            // handlers. The controls that used to call into window.Portfolixir
            // from an inline click attribute say what they want with a data
            // attribute and are served by these two listeners; both sit on the
            // document, so they run ahead of LiveView's own window listeners.
            document.addEventListener("click", function (event) {
              var target = event.target;
              if (!target || !target.closest) { return; }

              var exportButton = target.closest("[data-chart-export]");
              if (exportButton) {
                window.Portfolixir.exportChart(exportButton, exportButton.getAttribute("data-chart-export"));
              }

              if (target.closest("[data-notify-permission]")) {
                window.Portfolixir.ensureNotifyPermission();
              }

              // A control inside a clickable row (the quick-assign form in the
              // securities list) keeps its click to itself.
              if (target.closest("[data-swallow-click]")) {
                event.stopPropagation();
              }
            });

            // A phx-change form with no phx-submit would be submitted natively
            // on Enter (LiveView's external-submit path); data-no-submit keeps
            // it on the page, the way the inline return-false handler used to.
            document.addEventListener("submit", function (event) {
              var form = event.target;
              if (form && form.matches && form.matches("[data-no-submit]")) {
                event.preventDefault();
                event.stopPropagation();
              }
            }, true);

            liveSocket.connect();
            window.liveSocket = liveSocket;
          })();
        </script>
        <script id="theme-control-script" nonce={@csp_nonce}>
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
