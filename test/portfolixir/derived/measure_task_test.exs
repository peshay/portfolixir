defmodule Portfolixir.Derived.MeasureTaskTest do
  use Portfolixir.DataCase, async: false

  import Ecto.Query

  alias Mix.Tasks.Portfolixir.Derived.Measure
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quote
  alias Portfolixir.Derived
  alias Portfolixir.Derived.Memo
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Portfolio

  # User story (#711, ADR-0039 §2 and amendment §4):
  # As the maintainer deciding which derived values to activate,
  # I want the timings produced by a committed command rather than an ad-hoc
  # script,
  # so that the next activation decision can be compared against the last one
  # instead of taken from memory.
  #
  # Acceptance criteria:
  # - The command seeds a synthetic ledger and reports one row per candidate,
  #   with the first and second call timed separately.
  # - The seed is deterministic, so two runs are comparable.
  # - Measuring an empty database says so rather than crashing.

  setup do
    Memo.reset()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  defp output do
    Enum.reduce_while(1..500, [], fn _, acc ->
      receive do
        {:mix_shell, _kind, [line]} -> {:cont, [line | acc]}
      after
        0 -> {:halt, acc}
      end
    end)
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  test "it seeds a synthetic ledger and reports each candidate's first and second call" do
    Measure.run(["--securities", "2", "--bookings", "4", "--years", "1"])

    out = output()

    assert out =~ "Seeding 2 securities, 4 bookings over 1 years"
    assert out =~ "1st (ms)"
    assert out =~ "2nd (ms)"

    # The two walks are the reference rows; the tree candidates prove the
    # seeded classification is there for them to roll up.
    assert out =~ "Performance.analysis/2"
    assert out =~ "Performance.view_analysis/2"
    assert out =~ "Allocation.for_portfolio/3"
    assert out =~ "CategoryResult.for_all_portfolios/2"

    # The seed is real data, not a stub: it is what the timings are timings of.
    assert [%Portfolio{name: "Measurement"}] = Portfolios.list_portfolios()
    assert length(Catalog.list_securities()) == 2
    assert length(Ledger.list_transactions()) == 5
  end

  test "measuring leaves the derived layer's switch exactly as it found it" do
    configured = Application.get_env(:portfolixir, Derived, [])

    Measure.run(["--securities", "1", "--bookings", "1", "--years", "1"])

    assert Application.get_env(:portfolixir, Derived, []) == configured
    refute Derived.enabled?()
  end

  test "an empty database is reported, not crashed on" do
    Measure.run(["--skip-seed"])
    assert output() =~ "No portfolio in this database"
  end

  test "it seeds deterministically, so two runs are comparable" do
    Measure.run(["--securities", "2", "--bookings", "2", "--years", "1"])
    Measure.run(["--securities", "2", "--bookings", "2", "--years", "1"])

    # Four securities now: the second run's two must carry the same quote walk
    # as the first run's two, or two measurements are not comparable.
    closes = closes_by_security()
    assert length(closes) == 4
    assert Enum.take(closes, 2) == Enum.drop(closes, 2)
    refute Enum.at(closes, 0) == []
  end

  defp closes_by_security do
    Quote
    |> order_by([q], asc: q.security_id, asc: q.date)
    |> select([q], {q.security_id, q.close})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end
end
