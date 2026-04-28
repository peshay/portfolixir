defmodule PortfolixirWeb.AppShell do
  use Phoenix.Component

  attr(:current_path, :string, default: "/")
  slot(:inner_block, required: true)

  def shell(assigns) do
    assigns = assign_new(assigns, :current_path, fn -> "/" end)

    ~H"""
    <div id="app-shell" data-theme="light" data-sidebar-collapsed="false">
      <style id="app-shell-styles">
        :root {
          --pfx-bg: #f4f7fc;
          --pfx-surface: #ffffff;
          --pfx-surface-muted: #f8fbff;
          --pfx-text: #0f172a;
          --pfx-muted: #506280;
          --pfx-border: #dae2f0;
          --pfx-input: #ffffff;
          --pfx-input-border: #cbd8ed;
          --pfx-link: #2563eb;
          --pfx-accent: #6d28d9;
          --pfx-accent-soft: #ede9fe;
          --pfx-accent-faint: rgba(109, 40, 217, 0.14);
          --pfx-success: #16a34a;
          --pfx-success-soft: rgba(16, 185, 129, 0.15);
          --pfx-error: #b91c1c;
          --pfx-error-soft: rgba(239, 68, 68, 0.14);
        }

        [data-theme="dark"] {
          --pfx-bg: #080e1b;
          --pfx-surface: #0f172a;
          --pfx-surface-muted: #1e293b;
          --pfx-text: #f8fafc;
          --pfx-muted: #cbd5e1;
          --pfx-border: #334155;
          --pfx-input: #1e293b;
          --pfx-input-border: #475569;
          --pfx-link: #93c5fd;
          --pfx-accent: #a78bfa;
          --pfx-accent-soft: #312e81;
          --pfx-accent-faint: rgba(167, 139, 250, 0.22);
          --pfx-success: #34d399;
          --pfx-success-soft: rgba(52, 211, 153, 0.14);
          --pfx-error: #f87171;
          --pfx-error-soft: rgba(248, 113, 113, 0.14);
        }

        #app-shell {
          min-height: 100vh;
          margin: 0;
          background: var(--pfx-bg);
          color: var(--pfx-text);
          font-family:
            Inter,
            ui-sans-serif,
            system-ui,
            -apple-system,
            BlinkMacSystemFont,
            "Segoe UI",
            sans-serif;
        }

        #app-shell a {
          color: var(--pfx-link);
          text-decoration: none;
        }

        #app-shell .app-shell-layout {
          min-height: 100vh;
          display: flex;
          align-items: stretch;
          gap: 0;
        }

        #app-shell .app-shell-sidebar {
          width: 16rem;
          min-width: 16rem;
          padding: 1rem;
          box-sizing: border-box;
          background: var(--pfx-surface);
          border-right: 1px solid var(--pfx-border);
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
          transition: width 0.2s ease;
          min-height: 100vh;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-sidebar {
          width: 5rem;
          min-width: 5rem;
        }

        #app-shell .app-shell-sidebar-top {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 0.5rem;
          padding-bottom: 0.2rem;
        }

        #app-shell .app-shell-brand {
          display: flex;
          align-items: center;
          gap: 0.6rem;
          padding: 0.25rem 0.2rem;
          min-width: 0;
          flex: 1;
          color: var(--pfx-text);
          overflow: hidden;
        }

        #app-shell .app-shell-brand-wordmark,
        #app-shell .app-shell-logo-mark {
          width: auto;
          max-height: 2rem;
          height: 2rem;
          object-fit: contain;
          display: block;
          flex-shrink: 0;
        }

        #app-shell .app-shell-logo-wordmark-light,
        #app-shell .app-shell-logo-wordmark-dark,
        #app-shell .app-shell-logo-mark {
          display: none;
        }

        #app-shell:not([data-sidebar-collapsed="true"])[data-theme="light"]
          .app-shell-logo-wordmark-light {
          display: block;
        }

        #app-shell:not([data-sidebar-collapsed="true"])[data-theme="dark"]
          .app-shell-logo-wordmark-dark {
          display: block;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-logo-mark {
          display: block;
        }

        #app-shell .app-shell-visually-hidden {
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        #app-shell .app-shell-visually-hidden {
          position: absolute;
          width: 1px;
          height: 1px;
          padding: 0;
          margin: -1px;
          overflow: hidden;
          clip: rect(0, 0, 0, 0);
          border: 0;
        }

        #app-shell .app-shell-icon-button {
          border: 1px solid var(--pfx-border);
          border-radius: 0.75rem;
          background: var(--pfx-surface-muted);
          color: var(--pfx-text);
          width: 2.35rem;
          height: 2.35rem;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          cursor: pointer;
          transition:
            border-color 0.15s ease,
            background-color 0.15s ease;
        }

        #app-shell .app-shell-icon-button:hover {
          border-color: color-mix(in srgb, var(--pfx-accent) 30%, var(--pfx-border));
          background: var(--pfx-accent-faint);
        }

        #app-shell .app-shell-icon-button:focus-visible,
        #app-shell .app-shell-theme-toggle:focus-visible,
        #app-shell button.app-shell-primary:focus-visible,
        #app-shell button.app-shell-secondary:focus-visible {
          outline: 2px solid color-mix(in srgb, var(--pfx-accent) 45%, transparent);
          outline-offset: 2px;
        }

        #app-shell .app-shell-theme-toggle {
          border: 1px solid var(--pfx-input-border);
          border-radius: 0.65rem;
          background: var(--pfx-surface-muted);
          color: var(--pfx-text);
          padding: 0.5rem 0.7rem;
          cursor: pointer;
          min-height: 2.2rem;
          display: inline-flex;
          align-items: center;
          justify-content: flex-start;
          gap: 0.45rem;
          width: 100%;
          box-sizing: border-box;
          white-space: nowrap;
          transition:
            border-color 0.15s ease,
            background-color 0.15s ease;
        }

        #app-shell .app-shell-theme-label {
          display: inline-block;
          font-size: 0.92rem;
          line-height: 1;
        }

        #app-shell .app-shell-theme-icon {
          display: none;
          width: 1.1rem;
          text-align: center;
          font-size: 1rem;
          line-height: 1;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-theme-toggle {
          width: 2.35rem;
          padding: 0.5rem 0.55rem;
          justify-content: center;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-theme-label {
          display: none;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-theme-icon {
          display: inline-block;
        }

        #app-shell .app-shell-sidebar-nav {
          margin-top: 0.35rem;
          display: flex;
          flex-direction: column;
          gap: 0.45rem;
          min-width: 0;
        }

        #app-shell .app-shell-nav-group {
          display: flex;
          flex-direction: column;
          gap: 0.36rem;
        }

        #app-shell .app-shell-nav-group-title {
          margin: 0;
          font-size: 0.73rem;
          font-weight: 600;
          letter-spacing: 0.05em;
          text-transform: uppercase;
          color: var(--pfx-muted);
          padding: 0 0.55rem;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-nav-group-title {
          display: none;
        }

        #app-shell .app-shell-nav-link {
          display: flex;
          align-items: center;
          gap: 0.7rem;
          border: 1px solid transparent;
          border-radius: 0.7rem;
          padding: 0.58rem 0.75rem;
          min-height: 2.5rem;
          color: var(--pfx-text);
          transition:
            background-color 0.15s ease,
            border-color 0.15s ease,
            color 0.15s ease;
          font-weight: 500;
          cursor: pointer;
        }

        #app-shell .app-shell-nav-link:hover {
          background: color-mix(in srgb, var(--pfx-accent-faint) 100%, transparent);
          border-color: color-mix(in srgb, var(--pfx-accent) 18%, transparent);
        }

        #app-shell .app-shell-nav-link.is-active {
          background: var(--pfx-accent-faint);
          border-color: color-mix(in srgb, var(--pfx-accent) 40%, transparent);
          color: color-mix(in srgb, var(--pfx-accent) 92%, black);
          font-weight: 600;
        }

        #app-shell .app-shell-nav-link.is-disabled {
          opacity: 0.55;
          cursor: not-allowed;
          color: var(--pfx-muted);
          pointer-events: none;
        }

        #app-shell .app-shell-nav-icon {
          display: none;
          width: 1.5rem;
          min-width: 1.5rem;
          height: 1.5rem;
          border-radius: 0.45rem;
          font-weight: 700;
          line-height: 1;
          text-align: center;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          flex-shrink: 0;
          background: color-mix(in srgb, var(--pfx-surface) 45%, transparent);
          border: 1px solid color-mix(in srgb, var(--pfx-border) 85%, transparent);
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-nav-icon {
          display: inline-flex;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-nav-link {
          justify-content: center;
          padding: 0.58rem;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-nav-label {
          display: none;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-brand {
          justify-content: center;
        }

        #app-shell .app-shell-main {
          flex: 1;
          padding: 1.25rem 1.25rem 1.5rem;
          min-width: 0;
          background: var(--pfx-bg);
        }

        #app-shell .app-shell-main-inner {
          max-width: 1240px;
          margin: 0 auto;
        }

        #app-shell .app-shell-content-card {
          background: transparent;
          border: 0;
          padding: 0;
          box-sizing: border-box;
        }

        #app-shell .app-shell-section-card {
          background: var(--pfx-surface);
          border: 1px solid var(--pfx-border);
          border-radius: 0.8rem;
          padding: 1rem;
          box-sizing: border-box;
          box-shadow: 0 12px 30px -30px rgba(15, 23, 42, 0.45);
        }

        #app-shell .app-shell-section-card + .app-shell-section-card {
          margin-top: 1rem;
        }

        #app-shell .app-shell-section-card--compact {
          max-width: 720px;
        }

        #app-shell .app-shell-section-title {
          margin: 0 0 0.55rem;
          color: var(--pfx-text);
          font-size: 1rem;
          letter-spacing: 0.01em;
        }

        #app-shell .app-shell-page-header {
          margin-bottom: 1rem;
        }

        #app-shell .app-shell-page-header p {
          margin: 0.35rem 0 0;
          max-width: 64ch;
          color: var(--pfx-muted);
        }

        #app-shell .app-shell-empty-state {
          background: var(--pfx-surface-muted);
          border: 1px dashed var(--pfx-border);
          border-radius: 0.7rem;
          padding: 1rem;
        }

        #app-shell .app-shell-empty-state h3 {
          margin: 0 0 0.3rem;
          font-size: 1rem;
          color: var(--pfx-text);
        }

        #app-shell .app-shell-empty-state p {
          margin: 0;
          color: var(--pfx-muted);
        }

        #app-shell h1,
        #app-shell h2 {
          margin: 0;
          color: var(--pfx-text);
          font-weight: 600;
        }

        #app-shell label {
          display: block;
          margin-top: 0.55rem;
          margin-bottom: 0.25rem;
          color: var(--pfx-muted);
          font-size: 0.9rem;
        }

        #app-shell input,
        #app-shell textarea,
        #app-shell select,
        #app-shell table {
          background: var(--pfx-input);
          color: var(--pfx-text);
        }

        #app-shell input,
        #app-shell textarea,
        #app-shell select {
          width: 100%;
          border: 1px solid var(--pfx-input-border);
          border-radius: 0.55rem;
          padding: 0.48rem 0.6rem;
          box-sizing: border-box;
          font-family: inherit;
        }

        #app-shell button {
          border: 1px solid var(--pfx-input-border);
          border-radius: 0.6rem;
          padding: 0.5rem 0.8rem;
          margin-top: 0.75rem;
          margin-bottom: 0.35rem;
          cursor: pointer;
          background: var(--pfx-surface);
          color: var(--pfx-text);
          transition:
            background-color 0.15s ease,
            border-color 0.15s ease,
            color 0.15s ease;
          font-family: inherit;
        }

        #app-shell button.app-shell-primary {
          border-color: color-mix(in srgb, var(--pfx-accent) 70%, var(--pfx-input-border));
          background: var(--pfx-accent);
          color: #ffffff;
          font-weight: 600;
          padding: 0.6rem 0.95rem;
        }

        #app-shell button.app-shell-secondary {
          border-color: color-mix(in srgb, var(--pfx-muted) 50%, transparent);
          background: var(--pfx-surface-muted);
          color: var(--pfx-text);
          font-weight: 600;
        }

        #app-shell button.app-shell-primary:hover {
          filter: brightness(0.97);
        }

        #app-shell .app-shell-alert {
          margin: 0.6rem 0 0;
          border-radius: 0.55rem;
          padding: 0.55rem 0.65rem;
          border: 1px solid transparent;
        }

        #app-shell .app-shell-alert--success {
          border-color: color-mix(in srgb, var(--pfx-success) 55%, transparent);
          background: var(--pfx-success-soft);
          color: var(--pfx-success);
        }

        #app-shell .app-shell-alert--error {
          border-color: color-mix(in srgb, var(--pfx-error) 45%, transparent);
          background: var(--pfx-error-soft);
          color: var(--pfx-error);
        }

        #app-shell .app-shell-help-text {
          margin: 0.3rem 0 0;
          color: var(--pfx-muted);
          font-size: 0.86rem;
        }

        #app-shell table {
          width: 100%;
          border-collapse: collapse;
        }

        #app-shell th,
        #app-shell td {
          text-align: left;
          border: 1px solid var(--pfx-border);
          padding: 0.55rem 0.65rem;
        }

        #app-shell .app-shell-bottom-spacer {
          margin-top: auto;
        }

        @media (max-width: 860px) {
          #app-shell .app-shell-layout {
            flex-direction: column;
          }

          #app-shell .app-shell-sidebar {
            width: 100%;
            min-width: 100%;
            border-right: none;
            border-bottom: 1px solid var(--pfx-border);
            min-height: auto;
          }

          #app-shell[data-sidebar-collapsed="true"] .app-shell-sidebar {
            width: 100%;
            min-width: 100%;
          }

          #app-shell[data-sidebar-collapsed="true"] .app-shell-brand {
            justify-content: flex-start;
          }

          #app-shell .app-shell-theme-label {
            display: inline-block;
          }

          #app-shell .app-shell-theme-icon {
            display: none;
          }

          #app-shell .app-shell-main {
            padding: 1rem;
          }
        }
      </style>

      <div class="app-shell-layout">
        <aside class="app-shell-sidebar" aria-label="Primary navigation">
          <div class="app-shell-sidebar-top">
            <a href="/securities" class="app-shell-brand" aria-label="Portfolixir">
              <img
                id="app-shell-brand-light-wordmark"
                class="app-shell-logo-wordmark app-shell-logo-wordmark-light"
                src="/images/logo-light.svg"
                alt="Portfolixir"
              />
              <img
                id="app-shell-brand-dark-wordmark"
                class="app-shell-logo-wordmark app-shell-logo-wordmark-dark"
                src="/images/logo-dark.svg"
                alt="Portfolixir"
              />
              <img
                id="app-shell-brand-mark"
                class="app-shell-logo-mark"
                src="/images/logo-mark.svg"
                alt="Portfolixir mark"
              />
              <span class="app-shell-visually-hidden">Portfolixir</span>
            </a>
            <button
              id="sidebar-toggle"
              class="app-shell-icon-button"
              type="button"
              aria-label="Collapse sidebar"
              title="Collapse sidebar"
            >
              ☰
            </button>
          </div>

          <nav class="app-shell-sidebar-nav" aria-label="Main navigation">
            <div class="app-shell-nav-group">
              <p class="app-shell-nav-group-title">Securities</p>
              <a
                href="/securities"
                aria-label="All Securities"
                title="All Securities"
                class={if @current_path == "/securities" || @current_path == "/" do
                  "app-shell-nav-link is-active"
                else
                  "app-shell-nav-link"
                end}
              >
                <span class="app-shell-nav-icon" aria-hidden="true">S</span>
                <span class="app-shell-nav-label">All Securities</span>
              </a>
              <span
                class="app-shell-nav-link is-disabled"
                aria-label="Watchlist"
                aria-disabled="true"
                title="Coming soon"
              >
                <span class="app-shell-nav-icon" aria-hidden="true">W</span>
                <span class="app-shell-nav-label">Watchlist</span>
              </span>
            </div>

            <div class="app-shell-nav-group">
              <p class="app-shell-nav-group-title">Master data</p>
              <span
                class="app-shell-nav-link is-disabled"
                aria-label="Accounts"
                aria-disabled="true"
                title="Coming soon"
              >
                <span class="app-shell-nav-icon" aria-hidden="true">A</span>
                <span class="app-shell-nav-label">Accounts</span>
              </span>
              <span
                class="app-shell-nav-link is-disabled"
                aria-label="Securities accounts"
                aria-disabled="true"
                title="Coming soon"
              >
                <span class="app-shell-nav-icon" aria-hidden="true">💼</span>
                <span class="app-shell-nav-label">Securities accounts</span>
              </span>
              <span
                class="app-shell-nav-link is-disabled"
                aria-label="Deposit accounts"
                aria-disabled="true"
                title="Coming soon"
              >
                <span class="app-shell-nav-icon" aria-hidden="true">🏦</span>
                <span class="app-shell-nav-label">Deposit accounts</span>
              </span>
            </div>

            <div class="app-shell-nav-group">
              <p class="app-shell-nav-group-title">Classifications</p>
              <a
                href="/taxonomies"
                aria-label="Classifications"
                title="Classifications"
                class={if @current_path == "/taxonomies" do
                  "app-shell-nav-link is-active"
                else
                  "app-shell-nav-link"
                end}
              >
                <span class="app-shell-nav-icon" aria-hidden="true">C</span>
                <span class="app-shell-nav-label">Classifications</span>
              </a>
            </div>

            <div class="app-shell-nav-group">
              <p class="app-shell-nav-group-title">Reports</p>
              <span
                class="app-shell-nav-link is-disabled"
                aria-label="Holdings"
                aria-disabled="true"
                title="Coming soon"
              >
                <span class="app-shell-nav-icon" aria-hidden="true">H</span>
                <span class="app-shell-nav-label">Holdings</span>
              </span>
              <span
                class="app-shell-nav-link is-disabled"
                aria-label="Performance"
                aria-disabled="true"
                title="Coming soon"
              >
                <span class="app-shell-nav-icon" aria-hidden="true">📈</span>
                <span class="app-shell-nav-label">Performance</span>
              </span>
            </div>
          </nav>

          <button
            id="theme-toggle"
            class="app-shell-theme-toggle app-shell-bottom-spacer"
            type="button"
            title="Switch to dark mode"
            aria-label="Switch to dark mode"
          >
            <span class="app-shell-theme-label">Dark mode</span>
            <span class="app-shell-theme-icon" aria-hidden="true">◐</span>
          </button>
        </aside>

        <main class="app-shell-main">
          <div class="app-shell-main-inner">
            <section class="app-shell-content-card">
              <%= render_slot(@inner_block) %>
            </section>
          </div>
        </main>
      </div>

      <script id="theme-toggle-script">
        (function () {
          var themeKey = "portfolixir-theme";
          var sidebarKey = "portfolixir-sidebar-collapsed";
          var shell = document.getElementById("app-shell");
          var toggle = document.getElementById("theme-toggle");
          var themeLabel = document.querySelector("#theme-toggle .app-shell-theme-label");
          var themeIcon = document.querySelector("#theme-toggle .app-shell-theme-icon");
          var sidebarToggle = document.getElementById("sidebar-toggle");

          function normalizeTheme(value) {
            return value === "dark" ? "dark" : "light";
          }

          function applyTheme(theme) {
            var resolvedTheme = normalizeTheme(theme);
            shell.setAttribute("data-theme", resolvedTheme);
            document.documentElement.setAttribute("data-theme", resolvedTheme);
            var isDark = resolvedTheme === "dark";

            if (themeLabel) {
              themeLabel.textContent = isDark ? "Light mode" : "Dark mode";
            }

            if (themeIcon) {
              themeIcon.textContent = isDark ? "☀" : "◑";
            }

            if (toggle) {
              toggle.setAttribute("title", isDark ? "Switch to light mode" : "Switch to dark mode");
              toggle.setAttribute("aria-label", isDark ? "Switch to light mode" : "Switch to dark mode");
            }

            try {
              localStorage.setItem(themeKey, resolvedTheme);
            } catch (_error) {}
          }

          function applySidebarState(isCollapsed) {
            shell.setAttribute("data-sidebar-collapsed", isCollapsed ? "true" : "false");
            if (sidebarToggle) {
              sidebarToggle.setAttribute("aria-pressed", isCollapsed ? "true" : "false");
              sidebarToggle.setAttribute("title", isCollapsed ? "Expand sidebar" : "Collapse sidebar");
              sidebarToggle.setAttribute("aria-label", isCollapsed ? "Expand sidebar" : "Collapse sidebar");
            }

            try {
              localStorage.setItem(sidebarKey, isCollapsed ? "true" : "false");
            } catch (_error) {}
          }

          function currentTheme() {
            try {
              return normalizeTheme(localStorage.getItem(themeKey));
            } catch (_error) {}
            return "light";
          }

          function currentSidebarCollapsed() {
            try {
              return localStorage.getItem(sidebarKey) === "true";
            } catch (_error) {}
            return false;
          }

          function ensureFavicons() {
            var head = document.head;
            if (!head) {
              return;
            }

            var svgFavicon = document.querySelector("link[data-pfx-favicon='svg']");
            if (!svgFavicon) {
              svgFavicon = document.createElement("link");
              svgFavicon.setAttribute("rel", "icon");
              svgFavicon.setAttribute("type", "image/svg+xml");
              svgFavicon.setAttribute("data-pfx-favicon", "svg");
              head.appendChild(svgFavicon);
            }

            var icoFavicon = document.querySelector("link[data-pfx-favicon='ico']");
            if (!icoFavicon) {
              icoFavicon = document.createElement("link");
              icoFavicon.setAttribute("rel", "alternate icon");
              icoFavicon.setAttribute("type", "image/x-icon");
              icoFavicon.setAttribute("data-pfx-favicon", "ico");
              head.appendChild(icoFavicon);
            }

            svgFavicon.href = "/favicon.svg";
            icoFavicon.href = "/favicon.ico";
          }

          if (shell) {
            applyTheme(currentTheme());
            applySidebarState(currentSidebarCollapsed());
            ensureFavicons();
          }

          if (toggle) {
            toggle.addEventListener("click", function () {
              var nextTheme = shell.getAttribute("data-theme") === "dark" ? "light" : "dark";
              applyTheme(nextTheme);
            });
          }

          if (sidebarToggle) {
            sidebarToggle.addEventListener("click", function () {
              var isCollapsed = shell.getAttribute("data-sidebar-collapsed") === "true";
              applySidebarState(!isCollapsed);
            });
          }
        })();
      </script>
    </div>
    """
  end
end
