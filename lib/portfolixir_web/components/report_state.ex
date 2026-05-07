defmodule PortfolixirWeb.ReportState do
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:description, :string, default: nil)
  attr(:title_tag, :string, default: "h2")
  attr(:inline, :boolean, default: false)
  attr(:action_text, :string, default: nil)
  attr(:action_href, :string, default: nil)
  attr(:action_id, :string, default: nil)

  def empty_state(assigns) do
    assigns =
      assigns
      |> assign_new(:title_id, fn -> "#{assigns.id}-title" end)
      |> assign_new(:description_id, fn -> "#{assigns.id}-description" end)

    ~H"""
    <section
      id={@id}
      class={[
        "app-shell-empty-state",
        @inline && "app-shell-empty-state--inline"
      ]}
      role="status"
      aria-live="polite"
      aria-labelledby={@title_id}
      aria-describedby={if(@description, do: @description_id, else: nil)}
    >
      <.dynamic_tag name={@title_tag} id={@title_id}><%= @title %></.dynamic_tag>
      <p :if={@description} id={@description_id}><%= @description %></p>

      <p :if={@action_text && @action_href}>
        <a id={@action_id || "#{@id}-action"} href={@action_href}><%= @action_text %></a>
      </p>
    </section>
    """
  end

  attr(:id, :string, required: true)
  attr(:warnings, :list, required: true)
  attr(:title, :string, default: nil)

  def warning_state(assigns) do
    assigns = assign_new(assigns, :title, fn -> gettext("Warnings") end)

    ~H"""
    <section id={@id} class="app-shell-alert app-shell-alert--warning" role="alert" aria-live="polite">
      <h3><%= @title %></h3>
      <ul>
        <%= for warning <- @warnings do %>
          <li><%= warning %></li>
        <% end %>
      </ul>
    </section>
    """
  end
end
