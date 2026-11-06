defmodule PortfolixirWeb.SaleHindsightSection do
  @moduledoc """
  "After the sale" (Sprint 26 V3; I18 modes 1 and 2, FR-50; board
  `ux-design-2026-11-06-sprint26-i18`, pick C): what each sale missed, one
  row per sale booking, under the trades list of Cash flow → Trades and on a
  security's Trades tab, filtered to it.

  The figures are `Portfolixir.Portfolios.Performance.SaleHindsight.report/1`'s,
  the function `GET /api/v1/sales/hindsight` answers with, so both users read
  one figure. The page holds no figure of its own: it formats the read.

  The anatomy (DESIGN.md → Amendment 2026-11-06 → "After the sale"):

    * a head — on Cash flow an `h2` over the basis line and the section's
      ⓘ (the computation basis, six clauses); on the security page an `h3`
      with the ⓘ beside it;
    * the chooser „Vergleich“ — the shipped segmented control, as query
      state (`hindsight`, `hindsight_rate`, `hindsight_benchmark`), and the
      one field the chosen kind needs: the rate and „Anwenden“, or the
      flagged benchmark securities' select (ADR-0046), or the shipped hint
      when none is flagged;
    * the table — security (not on the security page), sale (date over
      quantity × booked price), start close (EUR, its date where it is not
      the sale day, the close in its own currency where that is not EUR),
      and the four spans as a column group whose head names the lead
      figure. A span is the lead figure over „Wertpapier ggü. Benchmark“, or
      „läuft“ over its end date, or the muted dash over its reason with the
      long reason as the cell's title;
    * under 560 px the phone rows, the four spans as a 2 × 2 grid;
    * the legend: what the lead figure is, and that it is a price return.

  No verdict anywhere: no word on whether a sale was right, no colour on a
  row, no ranking, no sum of what the sales missed (AGENTS.md: no advice).

  **Comparison modes** are an atom list (`modes/0`), each with its query
  value, its chooser label and its resolution. A fourth mode (R3, ADR-0057's
  follow-on purchase) adds one entry to `@modes`, one `mode_label/1` clause
  and its own row rendering; the rows and the URL handling stay as they are.
  """
  use Phoenix.LiveComponent
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Catalog
  alias Portfolixir.Portfolios.Performance.SaleHindsight
  alias Portfolixir.Portfolios.Performance.WindowReturn
  alias PortfolixirWeb.BenchmarkScope
  alias PortfolixirWeb.DecimalInput
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.LiveEventGuard
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.SecurityNames

  # The chooser's modes in their order. R3 adds `:switch` here.
  @modes [:none, :rate, :security]
  @mode_params Map.new(@modes, &{Atom.to_string(&1), &1})
  @param_prefix "hindsight"
  @rate_param "hindsight_rate"
  @benchmark_param "hindsight_benchmark"
  # The longest rate text the field echoes back into the address.
  @max_rate_echo 40

  @doc "The comparison modes the chooser offers, in its order."
  @spec modes() :: [atom()]
  def modes, do: @modes

  @impl true
  def mount(socket), do: {:ok, socket |> LiveEventGuard.attach() |> assign(:key, nil)}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    socket = assign_new(socket, :security_id, fn -> nil end)
    key = {socket.assigns.uri, socket.assigns.security_id}

    if socket.assigns.key == key do
      {:ok, socket}
    else
      {:ok, socket |> assign(:key, key) |> load()}
    end
  end

  defp load(socket) do
    %{uri: uri, security_id: security_id} = socket.assigns
    params = query_params(uri)
    benchmarks = Catalog.list_securities(is_benchmark: true)
    comparison = comparison(params, benchmarks)

    report =
      SaleHindsight.report(
        benchmark: comparison.benchmark,
        security_id: security_id
      )

    rows =
      report.rows
      |> Enum.map(
        &%{row: &1, security_id: &1.security.id, isin: &1.security.isin, wkn: &1.security.wkn}
      )
      |> SecurityNames.put_twin_ids(& &1.row.security.name)

    assign(socket,
      comparison: comparison,
      benchmarks: benchmarks,
      report: report,
      rows: rows
    )
  end

  # -- the comparison, from the address ----------------------------------------

  # The address is the comparison's one source: a chooser link, the rate
  # field and the select all patch it. No `hindsight` reads the flagged
  # benchmark when one exists, else none.
  defp comparison(params, benchmarks) do
    mode = Map.get(@mode_params, params[@param_prefix]) || default_mode(benchmarks)
    resolve(mode, params, benchmarks)
  end

  defp default_mode([]), do: :none
  defp default_mode(_benchmarks), do: :security

  defp resolve(:none, _params, _benchmarks), do: %{base(:none) | benchmark: nil}

  defp resolve(:rate, params, _benchmarks) do
    case params[@rate_param] do
      raw when is_binary(raw) and raw != "" ->
        case parse_rate(raw) do
          {:ok, rate} -> %{base(:rate) | benchmark: {:rate, rate}, rate_input: raw}
          :error -> %{base(:rate) | rate_input: raw, rate_error: true}
        end

      _none ->
        base(:rate)
    end
  end

  defp resolve(:security, params, benchmarks) do
    chosen =
      case LiveParam.id(params[@benchmark_param]) do
        nil -> nil
        id -> Enum.find(benchmarks, &(&1.id == id))
      end

    case chosen || List.first(benchmarks) do
      nil -> base(:security)
      security -> %{base(:security) | benchmark: {:security, security}}
    end
  end

  defp base(mode), do: %{mode: mode, benchmark: nil, rate_input: nil, rate_error: false}

  # A typed rate is read as every decimal field reads one
  # (`PortfolixirWeb.DecimalInput`: the page's separator, the other one
  # where it cannot be a thousands group) and bounded by the Wealth page's
  # rate field's one bound (E25 S4; the engine's -99.9999 % to 1000 % p.a.,
  # exact at its scale), so the screen computes exactly what
  # `benchmark=rate:<fraction>` computes.
  defp parse_rate(raw) do
    case DecimalInput.parse(raw) do
      {:ok, percent} -> BenchmarkScope.rate_from_percent(percent)
      _blank_or_invalid -> :error
    end
  end

  defp query_params(uri) do
    case URI.parse(uri) do
      %URI{query: query} when is_binary(query) ->
        try do
          URI.decode_query(query)
        rescue
          _malformed -> %{}
        end

      _none ->
        %{}
    end
  end

  # The same address with the comparison's parameters replaced: every
  # other parameter of the page (its tab, its filters, the locale) rides
  # along exactly as it came.
  defp path_with(uri, pairs) do
    %URI{path: path, query: query} = URI.parse(uri)

    kept =
      (query || "")
      |> String.split("&", trim: true)
      |> Enum.reject(&hindsight_pair?/1)

    added = pairs |> Enum.reject(fn {_key, value} -> value in [nil, ""] end) |> URI.encode_query()

    case Enum.reject(kept ++ [added], &(&1 == "")) do
      [] -> path || "/"
      parts -> (path || "/") <> "?" <> Enum.join(parts, "&")
    end
  end

  defp hindsight_pair?(pair) do
    key = pair |> String.split("=", parts: 2) |> hd()
    key == @param_prefix or String.starts_with?(key, @param_prefix <> "_")
  end

  # A mode keeps its own parameter and drops the others'.
  defp mode_path(uri, :none, _comparison), do: path_with(uri, [{@param_prefix, "none"}])

  defp mode_path(uri, :rate, comparison),
    do: path_with(uri, [{@param_prefix, "rate"}, {@rate_param, comparison.rate_input}])

  defp mode_path(uri, :security, comparison),
    do:
      path_with(uri, [
        {@param_prefix, "security"},
        {@benchmark_param, benchmark_id(comparison.benchmark)}
      ])

  defp benchmark_id({:security, security}), do: Integer.to_string(security.id)
  defp benchmark_id(_other), do: nil

  # -- events --------------------------------------------------------------

  @impl true
  def handle_event("rate", %{"rate" => raw}, socket) do
    raw =
      raw |> LiveParam.string() |> to_string() |> String.trim() |> String.slice(0, @max_rate_echo)

    {:noreply,
     push_patch(socket,
       to: path_with(socket.assigns.uri, [{@param_prefix, "rate"}, {@rate_param, raw}])
     )}
  end

  def handle_event("benchmark", %{"benchmark" => raw}, socket) do
    case LiveParam.id(raw) do
      nil ->
        {:noreply, socket}

      id ->
        {:noreply,
         push_patch(socket,
           to:
             path_with(socket.assigns.uri, [
               {@param_prefix, "security"},
               {@benchmark_param, Integer.to_string(id)}
             ])
         )}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # -- render -----------------------------------------------------------------

  @impl true
  def render(%{rows: []} = assigns) do
    ~H"""
    <div id={@id} hidden></div>
    """
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        group_head: group_head(assigns.comparison),
        legend: legend(assigns.comparison),
        show_name?: is_nil(assigns.security_id),
        spans: span_heads()
      )

    ~H"""
    <section
      id={@id}
      class={[
        "hs-section",
        if(@show_name?, do: "workspace-section", else: "hs-detail-section")
      ]}
      data-role="sale-hindsight"
    >
      <%= if @show_name? do %>
        <h2><%= gettext("After the sale") %></h2>
        <div class="summary-basis hs-basis">
          <%= gettext(
            "Price move per sale in EUR · from the sale day · one row per sale booking"
          ) %>
          <.info />
        </div>
      <% else %>
        <div class="section-title">
          <h3 class="detail-section-title"><%= gettext("After the sale") %></h3>
          <.info section />
        </div>
      <% end %>

      <div class="hs-controls" data-role="hindsight-compare">
        <span class="hs-controls__label" id={"#{@id}-compare-label"}>
          <%= gettext("Comparison") %>
        </span>
        <nav class="segmented-control" aria-labelledby={"#{@id}-compare-label"}>
          <.link
            :for={mode <- modes()}
            patch={mode_path(@uri, mode, @comparison)}
            class={["segmented-control__option", @comparison.mode == mode && "is-active"]}
            aria-current={if @comparison.mode == mode, do: "true"}
            data-mode={mode}
          >
            <%= mode_label(mode) %>
          </.link>
        </nav>
        <form
          :if={@comparison.mode == :rate}
          id={"#{@id}-rate-form"}
          class="hs-controls__field"
          phx-submit="rate"
          phx-target={@myself}
          data-role="hindsight-rate-form"
        >
          <label for={"#{@id}-rate"}><%= gettext("Fixed rate % p.a.") %></label>
          <input
            type="text"
            inputmode="decimal"
            class="num"
            autocomplete="off"
            id={"#{@id}-rate"}
            name="rate"
            value={DecimalInput.value(@comparison.rate_input)}
            aria-invalid={@comparison.rate_error && "true"}
            aria-describedby={@comparison.rate_error && "#{@id}-rate-error"}
          />
          <button type="submit"><%= gettext("Apply") %></button>
        </form>
        <form
          :if={@comparison.mode == :security and @benchmarks != []}
          id={"#{@id}-benchmark-form"}
          class="hs-controls__field"
          phx-change="benchmark"
          phx-target={@myself}
          data-role="hindsight-benchmark-form"
        >
          <label for={"#{@id}-benchmark"} class="visually-hidden"><%= gettext("Benchmark") %></label>
          <select id={"#{@id}-benchmark"} name="benchmark">
            <option
              :for={security <- @benchmarks}
              value={security.id}
              selected={benchmark_id(@comparison.benchmark) == Integer.to_string(security.id)}
            >
              <%= security.name %>
            </option>
          </select>
        </form>
        <span
          :if={@comparison.mode == :security and @benchmarks == []}
          class="hint"
          data-role="benchmark-none"
        >
          <%= gettext("No benchmark securities yet — mark one on the Securities page.") %>
        </span>
      </div>
      <p
        :if={@comparison.rate_error}
        id={"#{@id}-rate-error"}
        class="hint"
        role="alert"
        data-role="hindsight-rate-error"
      >
        <%= gettext("Not a rate to compare with: enter a percentage from -99.9999 to 1000, such as 2.5.") %>
      </p>

      <div class="data-table-wrapper hs-table-wrapper">
        <table class="data-table hs-table">
          <thead>
            <tr class="hs-grouprow">
              <th colspan={if @show_name?, do: 3, else: 2}></th>
              <th colspan="4" class="hs-group">
                <%= gettext("After the sale") %> <span class="hs-group__sub">· <%= @group_head %></span>
              </th>
            </tr>
            <tr>
              <th :if={@show_name?}><%= gettext("Security") %></th>
              <th><%= gettext("Sale") %></th>
              <th class="num"><%= gettext("Start close") %></th>
              <th :for={{label, sub} <- @spans} class="num">
                <%= label %><span :if={sub} class="hs-th-sub"><%= sub %></span>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={entry <- @rows} data-role="hindsight-row" data-sale={entry.row.sale_id}>
              <td :if={@show_name?} data-role="hindsight-name">
                <.link navigate={"/securities/#{entry.security_id}?tab=trades"}>
                  <%= entry.row.security.name %><SecurityNames.twin_id tag={entry.twin_id} />
                </.link>
              </td>
              <td class="hs-sale">
                <%= Format.date(entry.row.date) %> <span class="stat__sub"><%= sale_line(entry.row) %></span>
              </td>
              <.start_cell row={entry.row} />
              <.span_cell :for={span <- entry.row.spans} span={span} />
            </tr>
          </tbody>
        </table>
      </div>

      <ul class="phone-rows hs-phone-rows" aria-label={gettext("After the sale")}>
        <li
          :for={entry <- @rows}
          class="phone-row hs-phone-row"
          data-role="hindsight-phone-row"
          data-sale={entry.row.sale_id}
        >
          <span class="phone-row__body">
            <span :if={@show_name?} class="phone-row__name">
              <%= entry.row.security.name %><SecurityNames.twin_id tag={entry.twin_id} />
            </span>
            <span class="phone-row__ids">
              <%= gettext("Sale") %> <%= Format.date(entry.row.date) %> · <%= sale_line(entry.row) %>
            </span>
            <span class="phone-row__ids"><%= start_line(entry.row) %></span>
          </span>
          <dl class="hs-grid">
            <div
              :for={{span, {label, _sub}} <- Enum.zip(entry.row.spans, @spans)}
              class={["hs-grid__cell" | span_classes(cell(span))]}
              title={cell(span).title}
            >
              <dt><%= label %></dt>
              <dd>
                <.cell_body cell={cell(span)} />
              </dd>
            </div>
          </dl>
        </li>
      </ul>

      <p :if={@report.truncated} class="hint" data-role="hindsight-truncated">
        <%= ngettext(
          "The newest sale; older ones are left out.",
          "The newest %{count} sales; older ones are left out.",
          @report.limit
        ) %>
      </p>
      <p class="summary-basis hs-legend">
        <%= @legend %> · <%= gettext("Price return: distributions after the sale not included") %>
      </p>
    </section>
    """
  end

  attr(:section, :boolean, default: false)

  # The computation basis in words (AGENTS.md: every (a)-(c) metric states
  # its basis; the payload's `computation_basis` says the same for the
  # agent), one clause per line after the first.
  defp info(assigns) do
    ~H"""
    <details
      class={[
        "metric-tooltip metric-tooltip--inline",
        @section && "metric-tooltip--section"
      ]}
      data-role="hindsight-info"
    >
      <summary aria-label={gettext("About this section")}>ⓘ</summary>
      <p role="tooltip"><%= for {line, index} <- Enum.with_index(info_lines()) do %><br :if={index == 1} /><br :if={index > 0} /><%= line %><% end %></p>
    </details>
    """
  end

  defp info_lines do
    [
      gettext(
        "How the sold security moved after the sale: in EUR, over 1, 3 and 12 calendar months from the sale day and up to the latest close."
      ),
      gettext(
        "The start is the close of the sale day or the last one before it, at most %{days} days older; the booked sale price stands beside it and enters no figure.",
        days: WindowReturn.staleness_days()
      ),
      gettext(
        "Price return: distributions after the sale are not booked, so for a dividend payer the figure is too low."
      ),
      gettext(
        "A benchmark security is measured the same way, from the same start day to the same end day; a fixed rate compounds daily over the span's calendar days."
      ),
      gettext(
        "A span that ends after today is still running and has no figure. Where a close or an exchange rate is missing, the span stays without a figure and names the reason: never estimated."
      ),
      gettext(
        "One row per sale booking, not per FIFO lot; a sale with no matched buy counts, a delivery is not a sale."
      )
    ]
  end

  attr(:row, :map, required: true)

  defp start_cell(%{row: %{start: nil}} = assigns) do
    ~H"""
    <td class="num trade-pa--na" title={reason_title(@row.start_reason)}>
      <span aria-hidden="true">—</span> <span class="stat__sub"><%= reason_text(@row.start_reason) %></span>
    </td>
    """
  end

  defp start_cell(assigns) do
    ~H"""
    <td class="num">
      <%= Format.decimal(@row.start.eur_value, 2) %> <small class="value-suffix">EUR</small><%= for line <- start_subs(@row) do %><%= " " %><span class="stat__sub"><%= line %></span><% end %>
    </td>
    """
  end

  # The start close's date where it is not the sale day, and the close in
  # its own currency where that is not EUR.
  defp start_subs(%{start: start, date: date, security: security}) do
    dated =
      if Date.compare(start.date, date) == :eq,
        do: [],
        else: [gettext("Close %{date}", date: Format.date(start.date))]

    native =
      if security.currency_code == "EUR",
        do: [],
        else: ["#{Format.decimal(start.close, 2)} #{security.currency_code}"]

    dated ++ native
  end

  defp start_line(%{start: nil, start_reason: reason}), do: reason_text(reason)

  defp start_line(%{start: start} = row) do
    Enum.join(
      [gettext("Start close") <> " " <> Format.decimal(start.eur_value, 2) <> " EUR"] ++
        start_subs(row),
      " · "
    )
  end

  defp sale_line(row) do
    price = if row.price, do: Format.decimal(row.price, 2), else: "—"
    "#{Format.exact(row.quantity)} × #{price} #{row.currency_code}"
  end

  attr(:span, :map, required: true)

  defp span_cell(assigns) do
    assigns = assign(assigns, :cell, cell(assigns.span))

    ~H"""
    <td
      class={["num", "hs-span" | span_classes(@cell)]}
      title={@cell.title}
      data-span={@span.span}
    >
      <.cell_body cell={@cell} />
    </td>
    """
  end

  attr(:cell, :map, required: true)

  defp cell_body(assigns) do
    ~H"""
    <span class={["hs-lead", @cell.lead_class]}><%= if @cell.lead do %><%= @cell.lead %><% else %><span aria-hidden="true">—</span><% end %></span><%= for line <- @cell.subs do %><%= " " %><span class="stat__sub"><%= line %></span><% end %>
    """
  end

  defp span_classes(%{state: :pending}), do: ["hs-span--open"]
  defp span_classes(%{state: :missing}), do: ["trade-pa--na"]
  defp span_classes(_cell), do: []

  # One span as the screen reads it: the lead figure (nil for the dash),
  # its sign class, the lines under it and the cell's title.
  defp cell(%{status: :pending, end_on: end_on}) do
    %{
      state: :pending,
      lead: gettext("running"),
      lead_class: nil,
      subs: [gettext("until %{date}", date: Format.date(end_on))],
      title: nil
    }
  end

  defp cell(%{status: :incomplete, reason: reason, security: %{return: own}}) do
    %{
      state: :missing,
      lead: nil,
      lead_class: nil,
      subs: ["#{percent(own)} #{gettext("vs.")} —", reason_text(reason)],
      title: reason_title(reason)
    }
  end

  defp cell(%{status: :incomplete, reason: reason}) do
    %{
      state: :missing,
      lead: nil,
      lead_class: nil,
      subs: [reason_text(reason)],
      title: reason_title(reason)
    }
  end

  defp cell(%{status: :complete, difference: %Decimal{} = difference} = span) do
    %{
      state: :value,
      lead: percent(difference),
      lead_class: sign_class(difference),
      subs: [
        "#{percent(span.security.return)} #{gettext("vs.")} #{percent(span.benchmark.return)}"
      ],
      title: nil
    }
  end

  defp cell(%{status: :complete, security: %{return: own}}) do
    %{state: :value, lead: percent(own), lead_class: sign_class(own), subs: [], title: nil}
  end

  defp percent(%Decimal{} = fraction), do: Format.signed_percent(fraction) <> "%"

  defp sign_class(fraction) do
    case Format.displayed_percent_sign(fraction) do
      :positive -> "decimal-positive"
      :negative -> "decimal-negative"
      _zero -> nil
    end
  end

  defp reason_text(:no_start_close), do: gettext("no start close")
  defp reason_text(:no_fx_rate), do: gettext("no exchange rate")
  defp reason_text(:no_benchmark_close), do: gettext("no benchmark close")
  defp reason_text(_no_end_close), do: gettext("no end close")

  defp reason_title(:no_start_close),
    do: gettext("No close on the sale day and none in the 7 days before")

  defp reason_title(:no_fx_rate),
    do: gettext("No stored rate to EUR for one of the two closes")

  defp reason_title(:no_benchmark_close),
    do:
      gettext(
        "The benchmark security has no close for the start or the end; the security's figure stays"
      )

  defp reason_title(_no_end_close),
    do: gettext("No close at the span's end and none in the 7 days before")

  defp span_heads do
    [
      {gettext("1M"), nil},
      {gettext("3M"), nil},
      {gettext("12M"), nil},
      {gettext("To date"), gettext("latest close")}
    ]
  end

  defp mode_label(:none), do: pgettext("hindsight comparison", "None")
  defp mode_label(:rate), do: gettext("Fixed rate")
  defp mode_label(:security), do: gettext("Security")

  defp group_head(%{benchmark: {:rate, rate}}),
    do: gettext("Difference to %{rate} % p.a.", rate: rate_text(rate))

  defp group_head(%{benchmark: {:security, security}}),
    do: gettext("Difference to %{name}", name: security.name)

  defp group_head(_none), do: gettext("The security's price move")

  defp legend(%{benchmark: {:rate, rate}}),
    do:
      gettext("Per span the difference to %{rate} % p.a., below it security vs. rate",
        rate: rate_text(rate)
      )

  defp legend(%{benchmark: {:security, security}}),
    do:
      gettext("Per span the difference to %{name}, below it security vs. benchmark",
        name: security.name
      )

  defp legend(_none), do: gettext("Per span the sold security's price return")

  defp rate_text(rate), do: Format.decimal(Decimal.mult(rate, 100), 2)
end
