defmodule Portfolixir.Crashes.RankingsTest do
  # Sprint 29 C4 (FR-54, #1421; ADR-0058 §5, §6, amendment F2, F3): the
  # lists of a crash window — losers, winners and rebounders — over the
  # catalogue or a view's holdings today, each figure WindowReturn's.
  #
  # Risk tier: money math. Every pinned figure is an exact Decimal,
  # recomputed independently with Python's `decimal` module at the app's
  # precision (34 significant digits, ROUND_HALF_UP, IEEE 754 decimal128),
  # by WindowReturn's formula `(end_close × start_hub) / (start_close ×
  # end_hub) − 1`; each recomputation is written beside its figure. Every
  # name and figure is synthetic.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, put_quotes!: 2, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Crashes
  alias Portfolixir.Fx
  alias Portfolixir.Portfolios.Performance.SaleHindsight
  alias Portfolixir.Settings

  defp d(value), do: Decimal.new(value)

  defp assert_decimal(actual, expected) do
    assert %Decimal{} = actual
    assert Decimal.equal?(actual, d(expected)), "expected #{expected}, got #{inspect(actual)}"
  end

  defp rate!(date, rate, quote_currency \\ "USD") do
    {:ok, 1} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: quote_currency,
          date: date,
          rate: rate,
          source: "manual"
        }
      ])
  end

  defp choose!(security) do
    {:ok, _security} = Settings.set_crash_benchmark(Actor.owner_ui(), security.id)
  end

  defp flag!(security) do
    {:ok, flagged} = Catalog.update_security(Actor.owner_ui(), security, %{is_benchmark: true})
    flagged
  end

  defp agent, do: Actor.api_token_rw("mcp")

  defp names(entries), do: Enum.map(entries, &{&1.rank, &1.security.name, &1.security.isin})

  # The "spring 2020" world: a USD index falling 3386.15 -> 2237.40 from
  # 19 February to 23 March 2020 (recovered on 18 August), EUR/USD hub rates
  # 1.0800 and 1.0720 on the two days, and a catalogue built so every rule
  # of §5 shows: two ties on the figure split by the case-folded name, two
  # equal names split by the ISIN, a USD security, one that rose, one per
  # reason without an answer, a flagged reference instrument.
  defp spring_2020! do
    index = create_security!(name: "Synthetic Broad Index", ticker: "SBI", currency: "USD")

    put_quotes!(index, [
      {~D[2020-02-19], "3386.15"},
      {~D[2020-03-23], "2237.40"},
      {~D[2020-08-18], "3389.78"}
    ])

    rate!(~D[2020-02-19], "1.0800")
    rate!(~D[2020-03-23], "1.0720")

    two_days = fn name, ticker, isin, opts, from, to ->
      security = create_security!([name: name, ticker: ticker, isin: isin] ++ opts)
      put_quotes!(security, [{~D[2020-02-19], from}, {~D[2020-03-23], to}])
      security
    end

    # A lower-case first letter: a byte order would put "Beta" first.
    two_days.("alpha Travel", "ALT", "DE000CRSH002", [], "50", "20")
    two_days.("Beta Cruise", "BCR", "DE000CRSH010", [], "80", "32")
    # One name, two ISINs: the ISIN decides.
    two_days.("Gamma Air", "GA1", "XS000CRSH002", [], "10", "5")
    two_days.("Gamma Air", "GA2", "DE000CRSH028", [], "12", "6")
    two_days.("Delta Tech", "DLT", nil, [currency: "USD"], "100", "90")
    two_days.("Epsilon Gold", "EPG", nil, [], "40", "44")
    # No rate path to EUR at all.
    two_days.("Theta Krone", "THK", nil, [currency: "NOK"], "5", "4")

    # Younger than the window: its first close is after the start.
    young = create_security!(name: "Zeta Young", ticker: "ZYG")
    put_quotes!(young, [{~D[2020-03-01], "10"}, {~D[2020-03-23], "9"}])

    # Its last close is 13 days before the trough: none within 7 days.
    stale = create_security!(name: "Eta Stale", ticker: "ETS")
    put_quotes!(stale, [{~D[2020-02-19], "10"}, {~D[2020-03-10], "9"}])

    # A flagged reference instrument is in no list, though it fell most.
    reference = create_security!(name: "Iota Reference", ticker: "IOR")
    put_quotes!(reference, [{~D[2020-02-19], "100"}, {~D[2020-03-23], "10"}])
    flag!(reference)

    choose!(index)

    %{index: index, key: "d:#{index.id}:2020-02-19"}
  end

  # The index's EUR return over the window, recomputed in Python:
  # (2237.40 × 1.0800) / (3386.15 × 1.0720) − 1
  #   = -0.3343186170354611773464382236595473
  @index_return "-0.3343186170354611773464382236595473"

  # User story (ADR-0058 §5, §6):
  # As the operator, or the agent I run,
  # I want the securities that fell furthest and those that rose in a
  # crash window, each beside the crash benchmark over the same dates,
  # so that I see what the market's fall did across the catalogue.
  #
  # Acceptance criteria:
  # - Losers: the lowest EUR price returns from start to trough by
  #   WindowReturn.price_return/3, each with both ends, the benchmark's
  #   EUR return over the same dates and the difference in points.
  # - Ties by the figure, then the case-folded name, then the ISIN.
  # - The catalogue leaves out flagged securities and the crash benchmark.
  # - No answer is never a zero: counted per reason, ranked nowhere.
  test "losers over the catalogue: exact returns, ties by name and ISIN, no answer counted" do
    %{index: index, key: key} = spring_2020!()

    assert {:ok, losers} = Crashes.rankings(key, "catalogue", list: "losers")

    assert %{
             list: "losers",
             universe: "catalogue",
             limit: 8,
             provisional: false,
             completes_on: nil,
             from: ~D[2020-02-19],
             to: ~D[2020-03-23],
             answered: 6,
             reference_reason: nil
           } = losers

    assert %{key: ^key, kind: "detected", start: ~D[2020-02-19], trough: ~D[2020-03-23]} =
             losers.window

    assert losers.benchmark == %{
             id: index.id,
             name: "Synthetic Broad Index",
             isin: nil,
             currency_code: "USD",
             standing: "unheld"
           }

    assert losers.reference.security_id == index.id
    assert Decimal.to_string(losers.reference.return) == @index_return

    assert names(losers.entries) == [
             {1, "alpha Travel", "DE000CRSH002"},
             {2, "Beta Cruise", "DE000CRSH010"},
             {3, "Gamma Air", "DE000CRSH028"},
             {4, "Gamma Air", "XS000CRSH002"},
             {5, "Delta Tech", nil},
             {6, "Epsilon Gold", nil}
           ]

    [alpha, beta, gamma_de, gamma_xs, delta, epsilon] = losers.entries

    # EUR closes at a rate of exactly 1: 20 / 50 − 1 and 32 / 80 − 1.
    assert_decimal(alpha.return, "-0.6")
    assert_decimal(beta.return, "-0.6")
    assert_decimal(gamma_de.return, "-0.5")
    assert_decimal(gamma_xs.return, "-0.5")
    # Python: (90 × 1.0800) / (100 × 1.0720) − 1
    assert Decimal.to_string(delta.return) == "-0.0932835820895522388059701492537313"
    assert_decimal(epsilon.return, "0.1")

    # The difference in percentage points, (return − index return) × 100,
    # recomputed in Python:
    #   (-0.6 − index) × 100 = -26.56813829645388226535617763404527
    #   (-0.5 − index) × 100 = -16.56813829645388226535617763404527
    #   (delta − index) × 100 = 24.10350349459089385404680744058160
    #   (0.1 − index) × 100 = 43.43186170354611773464382236595473
    assert_decimal(alpha.vs_benchmark_pp, "-26.56813829645388226535617763404527")
    assert_decimal(gamma_xs.vs_benchmark_pp, "-16.56813829645388226535617763404527")
    assert_decimal(delta.vs_benchmark_pp, "24.10350349459089385404680744058160")
    assert_decimal(epsilon.vs_benchmark_pp, "43.43186170354611773464382236595473")

    for entry <- losers.entries do
      assert Decimal.to_string(entry.benchmark_return) == @index_return
    end

    # Both ends are WindowReturn's: the closes, their dates and the rate.
    assert delta.start.date == ~D[2020-02-19]
    assert delta.end.date == ~D[2020-03-23]
    assert_decimal(delta.start.close, "100")
    assert_decimal(delta.end.close, "90")
    assert delta.security.currency_code == "USD"
    refute delta.held

    # No answer, never a zero: one per reason, in no list.
    assert losers.unanswered == %{no_close_at_start: 1, no_close_at_end: 1, no_fx_rate: 1}
    refute Map.has_key?(losers, :unanswered_entries)
  end

  # Acceptance criteria (ADR-0058 §5):
  # - Winners: the highest returns first, ties again by name then ISIN,
  #   negative returns kept with their signs when few rose.
  # - `limit` cuts the entries, never the count of answers.
  # - include_unanswered lists each security without an answer with its
  #   reason, by name.
  test "winners: highest first, cut by limit, the unanswered listed on request" do
    %{key: key} = spring_2020!()

    assert {:ok, winners} =
             Crashes.rankings(key, "catalogue",
               list: "winners",
               limit: 4,
               include_unanswered: true
             )

    assert %{list: "winners", limit: 4, answered: 6} = winners

    assert names(winners.entries) == [
             {1, "Epsilon Gold", nil},
             {2, "Delta Tech", nil},
             {3, "Gamma Air", "DE000CRSH028"},
             {4, "Gamma Air", "XS000CRSH002"}
           ]

    assert Enum.map(winners.unanswered_entries, &{&1.security.name, &1.reason}) == [
             {"Eta Stale", "no_close_at_end"},
             {"Theta Krone", "no_fx_rate"},
             {"Zeta Young", "no_close_at_start"}
           ]
  end

  # Acceptance criteria (ADR-0058 §6; AGENTS.md, the computation basis):
  # - The basis names the benchmark and whether it is flagged, the rule,
  #   the window's dates and kind, the universe, the figure and its dates,
  #   the currencies, the close lookup, the split adjustment, the gaps,
  #   the ties and survivorship.
  test "the basis states what the lists are computed on, survivorship included" do
    %{index: index, key: key} = spring_2020!()

    {:ok, %{basis: basis}} = Crashes.rankings(key, "catalogue", list: "losers")

    assert %{
             benchmark: %{id: id, standing: "unheld"},
             reason: nil,
             rule: "peak_trough_v1",
             threshold: "0.10",
             window: %{key: ^key, kind: "detected", start: ~D[2020-02-19], trough: ~D[2020-03-23]},
             currency: "EUR",
             detection_currency: "USD",
             staleness_days: 7,
             recovery_span_months: 3,
             days_back_unit: "calendar_days"
           } = basis

    assert id == index.id
    assert basis.universe =~ "flagged"
    assert basis.figure =~ "WindowReturn"
    assert basis.close_lookup =~ "7"
    assert basis.split_adjustment =~ "split"
    assert basis.fx =~ "EUR-hub"
    assert basis.gaps =~ "no_close_at_start"
    assert basis.ties =~ "ISIN"
    assert basis.survivorship =~ "removed"
    assert basis.input_series =~ "closes"
  end

  # Acceptance criteria (ADR-0058 §2.5, §7.5):
  # - The lists of a window not yet recovered are provisional, as its
  #   trough is.
  test "the lists of an ongoing window carry its provisional flag" do
    index = create_security!(name: "Synthetic Falling Index", ticker: "SFI")
    put_quotes!(index, [{~D[2024-01-02], "100"}, {~D[2024-02-01], "85"}])
    choose!(index)

    held = create_security!(name: "Synthetic Fund", ticker: "SYF")
    put_quotes!(held, [{~D[2024-01-02], "20"}, {~D[2024-02-01], "19"}])

    assert {:ok, losers} = Crashes.rankings("d:#{index.id}:2024-01-02", "catalogue", [])

    assert %{list: "losers", provisional: true, completes_on: nil} = losers
    assert %{provisional: true} = losers.window
    # 85 / 100 − 1 and 19 / 20 − 1, EUR at exactly 1.
    assert_decimal(losers.reference.return, "-0.15")
    assert [%{rank: 1, return: return, vs_benchmark_pp: pp}] = losers.entries
    assert_decimal(return, "-0.05")
    assert_decimal(pp, "10")
  end

  # User story (ADR-0058 amendment F2):
  # As the operator without a crash benchmark,
  # I want my own window's lists ranked anyway,
  # so that a span I drew needs no market line to be read.
  #
  # Acceptance criteria:
  # - With no crash benchmark chosen, a manual window's lists carry no
  #   reference and no difference in points; the ranking is unchanged.
  # - The answer and its basis say benchmark: nil, reason
  #   "no_crash_benchmark".
  test "without a crash benchmark a manual window's lists carry no reference and say why" do
    falls = create_security!(name: "Synthetic Falls", ticker: "SFA")
    rises = create_security!(name: "Synthetic Rises", ticker: "SRI")
    put_quotes!(falls, [{~D[2022-02-16], "40"}, {~D[2022-03-07], "30"}])
    put_quotes!(rises, [{~D[2022-02-16], "40"}, {~D[2022-03-07], "42"}])

    {:ok, window} =
      Crashes.create_manual_window(agent(), %{
        "name" => "Synthetic War Outbreak",
        "start" => "2022-02-16",
        "trough" => "2022-03-07"
      })

    key = "m:#{window.id}"

    assert {:ok, losers} = Crashes.rankings(key, "catalogue", list: "losers")

    assert %{
             benchmark: nil,
             reference: nil,
             reference_reason: "no_crash_benchmark",
             provisional: false
           } = losers

    assert %{key: ^key, kind: "manual", name: "Synthetic War Outbreak"} = losers.window
    assert %{benchmark: nil, reason: "no_crash_benchmark", rule: nil} = losers.basis
    assert losers.basis.window.kind == "manual"
    assert losers.basis.dates =~ "chosen by a person"

    # 30 / 40 − 1 and 42 / 40 − 1.
    assert [first, second] = losers.entries
    assert {first.security.name, second.security.name} == {"Synthetic Falls", "Synthetic Rises"}
    assert_decimal(first.return, "-0.25")
    assert_decimal(second.return, "0.05")

    for entry <- losers.entries do
      assert entry.benchmark_return == nil
      assert entry.vs_benchmark_pp == nil
    end
  end

  # User story (ADR-0058, Consequences; the Sprint 29 plan's D-1 item 6):
  # As the agent comparing two reads,
  # I want a crash return and a sale's hindsight return over the same
  # dates to agree to the last digit,
  # so that one window return is measured one way everywhere.
  #
  # Acceptance criteria:
  # - A USD security sold on 3 March 2025, read by sale hindsight's 3m span
  #   (to 3 June 2025) against a USD benchmark, and the same security in a
  #   manual window from 3 March to 3 June 2025 with that benchmark as the
  #   crash benchmark: the security's return, the benchmark's return and
  #   the difference agree digit for digit, at moving EUR/USD rates.
  test "a crash return and a sale-hindsight return over the same dates agree to the last digit" do
    world = base_world(name: "Synthetic USD Portfolio", currency: "USD")
    stock = create_security!(name: "Synthetic Stock", ticker: "SYS", currency: "USD")
    index = create_security!(name: "Synthetic USD Index", ticker: "SUI", currency: "USD")

    rate!(~D[2025-03-03], "1.0485")
    rate!(~D[2025-06-03], "1.1372")
    put_quotes!(stock, [{~D[2025-03-03], "187.43"}, {~D[2025-06-03], "203.92"}])
    put_quotes!(index, [{~D[2025-03-03], "5849.72"}, {~D[2025-06-03], "5970.37"}])

    buy!(world, stock, quantity: "4", price: "150", date: ~D[2025-01-02], currency: "USD")
    sell!(world, stock, quantity: "4", price: "187", date: ~D[2025-03-03], currency: "USD")

    choose!(index)

    {:ok, window} =
      Crashes.create_manual_window(agent(), %{
        "name" => "Synthetic Spring 2025",
        "start" => "2025-03-03",
        "trough" => "2025-06-03"
      })

    %{rows: [row]} =
      SaleHindsight.report(today: ~D[2026-11-12], benchmark: {:security, index})

    span = Enum.find(row.spans, &(&1.span == "3m"))
    assert span.end_on == ~D[2025-06-03]

    {:ok, %{entries: [entry]} = losers} =
      Crashes.rankings("m:#{window.id}", "catalogue", list: "losers")

    # The same call, so the same digits: to_string compares every digit
    # and the exponent, not just the value.
    assert Decimal.to_string(entry.return) == Decimal.to_string(span.security.return)
    assert Decimal.to_string(losers.reference.return) == Decimal.to_string(span.benchmark.return)

    assert Decimal.to_string(entry.vs_benchmark_pp) ==
             Decimal.to_string(Decimal.mult(span.difference, 100))

    # Pinned, recomputed in Python:
    #   stock: (203.92 × 1.0485) / (187.43 × 1.1372) − 1
    #        = 0.003118641136400619228012788040704
    #   index: (5970.37 × 1.0485) / (5849.72 × 1.1372) − 1
    #        = -0.0589823888838290528110248105672775
    #   (stock − index) × 100 = 6.210103002022967203903759860798150
    assert Decimal.to_string(entry.return) == "0.003118641136400619228012788040704"
    assert Decimal.to_string(losers.reference.return) == "-0.0589823888838290528110248105672775"
    assert_decimal(entry.vs_benchmark_pp, "6.210103002022967203903759860798150")
  end

  # Acceptance criteria (ADR-0058 §5, §9):
  # - A key that names no window is :not_found; an unknown list, universe
  #   or a limit outside 1..50 is refused by name, before anything is read.
  test "an unknown window, list, universe or limit is refused" do
    %{key: key} = spring_2020!()

    assert {:error, :not_found} = Crashes.rankings("d:1:2020-02-19", "catalogue", [])
    assert {:error, :not_found} = Crashes.rankings("m:999999", "catalogue", [])
    assert {:error, :not_found} = Crashes.rankings("x", "catalogue", [])
    assert {:error, :invalid_list} = Crashes.rankings(key, "catalogue", list: "best")
    assert {:error, :invalid_universe} = Crashes.rankings(key, "everything", [])
    assert {:error, :invalid_universe} = Crashes.rankings(key, "view:01", [])
    assert {:error, :invalid_limit} = Crashes.rankings(key, "catalogue", limit: 0)
    assert {:error, :invalid_limit} = Crashes.rankings(key, "catalogue", limit: 51)
    assert {:ok, %{limit: 50}} = Crashes.rankings(key, "catalogue", limit: 50)
  end
end
