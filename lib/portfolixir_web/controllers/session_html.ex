defmodule PortfolixirWeb.SessionHTML do
  @moduledoc "The login page (ADR-0045 §1, #764): one field, no username, no recovery."
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  def confirm_logout(assigns) do
    ~H"""
    <main class="login-page" aria-labelledby="logout-title">
      <section class="login-card">
        <p class="login-brand" aria-hidden="true">Portfolixir</p>
        <h1 id="logout-title"><%= gettext("Log out") %></h1>
        <form action="/logout" method="post" class="login-form">
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <button type="submit" class="button-primary"><%= gettext("Log out") %></button>
        </form>
        <a class="button-ghost" href="/"><%= gettext("Back") %></a>
        <.locale_switcher path="/logout" query={%{}} />
      </section>
    </main>
    """
  end

  attr(:enabled, :boolean, required: true)
  attr(:return_to, :string, required: true)
  attr(:error, :string, default: nil)
  attr(:lockout, :string, default: nil)

  def new(assigns) do
    ~H"""
    <main class="login-page" aria-labelledby="login-title">
      <section class="login-card">
        <p class="login-brand" aria-hidden="true">Portfolixir</p>
        <h1 id="login-title"><%= gettext("Log in") %></h1>

        <%= if @enabled do %>
          <p :if={@lockout} id="login-lockout" class="field-error" role="alert"><%= @lockout %></p>
          <form
            action={"/login?" <> URI.encode_query(%{"to" => @return_to})}
            method="post"
            class="login-form"
          >
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <label for="session_password"><%= gettext("Password") %></label>
            <input
              type="password"
              id="session_password"
              name="session[password]"
              autocomplete="current-password"
              autofocus
              required
              aria-invalid={if @error, do: "true", else: nil}
              aria-describedby={if @error, do: "login-error", else: nil}
            />
            <p :if={@error} id="login-error" class="field-error" role="alert"><%= @error %></p>
            <button type="submit" class="button-primary"><%= gettext("Log in") %></button>
          </form>
        <% else %>
          <p class="login-open">
            <%= gettext(
              "No password is configured; the UI is open. Set PORTFOLIXIR_UI_PASSWORD to require one."
            ) %>
          </p>
          <a class="button-primary" href={@return_to}><%= gettext("Continue") %></a>
        <% end %>
        <.locale_switcher path="/login" query={%{"to" => @return_to}} />
      </section>
    </main>
    """
  end

  # The locale is a top-bar primitive everywhere else; the session pages
  # render outside the shell, so they carry their own copy of the switcher.
  attr(:path, :string, required: true)
  attr(:query, :map, required: true)

  defp locale_switcher(assigns) do
    current = Gettext.get_locale(PortfolixirWeb.Gettext)
    assigns = assign(assigns, :current, current)

    ~H"""
    <nav class="locale-switcher login-locale" aria-label={gettext("Language")}>
      <%= for {code, label} <- [{"en", "EN"}, {"de", "DE"}] do %>
        <a
          class={["locale-link", @current == code && "is-active"]}
          href={@path <> "?" <> URI.encode_query(Map.put(@query, "locale", code))}
          hreflang={code}
          aria-current={if @current == code, do: "true", else: nil}
        >
          <%= label %>
        </a>
      <% end %>
    </nav>
    """
  end
end
