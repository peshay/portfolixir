defmodule PortfolixirWeb.RawImportItemReviewLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Imports
  alias PortfolixirWeb.AppShell

  @unsafe_payload_key_patterns [
    ~r/raw/i,
    ~r/byte/i,
    ~r/base64/i,
    ~r/pdf/i,
    ~r/document/i,
    ~r/content/i,
    ~r/blob/i,
    ~r/body/i
  ]

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
              <tbody>
                <tr><th><%= gettext("Source") %></th><td><%= @raw_item.import_source.name %></td></tr>
                <tr><th><%= gettext("Status") %></th><td><%= @raw_item.status %></td></tr>
                <tr><th><%= gettext("External ID") %></th><td><%= @raw_item.external_id || "—" %></td></tr>
                <tr><th><%= gettext("Content hash") %></th><td><%= @raw_item.content_hash || "—" %></td></tr>
                <tr><th><%= gettext("Content type") %></th><td><%= @raw_item.content_type || "—" %></td></tr>
                <tr><th><%= gettext("Original filename") %></th><td><%= @raw_item.original_filename || "—" %></td></tr>
                <tr><th><%= gettext("Created at") %></th><td><%= format_datetime(@raw_item.inserted_at) %></td></tr>
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
        <section id="raw-import-item-not-found" class="app-shell-empty-state">
          <h2><%= gettext("Raw import item not found") %></h2>
          <p><%= gettext("The requested raw import item does not exist.") %></p>
        </section>
      <% end %>
    </AppShell.shell>
    """
  end

  defp safe_payload_preview(payload) when is_map(payload) do
    payload
    |> Enum.sort_by(fn {key, _} -> to_string(key) end)
    |> Enum.filter(fn {key, _value} -> safe_payload_key?(key) end)
    |> Enum.map(&format_payload_entry/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(8)
    |> case do
      [] -> nil
      entries -> Enum.join(entries, "\n")
    end
  end

  defp safe_payload_preview(_), do: nil

  defp safe_payload_key?(key) do
    key_string = to_string(key)

    Enum.all?(@unsafe_payload_key_patterns, fn pattern ->
      not String.match?(key_string, pattern)
    end)
  end

  defp format_payload_entry({key, value}) when is_binary(value) do
    if String.length(value) <= 80 do
      "#{key}: #{value}"
    else
      nil
    end
  end

  defp format_payload_entry({key, value}) when is_number(value) or is_boolean(value),
    do: "#{key}: #{value}"

  defp format_payload_entry({_key, _value}), do: nil

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
