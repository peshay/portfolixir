defmodule PortfolixirWeb.Api.V1.SecurityDossier do
  @moduledoc """
  The position dossier (FR-49; idea I7; Sprint 24 plan D-2): one read of one
  security carrying the parts an agent otherwise assembles from eight reads
  (seven before the news block of S28 N6).

  **No part computes anything of its own.** Each is built by the context
  function and the serializer its own read uses, and carries the
  computation basis or note that read carries:

    * `security` — the securities read (`GET /api/v1/securities/:id`);
    * `holdings` — the portfolio holdings read filtered by the security, one
      row per depot (securities account) holding it, across portfolios, and
      `total`, the security's row of the by-security holdings read;
    * `metrics` — the derived-metrics read at its default window;
    * `research` — the research-log read at `limit=5`: the newest five
      entries and `has_more`;
    * `events` — the events read, split at today by `SecurityEvent.span/1`
      (the rule the unconfirmed queue uses): every event whose span has not
      ended, soonest first, and the newest five past ones, newest first;
    * `categories` — `Classifications.list_trees/0`, the read the security
      page's Classifications tab and `GET /api/v1/classifications` use, one
      row per classification with the security's category and its path from
      the root, `nil` where it is not filed;
    * `targets` — the position-target read's rows naming the security, per
      portfolio, in the active plan of the unscoped (Gesamt) view, as that
      read answers without parameters; the parts note says so and names the
      same read with `view=`, which answers a view's plan;
    * `news` (S28 N6, ADR-0056 §9) — `Portfolixir.News.dossier_block/2`:
      the stories of the last 7 days as `news.list` with `since` reads them,
      how many are primary, their highest label materiality, and the newest
      primary story, in about 50 tokens;
    * `cycles` (S29 H6, ADR-0060 §11) — for a security with the cycles view,
      the next low's and the next top's band of
      `Portfolixir.Catalog.SecurityCycles.for_security/1` as `low` and `top`,
      each one array
      `[window from, window to, price from, price to, state, n]`, n the
      fewest observations a present part's time side read; about 40 tokens;
      `nil` without the view.

  Drift is left out on purpose (D-2): it needs a classification and a
  valuation per portfolio, and the `targets` part names the read that states
  it. Read-only: nothing is written.
  """

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecurityCycles
  alias Portfolixir.Catalog.SecurityMetrics
  alias Portfolixir.Classifications
  alias Portfolixir.Clock
  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Knowledge.SecurityEvent
  alias Portfolixir.Ledger
  alias Portfolixir.News
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Bonds
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Portfolios.Valuation
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ListLimit
  alias PortfolixirWeb.Api.V1.NoteController
  alias PortfolixirWeb.Api.V1.SecurityEventController

  # D-2: the newest five research-log entries and the newest five past events.
  @newest 5

  # The deepest category path walked (the tree's own bound, #940), so a
  # malformed parent chain can never loop.
  @max_depth 32

  @parts %{
    security: "GET /api/v1/securities/:id (portfolixir.securities.get)",
    holdings:
      "rows: GET /api/v1/portfolios/:portfolio_id/holdings?security_id=:id " <>
        "(portfolixir.holdings.list), one per depot (securities account) holding it, " <>
        "across portfolios; total: its row of " <>
        "GET /api/v1/holdings/by_security (portfolixir.holdings.by_security)",
    metrics: "GET /api/v1/securities/:id/metrics (portfolixir.securities.metrics), default as_of",
    research:
      "GET /api/v1/securities/:id/notes?limit=5 (portfolixir.notes.list); research.rest pages the rest",
    events:
      "GET /api/v1/securities/:id/events (portfolixir.events.list), split at as_of; " <>
        "events.rest pages the rest",
    categories: "GET /api/v1/classifications (portfolixir.classifications.list)",
    targets:
      "GET /api/v1/portfolios/:portfolio_id/position_targets (portfolixir.targets.list_positions), " <>
        "its rows naming the security in each portfolio's active plan of the unscoped view; " <>
        "a view's plan: GET /api/v1/portfolios/:portfolio_id/position_targets?view=:view_id; " <>
        "targets.drift names the read that states drift",
    # --- S28 N6 begin ---
    news:
      "GET /api/v1/news/stories?security_id=:id&since=<7 days back> (portfolixir.news.list); " <>
        "newest_primary at any age",
    # --- S28 N6 end ---
    # --- S29 H6 begin ---
    cycles:
      "GET /api/v1/securities/:id/cycles (portfolixir.securities.cycles): low and top are " <>
        "projection.next_low's and next_top's band as [window from, to, price from, to, " <>
        "state, n], n the fewest " <>
        "observations of a present part; an analog band, not a forecast; null without the view"
    # --- S29 H6 end ---
  }

  @doc """
  The dossier of the security `id` (an integer or its string form), or
  `:error` when no live security has that id.
  """
  @spec build(integer() | String.t()) :: {:ok, map()} | :error
  def build(id) do
    case Catalog.get_security(id) do
      %Security{} = security -> {:ok, dossier(security)}
      nil -> :error
    end
  end

  defp dossier(%Security{id: id} = security) do
    today = Clock.today()
    portfolio_ids = Enum.map(Portfolios.list_portfolios(), & &1.id)

    %{
      security_id: id,
      as_of: JSON.date(today),
      parts: @parts,
      security: security_part(security),
      holdings: holdings_part(id, portfolio_ids),
      metrics: metrics_part(id),
      research: research_part(id),
      events: events_part(id, today),
      categories: categories_part(id),
      targets: targets_part(id, portfolio_ids),
      # --- S28 N6 begin ---
      news: news_part(id),
      # --- S28 N6 end ---
      # --- S29 H6 begin ---
      cycles: cycles_part(security)
      # --- S29 H6 end ---
    }
  end

  # --- S29 H6 begin ---
  # ADR-0060 §11: the two bands of the cycles read, one array each, as the
  # read renders them; nothing is computed here.
  defp cycles_part(%Security{halving_chain: nil}), do: nil

  defp cycles_part(%Security{id: id}) do
    case SecurityCycles.for_security(id) do
      {:ok, %{reason: nil, projection: projection}} ->
        %{low: band_line(projection.next_low), top: band_line(projection.next_top)}

      {:ok, _no_view} ->
        nil
    end
  end

  defp band_line(%{band: %{window: window, price: price}} = event) do
    n = event.parts |> Enum.filter(& &1.window) |> Enum.map(& &1.n_time) |> Enum.min()

    [window.from, window.to, price.from, price.to, event.state, n]
    |> JSON.plain()
  end

  defp band_line(_no_band), do: nil
  # --- S29 H6 end ---

  # --- S28 N6 begin ---
  # ADR-0056 §9: the news block, its times to the second as the news reads
  # answer them.
  defp news_part(id) do
    block = News.dossier_block(id, DateTime.utc_now())

    case block.newest_primary do
      nil -> block
      story -> %{block | newest_primary: %{story | at: news_time(story.at)}}
    end
  end

  defp news_time(at), do: at |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  # --- S28 N6 end ---

  # The detail `GET /api/v1/securities/:id` answers.
  defp security_part(security) do
    security
    |> Catalog.with_identifier_aliases()
    |> Knowledge.with_thesis_state()
    |> Bonds.with_reading()
    |> JSON.security()
  end

  defp holdings_part(id, portfolio_ids) do
    rows =
      Enum.flat_map(portfolio_ids, fn pid ->
        pid
        |> Ledger.holdings_for_portfolio()
        |> Enum.filter(&(&1.security_id == id))
        |> JSON.holdings(pid)
        |> Map.fetch!(:data)
      end)

    report = JSON.holdings_by_security(Valuation.holdings_by_security_report())

    []
    |> JSON.holdings(nil)
    |> Map.take([:currency_basis, :currency_basis_note, :computation_basis])
    |> Map.merge(%{
      rows: rows,
      total: Enum.find(report.holdings, &(&1.security_id == id)),
      total_basis: Map.take(report, [:currency, :note])
    })
  end

  defp metrics_part(id) do
    {:ok, payload} = SecurityMetrics.for_security(id)
    JSON.security_metrics(payload)
  end

  defp research_part(id) do
    {entries, has_more} =
      id |> Knowledge.list_notes(limit: ListLimit.fetch(@newest)) |> ListLimit.page(@newest)

    %{
      entries: Enum.map(entries, &JSON.security_note/1),
      has_more: has_more,
      log_note: NoteController.log_note(),
      rest: "GET /api/v1/securities/#{id}/notes (portfolixir.notes.list)"
    }
  end

  defp events_part(id, today) do
    {upcoming, past} = id |> Events.list_for_security() |> Enum.split_with(&open?(&1, today))
    newest_past = Enum.reverse(past)

    %{
      upcoming: Enum.map(upcoming, &JSON.security_event/1),
      past: newest_past |> Enum.take(@newest) |> Enum.map(&JSON.security_event/1),
      has_more: length(newest_past) > @newest,
      events_note: SecurityEventController.events_note(),
      rest: "GET /api/v1/securities/#{id}/events (portfolixir.events.list)"
    }
  end

  # Not past: the last day the event could fall on is today or later.
  defp open?(event, today) do
    {_from, to} = SecurityEvent.span(event)
    Date.compare(to, today) != :lt
  end

  defp categories_part(id) do
    Enum.map(Classifications.list_trees(), fn tree ->
      category_id =
        Enum.find_value(tree.assignments, &(&1.security_id == id && &1.category_id))

      %{
        classification_id: tree.classification.id,
        classification_name: tree.classification.name,
        classification_key: tree.classification.key,
        built_in: tree.classification.built_in,
        category: category(tree.categories, category_id)
      }
    end)
  end

  defp category(_categories, nil), do: nil

  defp category(categories, category_id) do
    by_id = Map.new(categories, &{&1.id, &1})

    case path(by_id, category_id, [], @max_depth) do
      [] ->
        nil

      path ->
        path |> List.last() |> Map.put(:path, path)
    end
  end

  defp path(_by_id, nil, acc, _depth), do: acc
  defp path(_by_id, _id, acc, 0), do: acc

  defp path(by_id, id, acc, depth) do
    case Map.fetch(by_id, id) do
      {:ok, category} ->
        step = %{id: category.id, name: category.name, key: category.key}
        path(by_id, category.parent_id, [step | acc], depth - 1)

      :error ->
        acc
    end
  end

  defp targets_part(id, portfolio_ids) do
    rows =
      Enum.flat_map(portfolio_ids, fn pid ->
        pid
        |> Targets.list_position_targets()
        |> Enum.filter(&(&1.security_id == id))
        |> Enum.map(&JSON.position_target/1)
      end)

    %{
      rows: rows,
      drift:
        "GET /api/v1/portfolios/:portfolio_id/position_targets?classification_id=…&min_drift=0 " <>
          "(portfolixir.targets.list_positions with min_drift) states each row's drift_weight " <>
          "as the allocation read (portfolixir.portfolios.allocation) computes it"
    }
  end
end
