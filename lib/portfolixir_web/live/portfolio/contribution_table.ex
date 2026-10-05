defmodule PortfolixirWeb.Portfolio.ContributionTable do
  @moduledoc """
  The contribution table on Wealth → Holdings → Performance (FR-41,
  ADR-0051 §12; board `mockups/fr41-2026-09-25/01-contribution-surface`,
  pick A): which position made how much of the period's money result.

  It sits directly under the performance chart, inside the section, and
  reads the section's period and the page's view, so its sum row is the
  money figure of the section's badge ("+x EUR in the period"). The figures
  are `Portfolixir.Portfolios.Performance.Contribution`'s, the same the
  contribution read answers, so both users read one table.

  The anatomy (DESIGN.md → Amendment 2026-10-03 → the contribution table):

    * a head — the `h3` and a muted scope line: period · view · order, the
      order left out where the empty state lists nothing;
    * one row per position, largest contribution first: start value, flows
      (signed, uncoloured: a direction, not a gain), income, costs, end value
      and the contribution, signed in its sign colour with the drift bar's
      anatomy under it — decorative and `aria-hidden`, scaled so the largest
      absolute contribution fills 45 % of the track (UX-DR7). A row not held
      at both ends says so under its name; a row that counted zero on some
      days carries a marker in words (UX-DR25);
    * more than ten positions: the ten largest by absolute amount, in the
      table's order, and a "Show all N" control; the sum always covers every
      position;
    * the remainder under its own head — interest, standalone fees and
      taxes, the currency effect on cash — each from its own bookings, never
      a plug (ADR-0051 §3);
    * the sum row: every column summed over all positions; in the
      contribution column the period's result itself, which the positions
      and the remainder lines add up to (I1);
    * the basis line (UX-DR11) and, where a position or a cash account
      counted zero, the attention note naming each one (UX-DR25); an account
      also marks the currency-effect line, which holds the jump its first
      rate brings (#1055, board J2 A);
    * under 560 px two-line rows beside the table (UX-DR27).

  An empty window is the empty-state sentence, never a table of zeros
  (ADR-0051 §4).
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format

  # The board's limit: above it the table shows the largest by absolute
  # amount and a control for the rest.
  @shown 10

  # The drift bar's scale (DESIGN.md → Drift bars): the largest listed fills
  # 45 % of the track, so the rows read against each other.
  @bar_reach 45

  @lines [:interest, :standalone_fees_and_taxes, :cash_currency_effect]

  @doc """
  The rows the table shows: every position, or — above ten and not opened —
  the ten largest by absolute contribution, kept in the table's own order
  (largest contribution first).
  """
  def shown_positions(positions, show_all?)

  def shown_positions(positions, true), do: positions

  def shown_positions(positions, _show_all?) when length(positions) <= @shown, do: positions

  def shown_positions(positions, _show_all?) do
    kept =
      positions
      |> Enum.with_index()
      |> Enum.sort(&larger?/2)
      |> Enum.take(@shown)
      |> MapSet.new(fn {_position, index} -> index end)

    positions
    |> Enum.with_index()
    |> Enum.filter(fn {_position, index} -> MapSet.member?(kept, index) end)
    |> Enum.map(fn {position, _index} -> position end)
  end

  # By absolute amount, larger first; equal amounts keep the table's order.
  defp larger?({a, index_a}, {b, index_b}) do
    case Decimal.compare(Decimal.abs(a.contribution), Decimal.abs(b.contribution)) do
      :gt -> true
      :lt -> false
      :eq -> index_a <= index_b
    end
  end

  attr(:contribution, :map, default: nil, doc: "the engine's result; nil while it computes")
  attr(:failed?, :boolean, default: false)
  attr(:show_all?, :boolean, default: false)
  attr(:period_label, :string, required: true)
  attr(:view_name, :string, required: true)

  @doc "The block, placed by the page directly under the performance chart."
  def table(assigns) do
    f = figures(assigns.contribution, assigns.show_all?)

    assigns =
      assigns
      |> assign(:f, f)
      |> assign(:scope, scope_line(assigns.period_label, assigns.view_name, f))

    ~H"""
    <div id="performance-contribution" class="contribution" data-role="contribution">
      <div class="contribution__head">
        <h3 id="contribution-title"><%= gettext("Contribution by position") %></h3>
        <span class="contribution__scope" data-role="contribution-scope"><%= @scope %></span>
      </div>
      <%= cond do %>
        <% @failed? -> %>
          <AppShell.data_note severity={:problem} data-role="contribution-failed">
            <%= gettext("Computation failed. Reload retries.") %>
          </AppShell.data_note>
        <% is_nil(@f) -> %>
          <div
            class="section-skeleton"
            data-role="contribution-skeleton"
            role="status"
            aria-busy="true"
          >
            <span class="recomputing-cue">
              <span class="spinner"></span> <%= gettext("computing") %>
            </span>
          </div>
        <% @f.empty? -> %>
          <p class="empty-state" data-role="contribution-empty">
            <%= gettext(
              "Nothing to break down in this period: no position was held, and no interest, fee or currency effect fell in it."
            ) %>
          </p>
          <.unvalued_note
            :if={@f.unvalued_accounts != []}
            unvalued={[]}
            accounts={@f.unvalued_accounts}
          />
        <% true -> %>
          <.desktop_table f={@f} show_all?={@show_all?} />
          <.phone_rows f={@f} show_all?={@show_all?} />
          <p class="summary-basis" data-role="contribution-basis">
            <%= gettext(
              "Contribution = end value − start value − flows + income − costs · per position in %{currency}, currency move included · start value: the close of the day before the period · positions and remainder lines add up to exactly the result in the period; deposits and removals are no result",
              currency: @f.currency
            ) %>
          </p>
          <.unvalued_note
            :if={@f.unvalued != [] or @f.unvalued_accounts != []}
            unvalued={@f.unvalued}
            accounts={@f.unvalued_accounts}
          />
      <% end %>
    </div>
    """
  end

  attr(:f, :map, required: true)
  attr(:show_all?, :boolean, required: true)

  defp desktop_table(assigns) do
    ~H"""
    <div id="contribution-table-wrap" class="data-table-wrapper">
      <table
        id="contribution-table"
        class="data-table contribution-table"
        aria-labelledby="contribution-title"
      >
        <thead>
          <tr>
            <th scope="col"><%= gettext("Security") %></th>
            <th scope="col" class="num"><%= gettext("Start value") %></th>
            <th scope="col" class="num"><%= gettext("Flows in/out") %></th>
            <th scope="col" class="num"><%= gettext("Income") %></th>
            <th scope="col" class="num"><%= gettext("Costs") %></th>
            <th scope="col" class="num"><%= gettext("End value") %></th>
            <th scope="col" class="num"><%= gettext("Contribution") %></th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={position <- @f.shown}
            data-role="contribution-row"
            data-security-id={position.security_id}
          >
            <td class="contribution-table__name">
              <%= position_name(position) %>
              <span
                :if={position.unvalued_days > 0}
                class="contribution-unvalued-mark"
                data-role="contribution-unvalued-mark"
              ><%= days_at_zero(position.unvalued_days) %></span>
              <small :if={held_note(position)} class="contribution-table__note">
                <%= held_note(position) %>
              </small>
            </td>
            <td class="num"><%= Format.money(position.start_value) %></td>
            <td class="num"><%= Format.signed_decimal(position.net_flows, 2) %></td>
            <td class="num"><%= Format.signed_decimal(position.income, 2) %></td>
            <td class="num"><%= Format.money(position.costs) %></td>
            <td class="num"><%= Format.money(position.end_value) %></td>
            <td class="num contribution-table__figure">
              <span class={sign_class(position.contribution)}><%= signed_money(
                position.contribution
              ) %></span>
              <span class="drift-bar" aria-hidden="true">
                <span
                  :if={Decimal.compare(position.contribution, 0) != :eq}
                  class={["drift-bar__fill", bar_side(position.contribution)]}
                  style={"width: #{bar_width(position.contribution, @f.largest)}%"}
                >
                </span>
              </span>
            </td>
          </tr>
          <tr :if={@f.total > shown_limit()} class="contribution-table__more">
            <td colspan="7" data-role="contribution-more">
              <span :if={@f.hidden > 0}><%= hidden_sentence(@f.hidden) %></span>
              <.show_all_button show_all?={@show_all?} total={@f.total} />
            </td>
          </tr>
          <tr class="contribution-table__rest-head">
            <td colspan="7" data-role="contribution-rest-head">
              <%= gettext("Not attributed to a position") %>
            </td>
          </tr>
          <tr
            :for={line <- @f.lines}
            class="contribution-table__rest"
            data-role="contribution-remainder"
            data-line={line}
          >
            <td class="contribution-table__name">
              <%= line_label(line) %>
              <span
                :for={account <- line_accounts(line, @f.unvalued_accounts)}
                class="contribution-unvalued-mark"
                data-role="contribution-unvalued-mark"
                data-cash-account-id={account.cash_account_id}
              ><%= account_mark(account) %></span>
              <small class="contribution-table__note"><%= line_note(line) %></small>
            </td>
            <td class="num contribution-table__none">—</td>
            <td class="num contribution-table__none">—</td>
            <td class="num contribution-table__none">—</td>
            <td class="num contribution-table__none">—</td>
            <td class="num contribution-table__none">—</td>
            <td class="num">
              <span class={sign_class(@f.remainder[line])}><%= signed_money(@f.remainder[line]) %></span>
            </td>
          </tr>
          <tr class="contribution-table__sum" data-role="contribution-sum">
            <td><%= gettext("Sum = result in the period") %></td>
            <td class="num"><%= Format.money(@f.column_sums.start_value) %></td>
            <td class="num"><%= Format.signed_decimal(@f.column_sums.net_flows, 2) %></td>
            <td class="num"><%= Format.signed_decimal(@f.column_sums.income, 2) %></td>
            <td class="num"><%= Format.money(@f.column_sums.costs) %></td>
            <td class="num"><%= Format.money(@f.column_sums.end_value) %></td>
            <td class="num" data-role="contribution-sum-figure">
              <span class={sign_class(@f.sum)}><%= signed_money(@f.sum) %></span>
              <small class="value-suffix"><%= @f.currency %></small>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr(:f, :map, required: true)
  attr(:show_all?, :boolean, required: true)

  # UX-DR27: the same rows as two-line rows, shown under 560 px by the phone
  # lists' block, out of the layout above it. The name over the next most
  # important figures, the contribution on the right. No bar: the drift bar
  # is hidden on the phone, and the row is its text.
  defp phone_rows(assigns) do
    ~H"""
    <ul
      id="contribution-phone-rows"
      class="phone-rows contribution-phone-rows"
      aria-label={gettext("Contribution by position")}
    >
      <li
        :for={position <- @f.shown}
        class="phone-row"
        data-role="contribution-row"
        data-security-id={position.security_id}
      >
        <span class="phone-row__body">
          <span class="phone-row__name"><%= position_name(position) %></span>
          <span class="phone-row__ids"><%= phone_line(position) %></span>
        </span>
        <span class="phone-row__figures">
          <span class={["phone-row__figure", sign_class(position.contribution)]}>
            <%= signed_money(position.contribution) %>
          </span>
        </span>
      </li>
      <li :if={@f.total > shown_limit()} class="phone-row contribution-phone-rows__more">
        <span class="phone-row__body">
          <span :if={@f.hidden > 0} class="phone-row__ids"><%= hidden_sentence(@f.hidden) %></span>
          <span><.show_all_button show_all?={@show_all?} total={@f.total} /></span>
        </span>
      </li>
      <li class="phone-row contribution-phone-rows__rest" data-role="contribution-phone-rest">
        <span class="phone-row__body">
          <span class="phone-row__name"><%= gettext("Not attributed to a position") %></span>
          <span class="phone-row__ids">
            <%= Enum.join(
              Enum.map(@f.lines, &phone_rest(&1, @f.remainder[&1])) ++
                Enum.map(@f.unvalued_accounts, &account_mark/1),
              " · "
            ) %>
          </span>
        </span>
        <span class="phone-row__figures">
          <span class={["phone-row__figure", sign_class(@f.remainder_total)]}>
            <%= signed_money(@f.remainder_total) %>
          </span>
        </span>
      </li>
      <li class="phone-row contribution-phone-rows__sum" data-role="contribution-phone-sum">
        <span class="phone-row__body">
          <span class="phone-row__name"><%= gettext("Sum = result in the period") %></span>
          <span class="phone-row__ids"><%= gettext("positions and remainder lines") %></span>
        </span>
        <span class="phone-row__figures">
          <span class={["phone-row__figure", sign_class(@f.sum)]}>
            <%= signed_money(@f.sum) %> <small class="value-suffix"><%= @f.currency %></small>
          </span>
        </span>
      </li>
    </ul>
    """
  end

  attr(:show_all?, :boolean, required: true)
  attr(:total, :integer, required: true)

  # A standalone link-button, as a rule's name on Risk is: its own class
  # carries the 44 px coarse-pointer floor and the accent focus ring (board
  # ux-review-2026-10-03/01-contribution-repairs, R3).
  defp show_all_button(assigns) do
    ~H"""
    <button
      type="button"
      class="link-button contribution-show-all"
      data-role="contribution-show-all"
      phx-click="toggle_contribution_all"
      aria-expanded={to_string(@show_all?)}
    >
      <%= if @show_all? do %>
        <%= gettext("Show the ten largest") %>
      <% else %>
        <%= ngettext("Show all %{count}", "Show all %{count}", @total) %>
      <% end %>
    </button>
    """
  end

  attr(:unvalued, :list, required: true)
  attr(:accounts, :list, required: true)

  # UX-DR25: the count and every name, beside the total they are in. No
  # remedy control: nothing on this page can supply a past price or rate.
  # The positions first, then the cash accounts that counted zero for want
  # of a rate (#1055, board J2 A): one finding — something counted zero on
  # some days — so one note, in the positions' shape, with the native
  # balance, never a converted one (UX-DR25 clause 2).
  defp unvalued_note(assigns) do
    ~H"""
    <AppShell.data_note severity={:attention} data-role="contribution-unvalued">
      <%= if @unvalued != [] do %>
        <%= ngettext(
          "One position counted zero on some days of the period:",
          "%{count} positions counted zero on some days of the period:",
          length(@unvalued)
        ) %>
        <span :for={{position, index} <- Enum.with_index(@unvalued)}><%= if index > 0, do: ", " %><b><%= position_name(position) %></b> (<%= unvalued_detail(position) %>)</span>.
        <%= ngettext(
          "It stays in the sum, as in the result above.",
          "They stay in the sum, as in the result above.",
          length(@unvalued)
        ) %>
      <% end %>
      <%= if @accounts != [] do %>
        <%= ngettext(
          "One cash account counted zero on some days of the period:",
          "%{count} cash accounts counted zero on some days of the period:",
          length(@accounts)
        ) %>
        <span :for={{account, index} <- Enum.with_index(@accounts)}><%= if index > 0, do: ", " %><b><%= account_name(account) %></b> (<%= account_detail(account) %>)</span>.
        <%= first_rate_sentence(@accounts) %>
      <% end %>
    </AppShell.data_note>
    """
  end

  # -- figures --------------------------------------------------------------------

  defp shown_limit, do: @shown

  defp figures(nil, _show_all?), do: nil

  defp figures(contribution, show_all?) do
    positions = contribution.positions
    shown = shown_positions(positions, show_all?)

    %{
      empty?: empty?(contribution),
      shown: shown,
      total: length(positions),
      hidden: length(positions) - length(shown),
      largest: positions |> Enum.map(&Decimal.abs(&1.contribution)) |> max_decimal(),
      lines: @lines,
      remainder: contribution.remainder,
      remainder_total: contribution.totals.remainder,
      # The walk's own result, which the badge's walk reads too (I9): the
      # positions and the three lines add up to it (I1), but a rate whose
      # reciprocal does not terminate leaves a residue near the 34th digit
      # that could tip a cent the badge does not round the same way.
      sum: contribution.totals.result,
      column_sums: column_sums(positions),
      currency: contribution.base_currency,
      unvalued: Enum.filter(positions, &(&1.unvalued_days > 0)),
      unvalued_accounts: contribution.unvalued_cash_accounts
    }
  end

  # The walk's honest emptiness (no walked day in the window), or a window
  # in which nothing was held and no remainder line moved: either way the
  # table would be all zeros.
  defp empty?(%{start_date: nil}), do: true

  defp empty?(%{positions: [], remainder: remainder}),
    do: Enum.all?(@lines, &(Decimal.compare(remainder[&1], 0) == :eq))

  defp empty?(_contribution), do: false

  defp column_sums(positions) do
    for key <- [:start_value, :net_flows, :income, :costs, :end_value], into: %{} do
      {key, positions |> Enum.map(&Map.fetch!(&1, key)) |> sum()}
    end
  end

  defp sum(decimals), do: Enum.reduce(decimals, Decimal.new(0), &Decimal.add(&2, &1))

  defp max_decimal(decimals), do: Enum.max(decimals, Decimal, fn -> Decimal.new(0) end)

  # -- words ------------------------------------------------------------------------

  # The head's scope line: period · view · order. The order phrase only where
  # rows can be listed: an empty window sorts nothing (board
  # ux-review-2026-10-03/01-contribution-repairs, R7a).
  defp scope_line(period_label, view_name, figures) do
    order = if figures && figures.empty?, do: [], else: [gettext("sorted by contribution")]
    Enum.join([period_label, gettext("View %{name}", name: view_name) | order], " · ")
  end

  defp position_name(%{name: name}) when is_binary(name), do: name
  defp position_name(%{isin: isin}) when is_binary(isin), do: isin
  defp position_name(_position), do: "—"

  # The payload's two flags in words; a position held at both ends needs
  # none.
  defp held_note(%{held_at_start: true, held_at_end: true}), do: nil
  defp held_note(%{held_at_start: false, held_at_end: true}), do: gettext("not held at the start")

  defp held_note(%{held_at_start: true, held_at_end: false}),
    do: gettext("no longer held at the end")

  defp held_note(_position), do: gettext("held at neither end")

  defp hidden_sentence(count) do
    ngettext(
      "%{count} smaller position is not shown; the sum includes it.",
      "%{count} smaller positions are not shown; the sum includes them.",
      count
    )
  end

  defp days_at_zero(count), do: ngettext("%{count} day at zero", "%{count} days at zero", count)

  defp unvalued_detail(position) do
    gettext("%{days}, %{reason}",
      days: ngettext("%{count} day", "%{count} days", position.unvalued_days),
      reason: reason(position.unvalued_reason)
    )
  end

  defp reason(:no_rate), do: gettext("no exchange rate stored")
  defp reason(_no_price), do: gettext("no price stored")

  # A cash account that counted zero (#1055): its balance in its own
  # currency, as `dq-missing-fx` prints a native price, its days and the
  # reason — a balance needs no price, so the reason is always the rate.
  defp account_name(%{name: name}) when is_binary(name), do: name
  defp account_name(_account), do: "—"

  defp account_detail(account) do
    gettext("%{balance}, %{days}, %{reason}",
      balance: "#{Format.decimal(account.balance, 2)} #{account.currency_code}",
      days: ngettext("%{count} day", "%{count} days", account.unvalued_days),
      reason: reason(account.unvalued_reason)
    )
  end

  # Where the balance went when its first rate came inside the period: the
  # board's sentence for one account; for several, each account whose rate
  # came is named with its date. No rate inside the period: no sentence.
  defp first_rate_sentence([%{first_rate_date: %Date{} = date}]) do
    gettext(
      "With the first rate on %{date}, its whole balance entered the “Currency effect on cash” — that is no currency gain.",
      date: Format.date(date)
    )
  end

  defp first_rate_sentence([_one]), do: nil

  defp first_rate_sentence(accounts) do
    case Enum.filter(accounts, &match?(%{first_rate_date: %Date{}}, &1)) do
      [] ->
        nil

      dated ->
        ngettext(
          "With its first rate, the whole balance of %{names} entered the “Currency effect on cash” — that is no currency gain.",
          "With their first rates, the whole balances of %{names} entered the “Currency effect on cash” — that is no currency gain.",
          length(dated),
          names:
            Enum.map_join(
              dated,
              ", ",
              &"#{account_name(&1)} (#{Format.date(&1.first_rate_date)})"
            )
        )
    end
  end

  # The currency-effect line holds the jump a first rate brings, so it
  # carries each account's marker, as a position row carries its own; the
  # marker names the account, because the line itself is not the account.
  defp line_accounts(:cash_currency_effect, accounts), do: accounts
  defp line_accounts(_line, _accounts), do: []

  defp account_mark(account) do
    gettext("%{account}: %{days}",
      account: account_name(account),
      days: days_at_zero(account.unvalued_days)
    )
  end

  defp line_label(:interest), do: gettext("Interest")
  defp line_label(:standalone_fees_and_taxes), do: gettext("Standalone fees and taxes")
  defp line_label(:cash_currency_effect), do: gettext("Currency effect on cash")

  defp line_note(:interest),
    do: gettext("Account interest and coupons; an interest booking carries no security")

  defp line_note(:standalone_fees_and_taxes),
    do: gettext("Not part of a trade, even when one names a security")

  defp line_note(:cash_currency_effect),
    do: gettext("Foreign-currency balances and the settlement differences of buys and sells")

  defp phone_rest(:interest, amount),
    do: gettext("Interest %{amount}", amount: signed_money(amount))

  defp phone_rest(:standalone_fees_and_taxes, amount),
    do: gettext("Fees/taxes %{amount}", amount: signed_money(amount))

  defp phone_rest(:cash_currency_effect, amount),
    do: gettext("Currency %{amount}", amount: signed_money(amount))

  # The phone row's second line: the two ends (or, held at one end or
  # neither, the words for it), the flows and the income where they are not
  # zero, and the marker of a position that counted zero.
  defp phone_line(position) do
    ends =
      held_note(position) ||
        "#{Format.money(position.start_value)} → #{Format.money(position.end_value)}"

    [ends, phone_flow(position.net_flows), phone_income(position.income), phone_zero(position)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp phone_flow(flows) do
    case Decimal.compare(flows, 0) do
      :gt -> gettext("inflow %{amount}", amount: Format.money(flows))
      :lt -> gettext("outflow %{amount}", amount: Format.money(Decimal.abs(flows)))
      :eq -> nil
    end
  end

  defp phone_income(income) do
    if Decimal.compare(income, 0) == :eq,
      do: nil,
      else: gettext("income %{amount}", amount: Format.money(income))
  end

  defp phone_zero(%{unvalued_days: 0}), do: nil
  defp phone_zero(%{unvalued_days: days}), do: days_at_zero(days)

  # -- numbers ----------------------------------------------------------------------

  # The badge's own rule (`PortfolixirWeb.PortfolioLive`): a plus before a
  # positive amount, the minus from the number itself, two decimals — so the
  # sum row and the badge print the same characters.
  defp signed_money(value) do
    if Decimal.compare(value, 0) == :gt,
      do: "+" <> Format.money(value),
      else: Format.money(value)
  end

  defp sign_class(value) do
    case Decimal.compare(value, 0) do
      :gt -> "is-positive"
      :lt -> "is-negative"
      :eq -> nil
    end
  end

  defp bar_side(value) do
    if Decimal.compare(value, 0) == :lt, do: "is-under", else: "is-over"
  end

  defp bar_width(value, largest) do
    value
    |> Decimal.abs()
    |> Decimal.div(largest)
    |> Decimal.mult(@bar_reach)
    |> Decimal.round(1)
    |> Decimal.to_string(:normal)
  end
end
