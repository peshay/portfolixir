defmodule PortfolixirWeb.DocumentUploadLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.FactsheetDocuments
  alias PortfolixirWeb.AppShell

  @max_factsheet_size_bytes 4 * 1024 * 1024
  @fallback_filename "factsheet.pdf"
  @fallback_content_type "application/pdf"

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:securities, Catalog.list_securities())
      |> assign(:document_review_path, nil)
      |> assign(:document_upload_success, nil)
      |> assign(:document_upload_error, nil)
      |> assign(:selected_security_id, "")
      |> allow_upload(:factsheet_file,
        accept: ["application/pdf", ".pdf"],
        max_entries: 1,
        max_file_size: @max_factsheet_size_bytes
      )

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current_path="/documents/new">
      <header class="app-shell-page-header">
        <div>
          <h1><%= gettext("Factsheet document") %></h1>
          <p><%= gettext("Attach PDF factsheet files directly to a security.") %></p>
        </div>
      </header>

      <section class="app-shell-workspace-stack">
        <section class="app-shell-section-card">
          <div class="app-shell-section-header">
            <div>
              <h2 class="app-shell-section-title"><%= gettext("Add factsheet document") %></h2>
              <p class="app-shell-panel-intro">
                <%= gettext("Pick a security, upload a PDF, and register it in the factsheet library.") %>
              </p>
            </div>
          </div>

          <%= if @document_upload_error do %>
            <p id="document-upload-error" class="app-shell-alert app-shell-alert--error" role="alert">
              <%= @document_upload_error %>
            </p>
          <% end %>

          <%= if @document_upload_success do %>
            <p
              id="document-upload-success"
              class="app-shell-alert app-shell-alert--success"
              role="status"
              aria-live="polite"
            >
              <%= @document_upload_success %>
            </p>

            <%= if @document_review_path do %>
              <p class="app-shell-panel-intro">
                <a id="factsheet-review-link" href={@document_review_path}>
                  <%= gettext("Review parsed allocations") %>
                </a>
              </p>
            <% end %>
          <% end %>

          <%= for err <- upload_errors(@uploads.factsheet_file) do %>
            <p
              id="document-upload-upload-error"
              class="app-shell-alert app-shell-alert--error"
              role="alert"
            >
              <%= upload_error_to_string(err) %>
            </p>
          <% end %>

          <%= for entry <- @uploads.factsheet_file.entries do %>
            <%= for err <- upload_errors(@uploads.factsheet_file, entry) do %>
              <p
                id="document-upload-upload-error"
                class="app-shell-alert app-shell-alert--error"
                role="alert"
              >
                <%= upload_error_to_string(err) %>
              </p>
            <% end %>
          <% end %>

          <%= if Enum.empty?(@securities) do %>
            <div
              id="document-upload-empty-state"
              class="app-shell-empty-state"
              role="status"
              aria-live="polite"
              aria-labelledby="document-upload-empty-state-title"
              aria-describedby="document-upload-empty-state-description"
            >
              <h3 id="document-upload-empty-state-title"><%= gettext("No securities yet") %></h3>
              <p id="document-upload-empty-state-description">
                <%= gettext("Create a security first to attach factsheets.") %>
              </p>
              <p><a href="/securities"><%= gettext("Create your first security") %></a></p>
            </div>
          <% else %>
            <form id="document-upload-form" class="app-shell-form-grid" phx-submit="register_factsheet">
              <div class="app-shell-field">
                <label for="document-security-id"><%= gettext("Security") %></label>
                <select id="document-security-id" name="security_id">
                  <%= for security <- @securities do %>
                    <option
                      value={security.id}
                      selected={to_string(security.id) == @selected_security_id}
                    >
                      <%= security.name %> (<%= security.symbol %>)
                    </option>
                  <% end %>
                </select>
              </div>

              <div class="app-shell-field">
                <label for="factsheet-file"><%= gettext("PDF document") %></label>
                <.live_file_input upload={@uploads.factsheet_file} id="factsheet-file" />
                <small>
                  <%= gettext("Max size") %> <%= @uploads.factsheet_file.max_file_size |> format_bytes() %>
                </small>
              </div>

              <div class="app-shell-form-actions">
                <button id="document-upload-submit" class="app-shell-primary" type="submit">
                  <%= gettext("Upload factsheet") %>
                </button>
              </div>
            </form>
          <% end %>
        </section>
      </section>
    </AppShell.shell>
    """
  end

  @impl true
  def handle_event("register_factsheet", %{"security_id" => security_id}, socket) do
    socket =
      socket
      |> assign(:document_upload_success, nil)
      |> assign(:document_upload_error, nil)
      |> assign(:document_review_path, nil)
      |> assign(:selected_security_id, security_id)

    with {:ok, security_id} <- parse_security_id(security_id),
         {:ok, status, fund_document} <- register_uploaded_factsheet(socket, security_id) do
      message =
        case status do
          :created ->
            gettext("Factsheet registered.")

          :already_exists ->
            gettext("This factsheet has already been uploaded for the selected security.")
        end

      {:noreply,
       socket
       |> assign(:document_upload_success, message)
       |> assign(:document_review_path, review_path(fund_document.id))}
    else
      {:error, :missing_security} ->
        {:noreply, assign(socket, :document_upload_error, gettext("Please select a security."))}

      {:error, :invalid_security_id} ->
        {:noreply,
         assign(socket, :document_upload_error, gettext("Please select a valid security."))}

      {:error, :no_file} ->
        {:noreply,
         assign(
           socket,
           :document_upload_error,
           gettext("Please choose a PDF file before submitting.")
         )}

      {:error, :unsupported_content_type} ->
        {:noreply,
         assign(
           socket,
           :document_upload_error,
           gettext("Unsupported file type. Please upload a PDF.")
         )}

      {:error, :file_too_large} ->
        {:noreply,
         assign(
           socket,
           :document_upload_error,
           gettext("The selected file is too large.")
         )}

      {:error, reason} ->
        {:noreply,
         assign(
           socket,
           :document_upload_error,
           upload_error_reason_to_string(reason)
         )}
    end
  end

  defp register_uploaded_factsheet(socket, security_id) do
    result =
      consume_uploaded_entries(
        socket,
        :factsheet_file,
        &factsheet_upload_callback(&1, &2, security_id)
      )

    case result do
      [] ->
        {:error, upload_error_from_entries(socket)}

      [{status, fund_document}] when status in [:created, :already_exists] ->
        {:ok, status, fund_document}

      [{:error, reason}] ->
        {:error, reason}

      _ ->
        {:error, :invalid_upload_state}
    end
  end

  defp factsheet_upload_callback(%{path: path}, entry, security_id) do
    filename = entry.client_name || @fallback_filename
    content_type = entry.client_type || @fallback_content_type

    with {:ok, binary_content} <- File.read(path),
         {:ok, status, fund_document} <-
           FactsheetDocuments.register_factsheet(
             security_id,
             filename,
             content_type,
             binary_content
           ) do
      {:ok, {status, fund_document}}
    else
      {:error, reason} -> {:ok, {:error, reason}}
    end
  end

  defp parse_security_id(security_id) when security_id in ["", nil],
    do: {:error, :missing_security}

  defp parse_security_id(security_id) when is_binary(security_id) do
    with {id_int, ""} <- security_id |> String.trim() |> Integer.parse() do
      {:ok, id_int}
    else
      _ -> {:error, :invalid_security_id}
    end
  end

  defp parse_security_id(_), do: {:error, :invalid_security_id}

  defp upload_error_from_entries(socket) do
    entries = socket.assigns.uploads.factsheet_file.entries
    global_errors = upload_errors(socket.assigns.uploads.factsheet_file)

    per_entry_errors =
      Enum.flat_map(entries, &upload_errors(socket.assigns.uploads.factsheet_file, &1))

    cond do
      :not_accepted in global_errors || :not_accepted in per_entry_errors ->
        :unsupported_content_type

      :too_large in global_errors || :too_large in per_entry_errors ->
        :file_too_large

      Enum.empty?(entries) ->
        :no_file

      true ->
        :no_file
    end
  end

  defp upload_error_to_string(:not_accepted),
    do: gettext("Unsupported file type. Please upload a PDF.")

  defp upload_error_to_string(:too_large),
    do: gettext("The selected file is too large.")

  defp upload_error_to_string(:external_client_failure),
    do: gettext("Upload failed before it reached the server.")

  defp upload_error_to_string({:writer_failure, _reason}),
    do: gettext("Upload processing failed.")

  defp upload_error_to_string(_), do: gettext("The selected file is not accepted.")

  defp upload_error_reason_to_string(:security_not_found),
    do: gettext("Selected security is no longer available.")

  defp upload_error_reason_to_string(:unsupported_content_type),
    do: gettext("Unsupported file type. Please upload a PDF.")

  defp upload_error_reason_to_string(:invalid_arguments),
    do: gettext("Invalid file upload arguments.")

  defp upload_error_reason_to_string(:file_too_large),
    do: gettext("The selected file is too large.")

  defp upload_error_reason_to_string(:invalid_upload_state),
    do: gettext("Unexpected upload state. Please try again.")

  defp upload_error_reason_to_string(_),
    do: gettext("Could not register the factsheet. Please retry.")

  defp review_path(fund_document_id) when is_integer(fund_document_id),
    do: "/fund-documents/#{fund_document_id}/allocations/review"

  defp format_bytes(bytes) when is_integer(bytes) do
    megabytes = bytes / 1_048_576
    "#{Float.round(megabytes, 1)} MB"
  end
end
