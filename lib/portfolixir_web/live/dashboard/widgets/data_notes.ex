defmodule PortfolixirWeb.Dashboard.Widgets.DataNotes do
  @moduledoc """
  The section widget „Datenhinweise“ `data_notes` (I57; Sprint 32 W1;
  ADR-0062's amendment of 2026-11-25, point 3; planning board
  `ux-design-2026-11-25-sprint32/02` ①): Wealth's section „Data quality“
  of the tab „Bestände“ — why the totals can deviate from what the
  operator expects — moved here so that one code path draws its notes on
  Wealth (`notes/1`, inside Wealth's section) and on a dashboard
  (`widget/1`). Drawn only when a note exists, as on Wealth; in the edit
  mode a quiet line keeps it visible to move or remove.

  Its findings are Wealth's, from the same reads (`read/1`): the view
  valuation's positions and cash (`GET /api/v1/valuation`: unvalued_count,
  unvalued_cash_count, trade_priced_count, stale_priced_count and the
  positions' unvalued_reason, price_source and price_date), the view walk's
  suspect dates (`GET /api/v1/performance`'s suspect_dates), the
  negative-holdings report (`GET /api/v1/holdings/negative`), the bonds on
  two scales and the quotes that contradict their bookings (the securities'
  data-quality findings, `GET /api/v1/securities?data_quality=…`).

  A remedy that writes — „Wechselkurse abrufen“ — stays on Wealth: the
  dashboard's note links there (ADR-0022's amendment of 2026-11-21, point
  3). Sprint 32 D-8: the merge with the kind „Datenqualität“ waits for its
  own board.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Buckets
  alias Portfolixir.Catalog.DataQuality
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Bonds
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.QuotePlausibility
  alias Portfolixir.Portfolios.Valuation
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.PrivacyMode
  alias PortfolixirWeb.ValuationNotes

  # -- the read -----------------------------------------------------------------

  @doc """
  The widget's read for the scope `view_id` (`nil`: Everything), in the
  page's background task, as Wealth reads its section: the view valuation
  and the view walk in the first portfolio's base currency, the
  negative-holdings report, and the bonds on two scales and the
  implausible quotes among the valued positions. A view that vanished
  meanwhile reads Everything.
  """
  @spec read(integer() | nil) :: map()
  def read(view_id) do
    base_currency =
      case Portfolios.first_portfolio() do
        %{base_currency_code: code} -> code
        nil -> "EUR"
      end

    view_id = view_id && Buckets.get_view(view_id) && view_id
    opts = [base_currency: base_currency]

    valuation =
      case Valuation.for_view(view_id, opts) do
        {:error, :view_not_found} -> Valuation.for_view(nil, opts)
        valuation -> valuation
      end

    analysis =
      case Performance.view_analysis(view_id, opts) do
        %{} = analysis -> analysis
        _refused -> nil
      end

    %{
      valuation: valuation,
      analysis: analysis,
      negative: Ledger.negative_holdings_report(),
      two_scales: two_scales_in(valuation),
      implausible_quotes: implausible_quotes_in(valuation)
    }
  end

  @doc """
  The notes' findings from the section's inputs (Wealth's assigns or
  `read/1`'s answer): each note's entries, counted before a list is
  shortened.
  """
  @spec findings(map()) :: map()
  def findings(inputs) do
    two_scales = Map.get(inputs, :two_scales) || []

    %{
      valuation: inputs.valuation,
      no_price: unvalued_entries(inputs.valuation, :no_price),
      missing_fx: unvalued_entries(inputs.valuation, :missing_fx),
      trade_priced: trade_priced_entries(inputs.valuation),
      stale_priced: stale_priced_entries(inputs.valuation),
      suspect_dates: suspect_dates(inputs.analysis),
      unvalued_cash: ValuationNotes.unvalued_cash(inputs.valuation),
      negative_entries: negative_entries(inputs.negative),
      two_scales: two_scales,
      # #1068 (D-15, board 02): the two directions are two findings, each
      # with its own consequence and remedy, so each has its own note.
      two_scales_forward: Enum.filter(two_scales, &(&1.direction == :forward)),
      two_scales_reverse: Enum.filter(two_scales, &(&1.direction == :reverse)),
      implausible_quotes: Map.get(inputs, :implausible_quotes) || []
    }
  end

  @doc "Whether any note stands: the section is drawn only then."
  @spec any?(map()) :: boolean()
  def any?(f) do
    f.no_price.count > 0 or f.missing_fx.count > 0 or f.trade_priced.count > 0 or
      f.stale_priced.count > 0 or f.suspect_dates != [] or f.unvalued_cash != [] or
      f.negative_entries != [] or f.two_scales != [] or f.implausible_quotes != []
  end

  # -- Wealth's notes, moved ------------------------------------------------------

  attr(:f, :map, required: true, doc: "`findings/1`")
  attr(:prefix, :string, default: "dq", doc: "the notes' ids: Wealth's, or a widget form's")
  slot(:fx_sync, doc: "the exchange-rate remedy: Wealth's control, or a link to it")

  @doc """
  The notes of Wealth's section „Data quality“ (UX-DR17, issue 792): one
  data note per finding at its own severity, the remedy inside the note;
  one status region for the list.
  """
  def notes(assigns) do
    ~H"""
    <%!-- UX-DR17 (issue 792): one data note per finding at its own severity,
         glyph and word included, the remedy inside the note; one status
         region for the list, never a role per note. --%>
    <div role="status" data-role="dq-notes">
      <%!-- I1 (#1351, board ux-design-2026-11-01-sprint22/01-i1 ③ ④ ⑤;
           pick Q1): the problems lead and never fold; the notes that name
           rows left out of the totals clamp and never fold, so their
           count stays visible (UX-DR25); the notes that only qualify the
           totals fold into one line when two or more are present. Every
           note clamps to two lines (three on a phone); a problem's remedy
           links sit in its actions, never under the clamp (pick Q1,
           correction 2). --%>
      <AppShell.data_note
        id={@prefix <> "-negative-holdings-note"}
        clamp
        :if={@f.negative_entries != []}
        severity={:problem}
        data-role="dq-negative-holdings"
      >
        <%= ngettext(
          "One security has an impossible negative holding quantity — likely an unmodeled corporate action from an imported history. Repair the transaction history:",
          "%{count} securities have an impossible negative holding quantity — likely an unmodeled corporate action from an imported history. Repair the transaction history:",
          length(@f.negative_entries)
        ) %>
        <:actions>
          <span :for={entry <- @f.negative_entries} class="dq-negative-entry">
            <.link navigate={"/securities/#{entry.security_id}?tab=transactions"}>
              <%= entry.name %>
            </.link>
            (<%= PrivacyMode.html(Enum.map_join(
              entry.depots,
              ", ",
              &"#{&1.depot_name}: #{Format.decimal(&1.quantity, 2)}"
            )) %> · <%= gettext("total across depots") %> <%= Format.decimal(entry.total, 2) %>)
          </span>
        </:actions>
      </AppShell.data_note>
      <%!-- #330 (pick H3, W2): a bond priced on two scales counts a hundred
           times too high in the totals read here, and the return cannot
           show it (bond discovery, point 5). Each name links to where its
           bookings are checked against the statement; nothing is
           converted. #1068 (board 02, pin 3): a bond named by its master
           data alone, with no stored class, carries a neutral badge. --%>
      <AppShell.data_note
        id={@prefix <> "-two-scales-note"}
        clamp
        :if={@f.two_scales_forward != []}
        severity={:problem}
        data-role="dq-two-scales"
      >
        <%= ngettext(
          "One bond is priced on two scales (quotes around 100, booked price per unit around 1) and counts a hundred times too high in the totals; the return does not show it. Check the quantity of its bookings against the nominal on the statement:",
          "%{count} bonds are priced on two scales (quotes around 100, booked price per unit around 1) and count a hundred times too high in the totals; the return does not show it. Check the quantity of their bookings against the nominal on the statement:",
          length(@f.two_scales_forward)
        ) %>
        <:actions>
          <.two_scales_entries findings={@f.two_scales_forward} tab="transactions" />
        </:actions>
      </AppShell.data_note>
      <%!-- #1068 (D-15, board 02, pin 4): the reverse case — quotes near 1
           beside bookings near 100 — counts a hundred times too low, and
           its remedy is the stored quotes, so each name links to its
           Quotes tab. It names; nothing is converted (ADR-0052 §4). --%>
      <AppShell.data_note
        id={@prefix <> "-two-scales-reverse-note"}
        clamp
        :if={@f.two_scales_reverse != []}
        severity={:problem}
        data-role="dq-two-scales-reverse"
      >
        <%= ngettext(
          "One bond is priced on two scales (quotes around 1, booked price per unit around 100) and counts a hundred times too low in the totals. Check its stored quotes — a quote around 1 is not a percent of face:",
          "%{count} bonds are priced on two scales (quotes around 1, booked price per unit around 100) and count a hundred times too low in the totals. Check their stored quotes — a quote around 1 is not a percent of face:",
          length(@f.two_scales_reverse)
        ) %>
        <:actions>
          <.two_scales_entries findings={@f.two_scales_reverse} tab="quotes" />
        </:actions>
      </AppShell.data_note>
      <%!-- #1101 (D-7, board 02 L2 A): a held position valued at quotes
           that contradict its own bookings — two stored facts about one
           day more than a factor of two apart — has a wrong value or a
           wrong cost, so the note is a problem, after the other problem
           notes. The sentence states the rule, the consequence and the
           remedy in order, the quote source first, then the booking;
           each entry names one booking with the quote of its day, and
           each name links to its Quotes tab. It names; nothing is
           converted. --%>
      <AppShell.data_note
        id={@prefix <> "-implausible-quote-note"}
        clamp
        :if={@f.implausible_quotes != []}
        severity={:problem}
        data-role="dq-implausible-quote"
      >
        <a href="/securities?dq=implausible_quote&holding=held">
          <%= ngettext(
            "One held position is valued at quotes that do not match its own bookings (on a booking's day, below half or above twice the price per unit), so its value or its cost is wrong. Check its quote source (ticker, exchange), then the booking:",
            "%{count} held positions are valued at quotes that do not match their own bookings (on a booking's day, below half or above twice the price per unit), so their value or their cost is wrong. Check their quote sources (ticker, exchange), then the bookings:",
            length(@f.implausible_quotes)
          ) %>
        </a>
        <:actions>
          <.implausible_quote_entry
            :for={{finding, index} <- Enum.with_index(@f.implausible_quotes)}
            finding={finding}
            lead_space={index > 0}
          />
        </:actions>
      </AppShell.data_note>

      <AppShell.data_note
        id={@prefix <> "-no-price-note"}
        clamp :if={@f.no_price.count > 0} severity={:attention} data-role="dq-no-price">
        <a href="/securities?dq=missing_quote&holding=held">
          <%= ngettext(
            "One held position has no price at all and is missing from the totals:",
            "%{count} held positions have no price at all and are missing from the totals:",
            @f.no_price.count
          ) %>
        </a>
        <%= Enum.join(@f.no_price.names, ", ") %>
      </AppShell.data_note>
      <AppShell.data_note
        id={@prefix <> "-missing-fx-note"}
        clamp :if={@f.missing_fx.count > 0} severity={:attention} data-role="dq-missing-fx">
        <%= PrivacyMode.html(ngettext(
          "One held position has a price but no exchange rate to %{base} stored, so it is missing from the totals: %{entries}.",
          "%{count} held positions have a price but no exchange rate to %{base} stored, so they are missing from the totals: %{entries}.",
          @f.missing_fx.count,
          base: @f.valuation.base_currency,
          entries: Enum.join(@f.missing_fx.names, ", ")
        )) %>
        <:actions>
          <%= render_slot(@fx_sync) %>
        </:actions>
      </AppShell.data_note>
      <AppShell.data_note
        id={@prefix <> "-unvalued-cash-note"}
        clamp :if={@f.unvalued_cash != []} severity={:attention} data-role="dq-unvalued-cash">
        <%= PrivacyMode.html(ngettext(
          "One cash account is not counted in the totals because there is no exchange rate to %{base}: %{names}.",
          "%{count} cash accounts are not counted in the totals because there is no exchange rate to %{base}: %{names}.",
          length(@f.unvalued_cash),
          base: @f.valuation.base_currency,
          names: Enum.map_join(@f.unvalued_cash, ", ", &ValuationNotes.unvalued_cash_label/1)
        )) %>
        <:actions :if={@f.missing_fx.count == 0}>
          <%= render_slot(@fx_sync) %>
        </:actions>
      </AppShell.data_note>
      <AppShell.data_note_fold
        id={@prefix <> "-folded-notes"}
        attention={Enum.count([@f.stale_priced.count > 0, @f.suspect_dates != []], & &1)}
        note={if @f.trade_priced.count > 0, do: 1, else: 0}
      >
        <AppShell.data_note
          id={@prefix <> "-trade-priced-note"}
          clamp :if={@f.trade_priced.count > 0} severity={:note} data-role="dq-trade-priced">
          <%!-- The finding links to where it is fixed (#561): the securities
               list pre-filtered to stale quotes.

               Overview and Wealth both surface this condition, and that is a
               role split rather than a duplication (#703): the Overview is the
               "does anything need me?" surface and keeps the bare count as the
               ALARM, while this page is where the number is distorted and so
               states the CONSEQUENCE for the total and names the positions.
               Naming them also makes this row consistent with every one of its
               siblings, all of which join their entries. --%>
          <a href="/securities?dq=stale_quote">
            <%= ngettext(
              "One held position is valued at its last trade price, so the total is not current:",
              "%{count} held positions are valued at their last trade price, so the total is not current:",
              @f.trade_priced.count
            ) %>
          </a>
          <%= Enum.join(@f.trade_priced.names, ", ") %>
        </AppShell.data_note>
        <AppShell.data_note
          id={@prefix <> "-stale-priced-note"}
          clamp
          :if={@f.stale_priced.count > 0}
          severity={:attention}
          data-role="dq-stale-priced"
        >
          <%!-- #779 / #610 (Sprint 11 Lane X): a quoted position whose feed
               has stopped reads as live without this row. It names the
               positions with the date each price is from and the remedy —
               the retired flag is what the performance walk keys on. --%>
          <a href="/securities?dq=stale_quote&holding=held">
            <%= ngettext(
              "One held position is valued at a quote older than %{days} days, so the totals may be stale — mark it retired if its listing ended, or sync its quotes:",
              "%{count} held positions are valued at quotes older than %{days} days, so the totals may be stale — mark them retired if their listings ended, or sync their quotes:",
              @f.stale_priced.count,
              days: @f.stale_priced.days
            ) %>
          </a>
          <%= Enum.join(@f.stale_priced.names, ", ") %>
        </AppShell.data_note>
        <AppShell.data_note
          id={@prefix <> "-suspect-dates-note"}
          clamp :if={@f.suspect_dates != []} severity={:attention} data-role="dq-suspect-dates">
          <%= gettext(
            "Bookings dated before 1970 (%{dates}) are applied on the first plausible day — fix those dates in the source and re-import.",
            dates: Enum.map_join(@f.suspect_dates, ", ", &Format.date/1)
          ) %>
        </AppShell.data_note>
      </AppShell.data_note_fold>
    </div>
    """
  end

  attr(:findings, :list, required: true)
  attr(:tab, :string, required: true)

  # The bonds of one two-scales note, one space between entries (closing
  # act, UAT): an entry is an inline block, whose own edge whitespace does
  # not render, so without it the entries read "…0,985)Ostsee…". Public
  # only so its raw render can be pinned; the test DOM drops that space.
  @doc false
  def two_scales_entries(assigns) do
    ~H"""
    <.two_scales_entry
      :for={{finding, index} <- Enum.with_index(@findings)}
      finding={finding}
      tab={@tab}
      lead_space={index > 0}
    />
    """
  end

  attr(:finding, :map, required: true)
  attr(:tab, :string, required: true)
  attr(:lead_space, :boolean, default: false)

  # One bond of a two-scales note: its name linking to the tab where it is
  # fixed, the neutral "no asset class" badge when it shows none, stored or
  # inferred (#1068, board 02, pin 3: it is named by its master data, not
  # its class), and
  # both scales' figures as stored. The link holds the name alone, so its
  # underline ends there; `lead_space` puts the separating space outside
  # the entry (closing act, UAT).
  defp two_scales_entry(assigns) do
    ~H"""
    <%= if @lead_space, do: " " %><span class="dq-negative-entry">
      <.link navigate={"/securities/#{@finding.security_id}?tab=#{@tab}"}><%= @finding.name %></.link>
      <span
        :if={is_nil(@finding.effective_asset_class)}
        class="badge badge--neutral"
        data-role="dq-two-scales-unclassed"
      >
        <%= gettext("no asset class") %>
      </span>
      (<%= PrivacyMode.html(gettext("quote %{close} · price per unit %{price}",
        close: Format.exact(@finding.latest_quote.close),
        price: Format.exact(@finding.last_unit_scale_booking.price)
      )) %>)
    </span>
    """
  end

  attr(:finding, :map, required: true)
  attr(:lead_space, :boolean, default: false)

  # One position of the implausible-quote note (#1101, board 02 L2 A): its
  # name linking to its Quotes tab, then the booking and the quote of its
  # day — kind, date, booked price, the quote's own date (the day before
  # when none is stored on the booking's), the close and the ratio with two
  # places. The figures are as `Format.exact` writes them, as the two-scales
  # entries'; `lead_space` keeps one space between entries outside them.
  defp implausible_quote_entry(assigns) do
    ~H"""
    <%= if @lead_space, do: " " %><span class="dq-negative-entry">
      <.link navigate={"/securities/#{@finding.security_id}?tab=quotes"}><%= @finding.name %></.link>
      (<%= PrivacyMode.html(gettext(
        "%{kind} %{date} at %{price} %{currency} · quote %{quote_date}: %{close} %{currency}, %{ratio} times that",
        kind: implausible_quote_kind(@finding.kind),
        date: Format.date(@finding.date),
        price: Format.exact(@finding.price),
        currency: @finding.currency_code,
        quote_date: Format.date(@finding.quote_date),
        close: Format.exact(@finding.close),
        ratio: Format.plain_decimal(@finding.ratio, 2)
      )) %>)
    </span>
    """
  end

  defp implausible_quote_kind("buy"), do: gettext("buy")
  defp implausible_quote_kind("sell"), do: gettext("sell")

  defp implausible_quote_kind("inbound_delivery"),
    do: gettext("inbound delivery")

  # -- data quality helpers ----------------------------------------------------

  # Unvalued positions of one honest state (#406): `:no_price` lists names
  # only (there is nothing to show), `:missing_fx` shows each position's
  # known native price with its currency (owner decision 2026-07-31). The
  # count is taken before the display list is shortened, so it stays truthful
  # when names are elided. The labels and the shortening live in
  # ValuationNotes (#1081).
  defp unvalued_entries(nil, _reason), do: %{count: 0, names: []}

  defp unvalued_entries(valuation, reason) do
    names =
      valuation.positions
      |> Enum.filter(&(&1.unvalued_reason == reason))
      |> reject_retired(reason)
      |> Enum.map(&ValuationNotes.unvalued_entry_label(&1, reason))
      |> Enum.uniq()

    %{count: length(names), names: ValuationNotes.shorten_list(names)}
  end

  # The no-price row links to ?dq=missing_quote&holding=held (#1366: the
  # held ones it counts, as the implausible-quote row's link), which leaves
  # a retired security out, so the row does too (PR #1102); the FX row
  # keeps it, as missing_fx does.
  defp reject_retired(positions, :no_price),
    do: Enum.reject(positions, &Map.get(&1, :retired, false))

  defp reject_retired(positions, _reason), do: positions

  @doc false
  # #1101 (D-7): the valued positions whose stored quotes contradict their
  # own bookings, a security two_scales_in/1 names left out by the rule.
  def implausible_quotes_in(%{positions: positions}) do
    positions
    |> Enum.map(& &1.security_id)
    |> Enum.reject(&is_nil/1)
    |> QuotePlausibility.findings()
  end

  @doc false
  # #330 (ADR-0052 §4): the bonds among the valued positions whose quotes and
  # booked unit prices sit on two scales.
  def two_scales_in(%{positions: positions}) do
    positions
    |> Enum.map(& &1.security_id)
    |> Enum.reject(&is_nil/1)
    |> Bonds.two_scales_findings()
  end

  # Negative-holdings debris grouped per security (#570): each entry keeps
  # its negative depot rows and the security's total across all depots, so
  # the report shows both, and links to the transaction history (no repair
  # wizard beyond splits, ADR-0028).
  defp negative_entries(nil), do: []

  defp negative_entries(report) do
    report.rows
    |> Enum.group_by(&{&1.security_id, &1.security_name})
    |> Enum.map(fn {{security_id, security_name}, rows} ->
      %{
        security_id: security_id,
        name: security_name || gettext("Unsorted"),
        depots: rows,
        total: hd(rows).total_quantity
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  # Mirrors unvalued_entries/2: the row names what it found, shortened by the
  # same rule so a long list does not swamp the section (#703).
  defp trade_priced_entries(nil), do: %{count: 0, names: []}

  defp trade_priced_entries(valuation) do
    names =
      valuation.positions
      # A retired holding is left out, as from the stale-quote row: its link,
      # ?dq=stale_quote, no longer lists it (PR #1102).
      |> Enum.filter(&(&1.price_source == :trade and not Map.get(&1, :retired, false)))
      |> Enum.map(&(&1.security_name || gettext("Unsorted")))
      |> Enum.uniq()

    %{count: length(names), names: ValuationNotes.shorten_list(names)}
  end

  # The stale-quoted positions (#779 / #610), each named with the date its
  # price is from, under the one staleness threshold DataQuality states.
  defp stale_priced_entries(nil), do: %{count: 0, names: [], days: DataQuality.stale_days()}

  defp stale_priced_entries(valuation) do
    today = Portfolixir.Clock.today()
    days = DataQuality.stale_days()

    names =
      valuation.positions
      |> Enum.filter(fn position ->
        # A retired holding is left out: the finding's own remedy (#610).
        not Map.get(position, :retired, false) and position.price_source == :quote and
          match?(%Date{}, position.price_date) and Date.diff(today, position.price_date) > days
      end)
      |> Enum.map(&"#{&1.security_name || gettext("Unsorted")} (#{Format.date(&1.price_date)})")
      |> Enum.uniq()

    %{count: length(names), names: ValuationNotes.shorten_list(names), days: days}
  end

  defp suspect_dates(nil), do: []
  defp suspect_dates(analysis), do: analysis.suspect_dates

  # -- the widget ---------------------------------------------------------------

  attr(:item, :map, required: true)
  attr(:card, :any, required: true, doc: "nil while the read runs, :error, or `read/1`'s answer")
  attr(:scope_label, :string, default: nil)

  @doc """
  The widget „Datenhinweise“: drawn only when a note exists, or in the
  edit mode, where a quiet line says there is none.
  """
  def widget(assigns) do
    f = if is_map(assigns.card), do: findings(assigns.card)

    assigns =
      assign(assigns,
        f: f,
        shown: f != nil and any?(f),
        editing: Map.get(assigns.item, :editing, false)
      )

    ~H"""
    <Widget.frame
      :if={@shown or @editing}
      id={"dashboard-data-notes" <> @item.uid}
      item={@item}
      title={Portfolixir.Dashboards.Widgets.title("data_notes")}
      scope_label={@scope_label}
      full_href="/portfolio"
      full_label={gettext("Full view →")}
      full_role="data-notes-full-view"
    >
      <:info>
        <%= gettext("Why the totals can differ from what is expected, as Wealth names it: positions without a price or an exchange rate, valued at a trade price or an old quote, cash without a rate, negative holdings, bonds on two scales, quotes that contradict their bookings, bookings dated before 1970. From the view valuation (GET /api/v1/valuation), the view's performance walk and the data-quality reads.") %>
      </:info>
      <.notes :if={@shown} f={@f} prefix={"dashboard-data-notes" <> @item.uid}>
        <:fx_sync>
          <a href="/portfolio" data-role="data-notes-fx-link"><%= gettext("Sync exchange rates on Wealth →") %></a>
        </:fx_sync>
      </.notes>
      <p :if={not @shown} class="hint" data-role="data-notes-none">
        <%= gettext("No data note: drawn only when one exists.") %>
      </p>
      <:compact>
        <.notes :if={@shown} f={@f} prefix={"dashboard-data-notes" <> @item.uid <> "-compact"}>
          <:fx_sync>
            <a href="/portfolio"><%= gettext("Sync exchange rates on Wealth →") %></a>
          </:fx_sync>
        </.notes>
        <p :if={not @shown} class="hint"><%= gettext("No data note: drawn only when one exists.") %></p>
      </:compact>
    </Widget.frame>
    """
  end
end
