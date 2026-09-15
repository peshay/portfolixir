defmodule PortfolixirWeb.TaxLive do
  @moduledoc """
  Recorded tax statements as a Wealth tab (ADR-0031, FR-36).

  The maintainer transcribes the Verlustverrechnungstöpfe /
  Freistellungsauftrag block of a broker statement once a year and reads the
  tax-free trim budget off it. The surface is a budget dashboard plus a check
  list (EXPERIENCE.md → Component Patterns → Tax surface, built by issue 795):

  - the budget renders as a **meter** — allowance utilisation as a fill level
    with the remaining amount, its as-of date and the institutions it covers
    on the basis line, and its composition beside it; no threshold colouring,
    because a used-up allowance is a tax year's normal end state;
  - what is wrong with the budget — a stale as-of, a missing institution — is
    a **data note** beside the meter with the remedy control inside;
  - the recorded statements are a **list**, each carrying its consistency
    findings as data notes with the check control inside, and the row's
    actions (correct, delete) in its row menu;
  - both entry forms sit behind a **disclosure**, closed by default; the
    configured allowance orders sit behind one carrying their purpose line.

  Three display rules bind the figures: the pots render with the
  **statement's printed sign** so a row is visually comparable to the paper
  while storage stays positive magnitudes (§2); the trim budget is always
  stated **with its as-of date** and marked stale once a later day exists in
  which investment income can have landed (§5); advisories are fact plus
  remedy, terse and impersonal, and domain terms sit behind ⓘ tooltips
  (UX-DR11) rather than permanently in the sightline.

  The scope — taxpayer and tax year — is URL-addressable (`?holder=…&year=…`);
  the segmented controls patch it. Nothing here is derived from holdings, and
  nothing here is tax advice — the recorded statement remains the authority.
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

  # ADR-0031 records German broker statements; every figure is a euro amount.
  @currency "EUR"

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()

    socket =
      socket
      |> assign(:current_path, "/tax")
      |> assign(:today, today)
      |> assign(:currency, @currency)
      |> assign(:form_errors, nil)
      |> assign(:order_errors, nil)
      |> assign(:editing_id, nil)
      |> assign(:statement_form_open?, false)
      |> assign(:order_form_open?, false)
      |> assign(:row_menu, nil)

    {:ok, socket}
  end

  # The scope is URL-addressable (issue 795): the segmented controls patch
  # `?holder=…&year=…`, and a patch to the current scope re-reads it.
  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(:holder, scope_holder(params["holder"]))
      |> assign(:tax_year, parse_int(params["year"]) || socket.assigns.today.year - 1)
      |> assign(:editing_id, nil)
      |> assign(:row_menu, nil)
      |> load_year()

    {:noreply, socket}
  end

  @impl true
  def handle_event("open_statement_form", _params, socket) do
    {:noreply,
     assign(socket, statement_form_open?: true, editing_id: nil, form_errors: nil)
     |> load_editing()}
  end

  def handle_event("toggle_form", %{"form" => "statement"}, socket) do
    open? = not socket.assigns.statement_form_open?

    {:noreply,
     socket
     |> assign(:statement_form_open?, open?)
     |> assign(:editing_id, if(open?, do: socket.assigns.editing_id))
     |> assign(:form_errors, nil)
     |> load_editing()}
  end

  def handle_event("toggle_form", %{"form" => "order"}, socket) do
    {:noreply,
     assign(socket, order_form_open?: not socket.assigns.order_form_open?, order_errors: nil)}
  end

  def handle_event("record_statement", %{"statement" => params}, socket) do
    case save_statement(socket, params) do
      {:ok, snapshot} ->
        socket =
          socket
          |> assign(form_errors: nil, editing_id: nil, statement_form_open?: false)
          |> push_patch(to: scope_path(snapshot.holder, snapshot.tax_year))

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form_errors, changeset_errors(changeset))}
    end
  end

  def handle_event("edit_statement", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(editing_id: parse_int(id), form_errors: nil)
     |> assign(statement_form_open?: true, row_menu: nil)
     |> load_editing()}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(editing_id: nil, form_errors: nil, statement_form_open?: false)
     |> load_editing()}
  end

  def handle_event("delete_statement", %{"id" => id}, socket) do
    # Already deleted elsewhere (other tab, API, MCP) is not an error — the row
    # is gone either way.
    case Tax.delete_snapshot(Actor.owner_ui(), parse_int(id)) do
      {:ok, _snapshot} -> :ok
      {:error, :not_found} -> :ok
    end

    {:noreply, socket |> assign(editing_id: nil, row_menu: nil) |> load_year()}
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
        {:noreply, socket |> assign(order_errors: nil, order_form_open?: false) |> load_year()}

      {:error, changeset} ->
        {:noreply, assign(socket, :order_errors, changeset_errors(changeset))}
    end
  end

  def handle_event("delete_allowance_order", %{"id" => id}, socket) do
    case Tax.delete_allowance_order(Actor.owner_ui(), parse_int(id)) do
      {:ok, _order} -> :ok
      {:error, :not_found} -> :ok
    end

    {:noreply, socket |> assign(:row_menu, nil) |> load_year()}
  end

  # The row menu (Part 4 rule 11 of the 2026-09-12 review): correct and
  # delete for a statement, delete for an order; one menu open at a time.
  def handle_event("open_row_menu", %{"kind" => kind, "id" => id}, socket) do
    menu =
      case {kind, parse_int(id)} do
        {"statement", id} when is_integer(id) ->
          if Enum.any?(socket.assigns.snapshots, &(&1.row.id == id)), do: {:statement, id}

        {"order", id} when is_integer(id) ->
          if Enum.any?(socket.assigns.orders, &(&1.id == id)), do: {:order, id}

        _other ->
          nil
      end

    {:noreply, assign(socket, :row_menu, menu)}
  end

  def handle_event("close_row_menu", _params, socket) do
    {:noreply, assign(socket, :row_menu, nil)}
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

  # The form carries its own taxpayer and year (defaulting to the scope), so
  # a first statement for a new taxpayer or an older year is recordable
  # without a scope control that lists it.
  defp statement_attrs(socket, params) do
    money =
      Map.new(StatementSnapshot.money_fields(), fn field ->
        {field, blank_to_zero(params[Atom.to_string(field)])}
      end)

    Map.merge(money, %{
      institution: params["institution"],
      holder: form_holder(params["holder"]) || socket.assigns.holder,
      tax_year: parse_int(params["tax_year"]) || socket.assigns.tax_year,
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
    %{holder: holder, tax_year: tax_year, today: today} = socket.assigns

    snapshots = Tax.list_snapshots(holder: holder, tax_year: tax_year)
    summary = Tax.holder_summary(holder, tax_year)

    socket
    |> assign(:snapshots, Enum.map(snapshots, &%{row: &1, findings: Tax.findings_for(&1)}))
    |> assign(:summary, summary)
    |> assign(:utilisation, utilisation(summary))
    # Activity-aware staleness (issue #667): warns on age over the threshold
    # OR tax-relevant bookings since the statement — never on the mere
    # passage of a day.
    |> assign(:staleness, Tax.staleness(summary.as_of, today))
    |> assign(:orders, Tax.list_allowance_orders(holder: holder, tax_year: tax_year))
    |> assign(:holders, holders(holder))
    |> assign(:years, years(holder, tax_year, today))
    |> load_editing()
  end

  defp load_editing(socket) do
    editing =
      case socket.assigns.editing_id do
        nil -> nil
        id -> Enum.find_value(socket.assigns.snapshots, &(&1.row.id == id && &1.row))
      end

    assign(socket, :editing, editing)
  end

  # The meter's fill: allowance used over allowance granted, in whole
  # percent, clamped — no threshold colouring, the fill level is the fact.
  defp utilisation(%{allowance_granted: granted, allowance_used: used}) do
    if Decimal.compare(granted, 0) == :gt do
      used
      |> Decimal.div(granted)
      |> Decimal.mult(100)
      |> Decimal.round(0)
      |> Decimal.to_integer()
      |> max(0)
      |> min(100)
    else
      0
    end
  end

  # The taxpayers with a recorded statement, plus the one in scope.
  defp holders(holder) do
    [holder | Tax.list_snapshot_holders()] |> Enum.uniq() |> Enum.sort()
  end

  # The years with a recorded statement for the taxpayer, the two years a
  # statement can currently arrive for, and the one in scope.
  defp years(holder, tax_year, today) do
    recorded = Tax.list_snapshots(holder: holder) |> Enum.map(& &1.tax_year)

    ([tax_year, today.year - 1, today.year] ++ recorded)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # The form's taxpayer field: a blank one means "the scope's holder", which
  # the caller supplies — unlike the URL scope, which falls back to the
  # default holder.
  defp form_holder(holder) when is_binary(holder) do
    case String.trim(holder) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp form_holder(_holder), do: nil

  defp scope_holder(nil), do: default_holder()

  defp scope_holder(holder) when is_binary(holder) do
    case String.trim(holder) do
      "" -> default_holder()
      trimmed -> trimmed
    end
  end

  defp scope_path(holder, year), do: "/tax?holder=#{URI.encode_www_form(holder)}&year=#{year}"

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

  # Several figures of one kind on one line, each with its printed sign.
  defp printed_group(row, fields) do
    Enum.map_join(fields, " / ", &printed(&1, Map.fetch!(row, &1)))
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

  # Every recorded source has a label; a raw value never reaches the row
  # (Part 4 rule 7 of the 2026-09-12 review).
  defp source_label("manual"), do: gettext("recorded manually")
  defp source_label("pdf_import"), do: gettext("from a PDF import")
  defp source_label(_other), do: gettext("recorded")

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

  # The remedy control inside a finding's note: the statement's own figures
  # are checked on the correction form; an order finding (c7, c8) is settled
  # on the orders form.
  defp order_finding?(%{code: code}), do: code in [:c7, :c8]

  defp invalid?(nil, _field), do: false
  defp invalid?(errors, field), do: Map.has_key?(errors, field)

  # A money input is described by the sign convention, and by the error
  # note while it is invalid.
  defp amount_describedby(errors, field) do
    if invalid?(errors, field), do: "tax-amount-help tax-form-error", else: "tax-amount-help"
  end

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

  defp orders_summary([]), do: gettext("none configured")

  defp orders_summary(orders) do
    Enum.map_join(orders, " · ", &"#{&1.institution} #{Format.money(&1.amount_granted)}")
  end

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

        <section class="workspace-section" id="tax-budget">
          <header class="section-head">
            <h2><%= gettext("Tax-free trim budget") %></h2>
            <%!-- Taxpayer and year as segmented controls (UX-DR16 class 2,
                 issue 795); each option patches the URL-addressable scope. --%>
            <div class="section-head-controls" data-role="tax-scope">
              <nav class="segmented-control" data-role="tax-holders" aria-label={gettext("Taxpayer")}>
                <.link
                  :for={holder <- @holders}
                  patch={scope_path(holder, @tax_year)}
                  class={["segmented-control__option", holder == @holder && "is-active"]}
                  aria-current={if holder == @holder, do: "true"}
                >
                  <%= holder %>
                </.link>
              </nav>
              <nav class="segmented-control" data-role="tax-years" aria-label={gettext("Tax year")}>
                <.link
                  :for={year <- @years}
                  patch={scope_path(@holder, year)}
                  class={["segmented-control__option", year == @tax_year && "is-active"]}
                  aria-current={if year == @tax_year, do: "true"}
                >
                  <%= year %>
                </.link>
              </nav>
            </div>
          </header>

          <div class="tax-budget-grid">
            <%!-- The budget meter (DESIGN.md → components.budget-meter): the
                 remaining amount as the value, the allowance fill level as a
                 decorative track, the as-of and the institutions on the basis
                 line. No threshold colouring — a used-up allowance is a tax
                 year's normal end state, not a warning. --%>
            <article class="stat tax-budget" data-role="budget-meter">
              <span><%= gettext("Tax-free trim budget") %></span>
              <strong data-role="budget-value">
                <%= Format.money(@summary.tax_free_trim_budget) %>
                <small class="value-suffix"><%= @currency %></small>
              </strong>
              <div class="budget-meter" aria-hidden="true">
                <div class="budget-meter__fill" style={"width: #{@utilisation}%"}></div>
              </div>
              <p class="summary-basis" data-role="budget-basis">
                <%= if @summary.as_of do %>
                  <%= gettext("Allowance %{used} of %{granted} used",
                    used: Format.money(@summary.allowance_used),
                    granted: Format.money(@summary.allowance_granted)
                  ) %>
                  · <%= gettext("as of %{date}", date: Date.to_iso8601(@summary.as_of)) %>
                  <span :if={@summary.institutions != []}>
                    · <%= Enum.join(@summary.institutions, ", ") %>
                  </span>
                <% else %>
                  <%= gettext("No statement recorded for this year.") %>
                <% end %>
              </p>
              <%!-- What is wrong with the budget is a data note beside the
                   meter with its remedy inside (UX-DR17); one status region
                   for both. --%>
              <div class="tax-budget__notes" role="status">
                <AppShell.data_note
                  :if={@staleness && @staleness.warning}
                  severity={:attention}
                  data-role="budget-stale"
                >
                  <%= staleness_message(@staleness) %>
                  <button type="button" class="link-button" phx-click="open_statement_form">
                    <%= gettext("Record a new statement") %>
                  </button>
                </AppShell.data_note>
                <AppShell.data_note
                  :if={not @summary.complete?}
                  severity={:attention}
                  data-role="budget-incomplete"
                >
                  <%= gettext(
                    "Incomplete: no statement recorded for %{institutions}. The total covers the listed institutions only.",
                    institutions: Enum.join(@summary.missing_institutions, ", ")
                  ) %>
                </AppShell.data_note>
              </div>
            </article>

            <article class="stat tax-composition" data-role="budget-composition">
              <span>
                <%= gettext("Composition") %>
                <details class="metric-tooltip metric-tooltip--inline" data-role="budget-info">
                  <summary aria-label={gettext("About this figure")}>ⓘ</summary>
                  <p role="tooltip">
                    <%= gettext(
                      "These pots are transcribed from the broker statement, never computed from the ledger. Not for want of FIFO — lots are matched FIFO already, on the trade list — but that yields a gross gain, and a gross gain is not a tax pot. Teilfreistellung, Vorabpauschale, chronological allowance consumption and prior-year carry-forward are absent from transaction data, and the pots are kept per institution. The statement remains the authority. This is not tax advice."
                    ) %>
                  </p>
                </details>
              </span>
              <dl class="tax-composition__rows">
                <div>
                  <dt><%= gettext("Loss pot, equities") %></dt>
                  <dd><%= Format.money(@summary.loss_pot_equities) %></dd>
                </div>
                <div>
                  <dt><%= gettext("Remaining allowance") %></dt>
                  <dd><%= Format.money(@summary.allowance_remaining) %></dd>
                </div>
                <div class="is-total">
                  <dt><%= gettext("Trim budget") %></dt>
                  <dd><%= Format.money(@summary.tax_free_trim_budget) %></dd>
                </div>
                <div :if={@summary.allowance_ceiling}>
                  <dt><%= gettext("Statutory ceiling %{year}", year: @tax_year) %></dt>
                  <dd><%= Format.money(@summary.allowance_ceiling) %></dd>
                </div>
              </dl>
            </article>
          </div>
        </section>

        <section class="workspace-section" id="tax-statements">
          <header class="section-head">
            <h2><%= gettext("Recorded statements") %></h2>
            <%!-- Both forms behind a disclosure, closed by default. --%>
            <div class="section-head-controls" data-role="tax-disclosures">
              <button
                type="button"
                class="button-ghost disclosure-button"
                phx-click="toggle_form"
                phx-value-form="statement"
                aria-expanded={to_string(@statement_form_open?)}
                aria-controls="tax-statement-panel"
              >
                <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
                <%= if @editing, do: gettext("Correct statement"), else: gettext("Record a statement") %>
              </button>
              <button
                type="button"
                class="button-ghost disclosure-button"
                phx-click="toggle_form"
                phx-value-form="order"
                aria-expanded={to_string(@order_form_open?)}
                aria-controls="tax-order-panel"
              >
                <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
                <%= gettext("Record an allowance order") %>
              </button>
            </div>
          </header>

          <div id="tax-statement-panel" class="tax-panel" hidden={not @statement_form_open?}>
            <AppShell.data_note :if={@form_errors} severity={:problem} id="tax-form-error" role="alert">
              <%= error_text(@form_errors) %>
            </AppShell.data_note>

            <form id="tax-statement-form" phx-submit="record_statement" class="tax-form">
              <label>
                <%= gettext("Taxpayer") %>
                <input
                  type="text"
                  name="statement[holder]"
                  value={(@editing && @editing.holder) || @holder}
                  list="tax-holders"
                  required
                />
                <datalist id="tax-holders">
                  <option :for={holder <- @holders} value={holder}></option>
                </datalist>
              </label>
              <label>
                <%= gettext("Tax year") %>
                <input
                  type="number"
                  name="statement[tax_year]"
                  value={(@editing && @editing.tax_year) || @tax_year}
                  min="1990"
                  max="2200"
                  required
                />
              </label>
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

              <%!-- The sign convention is field help on the amounts; the
                   term sits behind its ⓘ (UX-DR11 inventory, tax_live rows). --%>
              <fieldset class="tax-form__amounts">
                <legend>
                  <%= gettext("Figures on the statement") %>
                  <details class="metric-tooltip metric-tooltip--inline" data-role="loss-pot-info">
                    <summary aria-label={gettext("About loss pots")}>ⓘ</summary>
                    <p role="tooltip">
                      <%= gettext("A loss pot is the volume of loss available for offsetting.") %>
                    </p>
                  </details>
                </legend>
                <p id="tax-amount-help" class="hint field-help">
                  <%= gettext("Amounts without their sign; an empty field counts as zero.") %>
                </p>
                <label :for={field <- StatementSnapshot.money_fields()}>
                  <%= field_label(field) %>
                  <input
                    type="text"
                    inputmode="decimal"
                    name={"statement[#{field}]"}
                    value={value_of(@editing, field)}
                    aria-invalid={invalid?(@form_errors, field) && "true"}
                    aria-describedby={amount_describedby(@form_errors, field)}
                  />
                </label>
              </fieldset>

              <label class="tax-form__wide">
                <%= gettext("Note") %>
                <input type="text" name="statement[note]" value={@editing && @editing.note} />
              </label>

              <div class="tax-form__actions">
                <button type="submit" class="button">
                  <%= if @editing, do: gettext("Save correction"), else: gettext("Record statement") %>
                </button>
                <button type="button" class="button button-secondary" phx-click="cancel_edit">
                  <%= gettext("Cancel") %>
                </button>
              </div>
            </form>
          </div>

          <div id="tax-order-panel" class="tax-panel" hidden={not @order_form_open?}>
            <AppShell.data_note :if={@order_errors} severity={:problem} role="alert">
              <%= error_text(@order_errors) %>
            </AppShell.data_note>

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
          </div>

          <p :if={@snapshots == []} class="hint" data-role="statements-empty">
            <%= gettext("No statement recorded for this taxpayer and year.") %>
          </p>

          <ul :if={@snapshots != []} class="tax-statements" role="list">
            <li :for={entry <- @snapshots} class="tax-statement" id={"tax-statement-#{entry.row.id}"}>
              <div class="tax-statement__head">
                <h3><%= entry.row.institution %></h3>
                <span class="hint">
                  <%= Date.to_iso8601(entry.row.as_of) %>
                  · <%= gettext("Tax year %{year}", year: entry.row.tax_year) %>
                  · <%= source_label(entry.row.source) %>
                </span>
                <button
                  type="button"
                  id={"tax-row-kebab-statement-#{entry.row.id}"}
                  class="row-actions__kebab"
                  phx-click="open_row_menu"
                  phx-value-kind="statement"
                  phx-value-id={entry.row.id}
                  aria-label={gettext("Open actions menu")}
                  aria-haspopup="menu"
                  aria-expanded={@row_menu == {:statement, entry.row.id}}
                >
                  <AppShell.icon name={:ellipsis_vertical} />
                </button>
              </div>

              <dl class="tax-statement__figures">
                <div>
                  <dt><%= field_label(:taxable_income) %></dt>
                  <dd><%= printed(:taxable_income, entry.row.taxable_income) %></dd>
                </div>
                <div>
                  <dt><%= gettext("Allowance granted / used") %></dt>
                  <dd><%= printed_group(entry.row, [:allowance_granted, :allowance_used]) %></dd>
                </div>
                <div>
                  <dt><%= gettext("Loss pots: equities / other / carry-forward") %></dt>
                  <dd>
                    <%= printed_group(entry.row, [
                      :loss_pot_equities,
                      :loss_pot_other,
                      :loss_carryforward_prior_years
                    ]) %>
                  </dd>
                </div>
                <div>
                  <dt><%= gettext("Foreign withholding: pot / credited") %></dt>
                  <dd>
                    <%= printed_group(entry.row, [:withholding_tax_pot, :withholding_tax_credited]) %>
                  </dd>
                </div>
                <div>
                  <dt><%= gettext("Withheld: capital-gains tax / solidarity surcharge / church tax") %></dt>
                  <dd>
                    <%= printed_group(entry.row, [
                      :capital_gains_tax_withheld,
                      :solidarity_surcharge_withheld,
                      :church_tax_withheld
                    ]) %>
                  </dd>
                </div>
              </dl>

              <p class="summary-basis">
                <%= gettext("Tax-free trim budget at this institution: %{value}.",
                  value: Format.money(Budget.tax_free_trim_budget(entry.row))
                ) %>
              </p>

              <%!-- Each consistency finding is a data note with the check
                   control inside (UX-DR17); one status region per row. --%>
              <div :if={entry.findings != []} class="tax-statement__notes" role="status">
                <AppShell.data_note
                  :for={finding <- entry.findings}
                  severity={:attention}
                  data-role="statement-finding"
                >
                  <%= finding_text(finding) %>
                  <%= if order_finding?(finding) do %>
                    <button type="button" class="link-button" phx-click="toggle_form" phx-value-form="order">
                      <%= gettext("Adjust the allowance orders") %>
                    </button>
                  <% else %>
                    <button
                      type="button"
                      class="link-button"
                      phx-click="edit_statement"
                      phx-value-id={entry.row.id}
                    >
                      <%= gettext("Check against the statement") %>
                    </button>
                  <% end %>
                </AppShell.data_note>
              </div>

              <p :if={entry.row.note} class="hint"><%= entry.row.note %></p>
            </li>
          </ul>

          <%!-- The configured orders behind a disclosure carrying their
               purpose line (UX-DR11 inventory, tax_live.ex:502). --%>
          <details class="tax-orders-disclosure" data-role="orders">
            <summary class="disclosure-summary">
              <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
              <%= gettext("Configured allowance orders") %> · <%= orders_summary(@orders) %>
            </summary>
            <p class="summary-basis">
              <%= gettext(
                "What was instructed per institution, for comparison against what the bank applied."
              ) %>
            </p>
            <ul :if={@orders != []} class="tax-orders" role="list">
              <li :for={order <- @orders} id={"tax-order-#{order.id}"}>
                <span><%= order.institution %></span>
                <span class="num"><%= Format.money(order.amount_granted) %></span>
                <button
                  type="button"
                  id={"tax-row-kebab-order-#{order.id}"}
                  class="row-actions__kebab"
                  phx-click="open_row_menu"
                  phx-value-kind="order"
                  phx-value-id={order.id}
                  aria-label={gettext("Open actions menu")}
                  aria-haspopup="menu"
                  aria-expanded={@row_menu == {:order, order.id}}
                >
                  <AppShell.icon name={:ellipsis_vertical} />
                </button>
              </li>
            </ul>
          </details>
        </section>
      </div>

      <.row_menu :if={@row_menu} menu={@row_menu} />
    </AppShell.shell>
    """
  end

  # The row menu: the shared shell, positioned on its kebab.
  attr(:menu, :any, required: true)

  defp row_menu(%{menu: {:statement, id}} = assigns) do
    assigns = assign(assigns, :id, id)

    ~H"""
    <AppShell.row_menu
      id={"tax-row-menu-statement-#{@id}"}
      trigger={"tax-row-kebab-statement-#{@id}"}
      label={gettext("Statement actions")}
    >
      <button
        type="button"
        class="row-context-menu__item"
        role="menuitem"
        phx-click="edit_statement"
        phx-value-id={@id}
      >
        <AppShell.icon name={:edit} />
        <span><%= gettext("Correct") %></span>
      </button>
      <button
        type="button"
        class="row-context-menu__item row-context-menu__item--danger"
        role="menuitem"
        phx-click="delete_statement"
        phx-value-id={@id}
        data-confirm={gettext("Delete this recorded statement?")}
      >
        <AppShell.icon name={:trash} />
        <span><%= gettext("Delete") %></span>
      </button>
    </AppShell.row_menu>
    """
  end

  defp row_menu(%{menu: {:order, id}} = assigns) do
    assigns = assign(assigns, :id, id)

    ~H"""
    <AppShell.row_menu
      id={"tax-row-menu-order-#{@id}"}
      trigger={"tax-row-kebab-order-#{@id}"}
      label={gettext("Allowance order actions")}
    >
      <button
        type="button"
        class="row-context-menu__item row-context-menu__item--danger"
        role="menuitem"
        phx-click="delete_allowance_order"
        phx-value-id={@id}
        data-confirm={gettext("Delete this allowance order?")}
      >
        <AppShell.icon name={:trash} />
        <span><%= gettext("Delete") %></span>
      </button>
    </AppShell.row_menu>
    """
  end
end
