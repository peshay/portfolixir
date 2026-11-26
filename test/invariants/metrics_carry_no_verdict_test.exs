defmodule Portfolixir.Invariants.MetricsCarryNoVerdictTest do
  @moduledoc """
  ADR-0047 §7 and identity **I6**: no metric payload carries a signal, a
  recommendation, a rating, a score or an action.

  This is the level (a)/(d) boundary made **mechanical** rather than
  remembered. Level (a) reports what the series did — an SMA-50 above an
  SMA-200 is two numbers and a distance. The *rule* that reads a cross-over is
  FR-43, gated at B3.6; scoring whether such a rule works is level (c), and
  replaying it over a history that did not have it is level (d), which is out.

  The check walks the **rendered** payload's key set, not the source, because
  the payload is what a reviewer and an agent both read. Since Sprint 14 it
  walks the **portfolio-scope** payload as well — the `metrics` block FR-40's
  figures added to the risk read (ADR-0047 §9) — so the boundary covers both
  surfaces the record created. Since Sprint 18 it walks the two contribution
  reads too (ADR-0051 §11, I8): a level (b) decomposition carries no ranking
  label either.
  """
  # group: :crash_benchmark -- the async modules that choose the crash
  # benchmark never run at the same time (the closing act of Sprint 29). The
  # choice is one settings row for the instance (settings_key_index), taken
  # under an advisory lock on its key, and a sandboxed test never commits: a
  # module choosing beside another one waited on the other's lock and row
  # until that test ended, into the 15 s query timeout under load. The key
  # is the setting's, so no fixture of a test's own avoids it.
  use PortfolixirWeb.ConnCase, async: true, group: :crash_benchmark

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, buy!: 3, create_security!: 1, deposit!: 3, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Crashes
  alias Portfolixir.Crashes.Rankings
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Settings

  # The five words ADR-0047 §7 names, plus the two the neighbouring gates use
  # for the same thing (B3.6 rules, B3.7 push delivery). Matched as substrings
  # of a key, so `signal_strength` or `buy_score` cannot slip in under a
  # compound name.
  @forbidden ~w(signal recommend rating score action alert verdict advice)

  defp seed_series!(security_id, closes, last) do
    first = Date.add(last, -(length(closes) - 1))

    rows =
      closes
      |> Enum.with_index()
      |> Enum.map(fn {close, index} ->
        %{date: Date.add(first, index), close: Decimal.new(close), source: "manual"}
      end)

    {:ok, _count} = Quotes.upsert_many(security_id, rows)
    :ok
  end

  defp keys(value, acc \\ [])

  defp keys(%{} = map, acc) when not is_struct(map) do
    Enum.reduce(map, acc ++ Map.keys(map), fn {_key, value}, inner -> keys(value, inner) end)
  end

  defp keys(list, acc) when is_list(list),
    do: Enum.reduce(list, acc, fn value, inner -> keys(value, inner) end)

  defp keys(_value, acc), do: acc

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  # User story (ADR-0047 §7, identity I6):
  # As the maintainer holding the scope ladder,
  # I want the metrics payload's key set checked by the build,
  # so that a verdict cannot be added to a level (a) surface by anyone who did
  # not read the record.
  #
  # Acceptance criteria:
  # - No key of the rendered metrics payload contains signal, recommend,
  #   rating, score, action, alert, verdict or advice.
  # - The check runs over a payload with real values AND over one made of gap
  #   markers, so neither shape can carry a verdict key the other hides.
  test "the per-security metrics payload carries no verdict key", %{conn: conn} do
    as_of = ~D[2026-09-19]
    rich = create_security!(name: "Verdict Co", ticker: "VDC")
    thin = create_security!(name: "Thin Verdict Co", ticker: "TVC")

    seed_series!(rich.id, List.duplicate("100", 400), as_of)
    seed_series!(thin.id, ["100", "110"], as_of)

    for security <- [rich, thin] do
      %{"data" => data} =
        conn
        |> get("/api/v1/securities/#{security.id}/metrics", %{"as_of" => Date.to_iso8601(as_of)})
        |> json_response(200)

      # The basis is prose and names the gates it does not open — but `keys/2`
      # collects keys and never values, so the prose is already outside the
      # match and the basis map does not have to be dropped to keep it there.
      # It is walked like everything else: a verdict added as a *key* of the
      # basis would be as much a verdict on the payload as one beside a
      # number.
      offenders =
        data
        |> keys()
        |> Enum.filter(fn key ->
          downcased = String.downcase(to_string(key))
          Enum.any?(@forbidden, &String.contains?(downcased, &1))
        end)
        |> Enum.uniq()

      assert offenders == [],
             "ADR-0047 §7: the metrics payload of #{security.name} carries verdict keys " <>
               "#{inspect(offenders)}. Level (a) reports; a rule over a metric is FR-43 and " <>
               "is gated at B3.6."
    end
  end

  defp offenders(data) do
    data
    |> keys()
    |> Enum.filter(fn key ->
      downcased = String.downcase(to_string(key))
      Enum.any?(@forbidden, &String.contains?(downcased, &1))
    end)
    |> Enum.uniq()
  end

  # Acceptance criteria (ADR-0047 §7 and §9, Sprint 14 Lane A3):
  # - The portfolio-scope metrics on the risk read carry no verdict key, over
  #   a portfolio with computed figures AND over an empty one made of gap
  #   markers.
  # - The walk covers the whole `metrics` block, the correlation matrix and
  #   its `excluded` list included.
  test "the portfolio-scope metrics payload carries no verdict key", %{conn: conn} do
    today = Date.utc_today()
    rich = base_world()
    a = create_security!(name: "Verdict Alpha", ticker: "VAL")
    b = create_security!(name: "Verdict Beta", ticker: "VBE")
    deposit!(rich, "5000", Date.add(today, -200))
    buy!(rich, a, quantity: "10", price: "100", date: Date.add(today, -200))
    buy!(rich, b, quantity: "10", price: "100", date: Date.add(today, -200))

    seed_series!(a.id, Enum.map(0..200, &"#{100 + rem(&1, 7)}"), today)
    seed_series!(b.id, Enum.map(0..200, &"#{100 - rem(&1, 5)}"), today)

    empty = base_world()

    for world <- [rich, empty] do
      %{"data" => data} =
        conn
        |> get("/api/v1/portfolios/#{world.portfolio.id}/risk")
        |> json_response(200)

      assert %{} = data["metrics"]

      assert offenders(data["metrics"]) == [],
             "ADR-0047 §7: the portfolio metrics payload carries verdict keys " <>
               "#{inspect(offenders(data["metrics"]))}. Level (a) reports; a rule over a " <>
               "metric is FR-43 and is gated at B3.6."
    end

    %{"data" => rich_data} =
      conn |> get("/api/v1/portfolios/#{rich.portfolio.id}/risk") |> json_response(200)

    # The rich portfolio really computed — the check is not over gap markers only.
    refute rich_data["metrics"]["volatility"]["90d"]["insufficient_data"]
    refute hd(rich_data["metrics"]["correlations"]["pairs"])["insufficient_data"]
  end

  # User story (#984 rescoped, Sprint 17 T1, plan Lane T's identities):
  # As the maintainer holding the scope ladder,
  # I want the two reads that carry a trade's annualized return checked the
  # same way,
  # so that "was the trade worth it" stays a figure and never becomes a
  # rating of the trade.
  #
  # Acceptance criteria:
  # - No key of GET /api/v1/realized_gains or of
  #   GET /api/v1/securities/:id/trades contains signal, recommend, rating,
  #   score, action, alert, verdict or advice, over a payload with an
  #   annualized figure AND one with its null-and-reason marker.
  test "the trade reads carry no verdict key beside the annualized return", %{conn: conn} do
    world = base_world()
    long = create_security!(name: "Verdict Longhold", ticker: "VLH")
    short = create_security!(name: "Verdict Quickturn", ticker: "VQT")
    deposit!(world, "10000", ~D[2024-01-01])
    buy!(world, long, quantity: "10", price: "100", date: ~D[2024-01-02])
    sell!(world, long, quantity: "10", price: "120", date: ~D[2025-06-30])
    buy!(world, short, quantity: "10", price: "100", date: ~D[2025-03-01])
    sell!(world, short, quantity: "10", price: "90", date: ~D[2025-03-31])

    %{"data" => realized} = conn |> get("/api/v1/realized_gains") |> json_response(200)

    # Both shapes are in the walk: a computed figure and a null with its reason.
    assert Enum.any?(realized["trades"], &is_binary(&1["annualized_return"]))
    assert Enum.any?(realized["trades"], &is_binary(&1["annualized_return_reason"]))

    payloads =
      [realized] ++
        for security <- [long, short] do
          %{"data" => data} =
            conn |> get("/api/v1/securities/#{security.id}/trades") |> json_response(200)

          data
        end

    for data <- payloads do
      assert offenders(data) == [],
             "the trade reads carry verdict keys #{inspect(offenders(data))}: the " <>
               "annualized return is a figure, not a rating of the trade."
    end
  end

  # User story (FR-50, I18 modes 1 and 2; Sprint 25 plan D-3, "No verdict"):
  # As the maintainer holding the scope ladder,
  # I want the read of what a sale missed checked the same way,
  # so that a sale's spans stay figures and never become a judgement such as
  # "sold too early".
  #
  # Acceptance criteria:
  # - No key of GET /api/v1/sales/hindsight contains signal, recommend,
  #   rating, score, action, alert, verdict or advice, without a benchmark
  #   and with one, over complete, pending and incomplete spans, and with
  #   include=reinvestment over a matched and a no_match block (ADR-0057 §5).
  test "the sale hindsight read carries no verdict key", %{conn: conn} do
    world = base_world()
    sold = create_security!(name: "Verdict Sold", ticker: "VSD")
    seed_series!(sold.id, Enum.map(0..400, &"#{100 + rem(&1, 9)}"), ~D[2026-02-27])
    sell!(world, sold, quantity: "1", price: "100", date: ~D[2025-02-03])
    sell!(world, sold, quantity: "1", price: "100", date: Date.add(Date.utc_today(), -2))

    # --- Sprint 26 R2 begin ---
    # What a switch cost (ADR-0057 §5, no verdict): a buy within 30 days of
    # the first sale, so the walk covers a matched block and a no_match one.
    bought = create_security!(name: "Verdict Bought", ticker: "VBT")
    seed_series!(bought.id, Enum.map(0..400, &"#{50 + rem(&1, 7)}"), ~D[2026-02-27])
    buy!(world, bought, quantity: "1", price: "50", date: ~D[2025-02-10])

    paths = [
      "/api/v1/sales/hindsight",
      "/api/v1/sales/hindsight?benchmark=rate:0.02",
      "/api/v1/sales/hindsight?include=reinvestment&benchmark=rate:0.02"
    ]

    # --- Sprint 26 R2 end ---

    for path <- paths do
      %{"data" => data} = conn |> get(path) |> json_response(200)

      statuses = for row <- data["rows"], span <- row["spans"], uniq: true, do: span["status"]
      assert Enum.sort(statuses) == ["complete", "incomplete", "pending"], path

      assert offenders(data) == [],
             "#{path} carries verdict keys #{inspect(offenders(data))}: what a sale missed " <>
               "is a figure, never a judgement of the sale (plan D-3)."
    end

    # --- Sprint 26 R2 begin ---
    %{"data" => switched} = conn |> get(List.last(paths)) |> json_response(200)
    blocks = Enum.map(switched["rows"], & &1["reinvestment"]["status"])
    assert Enum.sort(blocks) == ["matched", "no_match"]
    # --- Sprint 26 R2 end ---
  end

  # User story (FR-41, ADR-0051 §11, identity I8):
  # As the maintainer holding the scope ladder,
  # I want the contribution reads checked the same way,
  # so that "which position made how much" stays a decomposition of a result
  # that happened and never becomes a ranking of the positions.
  #
  # Acceptance criteria:
  # - No key of either contribution read — the portfolio form, narrowed by a
  #   view or not, and the view form across every portfolio — contains
  #   signal, recommend, rating, score, action, alert, verdict or advice,
  #   over a table with positions, remainder lines and an unvalued position
  #   AND over an empty window.
  # - Since #1055 the two performance reads are walked too, and every
  #   payload names a cash account that counted zero for want of a rate
  #   (unvalued_cash_accounts), whose keys are checked like the rows'; each
  #   payload's basis names the field.
  test "the contribution reads carry no verdict key", %{conn: conn} do
    world = base_world()
    gain = create_security!(name: "Verdict Gainer", ticker: "VGN")
    loss = create_security!(name: "Verdict Loser", ticker: "VLS")
    unpriced = create_security!(name: "Verdict Unpriced", ticker: "VUP")
    deposit!(world, "5000", ~D[2025-01-02])
    buy!(world, gain, quantity: "10", price: "100", date: ~D[2025-01-02])
    buy!(world, loss, quantity: "10", price: "100", date: ~D[2025-01-02])
    sell!(world, loss, quantity: "10", price: "80", date: ~D[2025-06-02])
    seed_series!(gain.id, ["100", "120"], ~D[2025-12-31])

    owner = Actor.owner_ui()

    {:ok, _delivery} =
      Ledger.create_transaction(owner, %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: unpriced.id,
        type: "inbound_delivery",
        date: ~D[2025-03-03],
        quantity: "2",
        currency_code: "EUR"
      })

    # A CHF balance no rate ever values (#1055): named on every read below.
    {:ok, franc} =
      Portfolios.create_cash_account(owner, %{
        portfolio_id: world.portfolio.id,
        name: "Verdict Franc",
        currency_code: "CHF"
      })

    {:ok, _franc_deposit} =
      Ledger.create_transaction(owner, %{
        portfolio_id: world.portfolio.id,
        cash_account_id: franc.id,
        type: "deposit",
        date: ~D[2025-02-03],
        gross_amount: "300",
        currency_code: "CHF"
      })

    {:ok, bucket} = Buckets.create_bucket(owner, %{name: "Verdict Bucket"})
    :ok = Buckets.set_depot_default_buckets(owner, world.depot, [bucket.id])
    :ok = Buckets.set_cash_account_buckets(owner, world.cash, [bucket.id])
    :ok = Buckets.set_cash_account_buckets(owner, franc, [bucket.id])
    {:ok, view} = Buckets.create_view(owner, %{name: "Verdict View", include_all: false})
    :ok = Buckets.set_view_buckets(owner, view, [bucket.id], [])

    portfolio = "/api/v1/portfolios/#{world.portfolio.id}/performance/contribution"
    across = "/api/v1/views/#{view.id}/performance/contribution"
    performance = "/api/v1/portfolios/#{world.portfolio.id}/performance"
    view_performance = "/api/v1/views/#{view.id}/performance"

    payloads =
      for path <- [
            "#{portfolio}?year=2025",
            "#{portfolio}?year=2025&view=#{view.id}",
            "#{across}?year=2025",
            "#{portfolio}?from=2001-01-01&to=2001-12-31",
            "#{across}?from=2001-01-01&to=2001-12-31",
            "#{performance}?year=2025",
            "#{view_performance}?year=2025"
          ] do
        %{"data" => data} = conn |> get(path) |> json_response(200)
        {path, data}
      end

    # Both shapes are in the walk: a table with an unvalued row and the
    # remainder, and the empty window.
    {_path, rich} = hd(payloads)
    assert length(rich["positions"]) == 3
    assert Enum.any?(rich["positions"], &(&1["unvalued_reason"] == "no_price"))
    assert Enum.any?(payloads, fn {_path, data} -> data["positions"] == [] end)

    # #1055: every read of 2025 names the CHF account, and every basis says
    # where it is named.
    for {path, data} <- payloads do
      assert data["computation_basis"]["gaps"] =~ "unvalued_cash_accounts", path

      if path =~ "year=2025" do
        assert [%{"name" => "Verdict Franc"}] = data["unvalued_cash_accounts"]
      end
    end

    for {path, data} <- payloads do
      assert offenders(data) == [],
             "#{path} carries verdict keys #{inspect(offenders(data))}: a contribution " <>
               "decomposes a result that happened; it ranks and recommends nothing (ADR-0051 I8)."
    end
  end

  # User story (I23, FR-53; Sprint 27 S2):
  # As the maintainer holding the scope ladder,
  # I want the stacked chart's bands checked the same way,
  # so that a decomposition of the value series stays a decomposition and
  # never ranks or recommends a band.
  #
  # Acceptance criteria:
  # - No key of the bands read, in its three forms and at every level,
  #   merged into other or not, over a window with bands and over an empty
  #   one, contains a forbidden word.
  test "the bands reads carry no verdict key", %{conn: conn} do
    world = base_world()
    deposit!(world, "5000", ~D[2025-01-02])

    for index <- 1..9 do
      security = create_security!(name: "Verdict Band #{index}", ticker: "VB#{index}")
      buy!(world, security, quantity: "1", price: "#{index * 10}", date: ~D[2025-01-02])
    end

    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Verdict Bands"})
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), world.depot, [bucket.id])

    {:ok, view} =
      Buckets.create_view(Actor.owner_ui(), %{name: "Verdict Bands", include_all: false})

    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])

    payloads =
      for form <- [
            "/api/v1/portfolios/#{world.portfolio.id}/performance/bands",
            "/api/v1/views/#{view.id}/performance/bands",
            "/api/v1/performance/bands"
          ],
          query <- [
            "year=2025&level=total",
            "year=2025&level=category",
            "year=2025&level=security&sort=change",
            "from=2001-01-01&to=2001-12-31"
          ] do
        path = "#{form}?#{query}"
        %{"data" => data} = conn |> get(path) |> json_response(200)
        {path, data}
      end

    assert Enum.any?(payloads, fn {_path, data} ->
             Enum.any?(data["bands"], &(&1["key"] == "other"))
           end)

    assert Enum.any?(payloads, fn {_path, data} -> data["bands"] == [] end)

    for {path, data} <- payloads do
      assert offenders(data) == [],
             "#{path} carries verdict keys #{inspect(offenders(data))}: the bands decompose " <>
               "a series that happened; they rank and recommend nothing."
    end
  end

  # --- Sprint 29 C4 begin ---
  # User story (FR-54, ADR-0058 §5 and §8; Sprint 29 C4, walked over the API
  # since C5):
  # As the maintainer holding the scope ladder,
  # I want the crash lists' payload checked the same way,
  # so that a list of who fell and who rose stays a comparison of prices
  # and never says what to buy in the next crash.
  #
  # Acceptance criteria:
  # - No key of the rendered rankings payload of
  #   GET /api/v1/crashes/:key/rankings, for every list, with the
  #   unanswered listed, against a crash benchmark and without one, in the
  #   slim default and under projection=full (I45, Sprint 30 A1), contains
  #   a forbidden word; nor does the windows read, GET /api/v1/crashes.
  test "the crash rankings carry no verdict key", %{conn: conn} do
    index = create_security!(name: "Verdict Crash Index", ticker: "VCI")
    stock = create_security!(name: "Verdict Crash Stock", ticker: "VCS")
    young = create_security!(name: "Verdict Crash Young", ticker: "VCY")
    Quotes.upsert_many(index.id, crash_rows([{~D[2020-02-19], "100"}, {~D[2020-03-23], "70"}]))
    # A close at the recovery span's end, so the rebounders list holds an entry.
    Quotes.upsert_many(
      stock.id,
      crash_rows([{~D[2020-02-19], "50"}, {~D[2020-03-23], "40"}, {~D[2020-06-23], "45"}])
    )

    Quotes.upsert_many(young.id, crash_rows([{~D[2020-03-20], "50"}]))

    {:ok, window} =
      Crashes.create_manual_window(Actor.owner_ui(), %{
        "name" => "Verdict Crash",
        "start" => "2020-02-19",
        "trough" => "2020-03-23"
      })

    keys_read =
      for benchmark <- [nil, index], list <- Rankings.lists(), projection <- ["slim", "full"] do
        {:ok, _setting} =
          Settings.set_crash_benchmark(Actor.owner_ui(), benchmark && benchmark.id)

        path =
          "/api/v1/crashes/m:#{window.id}/rankings?list=#{list}&include_unanswered=true" <>
            "&projection=#{projection}"

        %{"data" => payload} = conn |> get(path) |> json_response(200)
        assert [_entry | _rest] = payload["entries"]
        assert [_unanswered | _rest] = payload["unanswered_entries"]

        %{"data" => windows} = conn |> get("/api/v1/crashes") |> json_response(200)

        for {read, data} <- [{path, payload}, {"/api/v1/crashes", windows}] do
          assert offenders(data) == [],
                 "#{read} carries verdict keys #{inspect(offenders(data))}: ADR-0058 §8, " <>
                   "the lists compare prices and say nothing about what to buy."
        end

        payload |> keys() |> length()
      end

    assert Enum.all?(keys_read, &(&1 > 0))
  end

  defp crash_rows(points),
    do:
      Enum.map(points, fn {date, close} ->
        %{date: date, close: Decimal.new(close), source: "manual"}
      end)

  # --- Sprint 29 C4 end ---

  # --- Sprint 29 H4 begin ---
  # User story (FR-58, ADR-0060 §8, §9; Sprint 29 H4):
  # As the maintainer holding the scope ladder,
  # I want the halving cycles' payload checked the same way,
  # so that a cycle's top, low and intervals stay figures and never become a
  # signal to buy at a low or sell at a top.
  #
  # Acceptance criteria:
  # - No key of the cycles read's payload — windows, tops, lows, the six
  #   intervals with their observations, the halvings and the computation
  #   basis — contains a forbidden word, over a payload with cycles AND over
  #   one with a reason and no cycles.
  # - The walk reads the rendered JSON of GET /api/v1/securities/:id/cycles
  #   (Sprint 29 H6 moved it there from the context), with and without
  #   include=aligned.
  test "the halving cycles payload carries no verdict key", %{conn: conn} do
    agent = Actor.api_token_rw("synthetic-agent")
    rich = create_security!(name: "Verdict Cycle", ticker: "VCY", asset_class: "crypto")
    {:ok, rich} = Catalog.update_security(agent, rich, %{halving_chain: :litecoin})
    bare = create_security!(name: "Verdict Bare", ticker: "VBR", asset_class: "crypto")

    for {k, date, confirmed} <- [
          {1, "2020-01-10", true},
          {2, "2021-01-10", true},
          {3, "2022-01-10", true},
          {4, "2023-01-10", false}
        ] do
      {:ok, _event} =
        Events.create_event(agent, %{
          "security_id" => rich.id,
          "kind" => "halving",
          "chain_height" => k * 840_000,
          "date" => date,
          "timing" => "exact",
          "confirmed" => confirmed,
          "source_quality" => "unverified"
        })
    end

    closes = [
      {~D[2020-01-10], "10"},
      {~D[2020-05-01], "40"},
      {~D[2020-09-01], "8"},
      {~D[2021-01-10], "9"},
      {~D[2021-06-01], "90"},
      {~D[2021-10-01], "30"},
      {~D[2022-01-10], "35"},
      {~D[2022-06-01], "200"},
      {~D[2022-09-01], "120"}
    ]

    rows =
      for {date, close} <- closes, do: %{date: date, close: Decimal.new(close), source: "manual"}

    {:ok, _count} = Quotes.upsert_many(rich.id, rows)

    %{"data" => with_cycles} =
      conn |> get("/api/v1/securities/#{rich.id}/cycles") |> json_response(200)

    %{"data" => aligned} =
      conn |> get("/api/v1/securities/#{rich.id}/cycles?include=aligned") |> json_response(200)

    %{"data" => without} =
      conn |> get("/api/v1/securities/#{bare.id}/cycles") |> json_response(200)

    assert length(with_cycles["cycles"]) == 3
    assert with_cycles["intervals"]["low_to_top"]["n"] == 2
    assert [%{"points" => [_ | _]} | _] = aligned["aligned"]
    assert without["reason"] == "no_halving_chain"

    for payload <- [with_cycles, aligned, without] do
      assert offenders(payload) == [],
             "ADR-0060 §8: the cycles payload carries verdict keys #{inspect(offenders(payload))}; " <>
               "a top, a low and an interval are figures, never a signal."
    end
  end

  # --- Sprint 29 H4 end ---

  # --- Sprint 29 H5 begin ---
  # User story (FR-58, ADR-0060 §8; Sprint 29 H5):
  # As the maintainer holding the scope ladder,
  # I want the analog band's payload walked as well, over a read where both
  # bands, their parts, `agree`, the states and the cones are present,
  # so that a band never becomes a signal to buy in it or sell at its edge.
  #
  # Acceptance criteria:
  # - The walk covers the projection's keys: the bands, `agree`, the states,
  #   every part with its anchor, the cones with their apex, `low_so_far`
  #   (asserted present, so a renamed or missing block cannot pass empty).
  # - No key contains a forbidden word.
  test "the analog band payload carries no verdict key", %{conn: conn} do
    agent = Actor.api_token_rw("synthetic-agent")
    coin = create_security!(name: "Verdict Band", ticker: "VBD", asset_class: "crypto")
    {:ok, coin} = Catalog.update_security(agent, coin, %{halving_chain: :litecoin})

    for {k, date, confirmed} <- [
          {1, "2013-01-10", true},
          {2, "2015-01-10", true},
          {3, "2017-01-10", true},
          {4, "2019-01-10", true},
          {5, "2021-01-05", false}
        ] do
      {:ok, _event} =
        Events.create_event(agent, %{
          "security_id" => coin.id,
          "kind" => "halving",
          "chain_height" => k * 840_000,
          "date" => date,
          "timing" => "exact",
          "confirmed" => confirmed,
          "source_quality" => "unverified"
        })
    end

    closes = [
      {~D[2013-03-01], "50"},
      {~D[2013-06-01], "80"},
      {~D[2014-09-01], "10"},
      {~D[2015-01-10], "9"},
      {~D[2016-03-01], "200"},
      {~D[2016-09-01], "30"},
      {~D[2017-01-10], "50"},
      {~D[2017-08-01], "500"},
      {~D[2018-05-01], "100"},
      {~D[2019-01-10], "470"},
      {~D[2019-10-01], "1500"},
      {~D[2020-05-01], "1000"}
    ]

    rows =
      for {date, close} <- closes, do: %{date: date, close: Decimal.new(close), source: "manual"}

    {:ok, _count} = Quotes.upsert_many(coin.id, rows)

    %{"data" => payload} =
      conn |> get("/api/v1/securities/#{coin.id}/cycles") |> json_response(200)

    walked = keys(payload)

    for key <- ~w(projection not_a_forecast band agree state window_ended parts anchor
                  factors_used cones apex low_so_far chain_source) do
      assert key in walked, "the walk misses #{inspect(key)}"
    end

    assert payload["projection"]["next_low"]["agree"] != nil
    assert payload["projection"]["next_top"]["band"] != nil

    assert offenders(payload) == [],
           "ADR-0060 §8: the band payload carries verdict keys #{inspect(offenders(payload))}; " <>
             "a band is a range with its basis, never a signal."
  end

  # --- Sprint 29 H5 end ---

  # --- S30 T2 begin ---
  # User story (FR-59, ADR-0061 §7, §9; Sprint 30 T2):
  # As the maintainer holding the scope ladder,
  # I want the tops and flops' payload checked the same way,
  # so that a list of what moved most stays an order of figures and never
  # says what to buy or sell.
  #
  # Acceptance criteria:
  # - No key of the rendered payload of GET /api/v1/views/:view_id/movers
  #   and GET /api/v1/movers, for every window, with the unanswered listed,
  #   contains a forbidden word: the two rankings, their halves, their
  #   entries, the unanswered and each computation basis included.
  test "the tops and flops carry no verdict key", %{conn: conn} do
    # The read's own day, so no close lies after the as-of day.
    today = Portfolixir.Clock.today()
    world = base_world()
    deposit!(world, "5000", Date.add(today, -60))
    rising = create_security!(name: "Verdict Movers Rising", ticker: "VMR")
    falling = create_security!(name: "Verdict Movers Falling", ticker: "VMF")
    unpriced = create_security!(name: "Verdict Movers Unpriced", ticker: "VMU")

    for {security, step} <- [{rising, 2}, {falling, -1}] do
      rows =
        for back <- 400..0//-1,
            do: %{
              date: Date.add(today, -back),
              close: Decimal.new(500 + step * (400 - back)),
              source: "manual"
            }

      {:ok, _count} = Quotes.upsert_many(security.id, rows)
    end

    for security <- [rising, falling, unpriced],
        do: buy!(world, security, quantity: "2", price: "500", date: Date.add(today, -30))

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Verdict movers"})

    for window <- ~w(day week month quarter ytd 1y),
        path <- ["/api/v1/views/#{view.id}/movers", "/api/v1/movers"] do
      read = "#{path}?window=#{window}&include_unanswered=true"
      %{"data" => payload} = conn |> get(read) |> json_response(200)

      for side <- ~w(price_return contribution) do
        assert [_entry | _rest] = payload[side]["highest"], "#{read} #{side}"
        assert [_entry | _rest] = payload[side]["lowest"], "#{read} #{side}"
      end

      assert [_unanswered | _rest] = payload["price_return"]["unanswered_entries"]

      assert offenders(payload) == [],
             "#{read} carries verdict keys #{inspect(offenders(payload))}: ADR-0061 §7, a " <>
               "ranking orders figures and says nothing about what to buy or sell."
    end
  end

  # --- S30 T2 end ---

  # --- S31 D2 begin ---
  # User story (FR-60, ADR-0062 §1, §8; Sprint 31 D2):
  # As the maintainer holding the scope ladder,
  # I want the widget catalogue's payload, and a dashboard's, checked the
  # same way,
  # so that a widget, which draws its source's figures and carries none of
  # its own, never carries a verdict either.
  #
  # Acceptance criteria:
  # - No key of GET /api/v1/widgets, nor of the template „Überblick“ as GET
  #   /api/v1/dashboards/template:overview answers it (each item with its
  #   source), contains a forbidden word.
  # - The walk reaches every part (asserted present, so a renamed or
  #   missing block cannot pass empty): the kinds, their sources and period
  #   rules, the groups, the grid and the layout's items.
  test "the widget catalogue and a dashboard carry no verdict key", %{conn: conn} do
    %{"data" => catalogue} = conn |> get("/api/v1/widgets") |> json_response(200)

    %{"data" => template} =
      conn |> get("/api/v1/dashboards/template:overview") |> json_response(200)

    walked = keys(catalogue) ++ keys(template)

    for key <- ~w(widgets title_key sizes source routes function period periods param values
                  ranges translated scope compact groups grid max_items layout settings) do
      assert key in walked, "the walk misses #{inspect(key)}"
    end

    for payload <- [catalogue, template] do
      assert offenders(payload) == [],
             "ADR-0062 §1: the widget payloads carry verdict keys #{inspect(offenders(payload))}; " <>
               "a widget draws its source's figures and says nothing about what to do."
    end
  end

  # --- S31 D2 end ---

  # --- S32 S5 begin ---
  # Words that tell the operator what to do with a price, in the two
  # languages the screen speaks (AGENTS.md, „no advice“; board 05: „ohne
  # ‚günstig‘ oder ‚Kaufchance‘“). Matched case-folded as substrings.
  @verdict_words ~w(buy sell cheap bargain opportunity kauf verkauf günstig chance schnäppchen
                    empfehl) ++ @forbidden

  defp verdict_words(text) do
    folded = String.downcase(text)
    Enum.filter(@verdict_words, &String.contains?(folded, &1))
  end

  # User story (Sprint 32 S5; I61; board 05):
  # As the maintainer holding the scope ladder,
  # I want the widget „Abstand zum Hoch“ walked as a metric payload is —
  # its read's keys and the words it draws, in English and German,
  # so that a distance to a high never reads as a reason to buy.
  #
  # Acceptance criteria:
  # - The widget's read (`DistanceToHigh.read/1`) over a held security walks
  #   every row key (security_id, name, currency, high, high_date,
  #   distance, drawdown) and none carries a forbidden word.
  # - The widget drawn from that read, in English and in German, holds no
  #   verdict word (buy, cheap, opportunity, kauf, günstig, chance, …).
  # - The check's own attack: „Kaufchance“ and "buy_signal" are caught.
  test "the widget „Abstand zum Hoch“ carries no verdict, in its read or its words" do
    require Phoenix.LiveViewTest

    alias PortfolixirWeb.Dashboard.Widget
    alias PortfolixirWeb.Dashboard.Widgets.DistanceToHigh

    world = base_world()
    security = create_security!(name: "Synthetic Fallen")
    today = Portfolixir.Clock.today()
    seed_series!(security.id, Enum.map(1..400, &to_string(100 + rem(&1, 37))), today)
    deposit!(world, "10000", Date.add(today, -399))
    buy!(world, security, quantity: "1", price: "100", date: Date.add(today, -399))

    read = DistanceToHigh.read(nil)
    assert %{state: :ok, rows: [_row]} = read

    for key <- ~w(rows security_id name currency high high_date distance drawdown)a do
      assert key in keys(read), "the walk misses #{inspect(key)}"
    end

    assert offenders(read) == []

    [item] =
      [%{"kind" => "distance_to_high", "size" => "L", "col" => 1, "row" => 1}]
      |> Widget.items(nil, [])
      |> Enum.map(&Widget.with_period(&1, "1y", true))

    for locale <- ~w(en de) do
      html =
        Gettext.with_locale(PortfolixirWeb.Gettext, locale, fn ->
          Phoenix.LiveViewTest.render_component(&DistanceToHigh.widget/1, item: item, card: read)
        end)

      text = html |> Floki.parse_document!() |> Floki.text(sep: " ")
      assert text =~ "Synthetic Fallen"
      assert verdict_words(text) == [], "#{locale}: #{inspect(verdict_words(text))}"
    end

    # The themes that carry it (Sprint 32 S5), as the API answers them.
    for key <- ~w(krypto_lover pullbacks) do
      %{"data" => template} =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer test-api-token")
        |> get("/api/v1/dashboards/template:#{key}")
        |> json_response(200)

      assert offenders(template) == [], key
      assert verdict_words(template["name"] <> " " <> template["subtitle"]) == [], key
    end

    assert verdict_words("Eine Kaufchance") == ["kauf", "chance"]
    assert offenders(%{"buy_signal" => 1}) != []
  end

  # --- S32 S5 end ---

  # --- S32 W4 begin ---
  # User story (Sprint 32 W4; I57; board 02 ②; ADR-0047 §7):
  # As the maintainer holding the scope ladder, where risk stands closest
  # to advice,
  # I want the section widgets of „Risiko“ walked as a metric payload is —
  # their reads' keys and the words they draw, in English and German,
  # so that a breached rule, a band or a threshold never reads as what to
  # do.
  #
  # Acceptance criteria:
  # - The lens's read (`RiskLens.read/1`) walks top_holdings, hhi, metrics
  #   and severity, the own rules' (`OwnRules.read/1`) findings, summary and
  #   state; none carries a forbidden word.
  # - Each widget — Kennzahlen des Portfolios (Zeile, M), Größte
  #   Einzelpositionen, Klumpenrisiko (Zeile, S), Anlageklassen-
  #   Obergrenzen, Eigene Regeln, and the crash section embedded — drawn
  #   in English and in German holds no verdict word outside its ⓘ, whose
  #   method lines name what the widget does not say.
  # - The starter „Risiko“ as the API answers it carries none; the check
  #   catches „Verkaufen“ in a drawn line.
  test "the widgets of „Risiko“ carry no verdict, in their reads or their words" do
    require Phoenix.LiveViewTest

    alias Portfolixir.Portfolios.PolicyRules
    alias PortfolixirWeb.Dashboard.Widget
    alias PortfolixirWeb.Dashboard.Widgets.OwnRules
    alias PortfolixirWeb.Dashboard.Widgets.RiskLens
    alias PortfolixirWeb.Risk.CrashSection

    world = base_world()
    today = Portfolixir.Clock.today()
    big = create_security!(name: "Synthetic Heavy")
    small = create_security!(name: "Synthetic Light")
    seed_series!(big.id, Enum.map(1..120, &to_string(100 + rem(&1, 13))), today)
    seed_series!(small.id, Enum.map(1..120, &to_string(40 + rem(&1, 7))), today)
    deposit!(world, "20000", Date.add(today, -119))
    buy!(world, big, quantity: "100", price: "100", date: Date.add(today, -119))
    buy!(world, small, quantity: "10", price: "40", date: Date.add(today, -119))

    {:ok, _rule} =
      PolicyRules.create_rule(
        Actor.owner_ui(),
        %{
          portfolio_id: world.portfolio.id,
          view_id: nil,
          name: "Heavy cap",
          version: %{
            subject_type: "security",
            security_id: big.id,
            measure: "weight",
            kind: "cap",
            threshold: "10",
            severity: "hard"
          }
        },
        today: today
      )

    lens = RiskLens.read(nil)
    rules = OwnRules.read(nil)
    assert %{state: :ok} = lens
    assert %{state: :ok} = rules

    for key <- ~w(top_holdings hhi metrics severity band)a,
        do: assert(key in keys(lens), "the walk misses #{inspect(key)}")

    for key <- ~w(findings summary state)a,
        do: assert(key in keys(rules), "the walk misses #{inspect(key)}")

    assert offenders(lens) == []
    assert offenders(rules) == []

    item = fn kind, size ->
      [%{"kind" => kind, "size" => size, "col" => 1, "row" => 1}]
      |> Widget.items(nil, [])
      |> Enum.map(&Widget.with_period(&1, "1y", true))
      |> hd()
    end

    drawn = [
      {&RiskLens.key_figures_widget/1, item.("key_figures", "row"), lens},
      {&RiskLens.key_figures_widget/1, item.("key_figures", "M"), lens},
      {&RiskLens.top_holdings_widget/1, item.("top_holdings", "row"), lens},
      {&RiskLens.concentration_widget/1, item.("concentration", "row"), lens},
      {&RiskLens.concentration_widget/1, item.("concentration", "S"), lens},
      {&RiskLens.asset_class_limits_widget/1, item.("asset_class_limits", "row"), lens},
      {&OwnRules.widget/1, item.("own_rules", "row"), rules}
    ]

    # The words a widget draws, its ⓘ left out.
    words = fn html ->
      html
      |> Floki.parse_document!()
      |> Floki.filter_out("[data-role='section-info']")
      |> Floki.text(sep: " ")
    end

    for locale <- ~w(en de) do
      Gettext.with_locale(PortfolixirWeb.Gettext, locale, fn ->
        for {fun, item, card} <- drawn do
          text = words.(Phoenix.LiveViewTest.render_component(fun, item: item, card: card))

          assert text =~ "Synthetic Heavy" or item.kind in ~w(concentration key_figures),
                 "#{item.kind}: #{text}"

          assert verdict_words(text) == [],
                 "#{locale} #{item.kind}: #{inspect(verdict_words(text))}"
        end

        crash =
          Phoenix.LiveViewTest.render_component(CrashSection,
            id: "verdict-crash",
            params: %{},
            view_id: nil,
            base_currency: "EUR",
            embedded: true
          )

        assert verdict_words(words.(crash)) == [], "#{locale} crash section"
      end)
    end

    %{"data" => template} =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")
      |> get("/api/v1/dashboards/template:risk")
      |> json_response(200)

    assert offenders(template) == []
    assert verdict_words(template["name"] <> " " <> template["subtitle"]) == []
    assert verdict_words(words.("<p>Jetzt Verkaufen</p>")) == ["kauf", "verkauf"]
  end

  # --- S32 W4 end ---
end
