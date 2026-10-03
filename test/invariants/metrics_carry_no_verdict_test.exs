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
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, buy!: 3, create_security!: 1, deposit!: 3, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Ledger

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

    {:ok, bucket} = Buckets.create_bucket(owner, %{name: "Verdict Bucket"})
    :ok = Buckets.set_depot_default_buckets(owner, world.depot, [bucket.id])
    :ok = Buckets.set_cash_account_buckets(owner, world.cash, [bucket.id])
    {:ok, view} = Buckets.create_view(owner, %{name: "Verdict View", include_all: false})
    :ok = Buckets.set_view_buckets(owner, view, [bucket.id], [])

    portfolio = "/api/v1/portfolios/#{world.portfolio.id}/performance/contribution"
    across = "/api/v1/views/#{view.id}/performance/contribution"

    payloads =
      for path <- [
            "#{portfolio}?year=2025",
            "#{portfolio}?year=2025&view=#{view.id}",
            "#{across}?year=2025",
            "#{portfolio}?from=2001-01-01&to=2001-12-31",
            "#{across}?from=2001-01-01&to=2001-12-31"
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

    for {path, data} <- payloads do
      assert offenders(data) == [],
             "#{path} carries verdict keys #{inspect(offenders(data))}: a contribution " <>
               "decomposes a result that happened; it ranks and recommends nothing (ADR-0051 I8)."
    end
  end
end
