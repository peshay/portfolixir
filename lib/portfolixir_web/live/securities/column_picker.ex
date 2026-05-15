defmodule PortfolixirWeb.Securities.ColumnPicker do
  use Phoenix.LiveComponent
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Catalog.SecurityFields

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :grouped, group_fields())

    ~H"""
    <div id={@id} class="popover column-picker" role="dialog" aria-label={gettext("Choose columns")}>
      <div class="popover-head">
        <h3><%= gettext("Columns") %></h3>
      </div>
      <form phx-change="toggle_columns" phx-target={@myself}>
        <%= for {group, fields} <- @grouped do %>
          <fieldset class="column-group">
            <legend><%= group_label(group) %></legend>
            <%= for field <- fields do %>
              <label class="checkbox-row">
                <input
                  type="checkbox"
                  name="columns[]"
                  value={Atom.to_string(field.key)}
                  checked={field.key in @visible}
                />
                <span><%= field.label %></span>
              </label>
            <% end %>
          </fieldset>
        <% end %>
        <%!-- Hidden sentinel: ensures Phoenix always receives a (possibly empty)
            list for "columns[]" even when the user unchecks every box. --%>
        <input type="hidden" name="columns[]" value="" />
      </form>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_columns", params, socket) do
    raw = Map.get(params, "columns", [])

    keys =
      raw
      |> List.wrap()
      |> Enum.reject(&(&1 == "" or is_nil(&1)))
      |> Enum.map(&safe_atom/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    send(self(), {:columns_changed, keys})
    {:noreply, socket}
  end

  defp safe_atom(key) when is_binary(key) do
    field = Enum.find(SecurityFields.all(), &(Atom.to_string(&1.key) == key))
    field && field.key
  end

  defp safe_atom(_), do: nil

  defp group_fields do
    SecurityFields.all()
    |> Enum.group_by(& &1.group)
    |> Enum.sort_by(fn {group, _} -> group_order(group) end)
  end

  defp group_order(:stammdaten), do: 0
  defp group_order(:online_quelle), do: 1
  defp group_order(:sonstiges), do: 2
  defp group_order(_), do: 99

  defp group_label(:stammdaten), do: gettext("Core data")
  defp group_label(:online_quelle), do: gettext("Online source")
  defp group_label(:sonstiges), do: gettext("Other")
  defp group_label(other), do: to_string(other)
end
