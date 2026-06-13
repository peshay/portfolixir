defmodule PortfolixirWeb.AppShell do
  @moduledoc "Application shell: top bar, navigation, and page chrome."
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  attr(:current_path, :string, default: "/")
  attr(:page_title, :string, default: nil)
  attr(:page_subtitle, :string, default: nil)
  attr(:main_class, :any, default: "app-main--workspace")
  slot(:inner_block, required: true)

  def shell(assigns) do
    assigns =
      assign_new(assigns, :classifications, fn ->
        Portfolixir.Classifications.list_classifications()
      end)

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
            <%= if group[:kind] == :classifications do %>
              <.classifications_nav classifications={@classifications} current_path={@current_path} />
            <% else %>
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
          <% end %>
        </nav>
      </aside>

      <label class="sidebar-backdrop" for="app-sidebar-toggle" aria-hidden="true"></label>

      <div class="app-frame">
        <header class="topbar">
          <label class="sidebar-toggle" for="app-sidebar-toggle" aria-label={gettext("Open navigation")}>
            <span class="burger-bars" aria-hidden="true"></span>
          </label>

          <div class="topbar-primary">
            <a class="topbar-brand" href="/" aria-label="Portfolixir">
              <span class="brand-logo" aria-hidden="true">
                <img class="topbar-mark brand-mark-light" src="/images/logo-mark-light.svg" alt="" />
                <img class="topbar-mark brand-mark-dark" src="/images/logo-mark-dark.svg" alt="" />
              </span>
              <span>Portfolixir</span>
            </a>

            <div class="topbar-page" aria-live="polite">
              <%= if @page_title do %>
                <h1 id="app-topbar-title"><%= @page_title %></h1>
              <% end %>
              <%= if @page_subtitle do %>
                <p id="app-topbar-subtitle"><%= @page_subtitle %></p>
              <% end %>
            </div>
          </div>

          <div class="topbar-controls" aria-label={gettext("Display preferences")}>
            <details id="theme-mode" class="theme-menu" aria-label={gettext("Theme")} data-theme-control>
              <summary class="theme-menu-trigger" title={gettext("Theme")}>
                <span
                  class="theme-current-icon theme-current-icon-system"
                  data-current-theme-icon="system"
                  aria-hidden="true"
                >
                  <.icon name={:monitor} size={16} class="theme-svg-icon" />
                </span>
                <span
                  class="theme-current-icon theme-current-icon-light"
                  data-current-theme-icon="light"
                  aria-hidden="true"
                >
                  <.icon name={:sun} size={16} class="theme-svg-icon" />
                </span>
                <span
                  class="theme-current-icon theme-current-icon-dark"
                  data-current-theme-icon="dark"
                  aria-hidden="true"
                >
                  <.icon name={:moon} size={16} class="theme-svg-icon" />
                </span>
                <span class="visually-hidden"><%= gettext("Theme") %></span>
              </summary>

              <div class="theme-menu-list" role="group" aria-label={gettext("Theme")}>
                <%= for mode <- theme_modes() do %>
                  <button
                    type="button"
                    class={["theme-choice", mode.value == "system" && "is-active"]}
                    data-theme-choice={mode.value}
                    data-theme-icon={mode.icon_name}
                    aria-label={mode.label}
                    aria-pressed={if mode.value == "system", do: "true", else: "false"}
                    title={mode.label}
                  >
                    <.icon name={mode.icon} size={16} class="theme-svg-icon" />
                    <span class="visually-hidden"><%= mode.label %></span>
                  </button>
                <% end %>
              </div>
            </details>

            <details
              id="accent-color"
              class="accent-menu"
              aria-label={gettext("Accent color")}
              data-accent-control
            >
              <summary class="accent-menu-trigger" title={gettext("Accent color")}>
                <span class="accent-current-dot accent-current-dot-violet" aria-hidden="true"></span>
                <span class="accent-current-dot accent-current-dot-teal" aria-hidden="true"></span>
                <span class="accent-current-dot accent-current-dot-coral" aria-hidden="true"></span>
                <span class="visually-hidden"><%= gettext("Accent color") %></span>
              </summary>

              <div class="accent-menu-list" role="group" aria-label={gettext("Accent color")}>
                <%= for accent <- accent_colors() do %>
                  <button
                    type="button"
                    class={["accent-choice", accent.value == "violet" && "is-active"]}
                    data-accent-choice={accent.value}
                    aria-label={accent.label}
                    aria-pressed={if accent.value == "violet", do: "true", else: "false"}
                    title={accent.label}
                  >
                    <span class={"accent-dot accent-dot-#{accent.value}"} aria-hidden="true"></span>
                    <span class="visually-hidden"><%= accent.label %></span>
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

        <main class={["app-main", @main_class]}>
          <%= render_slot(@inner_block) %>
        </main>
      </div>
    </div>
    """
  end

  defp classifications_nav(assigns) do
    ~H"""
    <div class="nav-group">
      <div class="nav-group-head">
        <span><%= gettext("Classifications") %></span>
        <.link
          navigate="/classifications/new"
          class="nav-add"
          aria-label={gettext("New classification")}
          title={gettext("New classification")}
        >+</.link>
      </div>

      <%= for classification <- @classifications do %>
        <.link
          id={"nav-classification-#{classification.id}"}
          navigate={"/classifications/#{classification.id}"}
          class={[
            "nav-link",
            @current_path == "/classifications/#{classification.id}" && "is-active"
          ]}
          aria-current={
            if @current_path == "/classifications/#{classification.id}", do: "page", else: nil
          }
        >
          <span class="nav-marker" aria-hidden="true"></span>
          <span class="nav-ico" aria-hidden="true"><%= nav_icon(:tag) %></span>
          <span class="nav-label"><%= classification.name %></span>
        </.link>
      <% end %>

      <%= if @classifications == [] do %>
        <.link navigate="/classifications/new" class="nav-link is-disabled">
          <span class="nav-marker" aria-hidden="true"></span>
          <span class="nav-label"><%= gettext("Add your first") %></span>
        </.link>
      <% end %>
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
          },
          %{
            id: "nav-portfolio",
            href: "/portfolio",
            label: gettext("Portfolio"),
            section: :portfolio,
            icon: :chart_line
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
          # "Soon": covered by open issue #320 (watchlist).
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
            id: "nav-transactions",
            href: "/transactions",
            label: gettext("All transactions"),
            section: :transactions,
            icon: :bars
          }
        ]
      },
      %{
        title: gettext("Tools"),
        items: [
          %{
            id: "nav-imports",
            href: "/imports",
            label: gettext("Imports"),
            section: :imports,
            icon: :upload
          }
        ]
      },
      %{
        title: gettext("Reports"),
        items: [
          # "Soon": ships with open issue #316 (IRR returns and risk).
          %{
            id: "nav-returns-risk",
            label: gettext("Returns & risk"),
            disabled: true,
            icon: :chart_bar
          },
          # The income report (issue #331). Labelled "Income" rather than
          # "Dividends" because it also reports interest (PP INTEREST: account
          # interest and bond coupons), not only dividends.
          %{
            id: "nav-dividends",
            href: "/income",
            label: gettext("Income"),
            section: :income,
            icon: :coins
          }
        ]
      },
      %{
        title: gettext("Classifications"),
        kind: :classifications,
        items: []
      }
    ]
  end

  defp nav_current?("/", %{section: :dashboard}), do: true
  defp nav_current?(path, %{section: :portfolio}), do: path == "/portfolio"
  defp nav_current?(path, %{section: :securities}), do: String.starts_with?(path, "/securities")
  defp nav_current?(path, %{section: :portfolios}), do: String.starts_with?(path, "/portfolios")

  defp nav_current?(path, %{section: :transactions}),
    do: String.starts_with?(path, "/transactions")

  defp nav_current?(path, %{section: :imports}),
    do: String.starts_with?(path, "/imports")

  defp nav_current?(path, %{section: :income}),
    do: String.starts_with?(path, "/income")

  defp nav_current?(path, %{section: :classifications}),
    do: String.starts_with?(path, "/classifications")

  defp nav_current?(_path, _item), do: false

  defp theme_modes do
    [
      %{value: "system", label: gettext("System"), icon: :monitor, icon_name: "monitor"},
      %{value: "light", label: gettext("Light"), icon: :sun, icon_name: "sun"},
      %{value: "dark", label: gettext("Dark"), icon: :moon, icon_name: "moon"}
    ]
  end

  defp accent_colors do
    [
      %{value: "violet", label: gettext("Violet")},
      %{value: "teal", label: gettext("Teal")},
      %{value: "coral", label: gettext("Coral")}
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

  defp icon_paths(:monitor),
    do: ~s(<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/>)

  defp icon_paths(:sun),
    do:
      ~s(<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/>)

  defp icon_paths(:moon),
    do: ~s(<path d="M20 14.3A7.4 7.4 0 0 1 9.7 4a7.4 7.4 0 1 0 10.3 10.3Z"/>)

  defp icon_paths(:plus), do: ~s(<path d="M12 5v14M5 12h14"/>)

  defp icon_paths(:upload),
    do: ~s(<path d="M12 3v12M7 8l5-5 5 5"/><path d="M5 19h14"/>)

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

  defp icon_paths(:ellipsis_vertical),
    do:
      ~s(<circle cx="12" cy="6" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="12" cy="18" r="1.4"/>)

  defp icon_paths(:copy),
    do: ~s(<rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/>)

  defp icon_paths(:edit), do: ~s(<path d="M4 20h4l10-10-4-4L4 16Z"/>)

  defp icon_paths(:archive),
    do: ~s(<rect x="3" y="4" width="18" height="4"/><path d="M5 8v12h14V8M10 12h4"/>)

  defp icon_paths(:external_link),
    do:
      ~s(<path d="M14 4h6v6M10 14 20 4M19 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1h5"/>)

  defp icon_paths(:maximize),
    do: ~s(<path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/>)

  defp icon_paths(:minimize),
    do: ~s(<path d="M9 4v5H4M15 4v5h5M9 20v-5H4M15 20v-5h5"/>)

  defp icon_paths(:image),
    do:
      ~s(<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m21 15-5-5L5 21"/>)

  defp icon_paths(_), do: ~s(<circle cx="12" cy="12" r="5"/>)
end
