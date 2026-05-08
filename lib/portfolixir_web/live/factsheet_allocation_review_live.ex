defmodule PortfolixirWeb.FactsheetAllocationReviewLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog.FactsheetAllocationImport
  alias Portfolixir.Catalog.FactsheetAllocationPreview
  alias Portfolixir.Catalog.FundDocument
  alias Portfolixir.Repo
  alias PortfolixirWeb.AppShell

  @empty_state_id "factsheet-review-empty-state"
  @empty_state_title_id "#{@empty_state_id}-title"
  @empty_state_description_id "#{@empty_state_id}-description"

  def mount(%{"id" => id_param}, _session, socket) do
    socket =
      socket
      |> assign(:fund_document, nil)
      |> assign(:fund_document_id, nil)
      |> assign(:preview, nil)
      |> assign(:confirmation_summary, nil)
      |> assign(:confirmation_error, nil)
      |> assign(:fund_document_not_found, false)

    case load_review_data(id_param) do
      {:ok, fund_document, preview} ->
        {:ok,
         socket
         |> assign(:fund_document, fund_document)
         |> assign(:fund_document_id, fund_document.id)
         |> assign(:preview, preview)
         |> assign(:fund_document_not_found, false)}

      {:error, :not_found} ->
        {:ok, assign(socket, :fund_document_not_found, true)}

      {:error, _} ->
        {:ok, assign(socket, :fund_document_not_found, true)}
    end
  end

  def render(assigns) do
    ~H"""
    <AppShell.shell current_path={review_current_path(@fund_document)}>
      <%= if @fund_document_not_found do %>
        <section
          id="factsheet-review-not-found"
          class="app-shell-empty-state"
          role="status"
          aria-labelledby="factsheet-review-not-found-title"
          aria-describedby="factsheet-review-not-found-description"
        >
          <h1 id="factsheet-review-not-found-title"><%= gettext("Fund document not found") %></h1>
          <p id="factsheet-review-not-found-description">
            <%= gettext("This factsheet document is not available.") %>
          </p>
        </section>
      <% else %>
        <header class="app-shell-page-header">
          <div>
            <p class="app-shell-page-kicker"><%= gettext("Imports") %></p>
            <h1><%= gettext("Factsheet allocation review") %></h1>
            <p>
              <%= gettext("Review parsed allocations and confirm only what should be persisted.") %>
            </p>
          </div>
        </header>

        <section id="factsheet-review-metadata" class="app-shell-section-card">
          <div class="app-shell-section-header">
            <div>
              <h2 class="app-shell-section-title"><%= gettext("Factsheet metadata") %></h2>
            </div>
          </div>

          <p id="factsheet-review-security">
            <strong><%= gettext("Security") %>:</strong>
            <%= @fund_document.security.name %> (<%= @fund_document.security.symbol %>)
          </p>
          <p id="factsheet-review-filename">
            <strong><%= gettext("Original filename") %>:</strong>
            <%= @fund_document.original_filename %>
          </p>
          <p id="factsheet-review-status">
            <strong><%= gettext("Extraction status") %>:</strong>
            <%= @fund_document.extraction_status %>
          </p>
        </section>

        <section id="factsheet-review-preview" class="app-shell-section-card">
          <div class="app-shell-section-header">
            <div>
              <h2 class="app-shell-section-title"><%= gettext("Parsed allocations") %></h2>
              <p class="app-shell-panel-intro">
                <%= gettext("Review every parsed allocation row before writing records.") %>
              </p>
            </div>
          </div>

          <%= if Enum.empty?(@preview["allocations"]) do %>
            <div
              id={empty_state_id()}
              class="app-shell-empty-state"
              role="status"
              aria-live="polite"
              aria-labelledby={empty_state_title_id()}
              aria-describedby={empty_state_description_id()}
            >
              <h3 id={empty_state_title_id()}><%= gettext("No allocations were parsed") %></h3>
              <p id={empty_state_description_id()}>
                <%= gettext("No allocation rows were available for review from this factsheet.") %>
              </p>
            </div>
          <% else %>
            <div class="app-shell-table-wrapper">
              <table
                id="factsheet-allocation-groups"
                aria-describedby="factsheet-allocation-groups-caption"
              >
                <caption id="factsheet-allocation-groups-caption" class="app-shell-visually-hidden">
                  <%= gettext("Parsed allocation preview with allocation type, item label, weight, confidence, and raw line before confirmation.") %>
                </caption>
                <thead>
                  <tr>
                    <th scope="col"><%= gettext("Allocation type") %></th>
                    <th scope="col"><%= gettext("Item label") %></th>
                    <th scope="col"><%= gettext("Weight") %></th>
                    <th scope="col"><%= gettext("Confidence") %></th>
                    <th scope="col"><%= gettext("Raw line") %></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for allocation <- @preview["allocations"] do %>
                    <%= for item <- allocation["items"] do %>
                      <tr id={allocation_row_id(allocation["allocation_type"], item["label"])}>
                        <td><%= allocation["allocation_type"] %></td>
                        <td><%= item["label"] %></td>
                        <td><%= format_percent(item["weight"], true) %></td>
                        <td><%= format_percent(item["confidence"], false) %></td>
                        <td><%= item["raw_line"] %></td>
                      </tr>
                    <% end %>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </section>

        <%= if !Enum.empty?(@preview["warnings"]) do %>
          <section id="factsheet-review-warnings" class="app-shell-section-card">
            <div class="app-shell-section-header">
              <div>
                <h2 class="app-shell-section-title"><%= gettext("Preview warnings") %></h2>
              </div>
            </div>

            <ul id="factsheet-review-warnings-list">
              <%= for warning <- @preview["warnings"] do %>
                <li><%= warning %></li>
              <% end %>
            </ul>
          </section>
        <% end %>

        <section class="app-shell-section-card">
          <%= if @confirmation_error do %>
            <p id="factsheet-review-confirm-error" class="app-shell-alert app-shell-alert--error" role="alert">
              <%= @confirmation_error %>
            </p>
          <% end %>

          <%= if @confirmation_summary do %>
            <section id="factsheet-review-confirmation-summary" class="app-shell-section-card">
              <div class="app-shell-section-header">
                <div>
                  <h2 class="app-shell-section-title"><%= gettext("Confirmation summary") %></h2>
                </div>
              </div>

              <ul>
                <li id="factsheet-summary-created-allocations">
                  <%= gettext("Created allocations") %>:
                  <%= @confirmation_summary["created"]["allocations"] %>
                </li>
                <li id="factsheet-summary-created-items">
                  <%= gettext("Created items") %>:
                  <%= @confirmation_summary["created"]["fund_allocation_items"] %>
                </li>
                <li id="factsheet-summary-skipped-allocations">
                  <%= gettext("Skipped allocations") %>:
                  <%= @confirmation_summary["skipped"]["allocations"] %>
                </li>
                <li id="factsheet-summary-skipped-items">
                  <%= gettext("Skipped items") %>:
                  <%= @confirmation_summary["skipped"]["fund_allocation_items"] %>
                </li>
                <li id="factsheet-summary-failed-allocations">
                  <%= gettext("Failed allocations") %>:
                  <%= @confirmation_summary["failed"]["allocations"] %>
                </li>
                <li id="factsheet-summary-failed-items">
                  <%= gettext("Failed items") %>:
                  <%= @confirmation_summary["failed"]["fund_allocation_items"] %>
                </li>
              </ul>

              <%= if Enum.any?(@confirmation_summary["warnings"]) do %>
                <ul id="factsheet-review-summary-warnings">
                  <%= for warning <- @confirmation_summary["warnings"] do %>
                    <li><%= warning %></li>
                  <% end %>
                </ul>
              <% end %>
            </section>
          <% end %>

          <p id="factsheet-review-confirm-feedback-context" class="app-shell-visually-hidden">
            <%= gettext("Submit this form to confirm parsed allocations.") %>
          </p>

          <form
            id="factsheet-review-confirm-form"
            phx-submit="confirm_allocations"
            aria-describedby={confirm_form_description_ids(@confirmation_error)}
          >
            <div class="app-shell-form-actions">
              <button
                id="factsheet-review-confirm-button"
                type="submit"
                class="app-shell-primary"
                disabled={Enum.empty?(@preview["allocations"])}
              >
                <%= gettext("Confirm allocations") %>
              </button>
            </div>
          </form>
        </section>
      <% end %>
    </AppShell.shell>
    """
  end

  def handle_event("confirm_allocations", _params, socket) do
    with %{} = fund_document <- socket.assigns.fund_document,
         {:ok, confirmation_summary} <-
           FactsheetAllocationImport.confirm_fund_document(fund_document.id) do
      {:noreply,
       socket
       |> assign(:confirmation_summary, confirmation_summary)
       |> assign(:confirmation_error, nil)}
    else
      {:error, {:missing_security_id, _} = error} ->
        {:noreply, assign(socket, :confirmation_error, format_confirm_error(error))}

      {:error, {:not_found, _} = error} ->
        {:noreply, assign(socket, :confirmation_error, format_confirm_error(error))}

      {:error, error} ->
        {:noreply, assign(socket, :confirmation_error, format_confirm_error(error))}
    end
  end

  defp load_review_data(id_param) do
    with {:ok, fund_document_id} <- parse_id_param(id_param),
         %FundDocument{} = fund_document <- get_fund_document(fund_document_id),
         {:ok, preview} <- FactsheetAllocationPreview.preview_fund_document(fund_document_id) do
      {:ok, fund_document, preview}
    else
      _ -> {:error, :not_found}
    end
  end

  defp parse_id_param(id_param) do
    case Integer.parse(id_param) do
      {fund_document_id, ""} -> {:ok, fund_document_id}
      _ -> {:error, :not_found}
    end
  end

  defp get_fund_document(fund_document_id) do
    Repo.get(FundDocument, fund_document_id)
    |> Repo.preload(:security)
  end

  defp review_current_path(nil), do: "/fund-documents/review"

  defp review_current_path(fund_document),
    do: "/fund-documents/#{fund_document.id}/allocations/review"

  defp format_percent(nil, _show_suffix? = true), do: gettext("—")

  defp format_percent(decimal, true) when is_struct(decimal, Decimal),
    do: "#{Decimal.to_string(decimal, :normal)}%"

  defp format_percent(decimal, true),
    do: "#{format_percent(decimal, false)}%"

  defp format_percent(decimal, false) when is_struct(decimal, Decimal),
    do: Decimal.to_string(decimal, :normal)

  defp format_percent(value, false),
    do: to_string(value)

  defp allocation_row_id(allocation_type, label) do
    escaped_label =
      label
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    "factsheet-allocation-item-#{allocation_type}-#{escaped_label}"
  end

  defp confirm_form_description_ids(confirmation_error) do
    [
      "factsheet-review-confirm-feedback-context",
      if(confirmation_error, do: "factsheet-review-confirm-error")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp format_confirm_error({reason, message}) when is_binary(message),
    do: "#{Atom.to_string(reason)}: #{message}"

  defp format_confirm_error(reason), do: inspect(reason)

  defp empty_state_id, do: @empty_state_id
  defp empty_state_title_id, do: @empty_state_title_id
  defp empty_state_description_id, do: @empty_state_description_id
end
