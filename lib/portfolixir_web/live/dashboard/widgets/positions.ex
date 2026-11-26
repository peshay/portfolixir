defmodule PortfolixirWeb.Dashboard.Widgets.Positions do
  @moduledoc """
  The section widget „Positionen“ `positions` (I57; Sprint 32 W1;
  ADR-0062's amendment of 2026-11-25, point 3; planning board
  `ux-design-2026-11-25-sprint32/02` ①): Wealth's section „Positions“ of
  the tab „Bestände“ (#814), moved here so that one code path draws it on
  Wealth (`picker/1` and `table/1`, which `PortfolixirWeb.PortfolioLive`
  renders) and on a dashboard (`widget/1`).

  The rows are the holdings projection the API answers per portfolio
  (`Portfolixir.Ledger.holdings_for_portfolio/1`, `GET
  /api/v1/portfolios/:portfolio_id/holdings`), narrowed to the scope as the
  view valuation narrows its positions (`rows/1`), the market value the
  view valuation's own for the same depot and security (`put_base_values/3`,
  `GET /api/v1/valuation`). The column picker is the human half of the
  API's `fields=`; the choice is the browser's, under Wealth's key
  (`storage_key/0`), so Wealth and every dashboard show the columns picked
  once.

    * **Zeile** — the section as Wealth draws it, its picker in the head;
    * **compact** — the phone rows Wealth draws under 560 px: the name
      over the depot, the quantity at the right.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Buckets
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Valuation
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.ColumnPicker
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.PrivacyMode
  alias PortfolixirWeb.SecurityNames
  alias PortfolixirWeb.TransactionManagementLive

  # #814: the columns are the API's own (`Ledger.holdings_for_portfolio/1`
  # through `JSON.holding_fields/0`), so the picker offers the figures an
  # agent reads rather than a second calculation.
  @defaults ["depot", "security", "quantity"]

  # The one place the key is written: the hook restores from the table's
  # `data-storage-key` and the handler pushes to it, and a picker that only
  # ever reads the key is a preference that silently never persists.
  @storage_key "wealth.holdings.columns"

  @column_keys @defaults ++
                 ~w(isin wkn currency avg_cost latest_price market_value unrealized_pnl_abs unrealized_pnl_pct)

  @doc "The columns shown before a pick: depot, security, quantity."
  @spec default_columns() :: [String.t()]
  def default_columns, do: @defaults

  @doc "The browser key the picked columns are kept under, Wealth's."
  @spec storage_key() :: String.t()
  def storage_key, do: @storage_key

  @doc """
  The columns a pick names, in the picker's order: only known keys; an
  empty pick falls back to the defaults rather than a table with no
  columns.
  """
  @spec choose([term()]) :: [String.t()]
  def choose(columns) when is_list(columns) do
    case Enum.filter(@column_keys, &(&1 in columns)) do
      [] -> @defaults
      picked -> picked
    end
  end

  @doc """
  The widget's read for the scope `view_id` (`nil`: Everything), in the
  page's background task: the rows with their market value in the first
  portfolio's base currency, as Wealth reads them, and that currency. A
  view that vanished meanwhile reads Everything.
  """
  @spec read(integer() | nil) :: %{rows: [map()], base_currency: String.t()}
  def read(view_id) do
    base_currency =
      case Portfolios.first_portfolio() do
        %{base_currency_code: code} -> code
        nil -> "EUR"
      end

    {view_id, rows} =
      case rows(view_id) do
        {:ok, rows} -> {view_id, rows}
        {:error, :view_not_found} -> {nil, elem(rows(nil), 1)}
      end

    valuation =
      case Valuation.for_view(view_id, base_currency: base_currency) do
        %{} = valuation -> valuation
        _refused -> nil
      end

    %{rows: put_base_values(rows, valuation, base_currency), base_currency: base_currency}
  end

  @doc "The picker's groups (#850), every column key in exactly one."
  @spec column_groups() :: [{String.t(), [{String.t(), String.t()}]}]
  def column_groups do
    [
      {gettext("Position"), ~w(depot security quantity)},
      {gettext("Identifiers"), ~w(isin wkn)},
      {gettext("Valuation"),
       ~w(currency avg_cost latest_price market_value unrealized_pnl_abs unrealized_pnl_pct)}
    ]
    |> Enum.map(fn {legend, keys} ->
      {legend, Enum.map(keys, &{&1, holdings_column_label(&1)})}
    end)
  end

  # #1124 (Sprint 20 plan D-8): the rows read the scope the page reads
  # (ADR-0024) — the active view's positions across every portfolio,
  # Everything when none is picked — narrowed exactly as the view valuation
  # narrows its positions, so a holding the page's totals and notes count is
  # a row here. A view gone since the page resolved it degrades the page to
  # Everything, the way every other section's read does.
  # The rows are the API's projection, each portfolio's own, decorated with
  # the depot's name so the human column reads as a name where the payload
  # carries an id.
  @spec rows(integer() | nil) :: {:ok, [map()]} | {:error, :view_not_found}
  def rows(view_id) do
    with scope when not is_tuple(scope) <- Buckets.load_global_scope(view_id) do
      names = Map.new(Portfolios.list_securities_accounts(), &{&1.id, &1.name})

      rows =
        Portfolios.list_portfolios()
        |> Enum.flat_map(&Ledger.holdings_for_portfolio(&1.id))
        |> Enum.filter(
          &Buckets.position_in_scope?(scope, &1.securities_account_id, &1.security_id)
        )
        |> Enum.map(fn row ->
          Map.put(
            row,
            :securities_account_name,
            Map.get(names, row.securities_account_id, gettext("Unknown depot"))
          )
        end)
        |> Enum.sort_by(&{&1.securities_account_name, &1.security_name})
        # #1057 (pick J6.2 A): a name collides over the whole table — depot
        # names may read alike, the Depot column may be off; one security
        # never does.
        |> SecurityNames.put_twin_ids(& &1.security_name)

      {:ok, rows}
    end
  end

  # #1332 and the D-9 finding (board 02 ①): the Marktwert column is the
  # base-currency figure the page's total sums — the view valuation's own
  # `market_value` for the same (depot, security), the row and the total
  # priced and converted by one function (`Valuation`), a USD row at the
  # latest stored rate. Until that read lands, a row already in the base
  # currency reads its own value (the same price, no conversion); any other
  # waits for the valuation and reads "—", never a figure in another
  # currency under a total it does not add to.
  @spec put_base_values([map()], map() | nil, String.t()) :: [map()]
  def put_base_values(rows, valuation, base_currency) do
    {positions, base} = valuation_positions(valuation, base_currency)

    Enum.map(rows, fn row ->
      {base_value, reason} =
        case Map.fetch(positions, {row.securities_account_id, row.security_id}) do
          {:ok, position} -> {position.market_value, Map.get(position, :unvalued_reason)}
          :error -> {own_base_value(row, base), nil}
        end

      Map.merge(row, %{
        base_market_value: base_value,
        base_market_currency: base,
        base_unvalued_reason: reason
      })
    end)
  end

  defp valuation_positions(%{positions: positions, base_currency: base}, _base_currency) do
    {Map.new(positions, &{{&1.securities_account_id, &1.security_id}, &1}), base}
  end

  # The valuation is read in the page's base currency; until it lands, the
  # rows name that currency.
  defp valuation_positions(_none, base_currency), do: {%{}, base_currency}

  defp own_base_value(%{currency_code: code, market_value: value}, code), do: value
  defp own_base_value(_row, _base), do: nil

  defp holdings_num_attrs(key)
       when key in ~w(quantity avg_cost latest_price market_value unrealized_pnl_abs unrealized_pnl_pct),
       do: %{class: "num"}

  # #1322 (#1366 line 3; board ux-design-2026-11-05-sprint24-p1): the
  # Security column's head and cells carry `cell-name`, the class its
  # floor and its break key on, wherever the picker puts the column.
  defp holdings_num_attrs("security"), do: %{class: "cell-name"}

  defp holdings_num_attrs(_key), do: %{}

  # Board ux-design-2026-10-07/02-money-findings, found while drawing 4: the
  # "P&L %" cell is a percentage in DESIGN.md's form, so it carries its sign
  # colour, decided on the percent as shown (issue 1010's rule: every signed
  # cell of a data table). A position on no cost (#1142) is the muted reason
  # dash, its reason in the cell's title (#1089's anatomy).
  defp holdings_cell_attrs(row, "unrealized_pnl_pct" = key) do
    if holdings_return_absent?(row) do
      %{class: "num trade-pa--na", title: gettext("No return: no cost basis")}
    else
      case Format.displayed_percent_sign(row.unrealized_pnl_pct) do
        :positive -> %{class: "num is-positive"}
        :negative -> %{class: "num is-negative"}
        :zero -> %{class: "num is-flat"}
        nil -> holdings_num_attrs(key)
      end
    end
  end

  # #1125 (board 04, found while drawing 1): "P&L" is a signed figure, so it
  # carries its sign colour, decided on the figure as displayed (#1149).
  defp holdings_cell_attrs(row, "unrealized_pnl_abs") do
    case Format.displayed_sign(row.unrealized_pnl_abs, 2) do
      :positive -> %{class: "num is-positive"}
      :negative -> %{class: "num is-negative"}
      :zero -> %{class: "num is-flat"}
      nil -> holdings_num_attrs("unrealized_pnl_abs")
    end
  end

  defp holdings_cell_attrs(_row, key), do: holdings_num_attrs(key)

  defp holdings_column_label("depot"), do: gettext("Depot")
  defp holdings_column_label("security"), do: gettext("Security")
  defp holdings_column_label("quantity"), do: gettext("Quantity")
  defp holdings_column_label("isin"), do: gettext("ISIN")
  defp holdings_column_label("wkn"), do: gettext("WKN")
  defp holdings_column_label("currency"), do: gettext("Currency")
  defp holdings_column_label("avg_cost"), do: gettext("Avg cost")
  defp holdings_column_label("latest_price"), do: gettext("Latest price")
  defp holdings_column_label("market_value"), do: gettext("Market value")
  defp holdings_column_label("unrealized_pnl_abs"), do: gettext("P&L")
  defp holdings_column_label("unrealized_pnl_pct"), do: gettext("P&L %")

  defp holdings_cell(row, "depot"), do: row.securities_account_name
  defp holdings_cell(row, "security"), do: row.security_name
  defp holdings_cell(row, "quantity"), do: holdings_decimal(row.quantity)
  defp holdings_cell(row, "isin"), do: row.isin
  defp holdings_cell(row, "wkn"), do: row.wkn
  defp holdings_cell(row, "currency"), do: row.currency_code
  # #1125 (board 04, pick N5 A; ADR-0016 §4): money at the human boundary
  # is two places, a price per unit the history's stored figure (R10c) — so
  # Wealth, the Kurse tab and the history print one stored quote alike — and
  # a signed P&L carries its "+". The API and MCP serve every digit.
  defp holdings_cell(row, "avg_cost"), do: holdings_price(row.avg_cost)
  defp holdings_cell(row, "latest_price"), do: holdings_price(row.latest_price)
  defp holdings_cell(row, "market_value"), do: Format.money(row.base_market_value)

  defp holdings_cell(row, "unrealized_pnl_abs"),
    do: Format.signed_decimal(row.unrealized_pnl_abs, 2)

  # Found while drawing 4 (board 02): a percentage, not the raw fraction —
  # DESIGN.md's percent form, one decimal with the sign and "%" glued on
  # ("+18,7%"), where it printed every digit of 0.1871… under a "%" header.
  # #1142 (board 02): a position on no cost has no return, so the cell is
  # the dash, aria-hidden, with its reason for the screen reader.
  defp holdings_cell(row, "unrealized_pnl_pct") do
    if holdings_return_absent?(row) do
      assigns = %{sentence: gettext("no return, no cost basis")}

      ~H"""
      <span aria-hidden="true">—</span><span class="visually-hidden"><%= @sentence %></span>
      """
    else
      holdings_percent(row.unrealized_pnl_pct)
    end
  end

  # A quantity keeps the projection's own digits (#1125 leaves them); the
  # separators are the reader's — `1234.5` beside a neighbouring table's
  # `1.234,50` is the page disagreeing with itself for no gain. An absent
  # value is an em dash rather than a blank cell.
  defp holdings_decimal(nil), do: "—"

  defp holdings_decimal(%Decimal{} = value), do: PortfolixirWeb.Format.exact(value)

  defp holdings_decimal(value), do: to_string(value)

  defp holdings_price(%Decimal{} = price), do: TransactionManagementLive.stored_figure(price)
  defp holdings_price(_none), do: "—"

  defp holdings_percent(%Decimal{} = fraction), do: Format.signed_percent(fraction) <> "%"
  defp holdings_percent(_none), do: "—"

  # #1142: a P&L with no percentage beside it is one on no cost — the ledger
  # leaves the percentage nil exactly where the cost basis is zero, and both
  # nil where there is no price.
  defp holdings_return_absent?(row),
    do: not is_nil(row.unrealized_pnl_abs) and is_nil(row.unrealized_pnl_pct)

  # The phone row's quantity (#1065): the table's own digits, with the
  # history's unit words — one unit is a unit, any other quantity units.
  defp holdings_units(%Decimal{} = quantity) do
    ngettext(
      "%{quantity} unit",
      "%{quantity} units",
      TransactionManagementLive.plural_count(quantity),
      quantity: holdings_decimal(quantity)
    )
  end

  defp holdings_units(quantity), do: holdings_decimal(quantity)

  # The money columns carry the row's own currency, because `currency` is an
  # opt-in column and a bare market value with no currency states less than
  # the payload it mirrors (EXPERIENCE.md → Voice and Tone: numbers state
  # their basis where it is cheap).
  defp holdings_money?(key), do: key in ~w(avg_cost latest_price market_value unrealized_pnl_abs)

  defp holdings_currency(row, key) do
    if holdings_money?(key) and holdings_cell(row, key) != "—", do: holdings_suffix(row, key)
  end

  # The market value is the base-currency figure (#1332, D-9); the price
  # and its P&L stay in the security's own currency.
  defp holdings_suffix(row, "market_value"), do: row.base_market_currency
  defp holdings_suffix(row, _key), do: row.currency_code

  # #1332 (board 02 ①): the price cell's second line names a price that is
  # not a quote, and a row with no price says it is in no total.
  defp holdings_cell_note(%{price_source: :trade} = row, "latest_price"),
    do: gettext("Trade price · %{date}", date: Format.date(row.price_date))

  defp holdings_cell_note(%{latest_price: nil}, "latest_price"),
    do: gettext("no price · not in the total")

  # The closing act (S3): a priced row whose market value is "—" because no
  # exchange rate reaches the base currency says so, as the no-price row
  # does; the valuation's own reason, so a row still waiting for the read
  # carries no note.
  defp holdings_cell_note(%{base_unvalued_reason: :missing_fx}, "market_value"),
    do: gettext("no exchange rate · not in the total")

  defp holdings_cell_note(_row, _key), do: nil

  # A note's first phrase, up to its first " · ", and the rest with that
  # separator: the first never breaks (#1366, board 02 ①).
  defp note_lead(note), do: note |> String.split(" · ", parts: 2) |> hd()

  defp note_rest(note) do
    case String.split(note, " · ", parts: 2) do
      [_lead, rest] -> " · " <> rest
      [_lead] -> ""
    end
  end

  # -- Wealth's section, moved ---------------------------------------------------

  attr(:prefix, :string, default: "holdings", doc: "the ids' prefix: Wealth's, or a widget's")
  attr(:rows, :list, required: true)
  attr(:columns, :list, required: true)
  attr(:picker_open?, :boolean, required: true)

  @doc "The column picker of Wealth's section „Positions“, in the section's head."
  def picker(assigns) do
    ~H"""
    <%!-- #850: the shared grouped popover (DESIGN.md → Overlays, pick
         E3). It sits in the head now that it opens over the table:
         the <details> it replaces had to live in the body flow,
         because opening it re-centred the heading. Not offered over
         an empty state — picking columns for a table that is not
         there is an offer with nothing behind it. --%>
    <div :if={@rows != []} class="popover-container">
      <ColumnPicker.toggle
        id={@prefix <> "-column-toggle"}
        open={@picker_open?}
        on_toggle="toggle_column_picker"
      />
      <ColumnPicker.picker
        :if={@picker_open?}
        id={@prefix <> "-column-picker"}
        form_id={@prefix <> "-column-form"}
        on_change="set_holdings_columns"
        on_close="close_column_picker"
        toggle_id={@prefix <> "-column-toggle"}
        groups={column_groups()}
        selected={@columns}
      />
    </div>
    """
  end

  attr(:prefix, :string, default: "holdings", doc: "the ids' prefix: Wealth's, or a widget's")
  attr(:rows, :list, required: true)
  attr(:columns, :list, required: true)
  attr(:base_currency, :string, required: true)
  attr(:storage_key, :string, default: @storage_key)

  @doc """
  The body of Wealth's section „Positions“: the basis line, the table in
  the picked columns and the phone rows under 560 px (#1065).
  """
  def table(assigns) do
    ~H"""
    <%!-- #1090 (board 08 ①): a basis line about the rows, in the
         screen's nouns. That the table is the API's own projection
         stays true and is said where it helps: the API guide and the
         column picker's grouping. --%>
    <%!-- #1332 (board 02 ①) and D-9: the rule the total uses, named,
         and the currency the market value is in. #1435 (4), L5
         (board ux-design-2026-11-12-sprint29/06 ⑤): one sentence on
         the line, what the total sums behind its ⓘ (I1). A `div`: a
         <details> is not phrasing content. --%>
    <div class="summary-basis" data-role="positions-basis">
      <%= gettext(
        "One row per depot and security, valued at the latest stored price or, without a quote, at the last own trade price."
      ) %>
      <AppShell.section_info>
        <:line>
          <%= gettext("Market value in %{currency}, the figure the total sums.",
            currency: @base_currency
          ) %>
        </:line>
      </AppShell.section_info>
    </div>
    <%= if @rows == [] do %>
      <div id={if @prefix == "holdings", do: "no-positions", else: @prefix <> "-none"} class="empty-state" role="status">
        <%= gettext("No holdings yet") %>
      </div>
    <% else %>
      <div
        id={@prefix <> "-positions-wrapper"}
        class="data-table-wrapper"
        phx-hook="ColumnPrefs"
        data-storage-key={@storage_key}
        data-restore-event="set_holdings_columns"
        data-current-columns={Jason.encode!(@columns)}
      >
        <table id={@prefix <> "-positions-table"} class="data-table">
          <thead>
            <tr>
              <th :for={key <- @columns} {holdings_num_attrs(key)}>
                <%= holdings_column_label(key) %>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={row <- @rows}
              data-role="holdings-position"
              data-security-id={row.security_id}
            >
              <%!-- #1125 (board 04, N5 A): a text space before the
                   suffix, as the contribution table's sum row has it,
                   so a cell reads "2.569,68 EUR". --%>
              <td
                :for={key <- @columns}
                data-column={key}
                {holdings_cell_attrs(row, key)}
              >
                <%!-- #1366 (board 02 ①, answer A): the depot on one
                     line, cut past 7rem, whole in its title. --%>
                <span
                  :if={key == "depot"}
                  class="cell-depot"
                  title={holdings_cell(row, key)}
                ><%= holdings_cell(row, key) %></span><%= if key != "depot",
                  do: holdings_cell(row, key) %><SecurityNames.twin_id
                  :if={key == "security"}
                  tag={row.twin_id}
                /><%= if holdings_currency(row, key), do: " " %><small
                  :if={holdings_currency(row, key)}
                  class="value-suffix"
                ><%= holdings_currency(row, key) %></small>
                <%!-- #1366 (board 02 ①, answer A): the note's first
                     phrase never breaks. --%>
                <small
                  :if={holdings_cell_note(row, key)}
                  class="cell-note"
                ><span class="cell-note__lead"> <%= note_lead(holdings_cell_note(row, key)) %></span><%= note_rest(holdings_cell_note(row, key)) %></small>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <%!-- #1065 (board 06, pick J6 A; UX-DR27): under 560 px the
           table gives way to two-line rows, shown by the phone lists'
           block: the name over the depot, the quantity on the right —
           the projection's default columns, a fixed composition the
           picker does not touch. --%>
      <ul id={@prefix <> "-phone-rows"} class="phone-rows" aria-label={gettext("Positions")}>
        <li
          :for={row <- @rows}
          class="phone-row"
          data-role="holdings-position"
          data-security-id={row.security_id}
        >
          <span class="phone-row__body">
            <span class="phone-row__name"><%= row.security_name %><SecurityNames.twin_id tag={row.twin_id} /></span>
            <span class="phone-row__ids"><%= row.securities_account_name %></span>
          </span>
          <span class="phone-row__figures">
            <span class="phone-row__figure"><%= PrivacyMode.html(holdings_units(row.quantity)) %></span>
          </span>
        </li>
      </ul>
    <% end %>
    """
  end

  # -- the widget ---------------------------------------------------------------

  attr(:item, :map, required: true)
  attr(:card, :any, required: true, doc: "nil while the read runs, :error, or `read/1`'s answer")
  attr(:columns, :list, required: true)
  attr(:picker_open?, :boolean, default: false)
  attr(:scope_label, :string, default: nil)

  @doc "The widget „Positionen“ with its column picker and its compact form."
  def widget(assigns) do
    assigns =
      assign(assigns,
        prefix: "dashboard-positions" <> assigns.item.uid,
        rows: if(is_map(assigns.card), do: assigns.card.rows, else: [])
      )

    ~H"""
    <Widget.frame
      id={@prefix}
      item={@item}
      title={Portfolixir.Dashboards.Widgets.title("positions")}
      scope_label={@scope_label}
      full_href="/portfolio"
      full_label={gettext("Full view →")}
      full_role="positions-full-view"
    >
      <:info>
        <%= gettext("One row per depot and security of the view: the holdings projection, GET /api/v1/portfolios/:id/holdings, its fields the picker's columns. The market value is the view valuation's for the same depot and security, GET /api/v1/valuation, in the base currency.") %>
      </:info>
      <:switch>
        <.picker prefix={@prefix} rows={@rows} columns={@columns} picker_open?={@picker_open?} />
      </:switch>
      <:shared>
        <p :if={is_nil(@card)} class="section-skeleton" aria-busy="true" data-role="positions-skeleton"></p>
        <p :if={@card == :error} class="hint" data-role="positions-failed">
          <%= gettext("Couldn't load the positions.") %>
        </p>
      </:shared>
      <.table :if={is_map(@card)} prefix={@prefix} rows={@rows} columns={@columns} base_currency={@card.base_currency} />
      <:compact>
        <Widget.row
          :for={row <- @rows}
          title={row.security_name}
          data-compact-role="holdings-position"
          data-security-id={row.security_id}
        >
          <:name><%= row.security_name %></:name>
          <:sub><%= row.securities_account_name %></:sub>
          <:figure><%= PrivacyMode.html(holdings_units(row.quantity)) %></:figure>
        </Widget.row>
      </:compact>
    </Widget.frame>
    """
  end
end
