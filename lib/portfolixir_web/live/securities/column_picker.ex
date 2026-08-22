defmodule PortfolixirWeb.Securities.ColumnPicker do
  @moduledoc "Popover for choosing which columns the securities list shows."
  use Phoenix.LiveComponent
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Catalog.SecurityFields
  alias PortfolixirWeb.ClassificationName

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :grouped, group_fields())

    ~H"""
    <div id={@id} class="popover column-picker" role="dialog" aria-label={gettext("Choose columns")}>
      <div class="popover-head">
        <h3><%= gettext("Columns") %></h3>
      </div>
      <form id="securities-column-form" phx-change="toggle_columns" phx-target={@myself}>
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
        <%!-- Classification columns (#565): one entry per tree and level,
            custom and built-in alike. Values are serialized keys the parent
            LiveView validates; no atoms are minted from them. --%>
        <%= if @classification_columns != [] do %>
          <fieldset class="column-group">
            <legend><%= gettext("Classifications") %></legend>
            <%= for spec <- @classification_columns, level <- 1..spec.levels do %>
              <label class="checkbox-row">
                <input
                  type="checkbox"
                  name="columns[]"
                  value={"classification:#{spec.classification.id}:#{level}"}
                  checked={{:classification, spec.classification.id, level} in @visible}
                />
                <span><%= classification_label(spec, level) %></span>
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

  # Raw key strings go up to the parent LiveView, which owns the validation
  # against the field registry and the current classification trees (#565).
  @impl true
  def handle_event("toggle_columns", params, socket) do
    keys =
      params
      |> Map.get("columns", [])
      |> List.wrap()
      |> Enum.filter(&is_binary/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    send(self(), {:columns_changed, keys})
    {:noreply, socket}
  end

  defp classification_label(%{classification: classification, levels: 1}, _level),
    do: ClassificationName.display(classification)

  defp classification_label(%{classification: classification}, level) do
    gettext("%{name} (level %{level})",
      name: ClassificationName.display(classification),
      level: level
    )
  end

  defp group_fields do
    SecurityFields.all()
    |> Enum.group_by(& &1.group)
    |> Enum.sort_by(fn {group, _} -> group_order(group) end)
  end

  defp group_order(:stammdaten), do: 0
  defp group_order(:kurse), do: 1
  defp group_order(:online_quelle), do: 2
  defp group_order(:sonstiges), do: 3
  defp group_order(_), do: 99

  defp group_label(:stammdaten), do: gettext("Core data")
  defp group_label(:kurse), do: gettext("Prices")
  defp group_label(:online_quelle), do: gettext("Online source")
  defp group_label(:sonstiges), do: gettext("Other")
  defp group_label(other), do: to_string(other)
end
