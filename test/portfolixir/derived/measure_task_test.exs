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
    Measure.run(["--securities", "2", "--bookings", "2", "--years", "1", "--write-synthetic"])

    # Four securities now: the second run's two must carry the same quote walk
    # as the first run's two, or two measurements are not comparable.
    closes = closes_by_security()
    assert length(closes) == 4
    assert Enum.take(closes, 2) == Enum.drop(closes, 2)
    refute Enum.at(closes, 0) == []
  end

  # User story (security review 2026-10-12, K04):
  # As the operator running from source, whose development database holds my
  # real records,
  # I want the measurement task to refuse to write its synthetic ledger into
  # a database that already holds a portfolio unless I say so explicitly, to
  # say in its one-line help that it writes, and to journal what it writes
  # under its own name,
  # so that a measurement never pollutes my ledger by accident and the
  # journal tells its writes from mine.
  #
  # Acceptance criteria:
  # - With a portfolio present and no --write-synthetic, run/1 raises naming
  #   the database and the flag, and writes nothing.
  # - --skip-seed measures what is there without the flag.
  # - With --write-synthetic it seeds, and every journal entry of the seed is
  #   attributed to the system job "derived_measure".
  # - The shortdoc says the task writes.
  test "it refuses to seed beside an existing portfolio unless told to, and journals as itself" do
    {:ok, _} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Operator Portfolio",
        base_currency_code: "EUR"
      })

    database = Repo.config()[:database]
    entries_before = Repo.aggregate("audit_journal", :count)
    last_before = Repo.one(from(e in "audit_journal", select: max(e.id)))

    error =
      assert_raise Mix.Error, fn ->
        Measure.run(["--securities", "1", "--bookings", "1", "--years", "1"])
      end

    assert error.message =~ database
    assert error.message =~ "--write-synthetic"
    assert [%Portfolio{name: "Operator Portfolio"}] = Portfolios.list_portfolios()
    assert Catalog.list_securities() == []
    assert Repo.aggregate("audit_journal", :count) == entries_before

    Measure.run(["--skip-seed"])
    assert output() =~ "1st (ms)"
    assert length(Portfolios.list_portfolios()) == 1

    Measure.run(["--securities", "1", "--bookings", "1", "--years", "1", "--write-synthetic"])
    assert length(Portfolios.list_portfolios()) == 2

    actors =
      Repo.all(
        from(e in "audit_journal",
          where: e.id > ^last_before,
          distinct: true,
          select: {e.actor_type, e.actor_label}
        )
      )

    assert actors == [{"system_job", "derived_measure"}]
    assert Mix.Task.shortdoc(Measure) =~ "writes"
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
