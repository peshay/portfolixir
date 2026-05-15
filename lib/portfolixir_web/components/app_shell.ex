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
          <%= for group <- nav_groups() do %>
            <div class={["nav-group", group.title == nil && "nav-group-unlabeled"]}>
              <%= if group.title do %>
                <div class="nav-group-head"><span><%= group.title %></span></div>
              <% end %>

              <%= for item <- group.items do %>
                <%= if item[:disabled] do %>
                  <span
                    id={item.id}
                    class="nav-link is-disabled"
                    aria-disabled="true"
                    title={gettext("Coming soon")}
                  >
                    <span class="nav-marker" aria-hidden="true"></span>
                    <span class="nav-ico" aria-hidden="true"><%= nav_icon(item[:icon]) %></span>
                    <span class="nav-label"><%= item.label %></span>
                    <span class="nav-pill" aria-hidden="true"><%= gettext("Soon") %></span>
                  </span>
                <% else %>
                  <a
                    id={item.id}
                    class={["nav-link", nav_current?(@current_path, item) && "is-active"]}
                    href={item.href}
                    aria-current={if nav_current?(@current_path, item), do: "page", else: nil}
                  >
                    <span class="nav-marker" aria-hidden="true"></span>
                    <span class="nav-ico" aria-hidden="true"><%= nav_icon(item[:icon]) %></span>
                    <span class="nav-label"><%= item.label %></span>
                  </a>
                <% end %>
              <% end %>
            </div>
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

  defp nav_groups do
    [
      %{
        title: nil,
        items: [
          %{
            id: "nav-dashboard",
            href: "/",
            label: gettext("Dashboard"),
            section: :dashboard,
            icon: :dashboard
          }
        ]
      },
      %{
        title: gettext("Securities"),
        items: [
          %{
            id: "nav-securities",
            href: "/securities",
            label: gettext("Securities"),
            section: :securities,
            icon: :layers
          },
          %{
            id: "nav-watchlist",
            label: gettext("Watchlist"),
            disabled: true,
            icon: :bookmark
          }
        ]
      },
      %{
        title: gettext("Master data"),
        items: [
          %{
            id: "nav-portfolios",
            href: "/portfolios",
            label: gettext("Portfolios"),
            section: :portfolios,
            icon: :briefcase
          },
          %{
            id: "nav-grouped-accounts",
            label: gettext("Grouped accounts"),
            disabled: true,
            icon: :folder
          },
          %{
            id: "nav-savings-plans",
            label: gettext("Savings plans"),
            disabled: true,
            icon: :calc
          },
          %{
            id: "nav-transactions",
            href: "/transactions",
            label: gettext("All transactions"),
            section: :transactions,
            icon: :bars
          }
        ]
      },
      %{
        title: gettext("Reports"),
        items: [
          %{
            id: "nav-asset-allocation",
            label: gettext("Asset allocation"),
            disabled: true,
            icon: :pie
          },
          %{
            id: "nav-holdings",
            label: gettext("Holdings"),
            disabled: true,
            icon: :briefcase
          },
          %{
            id: "nav-performance",
            label: gettext("Performance"),
            disabled: true,
            icon: :chart_line
          },
          %{
            id: "nav-returns-risk",
            label: gettext("Returns & risk"),
            disabled: true,
            icon: :chart_bar
          },
          %{
            id: "nav-dividends",
            label: gettext("Dividends"),
            disabled: true,
            icon: :coins
          }
        ]
      },
      %{
        title: gettext("Classifications"),
        items: [
          %{
            id: "nav-classifications-asset-class",
            label: gettext("Asset class"),
            disabled: true,
            icon: :tag
          },
          %{
            id: "nav-classifications-regions",
            label: gettext("Regions"),
            disabled: true,
            icon: :globe
          },
          %{
            id: "nav-classifications-industries",
            label: gettext("Industries"),
            disabled: true,
            icon: :building
          },
          %{
            id: "nav-classifications-strategies",
            label: gettext("Strategies"),
            disabled: true,
            icon: :compass
          }
        ]
      },
      %{
        title: gettext("General"),
        items: [
          %{
            id: "nav-currencies",
            label: gettext("Currencies"),
            disabled: true,
            icon: :coins
          },
          %{
            id: "nav-settings",
            label: gettext("Settings"),
            disabled: true,
            icon: :settings
          }
        ]
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

  # Compact inline-SVG icon set (subset of the design bundle).
  defp nav_icon(name) do
    {:safe,
     ~s(<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">) <>
       icon_paths(name) <> ~s(</svg>)}
  end

  @doc "Renders one of the named inline SVG icons at the given size."
  attr(:name, :atom, required: true)
  attr(:size, :integer, default: 16)
  attr(:class, :string, default: nil)

  def icon(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.6"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={@class}
      aria-hidden="true"
    ><%= Phoenix.HTML.raw(icon_paths(@name)) %></svg>
    """
  end

  defp icon_paths(:dashboard),
    do:
      ~s(<rect x="3" y="3" width="8" height="8" rx="1.5"/><rect x="13" y="3" width="8" height="5" rx="1.5"/><rect x="13" y="10" width="8" height="11" rx="1.5"/><rect x="3" y="13" width="8" height="8" rx="1.5"/>)

  defp icon_paths(:layers),
    do: ~s(<path d="m12 2 10 6-10 6L2 8Z"/><path d="m2 16 10 6 10-6"/><path d="m2 12 10 6 10-6"/>)

  defp icon_paths(:bookmark), do: ~s(<path d="M19 21V5a2 2 0 0 0-2-2H7a2 2 0 0 0-2 2v16l7-4Z"/>)

  defp icon_paths(:briefcase),
    do:
      ~s(<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>)

  defp icon_paths(:folder),
    do: ~s(<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z"/>)

  defp icon_paths(:calc),
    do:
      ~s(<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 7h6"/><circle cx="9" cy="11" r=".6"/><circle cx="12" cy="11" r=".6"/><circle cx="15" cy="11" r=".6"/><circle cx="9" cy="14" r=".6"/><circle cx="12" cy="14" r=".6"/><circle cx="15" cy="14" r=".6"/><path d="M9 17h6"/>)

  defp icon_paths(:bars), do: ~s(<path d="M4 4h16M4 12h16M4 20h16"/>)

  defp icon_paths(:pie),
    do: ~s(<path d="M21 12A9 9 0 1 1 12 3v9Z"/><path d="M21 12a9 9 0 0 0-9-9v9h9Z"/>)

  defp icon_paths(:chart_line), do: ~s(<path d="M3 17 9 11l4 4 8-8"/>)
  defp icon_paths(:chart_bar), do: ~s(<path d="M3 20V8M9 20V4M15 20v-8M21 20v-5"/>)
  defp icon_paths(:coins), do: ~s(<circle cx="9" cy="9" r="6"/><circle cx="16" cy="16" r="6"/>)

  defp icon_paths(:tag),
    do:
      ~s(<path d="M20.6 11.4 12 2H4v8l9.4 9.4a2 2 0 0 0 2.8 0l4.4-4.4a2 2 0 0 0 0-2.8Z"/><circle cx="7.5" cy="7.5" r="1.2"/>)

  defp icon_paths(:globe),
    do:
      ~s(<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>)

  defp icon_paths(:building),
    do: ~s(<rect x="4" y="2" width="16" height="20" rx="1"/><path d="M10 22v-4h4v4"/>)

  defp icon_paths(:compass), do: ~s(<circle cx="12" cy="12" r="9"/><path d="m16 8-2 6-6 2 2-6Z"/>)

  defp icon_paths(:settings),
    do: ~s(<circle cx="12" cy="12" r="3"/><circle cx="12" cy="12" r="9"/>)

  defp icon_paths(:plus), do: ~s(<path d="M12 5v14M5 12h14"/>)

  defp icon_paths(:filter),
    do: ~s(<path d="M3 5h18l-7 9v6l-4-2v-4Z"/>)

  defp icon_paths(:columns),
    do:
      ~s(<rect x="3" y="4" width="6" height="16" rx="1"/><rect x="11" y="4" width="6" height="16" rx="1"/><rect x="19" y="4" width="2" height="16" rx="1"/>)

  defp icon_paths(:search),
    do: ~s(<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>)

  defp icon_paths(:trash),
    do:
      ~s(<path d="M4 7h16"/><path d="M9 7V4h6v3"/><path d="M6 7v13a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V7"/><path d="M10 11v7M14 11v7"/>)

  defp icon_paths(:x), do: ~s(<path d="M6 6l12 12M18 6 6 18"/>)

  defp icon_paths(:chevron_right), do: ~s(<path d="m9 6 6 6-6 6"/>)

  defp icon_paths(:refresh_cw),
    do: ~s(<path d="M21 12a9 9 0 1 1-3.2-6.9"/><path d="M21 4v5h-5"/>)

  defp icon_paths(_), do: ~s(<circle cx="12" cy="12" r="5"/>)
end
