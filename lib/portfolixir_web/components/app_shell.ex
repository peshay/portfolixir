defmodule PortfolixirWeb.AppShell do
  use Phoenix.Component

  slot(:inner_block, required: true)

  def shell(assigns) do
    ~H"""
    <div id="app-shell" data-theme="light">
      <style id="app-shell-styles">
        :root {
          --pfx-bg: #f8fafc;
          --pfx-surface: #ffffff;
          --pfx-text: #0f172a;
          --pfx-muted: #475569;
          --pfx-border: #e2e8f0;
          --pfx-input: #f8fafc;
          --pfx-input-border: #cbd5e1;
          --pfx-link: #2563eb;
        }

        [data-theme="dark"] {
          --pfx-bg: #0f172a;
          --pfx-surface: #1e293b;
          --pfx-text: #f8fafc;
          --pfx-muted: #cbd5e1;
          --pfx-border: #334155;
          --pfx-input: #1e293b;
          --pfx-input-border: #475569;
          --pfx-link: #93c5fd;
        }

        #app-shell {
          min-height: 100vh;
          margin: 0;
          background: var(--pfx-bg);
          color: var(--pfx-text);
          font-family: "Trebuchet MS", "Segoe UI", sans-serif;
        }

        #app-shell a {
          color: var(--pfx-link);
          text-decoration: none;
        }

        #app-shell .app-shell-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 1rem;
          flex-wrap: wrap;
          background: var(--pfx-surface);
          border-bottom: 1px solid var(--pfx-border);
          padding: 1rem 1.25rem;
        }

        #app-shell .app-shell-brand {
          font-weight: 700;
          letter-spacing: 0.03em;
        }

        #app-shell .app-shell-nav {
          display: flex;
          gap: 1rem;
          flex-wrap: wrap;
        }

        #app-shell .app-shell-theme-toggle {
          border: 1px solid var(--pfx-border);
          border-radius: 0.5rem;
          background: var(--pfx-bg);
          color: var(--pfx-text);
          padding: 0.45rem 0.8rem;
          cursor: pointer;
        }

        #app-shell .app-shell-main {
          max-width: 72rem;
          margin: 0 auto;
          width: 100%;
          padding: 1.25rem;
          box-sizing: border-box;
        }

        #app-shell .app-shell-content-card {
          background: var(--pfx-surface);
          border: 1px solid var(--pfx-border);
          border-radius: 0.75rem;
          padding: 1rem;
          box-sizing: border-box;
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
      </style>

      <header class="app-shell-header">
        <div class="app-shell-brand">Portfolixir</div>
        <nav class="app-shell-nav" aria-label="Main navigation">
          <a href="/securities">Securities</a>
          <a href="/taxonomies">Categories</a>
          <a href="/health">Health</a>
        </nav>
        <button id="theme-toggle" class="app-shell-theme-toggle" type="button">Dark mode</button>
      </header>

      <main class="app-shell-main">
        <section class="app-shell-content-card">
          <%= render_slot(@inner_block) %>
        </section>
      </main>
    </div>
    <script id="theme-toggle-script">
      (function () {
        var key = "portfolixir-theme";
        var shell = document.getElementById("app-shell");
        var toggle = document.getElementById("theme-toggle");

        function normalizeTheme(value) {
          return value === "dark" ? "dark" : "light";
        }

        function applyTheme(theme) {
          var resolvedTheme = normalizeTheme(theme);
          shell.setAttribute("data-theme", resolvedTheme);
          document.documentElement.setAttribute("data-theme", resolvedTheme);
          toggle.textContent = resolvedTheme === "dark" ? "Light mode" : "Dark mode";
          try {
            localStorage.setItem(key, resolvedTheme);
          } catch (_error) {}
        }

        function currentTheme() {
          try {
            return normalizeTheme(localStorage.getItem(key) || "light");
          } catch (_error) {}
          return "light";
        }

        if (shell && toggle) {
          applyTheme(currentTheme());
          toggle.addEventListener("click", function () {
            var nextTheme = shell.getAttribute("data-theme") === "dark" ? "light" : "dark";
            applyTheme(nextTheme);
          });
        }
      })();
    </script>
    """
  end
end
