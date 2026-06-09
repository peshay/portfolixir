defmodule PortfolixirWeb.Securities.FilterPopover do
  @moduledoc "Popover for building column filters on the securities list."
  use Phoenix.LiveComponent
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Catalog.AssetClasses
  alias Portfolixir.Catalog.Currencies
  alias Portfolixir.Catalog.SecurityFields
  alias Portfolixir.Catalog.SecurityFields.Field

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:field_key, default_field_key())
     |> assign(:operator, nil)
     |> assign(:value, "")}
  end

  @impl true
  def update(assigns, socket) do
    field_key = assigns[:field_key] || socket.assigns.field_key
    field = SecurityFields.get(field_key)
    operator = socket.assigns.operator || default_operator(field)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:field_key, field_key)
     |> assign(:field, field)
     |> assign(:operator, operator)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="popover" role="dialog" aria-label={gettext("Add filter")}>
      <div class="popover-head">
        <h3><%= gettext("Filter") %></h3>
      </div>
      <form phx-change="filter_change" phx-submit="apply_filter" phx-target={@myself}>
        <label>
          <span><%= gettext("Column") %></span>
          <select name="field">
            <%= for f <- SecurityFields.filterable() do %>
              <option value={Atom.to_string(f.key)} selected={f.key == @field_key}>
                <%= f.label %>
              </option>
            <% end %>
          </select>
        </label>

        <%= if @field do %>
          <label>
            <span><%= gettext("Operator") %></span>
            <select name="operator">
              <%= for op <- @field.operators do %>
                <option value={Atom.to_string(op)} selected={op == @operator}>
                  <%= operator_label(op) %>
                </option>
              <% end %>
            </select>
          </label>

          <%= if @operator not in [:is_true, :is_false] do %>
            <label>
              <span><%= gettext("Value") %></span>
              <%= if @field.type == :enum do %>
                <select name="value">
                  <option value=""></option>
                  <%= for {opt_label, opt_value} <- enum_options(@field) do %>
                    <option value={opt_value} selected={@value == opt_value}><%= opt_label %></option>
                  <% end %>
                </select>
              <% else %>
                <input type={input_type(@field.type)} name="value" value={@value} />
              <% end %>
            </label>
          <% end %>
        <% end %>

        <div class="popover-actions">
          <button type="submit" class="button-primary"><%= gettext("Apply filter") %></button>
        </div>
      </form>
    </div>
    """
  end

  @impl true
  def handle_event("filter_change", params, socket) do
    field_key = atom_or_default(params["field"], socket.assigns.field_key)
    field = SecurityFields.get(field_key)
    operator = atom_or_default(params["operator"], default_operator(field))

    {:noreply,
     socket
     |> assign(:field_key, field_key)
     |> assign(:field, field)
     |> assign(:operator, operator)
     |> assign(:value, params["value"] || "")}
  end

  def handle_event("apply_filter", params, socket) do
    field_key = atom_or_default(params["field"], socket.assigns.field_key)
    operator = atom_or_default(params["operator"], socket.assigns.operator)
    value = params["value"] || socket.assigns.value

    case build_filter(field_key, operator, value) do
      {:ok, filter} ->
        send(self(), {:filter_added, filter})

        {:noreply,
         socket
         |> assign(:value, "")}

      :error ->
        {:noreply, socket}
    end
  end

  defp build_filter(nil, _op, _value), do: :error
  defp build_filter(_key, nil, _value), do: :error

  defp build_filter(key, op, _value) when op in [:is_true, :is_false] do
    if SecurityFields.valid_filter?(key, op, true) do
      {:ok, %{key: key, op: op, value: op == :is_true}}
    else
      :error
    end
  end

  defp build_filter(key, op, value) when is_binary(value) and value != "" do
    if SecurityFields.valid_filter?(key, op, value) do
      {:ok, %{key: key, op: op, value: String.trim(value)}}
    else
      :error
    end
  end

  defp build_filter(_, _, _), do: :error

  defp atom_or_default(nil, default), do: default
  defp atom_or_default("", default), do: default

  defp atom_or_default(value, default) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> default
  end

  defp atom_or_default(value, _default) when is_atom(value), do: value

  defp default_field_key do
    case SecurityFields.filterable() do
      [%Field{key: key} | _] -> key
      _ -> nil
    end
  end

  defp default_operator(nil), do: nil
  defp default_operator(%Field{operators: [op | _]}), do: op
  defp default_operator(_), do: nil

  defp input_type(:integer), do: "number"
  defp input_type(:decimal), do: "number"
  defp input_type(:date), do: "date"
  defp input_type(_), do: "text"

  defp enum_options(%Field{key: :asset_class}), do: AssetClasses.options()
  defp enum_options(%Field{key: :currency_code}), do: Currencies.options()

  defp enum_options(%Field{enum_values: values}) when is_list(values) do
    Enum.map(values, fn v -> {to_string(v), v} end)
  end

  defp enum_options(_), do: []

  defp operator_label(:eq), do: gettext("equals")
  defp operator_label(:neq), do: gettext("not equal")
  defp operator_label(:contains), do: gettext("contains")
  defp operator_label(:starts_with), do: gettext("starts with")
  defp operator_label(:gt), do: gettext("greater than")
  defp operator_label(:lt), do: gettext("less than")
  defp operator_label(:is_true), do: gettext("is true")
  defp operator_label(:is_false), do: gettext("is false")
  defp operator_label(other), do: to_string(other)
end
