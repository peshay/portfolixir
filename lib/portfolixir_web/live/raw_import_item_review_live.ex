defmodule PortfolixirWeb.RawImportItemReviewLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Imports
  alias PortfolixirWeb.AppShell

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :raw_item, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    raw_item =
      case Integer.parse(id) do
        {raw_item_id, ""} -> Imports.get_raw_import_item(raw_item_id)
        _ -> nil
      end

    {:noreply, assign(socket, :raw_item, raw_item)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current_path="/imports">
      <section class="app-shell-page-heading">
        <h1><%= gettext("Raw import item review") %></h1>
        <p><%= gettext("Read-only metadata inspection for staged import items.") %></p>
      </section>

      <%= if @raw_item do %>
        <section id="raw-import-item-review" class="app-shell-section-card">
          <div class="app-shell-table-wrapper">
            <table id="raw-import-item-review-metadata-table">
              <caption id="raw-import-item-review-metadata-table-caption" class="app-shell-visually-hidden">
                <%= gettext("Raw import item metadata with source, status, identifiers, content details, and created timestamp") %>
              </caption>
              <tbody>
                <tr><th scope="row"><%= gettext("Source") %></th><td><%= @raw_item.import_source.name %></td></tr>
                <tr><th scope="row"><%= gettext("Status") %></th><td><%= @raw_item.status %></td></tr>
                <tr><th scope="row"><%= gettext("External ID") %></th><td><%= @raw_item.external_id || "—" %></td></tr>
                <tr><th scope="row"><%= gettext("Content hash") %></th><td><%= @raw_item.content_hash || "—" %></td></tr>
                <tr><th scope="row"><%= gettext("Content type") %></th><td><%= @raw_item.content_type || "—" %></td></tr>
                <tr><th scope="row"><%= gettext("Original filename") %></th><td><%= @raw_item.original_filename || "—" %></td></tr>
                <tr><th scope="row"><%= gettext("Created at") %></th><td><%= format_datetime(@raw_item.inserted_at) %></td></tr>
              </tbody>
            </table>
          </div>

          <div id="raw-import-item-payload-preview" class="app-shell-section-card app-shell-stack-md">
            <h2 class="app-shell-section-title"><%= gettext("Sanitized payload preview") %></h2>
            <%= if safe_payload_preview(@raw_item.payload) do %>
              <pre><%= safe_payload_preview(@raw_item.payload) %></pre>
            <% else %>
              <p><%= gettext("No safe compact payload preview is available for this item.") %></p>
            <% end %>
          </div>
        </section>
      <% else %>
        <section
          id="raw-import-item-not-found"
          class="app-shell-empty-state"
          role="status"
          aria-labelledby="raw-import-item-not-found-title"
          aria-describedby="raw-import-item-not-found-description"
        >
          <h2 id="raw-import-item-not-found-title"><%= gettext("Raw import item not found") %></h2>
          <p id="raw-import-item-not-found-description">
            <%= gettext("The requested raw import item does not exist.") %>
          </p>
        </section>
      <% end %>
    </AppShell.shell>
    """
  end

  defp safe_payload_preview(payload) when is_map(payload) do
    entries = Enum.sort_by(payload, fn {key, _} -> to_string(key) end)

    field_count = length(entries)

    type_counts =
      entries
      |> Enum.map(fn {_key, value} -> payload_value_type(value) end)
      |> Enum.frequencies()

    summary_lines = [
      "field_count: #{field_count}",
      "string_fields: #{Map.get(type_counts, :string, 0)}",
      "number_fields: #{Map.get(type_counts, :number, 0)}",
      "boolean_fields: #{Map.get(type_counts, :boolean, 0)}",
      "null_fields: #{Map.get(type_counts, :null, 0)}",
      "list_fields: #{Map.get(type_counts, :list, 0)}",
      "map_fields: #{Map.get(type_counts, :map, 0)}",
      "other_fields: #{Map.get(type_counts, :other, 0)}"
    ]

    Enum.join(summary_lines, "\n")
  end

  defp safe_payload_preview(_), do: nil

  defp payload_value_type(value) when is_binary(value), do: :string
  defp payload_value_type(value) when is_number(value), do: :number
  defp payload_value_type(value) when is_boolean(value), do: :boolean
  defp payload_value_type(nil), do: :null
  defp payload_value_type(value) when is_list(value), do: :list
  defp payload_value_type(value) when is_map(value), do: :map
  defp payload_value_type(_value), do: :other

  defp format_datetime(nil), do: "—"

  defp format_datetime(datetime) when is_struct(datetime, DateTime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp format_datetime(datetime) when is_struct(datetime, NaiveDateTime) do
    datetime
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_iso8601()
  end
end
