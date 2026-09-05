defmodule PortfolixirWeb.SessionHTML do
  @moduledoc "The login page (ADR-0045 §1, #764): one field, no username, no recovery."
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  attr(:enabled, :boolean, required: true)
  attr(:return_to, :string, required: true)
  attr(:error, :string, default: nil)

  def new(assigns) do
    ~H"""
    <main class="login-page" aria-labelledby="login-title">
      <section class="login-card">
        <p class="login-brand" aria-hidden="true">Portfolixir</p>
        <h1 id="login-title"><%= gettext("Sign in") %></h1>

        <%= if @enabled do %>
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
            <button type="submit" class="button-primary"><%= gettext("Sign in") %></button>
          </form>
        <% else %>
          <p class="login-open">
            <%= gettext(
              "No password is configured; the UI is open. Set PORTFOLIXIR_UI_PASSWORD to require one."
            ) %>
          </p>
          <a class="button-primary" href={@return_to}><%= gettext("Continue") %></a>
        <% end %>
      </section>
    </main>
    """
  end
end
