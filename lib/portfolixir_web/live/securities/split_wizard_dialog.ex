defmodule PortfolixirWeb.Securities.SplitWizardDialog do
  @moduledoc """
  Guided split wizard dialog for the security detail page (ADR-0028 §1,
  issue #591).

  A thin UI layer over `Portfolixir.Ledger.Splits`: every keystroke previews
  through `Splits.preview_split/1` (per-portfolio quantity before/after the
  effective date, resulting current position, all warnings including the §2
  quote-basis guard), and confirming calls `Splits.book_split/2` — the same
  single write path the API and MCP shells use, never a second one.
  """
  use Phoenix.LiveComponent
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Phoenix.LiveView.JS
  alias Portfolixir.Actor
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Ledger.Transaction
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:form, %{"ratio_numerator" => "", "ratio_denominator" => "", "date" => ""})
     |> assign(:preview, nil)
     |> assign(:error, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="modal-backdrop" phx-window-keydown={close_js(@myself)} phx-key="Escape">
      <div class="modal" role="dialog" aria-modal="true" aria-labelledby={"#{@id}-title"}>
        <header class="modal-head">
          <h2 id={"#{@id}-title"}><%= gettext("Record split") %></h2>
          <button type="button" class="icon-button" aria-label={gettext("Close")} phx-click={close_js(@myself)}>
            <AppShell.icon name={:x} />
          </button>
        </header>

        <div class="modal-body">
          <p class="dialog-help">
            <%= gettext(
              "Record a stock split for %{security}. Enter the ratio as new:old shares — 2:1 doubles the share count, 1:10 is a reverse split.",
              security: @security.name
            ) %>
          </p>

          <form id="split-wizard-form" phx-change="preview" phx-submit="confirm" phx-target={@myself}>
            <div class="form-grid">
              <label>
                <span><%= gettext("New shares") %></span>
                <input
                  type="number"
                  name="split[ratio_numerator]"
                  value={@form["ratio_numerator"]}
                  min="1"
                  step="1"
                  required
                  phx-debounce="300"
                  phx-mounted={JS.focus()}
                />
              </label>
              <label>
                <span><%= gettext("Old shares") %></span>
                <input
                  type="number"
                  name="split[ratio_denominator]"
                  value={@form["ratio_denominator"]}
                  min="1"
                  step="1"
                  required
                  phx-debounce="300"
                />
              </label>
              <label>
                <span><%= gettext("Effective date") %></span>
                <input
                  type="date"
                  name="split[date]"
                  value={@form["date"]}
                  max={Date.to_iso8601(Date.utc_today())}
                  required
                  phx-debounce="300"
                />
              </label>
            </div>

            <%= if @error do %>
              <p id="split-wizard-error" class="alert-error" role="alert"><%= @error %></p>
            <% end %>

            <%= if @preview do %>
              <%= render_warnings(assigns) %>
              <%= render_preview(assigns) %>
              <%= render_quotes(assigns) %>
            <% end %>

            <div class="modal-footer">
              <button type="button" class="button-ghost" phx-click={close_js(@myself)}>
                <%= gettext("Cancel") %>
              </button>
              <button type="submit" class="button-primary" disabled={is_nil(@preview)}>
                <%= gettext("Book split") %>
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  defp render_warnings(assigns) do
    ~H"""
    <div :if={@preview.warnings != []} id="split-wizard-warnings">
      <p :for={warning <- @preview.warnings} class="alert-warning" role="alert" data-warning={warning}>
        <%= warning_message(warning) %>
      </p>
    </div>
    """
  end

  defp render_preview(assigns) do
    ~H"""
    <div class="data-table-wrap">
      <table id="split-wizard-preview" class="data-table">
        <caption class="dialog-help">
          <%= gettext("Effect of the %{ratio} split per portfolio:",
            ratio: "#{@preview.ratio_numerator}:#{@preview.ratio_denominator}"
          ) %>
        </caption>
        <thead>
          <tr>
            <th><%= gettext("Portfolio") %></th>
            <th class="num"><%= gettext("Quantity before") %></th>
            <th class="num"><%= gettext("Quantity after") %></th>
            <th class="num"><%= gettext("Resulting position") %></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @preview.portfolios}>
            <td data-role="portfolio"><%= row.portfolio_name %></td>
            <td class="num" data-role="qty-before"><%= quantity(row.quantity_before) %></td>
            <td class="num" data-role="qty-after"><%= quantity(row.quantity_after) %></td>
            <td class="num" data-role="qty-current"><%= quantity(row.current_position) %></td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  # ADR-0028 §2: the preview renders the stored closes around the effective
  # date, so a visible jump (raw basis) or continuity (adjusted mirror) is on
  # screen next to the basis-check warning before the user confirms.
  defp render_quotes(assigns) do
    ~H"""
    <div :if={@preview.quotes_around != []} class="data-table-wrap">
      <table id="split-wizard-quotes" class="data-table">
        <caption class="dialog-help"><%= gettext("Stored closes around the effective date:") %></caption>
        <thead>
          <tr>
            <th><%= gettext("Date") %></th>
            <th class="num"><%= gettext("Close") %></th>
            <th><%= gettext("Source") %></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={quote_row <- @preview.quotes_around}>
            <td><%= Date.to_iso8601(quote_row.date) %></td>
            <td class="num"><%= Format.decimal(quote_row.close, 2) %></td>
            <td><%= quote_row.source %></td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  # -- events ---------------------------------------------------------------

  @impl true
  def handle_event("close", _params, socket) do
    notify_parent(socket, :close)
    {:noreply, socket}
  end

  def handle_event("preview", %{"split" => params}, socket) do
    {:noreply, socket |> assign(:form, params) |> run_preview()}
  end

  def handle_event("confirm", %{"split" => params}, socket) do
    socket = assign(socket, :form, params)

    case Splits.book_split(Actor.owner_ui(), split_attrs(socket)) do
      {:ok, transactions} ->
        notify_parent(socket, {:split_booked, length(transactions)})
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, socket |> assign(:error, error_message(reason)) |> assign(:preview, nil)}
    end
  end

  defp run_preview(%{assigns: %{form: form}} = socket) do
    if Enum.any?(Map.values(form), &(&1 in [nil, ""])) do
      socket |> assign(:preview, nil) |> assign(:error, nil)
    else
      case Splits.preview_split(split_attrs(socket)) do
        {:ok, preview} ->
          socket |> assign(:preview, preview) |> assign(:error, nil)

        {:error, reason} ->
          socket |> assign(:preview, nil) |> assign(:error, error_message(reason))
      end
    end
  end

  defp split_attrs(%{assigns: %{form: form, security: security}}) do
    %{
      security_id: security.id,
      date: form["date"],
      ratio_numerator: form["ratio_numerator"],
      ratio_denominator: form["ratio_denominator"]
    }
  end

  # -- copy -----------------------------------------------------------------

  defp warning_message(:effective_date_before_history) do
    gettext(
      "The effective date is before this security's earliest recorded transaction. An imported history may already contain post-split quantities — booking the split again would double-apply it."
    )
  end

  # §2 escape hatch: the contradiction copy names the per-security override
  # flag, as the ADR requires.
  defp warning_message(:quote_basis_contradiction) do
    gettext(
      "The stored closes around the effective date contradict their price-basis classification. Nothing is adjusted silently — review the quotes below, or force the raw basis via the security's \"Treat synced quotes as raw\" setting."
    )
  end

  defp warning_message(:insufficient_quotes_to_verify_basis) do
    gettext("Insufficient quotes around the effective date to verify the price basis.")
  end

  defp warning_message(other), do: to_string(other)

  defp error_message(:invalid_ratio),
    do: gettext("Enter the ratio as two positive whole numbers, e.g. 2:1.")

  defp error_message(:identity_ratio),
    do: gettext("The ratio must change the share count — a 1:1 split does nothing.")

  defp error_message(:invalid_date), do: gettext("Enter a valid effective date.")

  defp error_message(:future_effective_date),
    do: gettext("The effective date must not be in the future.")

  defp error_message(:no_position),
    do: gettext("No portfolio holds a position in this security at the effective date.")

  defp error_message(:security_not_found), do: gettext("This security no longer exists.")

  # Write idempotency (ADR-0028 §1): the rejection names the existing event.
  defp error_message({:existing_split, %Transaction{} = existing}) do
    gettext(
      "A split for this security is already booked on %{date}: transaction #%{id} records ratio %{ratio}%{portfolio}. Delete that event first if it is wrong.",
      date: Date.to_iso8601(existing.date),
      id: existing.id,
      ratio: "#{existing.split_ratio_numerator}:#{existing.split_ratio_denominator}",
      portfolio: existing_portfolio_suffix(existing)
    )
  end

  defp error_message(%Ecto.Changeset{}), do: gettext("Could not book the split.")

  defp existing_portfolio_suffix(%Transaction{portfolio: %{name: name}}) when is_binary(name),
    do: gettext(" for portfolio \"%{name}\"", name: name)

  defp existing_portfolio_suffix(_existing), do: ""

  # Exact quantities, not display-rounded: the scaled quantity is quantized
  # once at volume scale 6 (ADR-0028 §3) and the preview must show it as-is.
  defp quantity(%Decimal{} = value),
    do: value |> Decimal.normalize() |> Decimal.to_string(:normal)

  # Esc and the close/cancel buttons return focus to the trigger (UX-DR9)
  # before telling the server to drop the dialog.
  defp close_js(myself) do
    JS.focus(to: "#detail-record-split") |> JS.push("close", target: myself)
  end

  defp notify_parent(socket, message) do
    send(self(), {:dialog, socket.assigns.id, message})
  end
end
