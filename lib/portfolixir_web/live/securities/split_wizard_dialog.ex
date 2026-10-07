defmodule PortfolixirWeb.Securities.SplitWizardDialog do
  @moduledoc """
  Guided split wizard dialog for the security detail page (ADR-0028 §1,
  issue #591).

  A thin UI layer over `Portfolixir.Ledger.Splits`: every keystroke previews
  through `Splits.preview_split/1` (per-portfolio quantity before/after the
  effective date, resulting current position, all warnings including the §2
  quote-basis guard), and confirming calls `Splits.book_split/2` — the same
  single write path the API and MCP shells use, never a second one.

  Where a split already stands on the day — a different ratio the preview
  warns about, or the booking's refusal naming the existing event — the
  wizard names the booked ratio and carries "Delete the booked split…"
  (Sprint 18 U1, #912, pick H2-A A8): the parent hears
  `{:dialog, id, {:delete_split, transaction_id}}`, closes the wizard and
  opens the split's delete dialog on the same page, so deleting and booking
  again happen in one place.
  """
  use Phoenix.LiveComponent
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Phoenix.LiveView.JS
  alias Portfolixir.Actor
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Ledger.Transaction
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.LiveEventGuard
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.SecuritiesLive
  alias PortfolixirWeb.StoredText

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> LiveEventGuard.attach()
     |> assign(:form, %{"ratio_numerator" => "", "ratio_denominator" => "", "date" => ""})
     |> assign(:preview, nil)
     |> assign(:booked_split, nil)
     |> assign(:error, nil)
     |> assign(:error_split, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Native dialog (UX-DR9, issue 646): the ModalDialog hook opens it
         with showModal(); cancel (Esc) pushes the close event and the
         close buttons keep their focus-restoring JS. --%>
    <dialog
      id={@id}
      class="modal"
      phx-hook="ModalDialog"
      data-close-event="close"
      aria-labelledby={"#{@id}-title"}
    >
        <header class="modal-head">
          <h2 id={"#{@id}-title"}><%= gettext("Record split") %></h2>
          <button type="button" class="icon-button" aria-label={gettext("Close")} phx-click={close_js(@myself)}>
            <AppShell.icon name={:x} />
          </button>
        </header>

        <div class="modal-body">
          <%!-- The name is quoted, in <bdi>, and the sentence goes on after
               it: a name ending in an abbreviation ("… o.N.") met the
               sentence's own full stop as "o.N.." (the closing act's
               finding; board ux-review-2026-10-03/03-gamma-surface-repairs,
               G7). --%>
          <p class="dialog-help">
            <%= StoredText.isolate(
              gettext(
                "Stock split for “%{security}”, the ratio as new:old shares — 2:1 doubles the count, 1:10 is a reverse split.",
                security: StoredText.slot(:security)
              ),
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
                  type="text"
                  placeholder="YYYY-MM-DD"
                  pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}"
                  maxlength="10"
                  name="split[date]"
                  value={@form["date"]}
                  required
                  phx-debounce="300"
                />
              </label>
            </div>

            <%= if @error do %>
              <div id="split-wizard-error" class="alert-error" role="alert">
                <span><%= @error %></span>
                <span :if={@error_split}>
                  <.delete_link split={@error_split} myself={@myself} />
                </span>
              </div>
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
              <button
                type="submit"
                class="button-primary"
                disabled={is_nil(@preview) or submit_blocker(@preview) != nil}
                title={@preview && submit_blocker(@preview)}
                phx-disable-with={gettext("Booking…")}
              >
                <%= gettext("Book split") %>
              </button>
            </div>
          </form>
        </div>
    </dialog>
    """
  end

  defp render_warnings(assigns) do
    ~H"""
    <div :if={@preview.warnings != []} id="split-wizard-warnings">
      <%= for warning <- @preview.warnings do %>
        <%= if warning == :conflicting_split_ratio and @booked_split do %>
          <%!-- U1 (#912), A8: the booked ratio named, and the way to delete
               it where the refusal is read (UX-DR26). --%>
          <div class="alert-warning" role="alert" data-warning={warning}>
            <span>
              <%= gettext(
                "A split with a different ratio is already booked for this security on this date (%{ratio}). Booking is refused while it stands, and the preview shows no quantity after it.",
                ratio: ratio_label(@booked_split)
              ) %>
            </span>
            <span><.delete_link split={@booked_split} myself={@myself} /></span>
          </div>
        <% else %>
          <p class="alert-warning" role="alert" data-warning={warning}>
            <%= warning_message(warning) %>
          </p>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr(:split, Transaction, required: true)
  attr(:myself, :any, required: true)

  defp delete_link(assigns) do
    ~H"""
    <button
      type="button"
      class="link-button"
      phx-click="delete_booked_split"
      phx-value-id={@split.id}
      phx-target={@myself}
    >
      <%= gettext("Delete the booked split…") %>
    </button>
    """
  end

  defp ratio_label(%Transaction{split_ratio_numerator: p, split_ratio_denominator: q}),
    do: "#{p}:#{q}"

  # What the not-computable "after" cell says to a screen reader (#1066).
  defp conflict_na_sentence,
    do: gettext("no quantity after: a different ratio is booked on this day")

  defp render_preview(assigns) do
    assigns = assign(assigns, :conflict?, :conflicting_split_ratio in assigns.preview.warnings)

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
            <th class="num"><%= gettext("Quantity after (at date)") %></th>
            <th class="num"><%= gettext("Resulting position (today)") %></th>
          </tr>
        </thead>
        <tbody>
          <%!-- Rows booking would skip are muted (the retired-row visual)
                and labelled with the skip reason (E17 UX review, finding 2). --%>
          <tr :for={row <- @preview.portfolios} class={skipped_row_class(row)}>
            <td data-role="portfolio">
              <%= row.portfolio_name %>
              <%= if flag = row_flag(row) do %>
                <span class="badge badge--retired" data-role="row-flag"><%= flag %></span>
              <% end %>
            </td>
            <td class="num" data-role="qty-before"><%= quantity(row.quantity_before) %></td>
            <%!-- #1066, pick J8 = A (board 08): under a conflicting ratio
                 the "after" figures would be the refused ratio alone and
                 the refused ratio stacked on the booked one — two worlds
                 the refusal never lets happen. Both cells are the
                 not-computable dash in the muted voice; the warning above
                 the table says why, outside the table, which scrolls
                 sideways on a phone. A screen reader reads the reason in
                 the cell instead of the dash (UX-DR7, as the trades
                 table's p.a. cell does). --%>
            <%= if @conflict? do %>
              <td class="num split-na" data-role="qty-after">
                <span aria-hidden="true">—</span><span class="visually-hidden"><%= conflict_na_sentence() %></span>
              </td>
              <td class="num split-na" data-role="qty-current">
                <span aria-hidden="true">—</span><span class="visually-hidden"><%= conflict_na_sentence() %></span>
              </td>
            <% else %>
              <td class="num" data-role="qty-after"><%= quantity(row.quantity_after) %></td>
              <td class="num" data-role="qty-current"><%= quantity(row.current_position) %></td>
            <% end %>
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
            <th class="num"><%= gettext("Closing price") %></th>
            <th><%= gettext("Source") %></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={quote_row <- @preview.quotes_around}>
            <td><%= Format.date(quote_row.date) %></td>
            <td class="num">
              <%= Format.decimal(quote_row.close, 2) %>
              <small><%= @security.currency_code %></small>
            </td>
            <td><%= SecuritiesLive.quote_source_label(quote_row.source) %></td>
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

  # U1 (#912), A8: the parent closes the wizard and opens the split's delete
  # dialog — never a dialog from a dialog (UX-DR9).
  def handle_event("delete_booked_split", %{"id" => id_str}, socket) do
    case LiveParam.id(id_str) do
      nil ->
        {:noreply, socket}

      id ->
        notify_parent(socket, {:delete_split, id})
        {:noreply, socket}
    end
  end

  # The wizard's fields, as the strings its inputs send (E25 S4, F17).
  def handle_event("preview", %{"split" => params}, socket) do
    {:noreply, socket |> assign(:form, split_form(params)) |> run_preview()}
  end

  def handle_event("confirm", %{"split" => params}, socket) do
    socket = assign(socket, :form, split_form(params))

    case Splits.book_split(Actor.owner_ui(), split_attrs(socket)) do
      {:ok, transactions} ->
        notify_parent(socket, {:split_booked, length(transactions)})
        {:noreply, socket}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, error_message(reason))
         |> assign(:error_split, standing_split(reason))
         |> assign(:preview, nil)}
    end
  end

  # An event this component does not know, or a payload it cannot read,
  # changes nothing (E25 S4, F17).
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # The split a refusal names, for its "Delete the booked split…".
  defp standing_split({:conflicting_split_ratio, %Transaction{} = row}), do: row
  defp standing_split({:existing_split, %Transaction{} = row}), do: row
  defp standing_split(_reason), do: nil

  defp split_form(params) do
    Map.merge(
      %{"date" => "", "ratio_numerator" => "", "ratio_denominator" => ""},
      params |> LiveParam.form() |> Map.take(~w(date ratio_numerator ratio_denominator))
    )
  end

  defp run_preview(%{assigns: %{form: form}} = socket) do
    socket = assign(socket, booked_split: nil, error_split: nil)

    if Enum.any?(Map.values(form), &(&1 in [nil, ""])) do
      socket |> assign(:preview, nil) |> assign(:error, nil)
    else
      case Splits.preview_split(split_attrs(socket)) do
        {:ok, preview} ->
          socket
          |> assign(:preview, preview)
          |> assign(:booked_split, conflicting_row(preview))
          |> assign(:error, nil)

        {:error, reason} ->
          socket |> assign(:preview, nil) |> assign(:error, error_message(reason))
      end
    end
  end

  # The split standing on the previewed day with another ratio: the row the
  # A8 link deletes (with its whole event), and whose ratio the warning names.
  defp conflicting_row(%{warnings: warnings} = preview) do
    if :conflicting_split_ratio in warnings do
      ratio = {preview.ratio_numerator, preview.ratio_denominator}

      preview.security_id
      |> Splits.booked_on(preview.date)
      |> Enum.find(&(normalized({&1.split_ratio_numerator, &1.split_ratio_denominator}) != ratio))
    end
  end

  defp normalized({p, q}) do
    gcd = Integer.gcd(p, q)
    {div(p, gcd), div(q, gcd)}
  end

  defp split_attrs(%{assigns: %{form: form, security: security}}) do
    %{
      security_id: security.id,
      date: form["date"],
      ratio_numerator: form["ratio_numerator"],
      ratio_denominator: form["ratio_denominator"]
    }
  end

  # -- submit gating and row flags (E17 UX review, findings 1 and 2) --------

  # A booking that can only fail keeps the Book button disabled, with the
  # blocker named in the title: a same-day conflicting ratio is rejected
  # outright, and without any row that would be newly booked the booking
  # returns :no_position or {:existing_split, _}.
  defp submit_blocker(%{warnings: warnings, portfolios: rows}) do
    cond do
      :conflicting_split_ratio in warnings ->
        gettext(
          "Booking is blocked: a split with a different ratio is already booked on this date."
        )

      Enum.any?(rows, &(&1.bookable and not &1.already_booked)) ->
        nil

      :already_booked in warnings ->
        gettext(
          "Booking is blocked: this split is already booked for every positioned portfolio."
        )

      true ->
        gettext("Booking is blocked: no portfolio holds a position at the effective date.")
    end
  end

  defp skipped_row_class(row) do
    if row_flag(row), do: "security-row is-retired"
  end

  defp row_flag(%{already_booked: true}), do: gettext("already booked")
  defp row_flag(%{bookable: false}), do: gettext("no position at date")
  defp row_flag(_row), do: nil

  # -- copy -----------------------------------------------------------------

  defp warning_message(:effective_date_before_history) do
    gettext(
      "The effective date is before this security's earliest recorded transaction. An imported history may already contain post-split quantities — booking the split again would double-apply it."
    )
  end

  # §2 escape hatch: the contradiction copy names the per-security override
  # flag, as the ADR requires (E17 UX review, finding 4). The evidence table
  # (`render_quotes/1`) shows the jump itself, so the inline warning stays a
  # terse fact + remedy — the "how to grade the jump" tutorial is dropped
  # rather than moved into an ⓘ tooltip: the existing `.metric-tooltip`
  # pattern is CSS-anchored to `.stat`/`.drift-table` contexts and a modal
  # `alert-warning` establishes no positioning context to reuse it without
  # new CSS (owner microcopy rule 2026-07-23, UX-DR11).
  defp warning_message(:quote_basis_contradiction) do
    gettext(
      "The stored closes around the effective date contradict their price-basis classification. Nothing is adjusted silently — review the quotes below; if they are raw (as traded), force it via the security's \"Treat synced quotes as raw\" setting."
    )
  end

  defp warning_message(:insufficient_quotes_to_verify_basis) do
    gettext("Insufficient quotes around the effective date to verify the price basis.")
  end

  # E17 review, finding 3: a re-opened wizard on a booked split simulates
  # against the real rows; the warning says why nothing doubles.
  defp warning_message(:already_booked) do
    gettext(
      "An identical split is already booked on this date. Portfolios that already carry it are shown as booked and will be skipped — only newly positioned portfolios would get a row."
    )
  end

  # E17 review, finding 5: booking creates rows only for portfolios
  # positioned at the effective date; say up front when that set is empty.
  defp warning_message(:no_position_at_effective_date) do
    gettext(
      "No portfolio holds a position at the effective date — booking would create no rows and be rejected."
    )
  end

  # E17 review, finding 2: conflicting security-level events would corrupt
  # every split-adjusted quote read.
  defp warning_message(:conflicting_split_ratio) do
    gettext(
      "A split with a different ratio is already booked for this security on this date. Booking will be rejected, and the preview shows no quantity after it — delete the existing event first if it is wrong."
    )
  end

  defp warning_message(other), do: to_string(other)

  defp error_message(:invalid_ratio),
    do: gettext("Enter the ratio as two positive whole numbers, e.g. 2:1.")

  defp error_message(:identity_ratio),
    do: gettext("The ratio must change the share count — a 1:1 split does nothing.")

  defp error_message(:invalid_date), do: gettext("Enter a valid effective date.")

  defp error_message(:cumulative_factor_out_of_range),
    do:
      gettext(
        "This ratio, together with the splits already booked for this security, would scale it by more than 10^12."
      )

  defp error_message(:future_effective_date),
    do: gettext("The effective date must not be in the future.")

  defp error_message(:no_position),
    do: gettext("No portfolio holds a position in this security at the effective date.")

  defp error_message(:security_not_found), do: gettext("This security no longer exists.")

  # Write idempotency (ADR-0028 §1): the rejection names the existing event.
  # The date renders through the locale-aware formatter (E17 review,
  # finding 10), not as a bare ISO string.
  defp error_message({:existing_split, %Transaction{} = existing}) do
    gettext(
      "A split for this security is already booked on %{date}: transaction #%{id} records ratio %{ratio}%{portfolio}. Delete that event first if it is wrong.",
      date: Format.date(existing.date),
      id: existing.id,
      ratio: "#{existing.split_ratio_numerator}:#{existing.split_ratio_denominator}",
      portfolio: existing_portfolio_suffix(existing)
    )
  end

  # E17 review, finding 2: a same-day event with a different ratio is never
  # booked over — the copy names the conflicting event.
  defp error_message({:conflicting_split_ratio, %Transaction{} = existing}) do
    gettext(
      "A split with a different ratio is already booked on %{date}: transaction #%{id} records ratio %{ratio}%{portfolio}. Delete that event first if it is wrong.",
      date: Format.date(existing.date),
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
