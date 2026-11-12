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
      benchmark select with its labelled groups, „Benchmarks“ then „Im
      Bestand“ (ADR-0046's amendment of 2026-11-07; #1416, board
      `ux-design-2026-11-12-sprint29/02`, Q1 A; `PortfolixirWeb.BenchmarkChoices`),
      or the shipped hint when it offers none;
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
  value, its chooser label and its resolution. The fourth, `:reinvestment`
  („Anschlusskauf“, `hindsight=reinvestment`; Sprint 26 R3, I18 mode 3,
  ADR-0057 §6, board frame m3), reads the same report with
  `include: [:reinvestment]`, as `GET /api/v1/sales/hindsight?include=reinvestment`
  does: the third column is „Angelegt“ (what the buys took and its share
  of the proceeds), a span is the difference switched − kept in EUR over
  both sides and, where the sale paid taxes, the taxes the read adds back;
  a matched sale's buys (date, days after the sale, amount or „anteilig“)
  and the cost line of its latest measured span open in a row under it; a
  sale with no match reads its reason across the spans. An unknown
  `hindsight` value is the default comparison.
  """
  use Phoenix.LiveComponent
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Catalog.BenchmarkSecurity
  alias Portfolixir.Portfolios.Performance.SaleHindsight
  alias Portfolixir.Portfolios.Performance.SaleReinvestment
  alias Portfolixir.Portfolios.Performance.WindowReturn
  alias PortfolixirWeb.BenchmarkChoices
  alias PortfolixirWeb.BenchmarkScope
  alias PortfolixirWeb.ControlBar
  alias PortfolixirWeb.DecimalInput
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.LiveEventGuard
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.PrivacyMode
  alias PortfolixirWeb.SecurityNames

  # The chooser's modes in their order; `:reinvestment` is R3's follow-on
  # purchase (I18 mode 3, ADR-0057), read with the API's
  # `include=reinvestment`.
  @modes [:none, :rate, :security, :reinvestment]
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
    groups = BenchmarkChoices.groups()
    comparison = comparison(params, groups)
    groups = BenchmarkChoices.with_chosen(groups, chosen(comparison))

    report =
      SaleHindsight.report(
        benchmark: comparison.benchmark,
        security_id: security_id,
        include: include(comparison)
      )

    rows =
      report.rows
      |> Enum.map(
        &%{row: &1, security_id: &1.security.id, isin: &1.security.isin, wkn: &1.security.wkn}
      )
      |> SecurityNames.put_twin_ids(& &1.row.security.name)

    assign(socket,
      comparison: comparison,
      groups: groups,
      report: report,
      rows: rows
    )
  end

  # -- the comparison, from the address ----------------------------------------

  # The address is the comparison's one source: a chooser link, the rate
  # field and the select all patch it. No `hindsight` reads the first
  # flagged benchmark when one exists, else none (board 02 ③: the default
  # stays the flagged one).
  defp comparison(params, groups) do
    mode = Map.get(@mode_params, params[@param_prefix]) || default_mode(groups)
    resolve(mode, params, groups)
  end

  defp chosen(%{benchmark: {:security, security}}), do: [security]
  defp chosen(_comparison), do: []

  # Mode 3 reads the same rows with the reinvestment block, as
  # `GET /api/v1/sales/hindsight?include=reinvestment` does.
  defp include(%{mode: :reinvestment}), do: [:reinvestment]
  defp include(_comparison), do: []

  defp default_mode([%{key: :flagged} | _groups]), do: :security
  defp default_mode(_groups), do: :none

  defp resolve(:none, _params, _groups), do: %{base(:none) | benchmark: nil}
  defp resolve(:reinvestment, _params, _groups), do: base(:reinvestment)

  defp resolve(:rate, params, _groups) do
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

  # ADR-0058 F5 (#1416, B2): the id in the address is resolved by the
  # API's one rule — any security with a stored quote — so a held fund
  # picked is never dropped to the default; one the rule refuses falls back
  # to the first security the select offers, as before.
  defp resolve(:security, params, groups) do
    chosen =
      with id when is_integer(id) <- LiveParam.id(params[@benchmark_param]),
           {:ok, security} <- BenchmarkSecurity.resolve(id) do
        security
      else
        _none_or_refused -> nil
      end

    case chosen || BenchmarkChoices.first(groups) do
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
    case raw |> without_percent_sign() |> DecimalInput.parse() do
      {:ok, percent} -> BenchmarkScope.rate_from_percent(percent)
      _blank_or_invalid -> :error
    end
  end

  # „2,5 %“ is the rate as it is written, and the field's label names the
  # unit: one trailing percent sign, with the spaces around it, is dropped
  # before the number is read (closing act, the UAT persona on V3). A sign
  # alone leaves nothing, which stays refused.
  defp without_percent_sign(raw), do: String.replace(raw, ~r/\s*%\s*\z/u, "")

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

  defp mode_path(uri, :reinvestment, _comparison),
    do: path_with(uri, [{@param_prefix, "reinvestment"}])

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
        switch?: assigns.comparison.mode == :reinvestment,
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
          <.info switch={@switch?} />
        </div>
      <% else %>
        <div class="section-title">
          <h3 class="detail-section-title"><%= gettext("After the sale") %></h3>
          <.info section switch={@switch?} />
        </div>
      <% end %>

      <%!-- Issue 1435 (Sprint 29 L2; board
           ux-design-2026-11-12-sprint29/06-control-bar ②): a bar of
           labelled controls; the full-width comparison does not fit beside
           a label column on a phone, so below 560 px every label stands
           above its control (B), from one edge. --%>
      <ControlBar.bar class="hs-compare-bar" floor={560} data-role="hindsight-compare">
        <:group label={gettext("Comparison")} label_id={"#{@id}-compare-label"}>
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
        </:group>
        <:group
          :if={@comparison.mode == :rate}
          label={gettext("Fixed rate % p.a.")}
          for={"#{@id}-rate"}
          form={[
            id: "#{@id}-rate-form",
            "phx-submit": "rate",
            "phx-target": @myself,
            "data-role": "hindsight-rate-form"
          ]}
        >
          <span class="hs-compare-bar__field">
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
          </span>
        </:group>
        <:group
          :if={@comparison.mode == :security and @groups != []}
          form={[
            id: "#{@id}-benchmark-form",
            "phx-change": "benchmark",
            "phx-target": @myself,
            "data-role": "hindsight-benchmark-form"
          ]}
        >
          <span class="hs-compare-bar__field">
            <label for={"#{@id}-benchmark"} class="visually-hidden"><%= gettext("Benchmark") %></label>
            <%!-- #1416 (B2; board 02 ③, Q1 A): „Benchmarks“ then „Im
                 Bestand“ as optgroups of the native select. --%>
            <select id={"#{@id}-benchmark"} name="benchmark">
              <optgroup :for={group <- @groups} label={group.label} data-group={group.key}>
                <option
                  :for={security <- group.securities}
                  value={security.id}
                  selected={benchmark_id(@comparison.benchmark) == Integer.to_string(security.id)}
                >
                  <%= BenchmarkChoices.label(group, security) %>
                </option>
              </optgroup>
            </select>
          </span>
        </:group>
        <:group :if={@comparison.mode == :security and @groups == []}>
          <span class="hint" data-role="benchmark-none">
            <%= gettext("No benchmark securities yet — mark one on the Securities page.") %>
          </span>
        </:group>
      </ControlBar.bar>
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
              <th class="num">
                <%= if @switch?, do: gettext("Invested"), else: gettext("Start close") %>
              </th>
              <th :for={{label, sub} <- @spans} class="num">
                <%= label %><span :if={sub} class="hs-th-sub"><%= sub %></span>
              </th>
            </tr>
          </thead>
          <tbody>
            <%= for entry <- @rows do %>
              <tr
                data-role="hindsight-row"
                data-sale={entry.row.sale_id}
                class={matched?(entry.row, @switch?) && "hs-has-detail"}
              >
                <td :if={@show_name?} data-role="hindsight-name">
                  <.link navigate={"/securities/#{entry.security_id}?tab=trades"}>
                    <%= entry.row.security.name %><SecurityNames.twin_id tag={entry.twin_id} />
                  </.link>
                </td>
                <td class="hs-sale">
                  <%= Format.date(entry.row.date) %> <span class="stat__sub"><%= PrivacyMode.html(sale_line(entry.row)) %></span>
                </td>
                <%= if @switch? do %>
                  <.invested_cell block={entry.row.reinvestment} />
                  <td :if={not matched?(entry.row, true)} colspan="4" class="hs-nobuys">
                    <%= no_match_text(entry.row.reinvestment.reason) %>
                  </td>
                <% else %>
                  <.start_cell row={entry.row} />
                <% end %>
                <.span_cell :for={{label, cell} <- cells(entry.row, @switch?)} label={label} cell={cell} />
              </tr>
              <tr
                :if={matched?(entry.row, @switch?)}
                class="hs-detail"
                data-role="hindsight-detail"
                data-sale={entry.row.sale_id}
              >
                <td colspan={if @show_name?, do: 7, else: 6}>
                  <.switch_detail row={entry.row} />
                </td>
              </tr>
            <% end %>
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
              <%= gettext("Sale") %> <%= Format.date(entry.row.date) %> · <%= PrivacyMode.html(sale_line(entry.row)) %>
            </span>
            <span class="phone-row__ids">
              <%= PrivacyMode.html(
                if @switch?, do: invested_line(entry.row.reinvestment), else: start_line(entry.row)
              ) %>
            </span>
          </span>
          <dl :if={not @switch? or matched?(entry.row, true)} class="hs-grid">
            <div
              :for={{{_span, cell}, {label, _sub}} <- Enum.zip(cells(entry.row, @switch?), @spans)}
              class={["hs-grid__cell" | span_classes(cell)]}
              title={cell.title}
            >
              <dt><%= label %></dt>
              <dd>
                <.cell_body cell={cell} />
              </dd>
            </div>
          </dl>
          <p :if={matched?(entry.row, @switch?)} class="hs-detail-phone">
            <.switch_detail row={entry.row} />
          </p>
          <p :if={@switch? and not matched?(entry.row, true)} class="hs-nobuys hs-nobuys--phone">
            <%= no_match_text(entry.row.reinvestment.reason) %>
          </p>
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
  attr(:switch, :boolean, default: false)

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
      <p role="tooltip"><%= for {line, index} <- Enum.with_index(info_lines()) do %><br :if={index == 1} /><br :if={index > 0} /><%= line %><% end %><%= for {line, index} <- Enum.with_index(if(@switch, do: switch_info_lines(), else: [])) do %><br :if={index == 0} /><br /><%= line %><% end %></p>
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

  # Mode 3's three clauses (ADR-0057 §§1-3): the rule, the two sides, the
  # costs; the payload's `computation_basis.reinvestment` says the same.
  defp switch_info_lines do
    [
      gettext(
        "Follow-on purchase: the buys from the sale's cash account, on the sale day or up to %{days} days after it, take the proceeds in date order until they are used up; the last one counts pro rata; sales and buys on the same day share pro rata.",
        days: SaleReinvestment.window_days()
      ),
      gettext(
        "Kept: what the sold position would be worth, scaled to the part of the proceeds invested, price only. Switched: the value of the bought position; before the buy date the money counts as cash at its booked amount."
      ),
      gettext(
        "The booked fees of the sale and the buys are inside the difference. The sale's taxes are named apart and added back to the switched side, because the kept side's latent tax is just as unknown: both sides before tax. The bought position's income is named, not added."
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
      <%= Format.decimal(@row.start.eur_value, 2) %> <small class="value-suffix">EUR</small><%= for line <- start_subs(@row) do %><%= " " %><span class="stat__sub"><%= PrivacyMode.html(line) %></span><% end %>
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

  # A text that may carry a hidden figure (the privacy mode, P1): built by
  # interpolation, which reads it as its stand-in text, and drawn by
  # `PrivacyMode.html/1`, which draws that text as the bar. A masked
  # figure is no binary, so `<>` on it raises.
  defp start_line(%{start: start} = row) do
    Enum.join(
      ["#{gettext("Start close")} #{Format.decimal(start.eur_value, 2)} EUR"] ++
        start_subs(row),
      " · "
    )
  end

  defp sale_line(row) do
    price = if row.price, do: Format.decimal(row.price, 2), else: "—"
    "#{Format.exact(row.quantity)} × #{price} #{row.currency_code}"
  end

  attr(:label, :string, required: true)
  attr(:cell, :map, required: true)

  defp span_cell(assigns) do
    ~H"""
    <td class={["num", "hs-span" | span_classes(@cell)]} title={@cell.title} data-span={@label}>
      <.cell_body cell={@cell} />
    </td>
    """
  end

  # A row's spans as `{label, cell}`: the sale's own spans in modes 1 and 2,
  # its reinvestment block's in mode 3 (none for a sale with no match).
  defp cells(row, false), do: Enum.map(row.spans, &{&1.span, cell(&1)})
  defp cells(%{reinvestment: block}, true), do: Enum.map(block.spans, &{&1.span, switch_cell(&1)})

  attr(:cell, :map, required: true)

  defp cell_body(assigns) do
    ~H"""
    <span class={["hs-lead", @cell.lead_class]}><%= if @cell.lead do %><%= @cell.lead %><% else %><span aria-hidden="true">—</span><% end %><%= if @cell[:suffix] do %> <small class="value-suffix"><%= @cell.suffix %></small><% end %></span><%= for line <- @cell.subs do %><%= " " %><span class="stat__sub"><%= PrivacyMode.html(line) %></span><% end %>
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

  # --- Mode 3: the follow-on purchase (R3; ADR-0057 §§2-4, board 03 m3) ---

  defp matched?(%{reinvestment: %{status: :matched}}, true), do: true
  defp matched?(_row, _switch?), do: false

  # A span of the reinvestment block: the difference switched − kept in
  # EUR over both sides, and the sale's taxes where it paid any, because
  # the read adds them back to the switched side (§3), so the three lines
  # add up to the lead; the cost line of the span is the cell's title.
  defp switch_cell(%{status: :pending} = span), do: cell(span)

  defp switch_cell(%{status: :incomplete, reason: reason, side: side}) do
    %{
      state: :missing,
      lead: nil,
      lead_class: nil,
      subs: [reason_text(reason), side_text(side)],
      title: reason_title(reason)
    }
  end

  defp switch_cell(%{status: :complete, difference: difference} = span) do
    taxes =
      if Format.displayed_sign(span.taxes_apart, 2) == :zero,
        do: [],
        else: [
          gettext("taxes added back %{amount}",
            amount: Format.signed_decimal(span.taxes_apart, 2)
          )
        ]

    %{
      state: :value,
      lead: Format.signed_decimal(difference, 2),
      suffix: "EUR",
      lead_class: money_sign_class(difference),
      subs:
        [
          gettext("kept %{amount}", amount: Format.decimal(span.kept, 2)),
          gettext("switched %{amount}", amount: Format.decimal(span.switched, 2))
        ] ++ taxes,
      title: cost_text(span)
    }
  end

  defp side_text(:switched), do: gettext("switched side")
  defp side_text(_kept), do: gettext("kept side")

  defp money_sign_class(amount) do
    case Format.displayed_sign(amount, 2) do
      :positive -> "decimal-positive"
      :negative -> "decimal-negative"
      _zero -> nil
    end
  end

  attr(:block, :map, required: true)

  defp invested_cell(%{block: %{status: :matched}} = assigns) do
    ~H"""
    <td class="num" data-role="hindsight-invested">
      <%= Format.decimal(invested(@block), 2) %> <small class="value-suffix"><%= @block.currency_code %></small> <span class="stat__sub"><%= share_text(@block) %></span>
    </td>
    """
  end

  defp invested_cell(assigns) do
    ~H"""
    <td class="num trade-pa--na" data-role="hindsight-invested"><span aria-hidden="true">—</span></td>
    """
  end

  # What the matched buys took of the proceeds, in the cash account's
  # currency: the sum of the read's `amount_taken`.
  defp invested(block),
    do: Enum.reduce(block.buys, Decimal.new(0), &Decimal.add(&1.amount_taken, &2))

  defp share_text(block),
    do:
      gettext("%{share} of the proceeds",
        share: Format.percent(block.share_of_proceeds_matched) <> "%"
      )

  defp invested_line(%{status: :matched} = block) do
    "#{gettext("Invested")} #{Format.decimal(invested(block), 2)} #{block.currency_code} · " <>
      share_text(block)
  end

  defp invested_line(_no_match), do: ""

  defp no_match_text(:proceeds_taken_by_earlier_sale),
    do:
      gettext(
        "No follow-on purchases found: the buys within %{days} days were paid from an earlier sale's proceeds",
        days: SaleReinvestment.window_days()
      )

  defp no_match_text(:no_cash_account),
    do:
      gettext(
        "No follow-on purchases found: the sale has no cash account, or no proceeds booked on it"
      )

  defp no_match_text(_no_buy_within_30_days),
    do:
      gettext(
        "No follow-on purchases found: no buy from the sale's cash account within %{days} days of the sale day",
        days: SaleReinvestment.window_days()
      )

  attr(:row, :map, required: true)

  # Under a matched sale: the buys its proceeds went into, then the cost
  # line of its latest measured span, named by that span.
  defp switch_detail(assigns) do
    block = assigns.row.reinvestment

    assigns =
      assign(assigns,
        buys: buy_texts(assigns.row, block),
        costs: block.spans |> Enum.reverse() |> Enum.find(&(&1.status == :complete))
      )

    ~H"""
    <span class="hs-detail__buys"><%= gettext("Proceeds invested in") %>: <%= for {{name, line}, index} <- Enum.with_index(@buys) do %><%= if index > 0, do: "; " %><b><%= name %></b>, <%= PrivacyMode.html(line) %><% end %></span>
    <span :if={@costs} class="hs-detail__costs"><%= span_label(@costs.span) %> · <%= PrivacyMode.html(cost_text(@costs)) %></span>
    """
  end

  defp buy_texts(row, block) do
    block.buys
    |> Enum.with_index()
    |> Enum.map(fn {buy, index} ->
      days = if index == 0, do: block.days_to_first_buy, else: Date.diff(buy.date, row.date)
      {buy_name(buy), buy_line(buy, days, block.currency_code)}
    end)
  end

  defp buy_name(%{security: %{name: name}}), do: name
  defp buy_name(_buy), do: "—"

  defp buy_line(buy, days, currency) do
    amount =
      if Decimal.compare(buy.share_of_buy, 1) == :lt,
        do:
          gettext("pro rata %{part} of %{amount} %{currency}",
            part: Format.decimal(buy.amount_taken, 2),
            amount: Format.decimal(buy.cash_debit, 2),
            currency: currency
          ),
        else: "#{Format.decimal(buy.amount_taken, 2)} #{currency}"

    "#{gettext("bought %{date}", date: Format.date(buy.date))} (#{days_text(days)}), #{amount}"
  end

  defp days_text(0), do: gettext("on the sale day")

  defp days_text(days),
    do: ngettext("%{count} day after the sale", "%{count} days after the sale", days)

  # One span's costs (§3), in EUR at the span end's rate: the fees inside
  # the difference, the sale's taxes added back, the buys' income named.
  defp cost_text(span) do
    Enum.join(
      [
        "#{gettext("Fees, inside the difference")}: #{cost_amount(span.fees_inside)}",
        "#{gettext("The sale's taxes, added back to the switched side")}: #{cost_amount(span.taxes_apart)}",
        "#{gettext("The buys' income, not added")}: #{cost_amount(span.income_apart)}"
      ],
      " · "
    )
  end

  defp cost_amount(amount) do
    if Format.displayed_sign(amount, 2) == :zero,
      do: pgettext("hindsight costs", "none"),
      else: "#{Format.decimal(amount, 2)} EUR"
  end

  defp span_label(label) do
    SaleHindsight.span_labels()
    |> Enum.zip(span_heads())
    |> Enum.find_value(label, fn {key, {head, _sub}} -> if key == label, do: head end)
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
  defp mode_label(:reinvestment), do: gettext("Follow-on purchase")

  defp group_head(%{mode: :reinvestment}), do: gettext("Difference switched − kept, in EUR")

  defp group_head(%{benchmark: {:rate, rate}}),
    do: gettext("Difference to %{rate} % p.a.", rate: rate_text(rate))

  defp group_head(%{benchmark: {:security, security}}),
    do: gettext("Difference to %{name}", name: security.name)

  defp group_head(_none), do: gettext("The security's price move")

  defp legend(%{mode: :reinvestment}),
    do: gettext("Per span switched − kept in EUR, both before tax")

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

  # A rate is a percentage and stays in the privacy mode (P1).
  defp rate_text(rate), do: Format.plain_decimal(Decimal.mult(rate, 100), 2)
end
