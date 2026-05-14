defmodule PortfolixirWeb.AppShell do
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  attr(:current_path, :string, default: "/")
  slot(:inner_block, required: true)

  def shell(assigns) do
    ~H"""
    <div id="app-shell" class="app-shell">
      <input
        id="app-sidebar-toggle"
        class="sidebar-toggle-control"
        type="checkbox"
        aria-label={gettext("Toggle navigation")}
      />

      <aside id="app-sidebar" class="app-sidebar" aria-label={gettext("Application navigation")}>
        <a class="brand" href="/" aria-label="Portfolixir">
          <span class="brand-logo" aria-hidden="true">
            <img class="brand-mark brand-mark-light" src="/images/logo-mark-light.svg" alt="" />
            <img class="brand-mark brand-mark-dark" src="/images/logo-mark-dark.svg" alt="" />
          </span>
          <span class="brand-wordmark">Portfolixir</span>
        </a>

        <nav class="primary-nav" aria-label={gettext("Primary navigation")}>
          <%= for item <- nav_items() do %>
            <a
              id={item.id}
              class={["nav-link", nav_current?(@current_path, item) && "is-active"]}
              href={item.href}
              aria-current={if nav_current?(@current_path, item), do: "page", else: nil}
            >
              <span class="nav-marker" aria-hidden="true"></span>
              <span><%= item.label %></span>
            </a>
          <% end %>
        </nav>

      </aside>

      <label class="sidebar-backdrop" for="app-sidebar-toggle" aria-hidden="true"></label>

      <div class="app-frame">
        <header class="topbar">
          <label class="sidebar-toggle" for="app-sidebar-toggle" aria-label={gettext("Open navigation")}>
            <span class="burger-bars" aria-hidden="true"></span>
          </label>

          <a class="topbar-brand" href="/" aria-label="Portfolixir">
            <span class="brand-logo" aria-hidden="true">
              <img class="topbar-mark brand-mark-light" src="/images/logo-mark-light.svg" alt="" />
              <img class="topbar-mark brand-mark-dark" src="/images/logo-mark-dark.svg" alt="" />
            </span>
            <span>Portfolixir</span>
          </a>

          <div class="topbar-controls" aria-label={gettext("Display preferences")}>
            <details id="theme-mode" class="theme-menu" aria-label={gettext("Theme")} data-theme-control>
              <summary class="theme-menu-trigger" title={gettext("Theme")}>
                <span class="theme-current-icon theme-current-icon-system" aria-hidden="true">
                  <span class="theme-icon theme-icon-system"></span>
                </span>
                <span class="theme-current-icon theme-current-icon-light" aria-hidden="true">
                  <span class="theme-icon theme-icon-light"></span>
                </span>
                <span class="theme-current-icon theme-current-icon-dark" aria-hidden="true">
                  <span class="theme-icon theme-icon-dark"></span>
                </span>
                <span class="visually-hidden"><%= gettext("Theme") %></span>
              </summary>

              <div class="theme-menu-list" role="group" aria-label={gettext("Theme")}>
                <%= for mode <- theme_modes() do %>
                  <button
                    type="button"
                    class={["theme-choice", mode.value == "system" && "is-active"]}
                    data-theme-choice={mode.value}
                    aria-label={mode.label}
                    aria-pressed={if mode.value == "system", do: "true", else: "false"}
                    title={mode.label}
                  >
                    <span class={"theme-icon theme-icon-#{mode.value}"} aria-hidden="true"></span>
                    <span class="visually-hidden"><%= mode.label %></span>
                  </button>
                <% end %>
              </div>
            </details>

            <nav class="locale-switcher" aria-label={gettext("Language")}>
              <%= for locale <- [{"en", "EN"}, {"de", "DE"}] do %>
                <a
                  id={"locale-#{elem(locale, 0)}"}
                  class={["locale-link", current_locale() == elem(locale, 0) && "is-active"]}
                  href={locale_href(@current_path, elem(locale, 0))}
                  hreflang={elem(locale, 0)}
                  aria-label={locale_label(elem(locale, 0))}
                  aria-current={if current_locale() == elem(locale, 0), do: "true", else: nil}
                >
                  <%= elem(locale, 1) %>
                </a>
              <% end %>
            </nav>
          </div>
        </header>

        <main class="app-main">
          <%= render_slot(@inner_block) %>
        </main>
      </div>
    </div>
    """
  end

  defp nav_items do
    [
      %{id: "nav-dashboard", href: "/", label: gettext("Dashboard"), section: :dashboard},
      %{
        id: "nav-securities",
        href: "/securities",
        label: gettext("Securities"),
        section: :securities
      },
      %{
        id: "nav-portfolios",
        href: "/portfolios",
        label: gettext("Portfolios"),
        section: :portfolios
      },
      %{
        id: "nav-transactions",
        href: "/transactions",
        label: gettext("Transactions"),
        section: :transactions
      }
    ]
  end

  defp nav_current?("/", %{section: :dashboard}), do: true
  defp nav_current?(path, %{section: :securities}), do: String.starts_with?(path, "/securities")
  defp nav_current?(path, %{section: :portfolios}), do: String.starts_with?(path, "/portfolios")

  defp nav_current?(path, %{section: :transactions}),
    do: String.starts_with?(path, "/transactions")

  defp nav_current?(_path, _item), do: false

  defp theme_modes do
    [
      %{value: "system", label: gettext("System")},
      %{value: "light", label: gettext("Light")},
      %{value: "dark", label: gettext("Dark")}
    ]
  end

  defp current_locale do
    Gettext.get_locale(PortfolixirWeb.Gettext)
  end

  defp locale_href(path, locale) do
    "#{path}?locale=#{locale}"
  end

  defp locale_label("de"), do: gettext("German")
  defp locale_label("en"), do: gettext("English")
end
