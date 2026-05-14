defmodule PortfolixirWeb.AppShell do
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  attr(:current_path, :string, default: "/")
  slot(:inner_block, required: true)

  def shell(assigns) do
    ~H"""
    <div id="app-shell">
      <header>
        <a href="/">Portfolixir</a>
        <nav aria-label={gettext("Primary navigation")}>
          <a id="nav-dashboard" href="/"><%= gettext("Dashboard") %></a>
          <a id="nav-securities" href="/securities"><%= gettext("Securities") %></a>
          <a id="nav-portfolios" href="/portfolios"><%= gettext("Portfolios") %></a>
          <a id="nav-transactions" href="/transactions"><%= gettext("Transactions") %></a>
        </nav>
      </header>
      <main>
        <%= render_slot(@inner_block) %>
      </main>
    </div>
    """
  end
end
