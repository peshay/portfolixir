defmodule PortfolixirWeb.Securities.LogoOverrideDialog do
  @moduledoc """
  Stateless dialog for managing a single security's logo: set a manual logo
  from an image file the operator's browser uploads, remove it (lock "no
  logo"), or trigger automatic re-discovery. Submits to the parent LiveView's
  events; the parent owns the `:logo` upload (`allow_upload/3` with
  `LogoStore.upload_accept/0` and `LogoStore.upload_max_bytes/0`).

  The server never fetches an address typed into this dialog (security
  review 2026-10-12, H38): the image travels over the LiveView socket and is
  stored by `LogoStore.store_manual_bytes/5`, which checks its type, size and
  image header.
  """

  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.LogoStore
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format

  attr(:security, :map, required: true)
  attr(:upload, :any, required: true, doc: "the parent's `:logo` upload config")
  attr(:upload_error, :atom, default: nil, doc: "the store's refusal of the chosen file")

  def dialog(assigns) do
    upload = assigns.upload
    errors = upload_errors(upload) ++ Enum.flat_map(upload.entries, &upload_errors(upload, &1))
    errors = if assigns.upload_error, do: errors ++ [assigns.upload_error], else: errors

    assigns =
      assigns
      |> assign(:status, Catalog.logo_status(assigns.security))
      |> assign(:upload_message, errors |> List.first() |> upload_error_text())
      |> assign(:savable?, errors == [] and Enum.any?(upload.entries, & &1.valid?))

    ~H"""
    <%!-- Native dialog (UX-DR9, issue 646): opened via showModal() by the
         ModalDialog hook; cancel (Esc) pushes the close event. --%>
    <dialog
      id="logo-override-dialog"
      class="modal logo-override"
      phx-hook="ModalDialog"
      data-close-event="close_logo_dialog"
      aria-labelledby="logo-override-title"
    >
        <header class="modal-head">
          <h2 id="logo-override-title"><%= gettext("Manage logo") %></h2>
          <button
            type="button"
            class="icon-button"
            aria-label={gettext("Close")}
            phx-click="close_logo_dialog"
          >
            <AppShell.icon name={:x} />
          </button>
        </header>

        <div class="modal-body">
          <p class="detail-pane-sub"><%= @security.name %></p>

          <p>
            <%!-- A logo whose file is gone (#933, board 07b) says so and names
                 the way back, whatever its lock: never "a manual logo is set",
                 nor "set to have no logo". --%>
            <%= cond do %>
              <% @status.file_missing -> %>
                <%= gettext(
                  "The stored logo file is missing. Upload the image again, or remove the logo."
                ) %>
              <% @status.locked and @status.has_logo -> %>
                <%= gettext("A manual logo is set (discovery will not overwrite it).") %>
              <% @status.locked -> %>
                <%= gettext("This security is set to have no logo.") %>
              <% @status.has_logo -> %>
                <%= gettext("Current logo source: %{source}", source: source_label(@status.source)) %>
              <% true -> %>
                <%= gettext("No logo found yet.") %>
            <% end %>
          </p>

          <%!-- H38 (board 01 of ux-design-2026-10-27): the image comes from the
               operator's machine over the socket; a file dropped on the form
               chooses it too, with no zone drawn. --%>
          <form
            id="logo-upload-form"
            class="logo-override__form"
            phx-submit="save_logo_upload"
            phx-change="validate_logo_upload"
            phx-drop-target={@upload.ref}
          >
            <span class="logo-override__label"><%= gettext("Image file") %></span>
            <label for={@upload.ref} class="logo-override__choose">
              <AppShell.icon name={:upload} size={14} />
              <span><%= gettext("Choose image…") %></span>
            </label>
            <.live_file_input
              upload={@upload}
              class="visually-hidden"
              aria-describedby={
                if @upload_message,
                  do: "logo-upload-help logo-upload-error",
                  else: "logo-upload-help"
              }
              aria-invalid={if @upload_message, do: "true"}
            />
            <div :for={entry <- @upload.entries} class="logo-override__chosen">
              <%= if entry.valid? and is_nil(@upload_message) do %>
                <.live_img_preview entry={entry} class="security-logo security-logo--lg" alt="" />
              <% else %>
                <span class="security-logo security-logo--lg security-logo--initial" aria-hidden="true">
                  <AppShell.icon name={:image} size={18} />
                </span>
              <% end %>
              <span class="logo-override__file">
                <b><%= entry.client_name %></b>
                <small><%= file_size(entry.client_size) %></small>
              </span>
              <button
                type="button"
                class="icon-button"
                data-role="clear-logo-file"
                phx-click="cancel_logo_upload"
                phx-value-ref={entry.ref}
                aria-label={gettext("Remove the selection")}
                title={gettext("Remove the selection")}
              >
                <AppShell.icon name={:x} />
              </button>
            </div>
            <span :if={@upload_message} class="field-error" id="logo-upload-error">
              <%= @upload_message %>
            </span>
            <p class="hint" id="logo-upload-help">
              <%= gettext(
                "PNG, JPEG or WebP, at most %{size}. The image is stored on this instance; discovery does not overwrite it.",
                size: file_size(LogoStore.upload_max_bytes())
              ) %>
            </p>
            <button type="submit" class="button-primary" disabled={not @savable?}>
              <%= gettext("Save logo") %>
            </button>
          </form>
        </div>

        <div class="modal-footer">
          <button
            type="button"
            class="button-ghost"
            phx-click="row_action"
            phx-value-action="update_logo"
            phx-value-id={@security.id}
          >
            <%= gettext("Search again") %>
          </button>
          <button
            type="button"
            class="button-ghost"
            phx-click="remove_logo_override"
            phx-value-id={@security.id}
            disabled={not @status.has_logo and @status.locked and not @status.file_missing}
            data-confirm={gettext("Remove the logo and keep the security without one?")}
          >
            <%= gettext("Remove logo") %>
          </button>
        </div>
    </dialog>
    """
  end

  @doc """
  The words for a stored logo source (board 01 of ux-design-2026-10-27,
  found while drawing 1): the manual source reads "manually uploaded", every
  discovery adapter "found automatically". The stored value never reaches the
  sentence (EXPERIENCE.md → Voice and Tone).
  """
  @spec source_label(term()) :: String.t()
  def source_label("manual"), do: gettext("manually uploaded")
  def source_label(_adapter), do: gettext("found automatically")

  # The upload's refusals reuse the Imports page's words; the store's image
  # check after the upload has its own. Nothing prints an error's value.
  defp upload_error_text(nil), do: nil
  defp upload_error_text(:too_large), do: gettext("File too large.")
  defp upload_error_text(:not_accepted), do: gettext("File type not accepted.")
  defp upload_error_text(:too_many_files), do: gettext("Only one file at a time.")
  defp upload_error_text(:not_an_image), do: gettext("The file is not a readable image.")
  defp upload_error_text(_other), do: gettext("Could not save the logo.")

  # A file size as the chooser shows it: whole kilobytes below a megabyte,
  # one decimal above, in the page's number format.
  defp file_size(bytes) when is_integer(bytes) and bytes < 1024 * 1024,
    do: "#{max(div(bytes + 1023, 1024), 1)} KB"

  defp file_size(bytes) when is_integer(bytes),
    do: Format.decimal(Decimal.div(bytes, 1024 * 1024), 1) <> " MB"

  defp file_size(_bytes), do: ""
end
