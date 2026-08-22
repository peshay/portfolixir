defmodule PortfolixirWeb.TaxLive do
  @moduledoc """
  Recorded tax statements as a Wealth tab (ADR-0031, FR-36).

  The maintainer transcribes the Verlustverrechnungstöpfe /
  Freistellungsauftrag block of a broker statement once a year and reads the
  tax-free trim budget off it. Three display rules bind this surface:

  - the pots render with the **statement's printed sign** so a row is visually
    comparable to the paper, while storage stays positive magnitudes (§2);
  - the trim budget is always stated **with its as-of date** and marked stale
    once a later day exists in which investment income can have landed (§5);
  - consistency advisories are fact plus remedy, terse and impersonal, and
    domain terms sit behind ⓘ tooltips (UX-DR11) rather than permanently in
    the sightline.

  Nothing here is derived from holdings, and nothing here is tax advice — the
  recorded statement remains the authority.
  """

  use PortfolixirWeb, :live_view

  alias Portfolixir.Actor
  alias Portfolixir.Tax
  alias Portfolixir.Tax.Budget
  alias Portfolixir.Tax.StatementSnapshot
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format

  # Rendered with the statement's printed sign: the loss pots and the
  # allowance-consumption figures appear as negatives on the paper even though
  # they are stored as magnitudes.
  @negative_on_paper ~w(loss_pot_equities loss_pot_other loss_carryforward_prior_years
                        allowance_used capital_gains_tax_withheld
                        solidarity_surcharge_withheld church_tax_withheld)a

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()

    socket =
      socket
      |> assign(:current_path, "/tax")
      |> assign(:today, today)
      |> assign(:holder, default_holder())
      |> assign(:tax_year, today.year - 1)
      |> assign(:form_errors, nil)
      |> assign(:order_errors, nil)
      |> assign(:editing_id, nil)
      |> load_year()

    {:ok, socket}
  end

  @impl true
  def handle_event("select_scope", %{"scope" => params}, socket) do
    socket =
      socket
      |> assign(:holder, String.trim(params["holder"] || ""))
      |> assign(:tax_year, parse_int(params["tax_year"]) || socket.assigns.tax_year)
      |> assign(:editing_id, nil)
      |> load_year()

    {:noreply, socket}
  end

  def handle_event("record_statement", %{"statement" => params}, socket) do
    case save_statement(socket, params) do
      {:ok, _snapshot} ->
        {:noreply, socket |> assign(form_errors: nil, editing_id: nil) |> load_year()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form_errors, changeset_errors(changeset))}
    end
  end

  def handle_event("edit_statement", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_id: parse_int(id), form_errors: nil)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_id: nil, form_errors: nil)}
  end

  def handle_event("delete_statement", %{"id" => id}, socket) do
    # Already deleted elsewhere (other tab, API, MCP) is not an error — the row
    # is gone either way.
    case Tax.delete_snapshot(Actor.owner_ui(), parse_int(id)) do
      {:ok, _snapshot} -> :ok
      {:error, :not_found} -> :ok
    end

    {:noreply, socket |> assign(:editing_id, nil) |> load_year()}
  end

  def handle_event("put_allowance_order", %{"order" => params}, socket) do
    attrs = %{
      holder: socket.assigns.holder,
      institution: params["institution"],
      tax_year: socket.assigns.tax_year,
      amount_granted: params["amount_granted"]
    }

    case Tax.put_allowance_order(Actor.owner_ui(), attrs) do
      {:ok, _order} ->
        {:noreply, socket |> assign(:order_errors, nil) |> load_year()}

      {:error, changeset} ->
        {:noreply, assign(socket, :order_errors, changeset_errors(changeset))}
    end
  end

  def handle_event("delete_allowance_order", %{"id" => id}, socket) do
    case Tax.delete_allowance_order(Actor.owner_ui(), parse_int(id)) do
      {:ok, _order} -> :ok
      {:error, :not_found} -> :ok
    end

    {:noreply, load_year(socket)}
  end

  defp save_statement(socket, params) do
    attrs = statement_attrs(socket, params)

    case socket.assigns.editing_id do
      nil ->
        Tax.create_snapshot(Actor.owner_ui(), attrs, today: socket.assigns.today)

      id ->
        with {:ok, snapshot} <- Tax.fetch_snapshot(id) do
          Tax.update_snapshot(Actor.owner_ui(), snapshot, attrs, today: socket.assigns.today)
        end
    end
  end

  defp statement_attrs(socket, params) do
    money =
      Map.new(StatementSnapshot.money_fields(), fn field ->
        {field, blank_to_zero(params[Atom.to_string(field)])}
      end)

    Map.merge(money, %{
      institution: params["institution"],
      holder: socket.assigns.holder,
      tax_year: socket.assigns.tax_year,
      as_of: params["as_of"],
      note: params["note"]
    })
  end

  # An empty field means "not on this statement", which is zero — not a cast
  # error the maintainer has to fix field by field.
  defp blank_to_zero(nil), do: "0"

  defp blank_to_zero(value) when is_binary(value) do
    case String.trim(value) do
      "" -> "0"
      trimmed -> trimmed
    end
  end

  defp load_year(socket) do
    %{holder: holder, tax_year: tax_year} = socket.assigns

    snapshots = Tax.list_snapshots(holder: holder, tax_year: tax_year)

    summary = Tax.holder_summary(holder, tax_year)

    socket
    |> assign(:snapshots, Enum.map(snapshots, &%{row: &1, findings: Tax.findings_for(&1)}))
    |> assign(:summary, summary)
    # Activity-aware staleness (issue #667): warns on age over the threshold
    # OR tax-relevant bookings since the statement — never on the mere
    # passage of a day.
    |> assign(:staleness, Tax.staleness(summary.as_of, socket.assigns.today))
    |> assign(:orders, Tax.list_allowance_orders(holder: holder, tax_year: tax_year))
    |> assign(:holders, Tax.list_snapshot_holders())
    |> assign(:editing, editing_row(snapshots, socket.assigns.editing_id))
  end

  # The warning names its reason: activity first (the substantive condition),
  # age as the fallback.
  defp staleness_message(%{activity_warning: true, activity_since_count: count}) do
    ngettext(
      "Stale — %{count} tax-relevant booking since the statement date consumes pots or allowance.",
      "Stale — %{count} tax-relevant bookings since the statement date consume pots or allowance.",
      count,
      count: count
    )
  end

  defp staleness_message(%{age_days: age_days}) do
    gettext("Stale — the statement is %{days} days old.", days: age_days)
  end

  defp editing_row(_snapshots, nil), do: nil
  defp editing_row(snapshots, id), do: Enum.find(snapshots, &(&1.id == id))

  defp default_holder do
    case Tax.list_snapshot_holders() do
      [holder | _rest] -> holder
      [] -> gettext("Owner")
    end
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _other -> nil
    end
  end

  defp parse_int(_value), do: nil

  # -- display ---------------------------------------------------------------

  defp printed(field, value) do
    if field in @negative_on_paper and Decimal.compare(value, 0) == :gt do
      Format.money(Decimal.negate(value))
    else
      Format.money(value)
    end
  end

  defp field_label(:taxable_income), do: gettext("Taxable investment income")
  defp field_label(:allowance_granted), do: gettext("Allowance granted")
  defp field_label(:allowance_used), do: gettext("Allowance used")
  defp field_label(:loss_pot_equities), do: gettext("Loss pot, equities")
  defp field_label(:loss_pot_other), do: gettext("Loss pot, other")
  defp field_label(:loss_carryforward_prior_years), do: gettext("Loss carry-forward")
  defp field_label(:withholding_tax_pot), do: gettext("Foreign withholding pot")
  defp field_label(:withholding_tax_credited), do: gettext("Foreign withholding credited")
  defp field_label(:capital_gains_tax_withheld), do: gettext("Capital-gains tax withheld")
  defp field_label(:solidarity_surcharge_withheld), do: gettext("Solidarity surcharge withheld")
  defp field_label(:church_tax_withheld), do: gettext("Church tax withheld")

  # Fact plus remedy, impersonal and terse: what disagrees, by how much, and
  # what closes it. Never a proposed "corrected" value.
  defp finding_text(%{code: :c3} = finding) do
    gettext(
      "Withheld capital-gains tax %{recorded} against %{expected} reconstructed from the statement — gap %{gap}. Re-check the figure against the statement.",
      finding_bindings(finding)
    )
  end

  defp finding_text(%{code: :c4} = finding) do
    gettext(
      "Solidarity surcharge %{recorded} against %{expected} expected — gap %{gap}. Re-check the figure against the statement.",
      finding_bindings(finding)
    )
  end

  defp finding_text(%{code: :c5} = finding) do
    gettext(
      "Church tax %{recorded} against %{expected} expected — gap %{gap}. Re-check the figure, or the church-tax rate of the profile in force.",
      finding_bindings(finding)
    )
  end

  defp finding_text(%{code: :c6} = finding) do
    gettext(
      "%{field} %{recorded} is below the %{expected} an earlier statement of this year already reported. Year-to-date figures do not fall — check whether this is the right statement.",
      Map.put(finding_bindings(finding), :field, field_label(finding.field))
    )
  end

  defp finding_text(%{code: :c7} = finding) do
    gettext(
      "Allowance granted %{recorded} against %{expected} configured for this institution. Either the instruction never landed at the bank, or the configured order is stale.",
      finding_bindings(finding)
    )
  end

  defp finding_text(%{code: :c8} = finding) do
    gettext(
      "Configured allowance orders total %{recorded} against the %{expected} ceiling for this year — %{gap} above. Redistribute the orders with the banks.",
      finding_bindings(finding)
    )
  end

  defp finding_bindings(finding) do
    %{
      recorded: Format.money(finding.recorded),
      expected: Format.money(finding.expected),
      gap: Format.money(finding.gap)
    }
  end

  defp invalid?(nil, _field), do: false
  defp invalid?(errors, field), do: Map.has_key?(errors, field)

  defp error_text(errors) do
    Enum.map_join(errors, "; ", fn {field, messages} ->
      "#{field_label_or_name(field)}: #{Enum.join(messages, ", ")}"
    end)
  end

  defp field_label_or_name(field) do
    if field in StatementSnapshot.money_fields(), do: field_label(field), else: to_string(field)
  end

  defp value_of(nil, _field), do: nil
  defp value_of(row, field), do: Decimal.to_string(Map.fetch!(row, field), :normal)

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell
      current_path={@current_path}
      page_title={gettext("Tax")}
      page_subtitle={gettext("Recorded broker tax statements")}
    >
      <div class="workspace-page">
        <AppShell.area_tabs tabs={AppShell.wealth_tabs(:tax)} />

        <section class="workspace-section">
          <header class="section-head">
            <h2><%= gettext("Tax-free trim budget") %></h2>
          </header>

          <form id="tax-scope-form" phx-change="select_scope" class="tax-scope">
            <label>
              <%= gettext("Taxpayer") %>
              <input type="text" name="scope[holder]" value={@holder} list="tax-holders" required />
              <datalist id="tax-holders">
                <option :for={holder <- @holders} value={holder}></option>
              </datalist>
            </label>
            <label>
              <%= gettext("Tax year") %>
              <input type="number" name="scope[tax_year]" value={@tax_year} min="1990" max="2200" />
            </label>
          </form>

          <p class="tax-budget">
            <strong class="tax-budget__value"><%= Format.money(@summary.tax_free_trim_budget) %></strong>
            <span class="muted">
              <%= if @summary.as_of do %>
                <%= gettext("as of %{date}", date: Format.date(@summary.as_of)) %>
              <% else %>
                <%= gettext("No statement recorded for this year.") %>
              <% end %>
            </span>
            <span :if={@staleness && @staleness.warning} class="badge badge-warning">
              <%= staleness_message(@staleness) %>
            </span>
          </p>

          <p class="muted">
            <%= gettext("Equity loss pot %{pot} plus remaining allowance %{allowance}.",
              pot: Format.money(@summary.loss_pot_equities),
              allowance: Format.money(@summary.allowance_remaining)
            ) %>
            <span :if={@summary.allowance_ceiling}>
              <%= gettext("Statutory ceiling for this year: %{ceiling}.",
                ceiling: Format.money(@summary.allowance_ceiling)
              ) %>
            </span>
          </p>

          <p :if={@summary.institutions != []} class="muted">
            <%= gettext("Covers: %{institutions}.",
              institutions: Enum.join(@summary.institutions, ", ")
            ) %>
          </p>

          <p :if={not @summary.complete?} class="alert-warning" role="status">
            <%= gettext(
              "Incomplete: no statement recorded for %{institutions}. The total covers the listed institutions only.",
              institutions: Enum.join(@summary.missing_institutions, ", ")
            ) %>
          </p>

          <details class="tax-explainer">
            <summary aria-label={gettext("About this figure")}>ⓘ <%= gettext("About this figure") %></summary>
            <p>
              <%= gettext(
                "These pots are transcribed from the broker statement, never computed from the ledger. Not for want of FIFO — lots are matched FIFO already, on the trade list — but that yields a gross gain, and a gross gain is not a tax pot. Teilfreistellung, Vorabpauschale, chronological allowance consumption and prior-year carry-forward are absent from transaction data, and the pots are kept per institution. The statement remains the authority. This is not tax advice."
              ) %>
            </p>
          </details>
        </section>

        <section class="workspace-section">
          <header class="section-head">
            <h2>
              <%= if @editing, do: gettext("Correct statement"), else: gettext("Record a statement") %>
            </h2>
          </header>

          <p :if={@form_errors} id="tax-form-error" class="alert-error" role="alert">
            <%= error_text(@form_errors) %>
          </p>

          <p class="muted">
            <%= gettext(
              "Enter every amount without its sign. A loss pot is the volume of loss available for offsetting."
            ) %>
          </p>

          <form id="tax-statement-form" phx-submit="record_statement" class="tax-form">
            <label>
              <%= gettext("Institution") %>
              <input
                type="text"
                name="statement[institution]"
                value={@editing && @editing.institution}
                required
                aria-invalid={invalid?(@form_errors, :institution) && "true"}
                aria-describedby={invalid?(@form_errors, :institution) && "tax-form-error"}
              />
            </label>
            <label>
              <%= gettext("Statement date") %>
              <input
                type="text"
                placeholder="YYYY-MM-DD"
                pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}"
                maxlength="10"
                name="statement[as_of]"
                value={@editing && Date.to_iso8601(@editing.as_of)}
                required
                aria-invalid={invalid?(@form_errors, :as_of) && "true"}
                aria-describedby={invalid?(@form_errors, :as_of) && "tax-form-error"}
              />
            </label>

            <label :for={field <- StatementSnapshot.money_fields()}>
              <%= field_label(field) %>
              <input
                type="text"
                inputmode="decimal"
                name={"statement[#{field}]"}
                value={value_of(@editing, field)}
                aria-invalid={invalid?(@form_errors, field) && "true"}
                aria-describedby={invalid?(@form_errors, field) && "tax-form-error"}
              />
            </label>

            <label class="tax-form__wide">
              <%= gettext("Note") %>
              <input type="text" name="statement[note]" value={@editing && @editing.note} />
            </label>

            <div class="tax-form__actions">
              <button type="submit" class="button">
                <%= if @editing, do: gettext("Save correction"), else: gettext("Record statement") %>
              </button>
              <button :if={@editing} type="button" class="button button-secondary" phx-click="cancel_edit">
                <%= gettext("Cancel") %>
              </button>
            </div>
          </form>
        </section>

        <section class="workspace-section">
          <header class="section-head">
            <h2><%= gettext("Recorded statements") %></h2>
          </header>

          <p :if={@snapshots == []} class="muted">
            <%= gettext("No statement recorded for this taxpayer and year.") %>
          </p>

          <article :for={entry <- @snapshots} class="tax-statement" id={"tax-statement-#{entry.row.id}"}>
            <header class="tax-statement__head">
              <h3><%= entry.row.institution %></h3>
              <span class="muted"><%= Format.date(entry.row.as_of) %></span>
              <button type="button" class="button button-secondary" phx-click="edit_statement" phx-value-id={entry.row.id}>
                <%= gettext("Correct") %>
              </button>
              <button
                type="button"
                class="button button-danger"
                phx-click="delete_statement"
                phx-value-id={entry.row.id}
                data-confirm={gettext("Delete this recorded statement?")}
              >
                <%= gettext("Delete") %>
              </button>
            </header>

            <dl class="tax-statement__figures">
              <div :for={field <- StatementSnapshot.money_fields()}>
                <dt><%= field_label(field) %></dt>
                <dd><%= printed(field, Map.fetch!(entry.row, field)) %></dd>
              </div>
            </dl>

            <p class="muted">
              <%= gettext("Tax-free trim budget at this institution: %{value}.",
                value: Format.money(Budget.tax_free_trim_budget(entry.row))
              ) %>
            </p>

            <ul :if={entry.findings != []} class="tax-findings">
              <li :for={finding <- entry.findings} class="alert-warning"><%= finding_text(finding) %></li>
            </ul>

            <p :if={entry.row.note} class="muted"><%= entry.row.note %></p>
          </article>
        </section>

        <section class="workspace-section">
          <header class="section-head">
            <h2><%= gettext("Configured Freistellungsaufträge") %></h2>
          </header>

          <p :if={@order_errors} class="alert-error" role="alert"><%= error_text(@order_errors) %></p>

          <p class="muted">
            <%= gettext(
              "What was instructed per institution, for comparison against what the bank applied."
            ) %>
          </p>

          <ul class="tax-orders">
            <li :for={order <- @orders}>
              <span><%= order.institution %></span>
              <span><%= Format.money(order.amount_granted) %></span>
              <button
                type="button"
                class="button button-secondary"
                phx-click="delete_allowance_order"
                phx-value-id={order.id}
              >
                <%= gettext("Delete") %>
              </button>
            </li>
          </ul>

          <form id="tax-order-form" phx-submit="put_allowance_order" class="tax-order-form">
            <label>
              <%= gettext("Institution") %>
              <input type="text" name="order[institution]" required />
            </label>
            <label>
              <%= gettext("Amount granted") %>
              <input type="text" inputmode="decimal" name="order[amount_granted]" required />
            </label>
            <button type="submit" class="button"><%= gettext("Record order") %></button>
          </form>
        </section>
      </div>
    </AppShell.shell>
    """
  end
end
