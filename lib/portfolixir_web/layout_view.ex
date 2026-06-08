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

            Hooks.PositionedMenu = {
              mounted: function () {
                this.reposition();

                var self = this;
                this.onWindow = function () { self.reposition(); };
                window.addEventListener("resize", this.onWindow);
                window.addEventListener("scroll", this.onWindow, true);
              },
              updated: function () {
                this.reposition();
              },
              destroyed: function () {
                window.removeEventListener("resize", this.onWindow);
                window.removeEventListener("scroll", this.onWindow, true);
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
                  if (event.target.closest("[data-unassign-selected]")) {
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
