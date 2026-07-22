defmodule Portfolixir.Catalog.QuoteAdjustmentTest do
  # Pure engine — no DB, no Repo (AR-2: engines compute, the shell loads).
  use ExUnit.Case, async: true

  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Catalog.QuoteAdjustment
  alias Portfolixir.Catalog.Security

  defp event(date, {p, q}), do: %{date: date, ratio: {p, q}}

  defp quote_row(date, close, source),
    do: %{date: date, close: Decimal.new(close), source: source}

  # User story (ADR-0028 §2, issue #590):
  # As a local portfolio maintainer,
  # I want every stored quote source mapped to an explicit basis — raw or
  # provider mirror — with no catch-all clause,
  # so that adding a quote source without declaring its basis fails tests
  # instead of silently guessing (the double-adjustment trap, AR-7 spirit).
  #
  # Acceptance criteria:
  # - Every value of `Quote.sources/0` has an explicit basis.
  # - "manual" is raw; "auto"/"coingecko"/"portfolio_performance" are
  #   provider mirrors; the trade-price fallback is always raw.
  # - An unknown source raises instead of falling through a default.
  # - The per-security "treat as raw" override forces the raw basis for
  #   synced sources but is irrelevant for already-raw sources.
  describe "basis/2 (total, no catch-all)" do
    test "every declared quote source has an explicit basis" do
      for source <- SecurityQuote.sources() do
        assert QuoteAdjustment.basis(source, %Security{}) in [:raw, :provider_mirror]
      end
    end

    test "manual and the trade fallback are raw; sync sources mirror the provider" do
      assert QuoteAdjustment.basis("manual", %Security{}) == :raw
      assert QuoteAdjustment.basis(:trade, %Security{}) == :raw
      assert QuoteAdjustment.basis("auto", %Security{}) == :provider_mirror
      assert QuoteAdjustment.basis("coingecko", %Security{}) == :provider_mirror
      assert QuoteAdjustment.basis("portfolio_performance", %Security{}) == :provider_mirror
    end

    test "an undeclared source raises instead of guessing a basis" do
      assert_raise FunctionClauseError, fn ->
        QuoteAdjustment.basis("new_provider", %Security{})
      end
    end

    test "the per-security override forces the raw basis for synced rows" do
      flagged = %Security{treat_quotes_as_raw: true}

      assert QuoteAdjustment.basis("coingecko", flagged) == :raw
      assert QuoteAdjustment.basis("portfolio_performance", flagged) == :raw
      assert QuoteAdjustment.basis("auto", flagged) == :raw
      assert QuoteAdjustment.basis("manual", flagged) == :raw
    end
  end

  # User story (ADR-0028 §2/§5, issue #590):
  # As a local portfolio maintainer whose security split,
  # I want raw stored closes displayed divided by the cumulative ratio of all
  # strictly-later splits while provider-mirror closes pass through unchanged,
  # so that the chart is continuous on every basis and no series is ever
  # double-adjusted — with the stored values untouched (NFR-2).
  #
  # Acceptance criteria (deterministic quote-basis matrix, exact Decimals):
  # - Raw-only series: pre-split closes divide by the ratio; a close dated ON
  #   the effective date is post-split basis and stays as stored.
  # - Provider-adjusted series: no additional factor, byte-identical closes.
  # - Mixed series: each row adjusts per its own source.
  # - Sequential splits compound exactly (integer-pair product).
  # - A reverse split multiplies raw pre-split closes up.
  describe "display_close/4 and adjust_series/3 (quote-basis matrix)" do
    test "raw series: closes strictly before the effective date divide by the ratio" do
      events = [event(~D[2026-02-01], {10, 1})]

      before_split =
        QuoteAdjustment.display_close(Decimal.new("100"), ~D[2026-01-31], :raw, events)

      on_split = QuoteAdjustment.display_close(Decimal.new("10"), ~D[2026-02-01], :raw, events)

      after_split =
        QuoteAdjustment.display_close(Decimal.new("10.5"), ~D[2026-02-02], :raw, events)

      assert Decimal.equal?(before_split, Decimal.new("10"))
      assert Decimal.equal?(on_split, Decimal.new("10"))
      assert Decimal.equal?(after_split, Decimal.new("10.5"))
    end

    test "provider-mirror series: no additional factor (already back-adjusted)" do
      events = [event(~D[2026-02-01], {10, 1})]
      close = Decimal.new("10")

      assert QuoteAdjustment.display_close(close, ~D[2026-01-31], :provider_mirror, events) ==
               close
    end

    test "sequential splits compound as an exact integer-pair product" do
      events = [event(~D[2026-02-01], {10, 1}), event(~D[2026-03-01], {1, 3})]

      # 10:1 then 1:3 -> cumulative 10/3; a raw pre-both close of 100 displays
      # as 100 / (10/3) = 30.
      display = QuoteAdjustment.display_close(Decimal.new("100"), ~D[2026-01-15], :raw, events)
      assert Decimal.equal?(display, Decimal.new("30"))

      # Between the two events only the later reverse split applies: 10 / (1/3) = 30.
      between = QuoteAdjustment.display_close(Decimal.new("10"), ~D[2026-02-15], :raw, events)
      assert Decimal.equal?(between, Decimal.new("30"))
    end

    test "a reverse split multiplies raw pre-split closes up" do
      events = [event(~D[2026-02-01], {1, 3})]

      display = QuoteAdjustment.display_close(Decimal.new("30"), ~D[2026-01-15], :raw, events)
      assert Decimal.equal?(display, Decimal.new("90"))
    end

    test "adjust_series/3 keeps stored closes reachable and flags adjusted rows per basis" do
      events = [event(~D[2026-02-01], {2, 1})]

      rows =
        QuoteAdjustment.adjust_series(
          [
            quote_row(~D[2026-01-30], "100", "manual"),
            quote_row(~D[2026-01-31], "50", "coingecko"),
            quote_row(~D[2026-02-01], "50", "coingecko"),
            quote_row(~D[2026-02-02], "51", "manual")
          ],
          events,
          %Security{}
        )

      [manual_before, provider_before, provider_on, manual_after] = rows

      assert Decimal.equal?(manual_before.close, Decimal.new("50"))
      assert Decimal.equal?(manual_before.stored_close, Decimal.new("100"))
      assert manual_before.basis == :raw
      assert manual_before.adjusted?

      assert Decimal.equal?(provider_before.close, Decimal.new("50"))
      assert provider_before.basis == :provider_mirror
      refute provider_before.adjusted?

      refute provider_on.adjusted?

      assert Decimal.equal?(manual_after.close, Decimal.new("51"))
      refute manual_after.adjusted?
    end

    test "with no split events every close passes through as stored" do
      rows =
        QuoteAdjustment.adjust_series(
          [quote_row(~D[2026-01-30], "100", "manual")],
          [],
          %Security{}
        )

      assert [%{close: close, adjusted?: false}] = rows
      assert Decimal.equal?(close, Decimal.new("100"))
    end
  end

  # User story (ADR-0028 §2, issue #590):
  # As a consumer of the valuation and performance walks,
  # I want the raw as-traded close of any row for its own date — and a carry
  # helper that moves a price across effective-date boundaries,
  # so that a daily walk can value every day in that day's own quantity basis
  # regardless of which source priced the day.
  describe "raw_close/4 and rebase_close/4 (walk pricing basis)" do
    test "a provider close before the effective date multiplies back to as-traded" do
      events = [event(~D[2026-02-01], {10, 1})]

      raw = QuoteAdjustment.raw_close(Decimal.new("10"), ~D[2026-01-31], :provider_mirror, events)
      assert Decimal.equal?(raw, Decimal.new("100"))

      raw_on =
        QuoteAdjustment.raw_close(Decimal.new("10"), ~D[2026-02-01], :provider_mirror, events)

      assert Decimal.equal?(raw_on, Decimal.new("10"))
    end

    test "a raw close is already as-traded for its own date" do
      events = [event(~D[2026-02-01], {10, 1})]
      close = Decimal.new("100")

      assert QuoteAdjustment.raw_close(close, ~D[2026-01-31], :raw, events) == close
    end

    test "rebase_close/4 divides by every ratio effective within (from, to]" do
      events = [event(~D[2026-02-01], {10, 1}), event(~D[2026-03-01], {1, 3})]

      carried =
        QuoteAdjustment.rebase_close(Decimal.new("100"), ~D[2026-01-31], ~D[2026-03-01], events)

      # Across both boundaries: 100 / 10 / (1/3) = 30.
      assert Decimal.equal?(carried, Decimal.new("30"))

      unchanged =
        QuoteAdjustment.rebase_close(Decimal.new("100"), ~D[2026-02-01], ~D[2026-02-28], events)

      assert Decimal.equal?(unchanged, Decimal.new("100"))
    end
  end

  # User story (ADR-0028 §2 trade-price-fallback era, issue #590):
  # As a local portfolio maintainer whose security has no quotes,
  # I want the latest-own-trade-price fallback treated as raw basis and
  # divided by the cumulative ratio of splits effective after the trade date,
  # so that a pre-split trade price never values a post-split position at the
  # unsplit price.
  describe "display_trade_price/3 (trade-price fallback era)" do
    test "a pre-split trade price divides by the cumulative later ratio" do
      events = [event(~D[2026-02-01], {10, 1})]

      display = QuoteAdjustment.display_trade_price(Decimal.new("100"), ~D[2026-01-15], events)
      assert Decimal.equal?(display, Decimal.new("10"))
    end

    test "a post-split trade price stays as booked" do
      events = [event(~D[2026-02-01], {10, 1})]
      price = Decimal.new("10")

      assert QuoteAdjustment.display_trade_price(price, ~D[2026-02-01], events) == price
    end
  end

  # User story (ADR-0028 §2 UX-DR11, issue #590):
  # As a user reading the security chart and its chart-as-table,
  # I want the series' basis stated,
  # so that I know whether I look at split-adjusted raw rows, a
  # provider-adjusted mirror, or a mix.
  describe "series_basis/1" do
    test "classifies raw-only, provider-only, mixed and empty series" do
      raw = [%{basis: :raw}, %{basis: :raw}]
      provider = [%{basis: :provider_mirror}]
      mixed = raw ++ provider

      assert QuoteAdjustment.series_basis(raw) == :raw
      assert QuoteAdjustment.series_basis(provider) == :provider_mirror
      assert QuoteAdjustment.series_basis(mixed) == :mixed
      assert QuoteAdjustment.series_basis([]) == :empty
    end
  end

  # User story (ADR-0028 §2 misclassification guard, issue #590):
  # As a maintainer about to book a split,
  # I want the preview to check the stored closes around the effective date
  # against the per-row basis classification,
  # so that a contradiction warns me before a PP-style silent double
  # adjustment — and too few quotes state "insufficient" instead of implying
  # a clean check.
  describe "basis_check/4 (booking-preview basis guard)" do
    test "a raw series with the expected jump is consistent" do
      quotes = [
        quote_row(~D[2026-01-30], "100", "manual"),
        quote_row(~D[2026-02-01], "10", "manual")
      ]

      assert %{status: :consistent, expected_basis: :raw, observed: :jump} =
               QuoteAdjustment.basis_check(quotes, ~D[2026-02-01], {10, 1}, %Security{})
    end

    test "a continuous provider series is consistent for the mirror basis" do
      quotes = [
        quote_row(~D[2026-01-30], "10", "coingecko"),
        quote_row(~D[2026-02-01], "10.2", "coingecko")
      ]

      assert %{status: :consistent, expected_basis: :provider_mirror, observed: :continuous} =
               QuoteAdjustment.basis_check(quotes, ~D[2026-02-01], {10, 1}, %Security{})
    end

    test "a continuous series classified raw contradicts the classification" do
      quotes = [
        quote_row(~D[2026-01-30], "10", "manual"),
        quote_row(~D[2026-02-01], "10.2", "manual")
      ]

      assert %{status: :contradiction, expected_basis: :raw, observed: :continuous} =
               QuoteAdjustment.basis_check(quotes, ~D[2026-02-01], {10, 1}, %Security{})
    end

    test "a jumping series classified as provider mirror contradicts (names the override)" do
      quotes = [
        quote_row(~D[2026-01-30], "100", "coingecko"),
        quote_row(~D[2026-02-01], "10", "coingecko")
      ]

      result = QuoteAdjustment.basis_check(quotes, ~D[2026-02-01], {10, 1}, %Security{})
      assert %{status: :contradiction, expected_basis: :provider_mirror, observed: :jump} = result
    end

    test "a reverse split expects a downward jump on the raw basis" do
      quotes = [
        quote_row(~D[2026-01-30], "30", "manual"),
        quote_row(~D[2026-02-01], "90", "manual")
      ]

      assert %{status: :consistent, observed: :jump} =
               QuoteAdjustment.basis_check(quotes, ~D[2026-02-01], {1, 3}, %Security{})
    end

    test "too few quotes around the effective date report insufficient instead of a clean check" do
      only_before = [quote_row(~D[2026-01-30], "100", "manual")]

      assert %{status: :insufficient_quotes} =
               QuoteAdjustment.basis_check(only_before, ~D[2026-02-01], {10, 1}, %Security{})

      assert %{status: :insufficient_quotes} =
               QuoteAdjustment.basis_check([], ~D[2026-02-01], {10, 1}, %Security{})
    end
  end
end
