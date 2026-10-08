defmodule Portfolixir.ReviewSeedTest do
  # The review seed (priv/demo/finding_surfaces_seed.exs), run as the README
  # runs it, twice, on the test database. Synchronous: it writes names that
  # are unique instance-wide (views, buckets, classifications), which async
  # modules write too. It makes no outbound call: the test configuration
  # keeps logo discovery and the quote and FX sync off, as the seed demands.
  use Portfolixir.DataCase, async: false

  import ExUnit.CaptureIO

  alias Portfolixir.Catalog.Quote
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Ledger.Transaction

  @seed "priv/demo/finding_surfaces_seed.exs"

  # User story (#1126):
  # As the reviewer re-running the review seed on a seeded database, after
  # a migration, as its header advises,
  # I want the second run to leave the quotes alone,
  # so that the screenshots and walkthroughs show the figures a fresh
  # database shows.
  #
  # Acceptance criteria:
  # - A second run writes no quote: every security's quotes, date and
  #   close, are those of the first run, also for the securities the
  #   seed's later steps create after its quote step ran.
  # - It adds no security and no booking either, as the README says.
  test "a second run of the review seed leaves the quotes alone" do
    seed!()
    first = quotes()
    rows = row_counts()
    assert first != []

    seed!()
    second = quotes()

    assert row_counts() == rows
    # Written by the second run: none; changed or removed by it: none.
    assert {length(second -- first), length(first -- second)} == {0, 0}
  end

  defp row_counts,
    do: %{
      securities: Repo.aggregate(Security, :count),
      bookings: Repo.aggregate(Transaction, :count)
    }

  # The seed defines a module; a second run redefines it, as a second
  # `mix run` would in a fresh VM without the warning.
  defp seed! do
    conflicts = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      capture_io(fn -> Code.eval_file(@seed) end)
    after
      Code.put_compiler_option(:ignore_module_conflict, conflicts)
    end
  end

  defp quotes do
    Repo.all(
      from(q in Quote,
        select: {q.security_id, q.date, q.close},
        order_by: [q.security_id, q.date]
      )
    )
  end
end
