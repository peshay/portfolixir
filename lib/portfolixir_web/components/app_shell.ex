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
          --pfx-bg: #f8fafc;
          --pfx-surface: #ffffff;
          --pfx-surface-secondary: #f8fafc;
          --pfx-text: #0f172a;
          --pfx-muted: #475569;
          --pfx-border: #e2e8f0;
          --pfx-input: #ffffff;
          --pfx-input-border: #cbd5e1;
          --pfx-link: #2563eb;
          --pfx-accent: #6d28d9;
          --pfx-accent-soft: #ede9fe;
        }

        [data-theme="dark"] {
          --pfx-bg: #020617;
          --pfx-surface: #0f172a;
          --pfx-surface-secondary: #1e293b;
          --pfx-text: #f8fafc;
          --pfx-muted: #cbd5e1;
          --pfx-border: #334155;
          --pfx-input: #1e293b;
          --pfx-input-border: #475569;
          --pfx-link: #93c5fd;
          --pfx-accent: #a78bfa;
          --pfx-accent-soft: #312e81;
        }

        #app-shell {
          min-height: 100vh;
          margin: 0;
          background: var(--pfx-bg);
          color: var(--pfx-text);
          font-family: "Verdana", "Geneva", "Trebuchet MS", sans-serif;
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
          width: 18rem;
          padding: 1rem;
          box-sizing: border-box;
          background: var(--pfx-surface);
          border-right: 1px solid var(--pfx-border);
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
          transition: width 0.2s ease;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-sidebar {
          width: 5rem;
        }

        #app-shell .app-shell-sidebar-top {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 0.5rem;
        }

        #app-shell .app-shell-icon-button {
          border: 1px solid var(--pfx-border);
          border-radius: 0.65rem;
          background: var(--pfx-input);
          color: var(--pfx-text);
          padding: 0.45rem 0.55rem;
          cursor: pointer;
          width: 2.2rem;
          height: 2.2rem;
          display: inline-flex;
          align-items: center;
          justify-content: center;
        }

        #app-shell .app-shell-theme-toggle {
          border: 1px solid var(--pfx-input-border);
          border-radius: 0.45rem;
          background: var(--pfx-input);
          color: var(--pfx-text);
          padding: 0.45rem 0.7rem;
          cursor: pointer;
          min-height: 2.2rem;
          display: inline-flex;
          align-items: center;
          justify-content: flex-start;
          gap: 0.45rem;
          width: 100%;
          box-sizing: border-box;
          white-space: nowrap;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-theme-toggle {
          width: 2.2rem;
          padding: 0.45rem 0.55rem;
          justify-content: center;
        }

        #app-shell .app-shell-brand {
          display: flex;
          align-items: center;
          gap: 0.65rem;
          padding: 0.25rem 0;
          min-width: 0;
          flex: 1;
        }

        #app-shell .app-shell-logo {
          height: 2rem;
          width: auto;
          display: inline-block;
          flex: none;
        }

        #app-shell .app-shell-logo-wordmark {
          max-width: 100%;
          width: auto;
          height: 1.75rem;
        }

        #app-shell .app-shell-brand-wordmark {
          display: block;
        }

        #app-shell .app-shell-brand-mark {
          display: none;
        }

        #app-shell .app-shell-brand-label {
          display: block;
          font-weight: 700;
          letter-spacing: 0.03em;
          color: var(--pfx-text);
          white-space: nowrap;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-brand-wordmark,
        #app-shell[data-sidebar-collapsed="true"] .app-shell-brand-label {
          display: none;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-brand-mark {
          display: block;
        }

        #app-shell .app-shell-brand-label.sr-only {
          width: 1px;
          height: 1px;
          padding: 0;
          overflow: hidden;
          position: absolute;
          clip-path: inset(50%);
          clip: rect(0, 0, 0, 0);
          border: 0;
          white-space: nowrap;
        }

        #app-shell .app-shell-sidebar-nav {
          margin-top: 0.5rem;
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }

        #app-shell .app-shell-nav-link {
          display: flex;
          align-items: center;
          gap: 0.7rem;
          border: 1px solid transparent;
          border-radius: 0.65rem;
          padding: 0.55rem 0.7rem;
          min-height: 2.5rem;
          color: var(--pfx-text);
        }

        #app-shell .app-shell-nav-link:hover {
          background: var(--pfx-accent-soft);
        }

        #app-shell .app-shell-nav-link.is-active {
          background: color-mix(in srgb, var(--pfx-accent-soft) 60%, transparent);
          border-color: color-mix(in srgb, var(--pfx-accent) 45%, transparent);
          color: var(--pfx-text);
          font-weight: 600;
        }

        #app-shell .app-shell-nav-icon {
          display: none;
          width: 1.5rem;
          font-weight: 700;
          line-height: 1;
          text-align: center;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-nav-icon {
          display: inline-flex;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-nav-link {
          justify-content: center;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-nav-link .app-shell-nav-label {
          display: none;
        }

        #app-shell .app-shell-theme-label {
          display: inline-block;
        }

        #app-shell .app-shell-theme-icon {
          display: none;
          width: 1.1rem;
          text-align: center;
          font-size: 1rem;
          line-height: 1;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-theme-icon {
          display: inline-block;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-theme-label {
          display: none;
        }

        #app-shell .app-shell-main {
          flex: 1;
          padding: 1.25rem;
          min-width: 0;
        }

        #app-shell .app-shell-content-card {
          background: var(--pfx-surface);
          border: 1px solid var(--pfx-border);
          border-radius: 0.75rem;
          padding: 1.1rem;
          box-sizing: border-box;
          min-height: calc(100vh - 2.5rem);
        }

        #app-shell section {
          margin-top: 1rem;
        }

        #app-shell h1,
        #app-shell h2 {
          margin: 0;
        }

        #app-shell label {
          display: block;
          margin-top: 0.5rem;
          margin-bottom: 0.25rem;
          color: var(--pfx-muted);
          font-size: 0.9rem;
        }

        #app-shell input,
        #app-shell textarea,
        #app-shell select,
        #app-shell button,
        #app-shell table {
          background: var(--pfx-input);
          color: var(--pfx-text);
        }

        #app-shell input,
        #app-shell textarea,
        #app-shell select {
          width: 100%;
          border: 1px solid var(--pfx-input-border);
          border-radius: 0.45rem;
          padding: 0.45rem 0.5rem;
          box-sizing: border-box;
        }

        #app-shell button {
          border: 1px solid var(--pfx-input-border);
          border-radius: 0.45rem;
          padding: 0.45rem 0.7rem;
          margin-top: 0.75rem;
          margin-bottom: 0.35rem;
          cursor: pointer;
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
            border-right: none;
            border-bottom: 1px solid var(--pfx-border);
          }

          #app-shell[data-sidebar-collapsed="true"] .app-shell-sidebar {
            width: 100%;
          }
        }
      </style>

      <div class="app-shell-layout">
        <aside class="app-shell-sidebar" aria-label="Primary navigation">
          <div class="app-shell-sidebar-top">
            <a href="/securities" class="app-shell-brand">
              <img
                id="app-shell-brand-wordmark"
                class="app-shell-logo app-shell-logo-wordmark app-shell-brand-wordmark"
                src="/images/logo-light.svg"
                alt="Portfolixir"
              />
              <img
                id="app-shell-brand-mark"
                class="app-shell-logo app-shell-brand-mark"
                src="/images/logo-mark.svg"
                alt="Portfolixir mark"
              />
              <span class="app-shell-brand-label sr-only">Portfolixir</span>
            </a>
            <button
              id="sidebar-toggle"
              class="app-shell-icon-button"
              type="button"
              aria-label="Toggle sidebar"
            >
              ☰
            </button>
          </div>

          <nav class="app-shell-sidebar-nav" aria-label="Main navigation">
            <a
              href="/securities"
              aria-label="Securities"
              title="Securities"
              class={if @current_path == "/securities" || @current_path == "/" do
                "app-shell-nav-link is-active"
              else
                "app-shell-nav-link"
              end}
            >
              <span class="app-shell-nav-icon" aria-hidden="true">S</span>
              <span class="app-shell-nav-label">Securities</span>
            </a>
            <a
              href="/taxonomies"
              aria-label="Categories"
              title="Categories"
              class={if @current_path == "/taxonomies" do
                "app-shell-nav-link is-active"
              else
                "app-shell-nav-link"
              end}
            >
              <span class="app-shell-nav-icon" aria-hidden="true">C</span>
              <span class="app-shell-nav-label">Categories</span>
            </a>
          </nav>

          <button
            id="theme-toggle"
            class="app-shell-theme-toggle app-shell-bottom-spacer"
            type="button"
          >
            <span class="app-shell-theme-label">Dark mode</span>
            <span class="app-shell-theme-icon" aria-hidden="true">◐</span>
          </button>
        </aside>

        <main class="app-shell-main">
          <section class="app-shell-content-card">
            <%= render_slot(@inner_block) %>
          </section>
        </main>
      </div>
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
        var brandWordmark = document.getElementById("app-shell-brand-wordmark");

        function normalizeTheme(value) {
          return value === "dark" ? "dark" : "light";
        }

        function applyTheme(theme) {
          var resolvedTheme = normalizeTheme(theme);
          shell.setAttribute("data-theme", resolvedTheme);
          document.documentElement.setAttribute("data-theme", resolvedTheme);
          if (toggle) {
            var isDark = resolvedTheme === "dark";
            if (themeLabel) {
              themeLabel.textContent = isDark ? "Light mode" : "Dark mode";
            }
            if (themeIcon) {
              themeIcon.textContent = isDark ? "☀" : "◑";
            }
            toggle.setAttribute("title", isDark ? "Switch to light mode" : "Switch to dark mode");
            toggle.setAttribute("aria-label", isDark ? "Switch to light mode" : "Switch to dark mode");
          }

          if (brandWordmark) {
            brandWordmark.src =
              resolvedTheme === "dark" ? "/images/logo-dark.svg" : "/images/logo-light.svg";
          }

          try {
            localStorage.setItem(themeKey, resolvedTheme);
          } catch (_error) {}
        }

        function applySidebarState(isCollapsed) {
          shell.setAttribute("data-sidebar-collapsed", isCollapsed ? "true" : "false");
          if (sidebarToggle) {
            sidebarToggle.setAttribute("aria-pressed", isCollapsed ? "true" : "false");
            sidebarToggle.setAttribute(
              "title",
              isCollapsed ? "Expand sidebar" : "Collapse sidebar"
            );
            sidebarToggle.setAttribute(
              "aria-label",
              isCollapsed ? "Expand sidebar" : "Collapse sidebar"
            );
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
    """
  end
end
