defmodule Portfolixir.PeriodsTest do
  # Sprint 32 T1 (I59; ADR-0062's amendment of 2026-11-25, point 6): the
  # period vocabulary, one module, resolved against a given day into the
  # terms the performance family's reads already take. Every case names its
  # day, so none depends on the day the suite runs. Nothing here makes an
  # atom from a key.
  use ExUnit.Case, async: true

  alias Portfolixir.Periods

  # User story:
  # As the operator and my agent,
  # I want every period key of the vocabulary to resolve into one span,
  # the same wherever it is read,
  # so that "lfd. Quartal" or "Vorjahr" means one thing on every widget
  # and every route.
  #
  # Acceptance criteria:
  # - The rolling keys 1d 1w 1m 3m 6m 1y 3y 5y max and the calendar keys
  #   mtd prev_month qtd prev_quarter q1..q4 ytd prev_year are the fixed
  #   keys, in the menu's order.
  # - 1d, 1w, 1m, 3m and 6m are ranges ending today (ADR-0061 §3's money
  #   window); ytd, 1y, 3y, 5y and max stay the read's own keys.
  # - mtd and qtd run from the month's or quarter's first day to today;
  #   prev_month and prev_quarter are the whole previous month or quarter,
  #   across a year's turn; q1..q4 are the current year's quarters, one
  #   not yet begun refused; prev_year and year:YYYY are a calendar year,
  #   a year not yet begun refused.
  test "the fixed keys, in the menu's order" do
    assert Periods.rolling() == ~w(1d 1w 1m 3m 6m 1y 3y 5y max)
    assert Periods.calendar() == ~w(mtd prev_month qtd prev_quarter q1 q2 q3 q4 ytd prev_year)
    assert Periods.keys() == Periods.rolling() ++ Periods.calendar()
  end

  test "the rolling keys on a quarter's end, a leap day and the first of a year" do
    for {today, expected} <- [
          {~D[2026-03-31],
           %{
             "1d" => {:range, ~D[2026-03-31], ~D[2026-03-31]},
             "1w" => {:range, ~D[2026-03-25], ~D[2026-03-31]},
             "1m" => {:range, ~D[2026-03-01], ~D[2026-03-31]},
             "3m" => {:range, ~D[2026-01-01], ~D[2026-03-31]},
             "6m" => {:range, ~D[2025-10-01], ~D[2026-03-31]}
           }},
          {~D[2024-02-29],
           %{
             "1d" => {:range, ~D[2024-02-29], ~D[2024-02-29]},
             "1w" => {:range, ~D[2024-02-23], ~D[2024-02-29]},
             "1m" => {:range, ~D[2024-01-30], ~D[2024-02-29]},
             "3m" => {:range, ~D[2023-11-30], ~D[2024-02-29]},
             "6m" => {:range, ~D[2023-08-30], ~D[2024-02-29]}
           }},
          {~D[2027-01-01],
           %{
             "1d" => {:range, ~D[2027-01-01], ~D[2027-01-01]},
             "1w" => {:range, ~D[2026-12-26], ~D[2027-01-01]},
             "1m" => {:range, ~D[2026-12-02], ~D[2027-01-01]},
             "3m" => {:range, ~D[2026-10-02], ~D[2027-01-01]},
             "6m" => {:range, ~D[2026-07-02], ~D[2027-01-01]}
           }}
        ],
        {key, term} <- expected do
      assert Periods.resolve(key, today) == {:ok, term}, "#{key} on #{today}"
    end

    for key <- ~w(ytd 1y 3y 5y max),
        today <- [~D[2026-03-31], ~D[2024-02-29], ~D[2027-01-01]] do
      assert Periods.resolve(key, today) == {:ok, key}
    end
  end

  test "the calendar keys on a month's end, a leap day, the first of a year and of a quarter" do
    # The last day of a quarter: mtd is the whole month, qtd the whole
    # quarter, q2 to q4 not yet begun.
    today = ~D[2026-03-31]
    assert Periods.resolve("mtd", today) == {:ok, {:range, ~D[2026-03-01], today}}
    assert Periods.resolve("prev_month", today) == {:ok, {:range, ~D[2026-02-01], ~D[2026-02-28]}}
    assert Periods.resolve("qtd", today) == {:ok, {:range, ~D[2026-01-01], today}}

    assert Periods.resolve("prev_quarter", today) ==
             {:ok, {:range, ~D[2025-10-01], ~D[2025-12-31]}}

    assert Periods.resolve("q1", today) == {:ok, {:range, ~D[2026-01-01], ~D[2026-03-31]}}
    assert Periods.resolve("q2", today) == {:error, :not_begun}
    assert Periods.resolve("q4", today) == {:error, :not_begun}
    assert Periods.resolve("prev_year", today) == {:ok, {:year, 2025}}

    # 29 February: the previous month is January, the month to date the
    # whole of February.
    leap = ~D[2024-02-29]
    assert Periods.resolve("mtd", leap) == {:ok, {:range, ~D[2024-02-01], leap}}
    assert Periods.resolve("prev_month", leap) == {:ok, {:range, ~D[2024-01-01], ~D[2024-01-31]}}

    # 1 March after a leap day: the previous month ends on the 29th.
    assert Periods.resolve("prev_month", ~D[2024-03-01]) ==
             {:ok, {:range, ~D[2024-02-01], ~D[2024-02-29]}}

    # 1 January: the month, the quarter and the year to date are one day;
    # the previous month, quarter and year lie in the year before; every
    # quarter but q1 is not yet begun.
    new_year = ~D[2027-01-01]
    assert Periods.resolve("mtd", new_year) == {:ok, {:range, new_year, new_year}}
    assert Periods.resolve("qtd", new_year) == {:ok, {:range, new_year, new_year}}

    assert Periods.resolve("prev_month", new_year) ==
             {:ok, {:range, ~D[2026-12-01], ~D[2026-12-31]}}

    assert Periods.resolve("prev_quarter", new_year) ==
             {:ok, {:range, ~D[2026-10-01], ~D[2026-12-31]}}

    assert Periods.resolve("q1", new_year) == {:ok, {:range, ~D[2027-01-01], ~D[2027-03-31]}}

    for key <- ~w(q2 q3 q4),
        do: assert(Periods.resolve(key, new_year) == {:error, :not_begun}, key)

    assert Periods.resolve("prev_year", new_year) == {:ok, {:year, 2026}}

    # The first day of a quarter: qtd is that day, q3 has begun, q4 not.
    first = ~D[2026-07-01]
    assert Periods.resolve("qtd", first) == {:ok, {:range, first, first}}

    assert Periods.resolve("prev_quarter", first) ==
             {:ok, {:range, ~D[2026-04-01], ~D[2026-06-30]}}

    assert Periods.resolve("q3", first) == {:ok, {:range, ~D[2026-07-01], ~D[2026-09-30]}}
    assert Periods.resolve("q2", first) == {:ok, {:range, ~D[2026-04-01], ~D[2026-06-30]}}
    assert Periods.resolve("q4", first) == {:error, :not_begun}
  end

  test "year:YYYY names a calendar year, a year not yet begun refused" do
    today = ~D[2026-11-25]

    assert Periods.resolve("year:2026", today) == {:ok, {:year, 2026}}
    assert Periods.resolve("year:2019", today) == {:ok, {:year, 2019}}
    assert Periods.resolve("year:1970", today) == {:ok, {:year, 1970}}
    assert Periods.resolve("year:2027", today) == {:error, :not_begun}

    for key <- ~w(year:1969 year:26 year:02026 year:+2026 year:2026x year: YEAR:2026),
        do: assert(Periods.resolve(key, today) == {:error, :unknown_period}, key)
  end

  # User story:
  # As the operator,
  # I want the periods a dashboard already offered to resolve exactly as
  # they did before the vocabulary,
  # so that no figure an existing key returns moves (Sprint 31's alignment
  # of the short periods with ADR-0061 §3 stays).
  #
  # Acceptance criteria:
  # - 1d, 1w, 1m and 3m resolve to the ranges the dashboard sent as
  #   from/to before (Sprint 31 closing act, C1 and MO1), on the days the
  #   registry's test pinned them.
  # - ytd, 1y, 3y, 5y and max are the read's own keys, as the routes passed
  #   them through.
  test "every key the dashboard and the routes took before resolves as before" do
    assert Periods.resolve("1d", ~D[2026-11-21]) ==
             {:ok, {:range, ~D[2026-11-21], ~D[2026-11-21]}}

    assert Periods.resolve("1w", ~D[2026-11-21]) ==
             {:ok, {:range, ~D[2026-11-15], ~D[2026-11-21]}}

    assert Periods.resolve("1m", ~D[2026-11-21]) ==
             {:ok, {:range, ~D[2026-10-22], ~D[2026-11-21]}}

    assert Periods.resolve("3m", ~D[2026-05-31]) ==
             {:ok, {:range, ~D[2026-03-01], ~D[2026-05-31]}}

    for key <- ~w(ytd 1y 3y 5y max),
        do: assert(Periods.resolve(key, ~D[2026-11-21]) == {:ok, key})
  end

  # Attack (AGENTS.md: no atoms from input): a key is matched against a
  # closed set as a string; anything else is refused and makes no atom.
  test "an unknown key is refused and makes no atom" do
    today = ~D[2026-11-25]
    fresh = "period_#{System.unique_integer([:positive])}"

    assert Periods.resolve(fresh, today) == {:error, :unknown_period}
    assert_raise ArgumentError, fn -> String.to_existing_atom(fresh) end

    for key <- ["", "1Y", " 1y", "q5", "q0", "quarter", "prev_week", :"1y", 1, nil] do
      assert Periods.resolve(key, today) == {:error, :unknown_period}, inspect(key)
      refute Periods.key?(key), inspect(key)
    end

    assert Periods.key?("q4")
    assert Periods.key?("year:2030")
  end
end
