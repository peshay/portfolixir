defmodule PortfolixirWeb.WorkbenchToolbar do
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:description, :string, required: true)
  attr(:search_id, :string, required: true)
  attr(:search_name, :string, default: "q")
  attr(:search_value, :string, default: "")
  attr(:search_placeholder, :string, default: nil)
  attr(:search_label, :string, default: nil)
  attr(:time_ranges, :list, default: [])
  attr(:active_time_range, :string, default: nil)

  def toolbar(assigns) do
    assigns = assign_new(assigns, :search_label, fn -> gettext("Search") end)

    ~H"""
    <div id={@id} class="app-shell-section-header">
      <div>
        <h2 class="app-shell-section-title"><%= @title %></h2>
        <p><%= @description %></p>
      </div>

      <form class="app-shell-search" role="search" aria-label={@search_label}>
        <label for={@search_id}><%= @search_label %></label>
        <input
          id={@search_id}
          type="search"
          name={@search_name}
          value={@search_value}
          placeholder={@search_placeholder}
        />
      </form>

      <div class="app-shell-form-actions">
        <button id={"#{@id}-filter"} type="button" class="app-shell-secondary" disabled>
          <%= gettext("Filter") %>
        </button>
        <button id={"#{@id}-export"} type="button" class="app-shell-secondary" disabled>
          <%= gettext("Export") %>
        </button>
        <button id={"#{@id}-columns"} type="button" class="app-shell-secondary" disabled>
          <%= gettext("Columns") %>
        </button>
      </div>

      <%= if @time_ranges != [] do %>
        <div class="app-shell-form-actions" role="group" aria-label={gettext("Time range")}> 
          <%= for range <- @time_ranges do %>
            <button
              id={"#{@id}-range-#{String.downcase(range)}"}
              type="button"
              class="app-shell-secondary"
              disabled={@active_time_range == range}
              aria-pressed={to_string(@active_time_range == range)}
            >
              <%= range %>
            </button>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
