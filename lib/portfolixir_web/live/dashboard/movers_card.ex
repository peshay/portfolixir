defmodule PortfolixirWeb.Dashboard.MoversCard do
  @moduledoc """
  The Overview's card „Tops und Flops“ (FR-59, idea I32; ADR-0061 §9; board
  `ux-design-2026-11-15-sprint30/04-tops-flops`, A, stacked under 560 px as
  A1; Sprint 30, T3).

  Every figure it shows is `Portfolixir.Portfolios.Performance.Movers.read/3`
  for the Overview's scope (the default view, else everything) and the
  window the chips choose, the read `GET /api/v1/views/:view_id/movers` and
  `GET /api/v1/movers` answer, so the screen and the agent read one ranking.
  The page loads it in the background (`PortfolixirWeb.DashboardLive`) and
  hands it here; this module only draws.

  The anatomy (DESIGN.md → Amendment 2026-11-19 → the card „Tops und
  Flops“):

    * a head — the heading with its ⓘ, which holds the method, and
      „View in Wealth →“, Wealth with the contribution's window as a custom
      range;
    * the window as one group „Period“ of the shared control bar
      (`PortfolixirWeb.ControlBar.bar/1`), its chips patch links that keep
      the window in the address (`?movers_period=`);
    * one basis line: the view, the window and its dates, the currency;
    * two columns, „Price return“ first and „Contribution“ beside it, each
      with „Highest“ over „Lowest“ as `.attention-item` rows (name left,
      figure right) and the count of what has no answer under them; a „Day“
      row names its two closes, another row its last close where it is
      before the window's end; a position sold in the window carries
      „sold“, one that counted zero on some days the contribution table's
      marker, and each contribution the table's bar, scaled so the largest
      listed fills 45 %;
    * states: the block skeleton, marked busy, while the read runs; a
      problem note when it failed; „No holdings in this view.“ when the
      scope holds nothing and no position moved in the window.

  In the privacy mode every contribution is the app's mask
  (`PortfolixirWeb.Format.signed_decimal/3`); the percentages, the order,
  the sign colours, the bars and the counts stay (board 04 ④).
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.ControlBar
  alias PortfolixirWeb.Format

  @windows ~w(day week month quarter ytd 1y)
  @default_window "day"

  # The contribution table's bar scale (DESIGN.md → Drift bars): the largest
  # listed fills 45 % of the track.
  @bar_reach 45

  @price_reasons [:no_close_at_start, :no_close_at_end, :no_fx_rate, :one_close_only]

  @doc "The address key the window travels under."
  def param, do: "movers_period"

  @doc """
  The window an address names: one of the read's windows, else „Day“, the
  default (a value the card does not know opens the default).
  """
  @spec window(term()) :: String.t()
  def window(value) when value in @windows, do: value
  def window(_value), do: @default_window

  attr(:window, :string, required: true)
  attr(:card, :any, required: true, doc: "nil while the read runs, :error, or the loaded card")
  attr(:privacy_mode, :boolean, default: false)

  @doc "The card, placed by the Overview under its KPI strip."
  def card(assigns) do
    assigns = assign(assigns, :f, figures(assigns.card))

    ~H"""
    <section id="dashboard-movers" class="workspace-section movers" aria-labelledby="movers-title">
      <div class="section-head">
        <div class="section-title">
          <h2 id="movers-title"><%= gettext("Tops and flops") %></h2>
          <AppShell.section_info>
            <:line>
              <%= gettext(
                "Price return: the last stored close in the period ÷ the close before the period − 1, both in EUR at the stored exchange rate of their day; income and costs do not count."
              ) %>
            </:line>
            <:line>
              <%= gettext(
                "Contribution: end value − start value − flows + income − costs per position, as “Contribution by position” in Wealth; a position sold in the period counts."
              ) %>
            </:line>
            <:line>
              <%= gettext(
                "Five highest and five lowest each; under ten the list splits, and no name stands in both halves."
              ) %>
            </:line>
            <:line>
              <%= gettext(
                "No close before the period, none in it, or no exchange rate: no price return. A day without a price counts zero in the contribution, as in Wealth; a position valued on no day is counted, not ranked."
              ) %>
            </:line>
            <:line>
              <%= gettext(
                "Day: since each security's previous close, the two dates at the row; the contribution of the latest day with a close."
              ) %>
            </:line>
          </AppShell.section_info>
        </div>
        <a
          :if={@f && @f.wealth_href}
          class="kpi-summary__link"
          href={@f.wealth_href}
          data-role="movers-wealth-link"
        ><%= gettext("View in Wealth →") %></a>
      </div>
      <ControlBar.bar fold={560} floor={380} data-role="movers-bar">
        <:group label={gettext("Period")} label_id="movers-period-label">
          <div
            class="segmented-control"
            data-role="movers-period"
            role="group"
            aria-labelledby="movers-period-label"
          >
            <.link
              :for={{key, label} <- windows()}
              patch={"/?" <> URI.encode_query(%{param() => key})}
              class={["segmented-control__option", @window == key && "is-active"]}
              data-window={key}
              aria-current={if @window == key, do: "true"}
            >
              <%= label %>
            </.link>
          </div>
        </:group>
      </ControlBar.bar>
      <%= cond do %>
        <% is_nil(@card) -> %>
          <p class="section-skeleton" aria-busy="true" data-role="movers-skeleton"></p>
        <% @card == :error -> %>
          <AppShell.data_note
            severity={:problem}
            id="movers-error"
            data-role="movers-error"
            clamp
          >
            <%= gettext("Couldn't load the tops and flops.") %>
          </AppShell.data_note>
        <% @f.empty? -> %>
          <p class="empty-state" data-role="movers-empty">
            <%= gettext("No holdings in this view.") %>
          </p>
        <% true -> %>
          <p class="summary-basis" data-role="movers-basis"><%= @f.basis %></p>
          <div class="movers__grid">
            <div class="movers__col" data-role="movers-return">
              <h3><%= pgettext("movers", "Price return") %></h3>
              <.half
                :for={{half, rows} <- @f.price_halves}
                half={half}
                rows={rows}
                side={:price}
                f={@f}
                privacy_mode={@privacy_mode}
              />
              <p :if={@f.price_answered == 0} class="hint" data-role="movers-none">
                <%= gettext("No figure in this period.") %>
              </p>
              <p :if={@f.price_count} class="movers__count" data-role="movers-return-count">
                <%= @f.price_count %>
              </p>
            </div>
            <div class="movers__col" data-role="movers-contribution">
              <h3><%= gettext("Contribution") %></h3>
              <.half
                :for={{half, rows} <- @f.contribution_halves}
                half={half}
                rows={rows}
                side={:contribution}
                f={@f}
                privacy_mode={@privacy_mode}
              />
              <p :if={@f.contribution_answered == 0} class="hint" data-role="movers-none">
                <%= gettext("No figure in this period.") %>
              </p>
              <p
                :if={@f.contribution_count}
                class="movers__count"
                data-role="movers-contribution-count"
              >
                <%= @f.contribution_count %>
              </p>
            </div>
          </div>
      <% end %>
    </section>
    """
  end

  attr(:half, :atom, required: true)
  attr(:rows, :list, required: true)
  attr(:side, :atom, required: true)
  attr(:f, :map, required: true)
  attr(:privacy_mode, :boolean, required: true)

  defp half(assigns) do
    ~H"""
    <div data-half={@half}>
      <h4 class="movers__half"><%= half_label(@half) %></h4>
      <ul class="attention-list">
        <li :for={entry <- @rows}>
          <a
            href={"/securities/#{entry.security.id}"}
            class="attention-item"
            data-role="movers-row"
          >
            <.name entry={entry} side={@side} f={@f} />
            <.figure
              entry={entry}
              side={@side}
              largest={@f.largest}
              privacy_mode={@privacy_mode}
            />
          </a>
        </li>
      </ul>
    </div>
    """
  end

  attr(:entry, :map, required: true)
  attr(:side, :atom, required: true)
  attr(:f, :map, required: true)

  defp name(%{side: :price} = assigns) do
    assigns = assign(assigns, :dates, price_dates(assigns.entry, assigns.f))

    ~H"""
    <span class="attention-name"><%= security_name(@entry.security) %><small
        :if={@dates}
        class="attention-item__sub"
        data-role="movers-dates"
      ><%= @dates %></small></span>
    """
  end

  defp name(assigns) do
    ~H"""
    <span class="attention-name"><%= security_name(@entry.security) %>
      <span :if={@entry.held_at_end == false} class="badge badge--neutral" data-role="movers-sold"><%= pgettext("movers", "sold") %></span><span
        :if={@entry.unvalued_days > 0}
        class="contribution-unvalued-mark"
        data-role="movers-unvalued-mark"
      ><%= ngettext("%{count} day at zero", "%{count} days at zero", @entry.unvalued_days) %></span></span>
    """
  end

  attr(:entry, :map, required: true)
  attr(:side, :atom, required: true)
  attr(:largest, :any, required: true)
  attr(:privacy_mode, :boolean, required: true)

  defp figure(%{side: :price} = assigns) do
    ~H"""
    <span
      class={["num", percent_sign_class(@entry.return)]}
      data-role="movers-figure"
    ><%= Format.signed_percent(@entry.return) %>%</span>
    """
  end

  # The contribution table's figure: the signed amount in its sign colour,
  # the bar under it (decorative, aria-hidden). In the privacy mode the
  # amount is the mask alone, its colour and its bar kept (board 04 ④).
  defp figure(assigns) do
    ~H"""
    <span class="num movers__figure">
      <span
        class={money_sign_class(@entry.contribution)}
        data-role="movers-figure"
      ><%= Format.signed_decimal(@entry.contribution, 2) %><%= unless @privacy_mode, do: " EUR" %></span>
      <span class="drift-bar" aria-hidden="true">
        <span
          :if={Format.displayed_sign(@entry.contribution, 2) != :zero}
          class={["drift-bar__fill", bar_side(@entry.contribution)]}
          style={"width: #{bar_width(@entry.contribution, @largest)}%"}
        >
        </span>
      </span>
    </span>
    """
  end

  # -- figures ----------------------------------------------------------------------

  defp figures(nil), do: nil
  defp figures(:error), do: nil

  defp figures(%{result: result, view_name: view_name}) do
    price = result.price_return
    contribution = result.contribution
    listed = contribution.highest ++ contribution.lowest
    empty? = empty?(price) and empty?(contribution)

    %{
      empty?: empty?,
      window: result.window,
      end_on: result.end_on,
      basis: basis(result, view_name),
      price_halves: halves(price),
      contribution_halves: halves(contribution),
      price_answered: price.answered,
      contribution_answered: contribution.answered,
      price_count: price_count(price.unanswered),
      contribution_count: contribution_count(contribution.unanswered),
      largest: listed |> Enum.map(&Decimal.abs(&1.contribution)) |> max_decimal(),
      # An empty card links nowhere: Wealth would show nothing either.
      wealth_href: if(empty?, do: nil, else: wealth_href(contribution.from, contribution.to))
    }
  end

  # Nothing held and nothing moved: no ranked entry and none without an
  # answer on either side.
  defp empty?(ranking),
    do: ranking.answered == 0 and Enum.all?(ranking.unanswered, fn {_reason, n} -> n == 0 end)

  defp halves(ranking) do
    [{:highest, ranking.highest}, {:lowest, ranking.lowest}]
    |> Enum.reject(fn {_half, rows} -> rows == [] end)
  end

  defp max_decimal(decimals), do: Enum.max(decimals, Decimal, fn -> Decimal.new(0) end)

  # Wealth with the contribution's window as a custom range (`from=` and
  # `to=`, the address values Wealth's popover reads), so its table shows
  # the same contribution; none when the window has no day.
  defp wealth_href(%Date{} = from, %Date{} = to),
    do:
      "/portfolio?" <>
        URI.encode_query([{"from", Date.to_iso8601(from)}, {"to", Date.to_iso8601(to)}])

  defp wealth_href(_from, _to), do: nil

  # -- words ------------------------------------------------------------------------

  @doc false
  def windows do
    [
      {"day", pgettext("movers", "Day")},
      {"week", pgettext("movers", "Week")},
      {"month", pgettext("movers", "Month")},
      {"quarter", pgettext("movers", "Quarter")},
      {"ytd", gettext("YTD")},
      {"1y", gettext("1Y")}
    ]
  end

  defp window_label(window), do: windows() |> List.keyfind(window, 0) |> elem(1)

  defp half_label(:highest), do: gettext("Highest")
  defp half_label(:lowest), do: gettext("Lowest")

  defp view_label(nil), do: gettext("Everything")
  defp view_label(name), do: name

  # The one basis line (UX-DR11): the view, the window and its dates, the
  # currency; the method stands behind the ⓘ.
  defp basis(%{window: "day"} = result, view_name) do
    case result.contribution.from do
      %Date{} = day ->
        gettext(
          "View %{view} · %{window}: since each security's previous close, the dates at the row; contribution on %{date} · in EUR",
          view: view_label(view_name),
          window: window_label("day"),
          date: Format.date(day)
        )

      nil ->
        gettext(
          "View %{view} · %{window}: since each security's previous close, the dates at the row · in EUR",
          view: view_label(view_name),
          window: window_label("day")
        )
    end
  end

  defp basis(result, view_name) do
    gettext(
      "View %{view} · %{window}: close %{start} to %{end} · in EUR, from stored closes and bookings",
      view: view_label(view_name),
      window: window_label(result.window),
      start: Format.date(result.start_on),
      end: Format.date(result.end_on)
    )
  end

  # A „Day“ row's two closes with their weekdays; another window's row its
  # last close, where that is before the window's end (ADR-0061 §3, §4).
  defp price_dates(entry, %{window: "day"}),
    do: "#{dated(entry.start.date)} → #{dated(entry.end.date)}"

  defp price_dates(entry, %{end_on: end_on}) do
    if Date.compare(entry.end.date, end_on) == :lt,
      do: gettext("last close %{date}", date: Format.date(entry.end.date)),
      else: nil
  end

  defp dated(%Date{} = date), do: "#{weekday(date)} #{Format.date(date)}"

  defp weekday(%Date{} = date) do
    case Date.day_of_week(date) do
      1 -> pgettext("weekday", "Mon")
      2 -> pgettext("weekday", "Tue")
      3 -> pgettext("weekday", "Wed")
      4 -> pgettext("weekday", "Thu")
      5 -> pgettext("weekday", "Fri")
      6 -> pgettext("weekday", "Sat")
      7 -> pgettext("weekday", "Sun")
    end
  end

  # „n without a price return: a by reason, b by reason“, each reason with a
  # count above zero; none when every held security has a figure.
  defp price_count(unanswered) do
    parts =
      for reason <- @price_reasons,
          n = Map.get(unanswered, reason, 0),
          n > 0,
          do: reason_count(reason, n)

    case Enum.sum(Map.values(unanswered)) do
      0 ->
        nil

      total ->
        ngettext("%{count} without a price return", "%{count} without a price return", total) <>
          ": " <> Enum.join(parts, ", ")
    end
  end

  defp reason_count(:no_close_at_start, n),
    do:
      ngettext(
        "%{count} without a close at the start",
        "%{count} without a close at the start",
        n
      )

  defp reason_count(:no_close_at_end, n),
    do: ngettext("%{count} without a recent close", "%{count} without a recent close", n)

  defp reason_count(:no_fx_rate, n),
    do: ngettext("%{count} without an exchange rate", "%{count} without an exchange rate", n)

  defp reason_count(:one_close_only, n),
    do: ngettext("%{count} with one close only", "%{count} with one close only", n)

  defp contribution_count(unanswered) do
    case Map.get(unanswered, :no_valuation, 0) do
      0 ->
        nil

      n ->
        ngettext(
          "%{count} position not valued on any day of the period",
          "%{count} positions not valued on any day of the period",
          n
        )
    end
  end

  defp security_name(%{name: name}) when is_binary(name), do: name
  defp security_name(%{isin: isin}) when is_binary(isin), do: isin
  defp security_name(_security), do: "—"

  # -- numbers ----------------------------------------------------------------------

  defp percent_sign_class(value) do
    case Format.displayed_percent_sign(value) do
      :positive -> "is-positive"
      :negative -> "is-negative"
      _zero -> nil
    end
  end

  defp money_sign_class(value) do
    case Format.displayed_sign(value, 2) do
      :positive -> "is-positive"
      :negative -> "is-negative"
      _zero -> nil
    end
  end

  defp bar_side(value) do
    if Format.displayed_sign(value, 2) == :negative, do: "is-under", else: "is-over"
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
