defmodule PortfolixirWeb.ImportOverviewLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Imports
  alias PortfolixirWeb.AppShell

  @overview_limit 20

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:import_sources, Imports.list_import_sources_with_stats())
      |> assign(:recent_import_runs, Imports.list_recent_import_runs(@overview_limit))
      |> assign(:recent_raw_import_items, Imports.list_recent_raw_import_items(@overview_limit))

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current_path="/imports">
      <header class="app-shell-page-header">
        <div>
          <p class="app-shell-page-kicker"><%= gettext("Imports") %></p>
          <h1><%= gettext("Imports") %></h1>
          <p><%= gettext("Read-only overview of staged import sources, runs, and raw import items.") %></p>
          <p>
            <a id="imports-conflicts-queue-link" href="/imports/conflicts">
              <%= gettext("Open import conflict review queue") %>
            </a>
          </p>
        </div>
      </header>

      <section id="import-sources-section" class="app-shell-section-card">
        <div class="app-shell-section-header">
          <div>
            <h2 class="app-shell-section-title"><%= gettext("Import sources") %></h2>
            <p><%= gettext("Source configuration and latest run details.") %></p>
          </div>
        </div>

        <%= if Enum.empty?(@import_sources) do %>
          <div id="import-sources-empty-state" class="app-shell-empty-state">
            <h3><%= gettext("No import sources yet") %></h3>
            <p><%= gettext("Create or register import sources to see them here.") %></p>
          </div>
        <% else %>
          <div class="app-shell-table-wrapper">
            <table id="import-sources-table" aria-describedby="import-sources-table-caption">
              <caption id="import-sources-table-caption" class="app-shell-visually-hidden">
                <%= gettext("Import sources with status, run counts, and latest run timestamps") %>
              </caption>
              <thead>
                <tr>
                  <th scope="col"><%= gettext("Name") %></th>
                  <th scope="col"><%= gettext("Type") %></th>
                  <th scope="col"><%= gettext("Status") %></th>
                  <th scope="col"><%= gettext("Created") %></th>
                  <th scope="col"><%= gettext("Runs") %></th>
                  <th scope="col"><%= gettext("Raw items") %></th>
                  <th scope="col"><%= gettext("Latest run status") %></th>
                  <th scope="col"><%= gettext("Latest run started") %></th>
                  <th scope="col"><%= gettext("Latest run finished") %></th>
                </tr>
              </thead>
              <tbody>
                <%= for source <- @import_sources do %>
                  <tr id={"import-source-row-#{source.id}"}>
                    <td><%= source.name %></td>
                    <td><%= source.type %></td>
                    <td><%= source.status %></td>
                    <td><%= format_datetime(source.created_at) %></td>
                    <td><%= source.runs_count %></td>
                    <td><%= source.raw_import_items_count %></td>
                    <td><%= source.latest_import_run_status || gettext("—") %></td>
                    <td><%= format_datetime(source.latest_import_run_started_at) %></td>
                    <td><%= format_datetime(source.latest_import_run_finished_at) %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </section>

      <section id="recent-import-runs-section" class="app-shell-section-card">
        <div class="app-shell-section-header">
          <div>
            <h2 class="app-shell-section-title"><%= gettext("Recent import runs") %></h2>
            <p><%= gettext("Latest sync and import run attempts.") %></p>
          </div>
        </div>

        <%= if Enum.empty?(@recent_import_runs) do %>
          <div id="import-runs-empty-state" class="app-shell-empty-state">
            <h3><%= gettext("No import runs yet") %></h3>
            <p><%= gettext("Runs will appear here after source execution.") %></p>
          </div>
        <% else %>
          <div class="app-shell-table-wrapper">
            <table id="import-runs-table">
              <caption class="app-shell-visually-hidden">
                <%= gettext("Recent import runs with source, status, timestamps, and summary preview") %>
              </caption>
              <thead>
                <tr>
                  <th scope="col"><%= gettext("Source") %></th>
                  <th scope="col"><%= gettext("Status") %></th>
                  <th scope="col"><%= gettext("Started at") %></th>
                  <th scope="col"><%= gettext("Finished at") %></th>
                  <th scope="col"><%= gettext("Summary preview") %></th>
                </tr>
              </thead>
              <tbody>
                <%= for import_run <- @recent_import_runs do %>
                  <tr id={"import-run-row-#{import_run.id}"}>
                    <td><%= import_run.import_source.name %></td>
                    <td><%= import_run.status %></td>
                    <td><%= format_datetime(import_run.started_at) %></td>
                    <td><%= format_datetime(import_run.finished_at) %></td>
                    <td><%= summary_preview(import_run.summary) %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </section>

      <section id="recent-raw-import-items-section" class="app-shell-section-card">
        <div class="app-shell-section-header">
          <div>
            <h2 class="app-shell-section-title"><%= gettext("Recent raw import items") %></h2>
            <p><%= gettext("Latest raw payload staging entries without exposing full content.") %></p>
          </div>
        </div>

        <%= if Enum.empty?(@recent_raw_import_items) do %>
          <div id="import-raw-items-empty-state" class="app-shell-empty-state">
            <h3><%= gettext("No raw import items yet") %></h3>
            <p><%= gettext("Raw items will appear here after intake.") %></p>
          </div>
        <% else %>
          <div class="app-shell-table-wrapper">
            <table id="import-raw-items-table">
              <caption class="app-shell-visually-hidden">
                <%= gettext("Recent raw import items with source, metadata, status, and review links") %>
              </caption>
              <thead>
                <tr>
                  <th scope="col"><%= gettext("Source") %></th>
                  <th scope="col"><%= gettext("Original filename") %></th>
                  <th scope="col"><%= gettext("Content type") %></th>
                  <th scope="col"><%= gettext("Status") %></th>
                  <th scope="col"><%= gettext("External ID") %></th>
                  <th scope="col"><%= gettext("Content hash") %></th>
                  <th scope="col"><%= gettext("Created at") %></th>
                  <th scope="col"><%= gettext("Review") %></th>
                </tr>
              </thead>
              <tbody>
                <%= for item <- @recent_raw_import_items do %>
                  <tr id={"import-raw-item-row-#{item.id}"}>
                    <td><%= item.import_source.name %></td>
                    <td><%= item.original_filename || gettext("—") %></td>
                    <td><%= item.content_type || gettext("—") %></td>
                    <td><%= item.status %></td>
                    <td><%= item.external_id || gettext("—") %></td>
                    <td><%= item.content_hash || gettext("—") %></td>
                    <td><%= format_datetime(item.inserted_at) %></td>
                    <td>
                      <a id={"import-raw-item-review-link-#{item.id}"} href={"/imports/raw-items/#{item.id}/review"}>
                        <%= gettext("Review") %>
                      </a>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </section>
    </AppShell.shell>
    """
  end

  defp format_datetime(nil), do: gettext("—")

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

  defp summary_preview(nil), do: gettext("—")

  defp summary_preview(summary) when is_map(summary) do
    summary
    |> Enum.sort_by(fn {key, _} -> to_string(key) end)
    |> Enum.map(&format_summary_entry/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(5)
    |> Enum.join(", ")
    |> case do
      "" -> gettext("—")
      preview -> preview
    end
  end

  defp summary_preview(_), do: gettext("—")

  defp format_summary_entry({_key, nil}), do: nil

  defp format_summary_entry({key, value}) when is_map(value),
    do: "#{key}=map(#{map_size(value)})"

  defp format_summary_entry({key, value}) when is_list(value),
    do: "#{key}=list(#{length(value)})"

  defp format_summary_entry({key, value}) when is_binary(value),
    do: "#{key}=#{value}"

  defp format_summary_entry({key, value}), do: "#{key}=#{inspect(value)}"
end
