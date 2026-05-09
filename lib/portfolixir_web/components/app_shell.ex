defmodule PortfolixirWeb.AppShell do
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  attr(:current_path, :string, default: "/")
  slot(:inner_block, required: true)

  def shell(assigns) do
    ~H"""
    <div id="app-shell">
      <style>
        :root {
          --pfx-bg: #f6f8fb;
          --pfx-surface: #ffffff;
          --pfx-text: #172033;
          --pfx-muted: #5d6b82;
          --pfx-border: #d8e1ea;
          --pfx-accent: #0f766e;
          --pfx-accent-dark: #115e59;
          --pfx-error: #b91c1c;
          --pfx-success: #15803d;
        }

        body {
          margin: 0;
          background: var(--pfx-bg);
          color: var(--pfx-text);
          font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        }

        #app-shell * {
          box-sizing: border-box;
        }

        #app-shell a {
          color: var(--pfx-accent-dark);
          text-decoration: none;
        }

        #app-shell a:hover {
          text-decoration: underline;
          text-underline-offset: 0.18em;
        }

        .layout {
          min-height: 100vh;
          display: grid;
          grid-template-columns: 15rem minmax(0, 1fr);
        }

        .sidebar {
          padding: 1rem;
          background: #0f1d33;
          color: #f8fafc;
        }

        .brand {
          display: block;
          color: #ffffff;
          font-weight: 800;
          margin-bottom: 1.25rem;
        }

        .nav {
          display: grid;
          gap: 0.35rem;
        }

        .nav a {
          display: block;
          min-height: 2.5rem;
          padding: 0.62rem 0.7rem;
          border-radius: 8px;
          color: #e5eefb;
          font-weight: 650;
        }

        .nav a.is-active {
          background: rgba(45, 212, 191, 0.18);
          box-shadow: inset 3px 0 0 var(--pfx-accent);
        }

        main {
          min-width: 0;
          padding: 1.5rem;
        }

        .page-header {
          margin-bottom: 1rem;
        }

        .page-header h1 {
          margin: 0 0 0.25rem;
          font-size: 1.8rem;
        }

        .page-header p {
          margin: 0;
          color: var(--pfx-muted);
        }

        .stack {
          display: grid;
          gap: 1rem;
        }

        .grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(15rem, 1fr));
          gap: 1rem;
        }

        .panel,
        .stat,
        .empty-state {
          background: var(--pfx-surface);
          border: 1px solid var(--pfx-border);
          border-radius: 8px;
          padding: 1rem;
        }

        .panel h2,
        .panel h3 {
          margin-top: 0;
        }

        .stat strong {
          display: block;
          font-size: 1.6rem;
        }

        form {
          display: grid;
          gap: 0.75rem;
        }

        .form-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(12rem, 1fr));
          gap: 0.75rem;
          align-items: end;
        }

        label {
          display: grid;
          gap: 0.28rem;
          color: var(--pfx-muted);
          font-size: 0.9rem;
          font-weight: 650;
        }

        input,
        select,
        textarea {
          width: 100%;
          min-height: 2.4rem;
          border: 1px solid var(--pfx-border);
          border-radius: 6px;
          padding: 0.45rem 0.55rem;
          color: var(--pfx-text);
          font: inherit;
        }

        button,
        .button {
          min-height: 2.4rem;
          border: 1px solid var(--pfx-accent);
          border-radius: 6px;
          padding: 0.48rem 0.75rem;
          background: var(--pfx-accent);
          color: #ffffff;
          cursor: pointer;
          font: inherit;
          font-weight: 750;
        }

        table {
          width: 100%;
          border-collapse: collapse;
        }

        th,
        td {
          padding: 0.55rem;
          border-bottom: 1px solid var(--pfx-border);
          text-align: left;
          vertical-align: top;
        }

        th {
          color: var(--pfx-muted);
          font-size: 0.88rem;
        }

        .alert-error {
          color: var(--pfx-error);
          font-weight: 650;
        }

        .alert-success {
          color: var(--pfx-success);
          font-weight: 650;
        }

        .chart {
          width: 100%;
          max-width: 42rem;
          height: auto;
          display: block;
        }

        @media (max-width: 720px) {
          .layout {
            grid-template-columns: 1fr;
          }

          .sidebar {
            position: static;
          }

          .nav {
            grid-template-columns: repeat(2, minmax(0, 1fr));
          }
        }
      </style>

      <div class="layout">
        <aside class="sidebar">
          <a class="brand" href="/">Portfolixir</a>
          <nav class="nav" aria-label={gettext("Primary navigation")}>
            <a id="nav-dashboard" href="/" class={nav_class(@current_path, "/")}>
              <%= gettext("Dashboard") %>
            </a>
            <a id="nav-securities" href="/securities" class={nav_class(@current_path, "/securities")}>
              <%= gettext("Securities") %>
            </a>
            <a id="nav-portfolios" href="/portfolios" class={nav_class(@current_path, "/portfolios")}>
              <%= gettext("Portfolios") %>
            </a>
            <a id="nav-transactions" href="/transactions" class={nav_class(@current_path, "/transactions")}>
              <%= gettext("Transactions") %>
            </a>
          </nav>
        </aside>
        <main>
          <%= render_slot(@inner_block) %>
        </main>
      </div>
    </div>
    """
  end

  defp nav_class(current_path, "/") do
    if current_path == "/", do: "is-active", else: ""
  end

  defp nav_class(current_path, path) do
    if current_path == path or String.starts_with?(current_path, path <> "/") do
      "is-active"
    else
      ""
    end
  end
end
