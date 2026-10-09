defmodule Portfolixir.ReviewSeedTest do
  # The review seed (priv/demo/finding_surfaces_seed.exs), run as the README
  # runs it, twice, on the test database. Synchronous: it writes names that
  # are unique instance-wide (views, buckets, classifications), which async
  # modules write too. It makes no outbound call: the test configuration
  # keeps logo discovery and the quote and FX sync off, as the seed demands.
  use Portfolixir.DataCase, async: false

  import Ecto.Query
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

  # User story (#1127, Sprint 20 γ closing act, the correctness hunter):
  # As the reviewer walking the review instance's data-quality surfaces,
  # I want the README and the seed to name the held security that stores no
  # asset class,
  # so that the "Unclassified" surface is looked for where it is.
  #
  # Acceptance criteria:
  # - "Placeholder Anleihe 2031 3,25%", the delivered position with no
  #   price, keeps its name and stores bond (#1127 reads its bond word);
  #   "Ostsee Logistik 4,10% 2028/2033" stores no asset class.
  # - The README names Ostsee Logistik as the held security with no asset
  #   class and no longer says the delivered position has none; the seed's
  #   step 2 says the same.
  test "the README names the held security that stores no asset class" do
    seed!()

    assert stored_class("Placeholder Anleihe 2031 3,25%") == "bond"
    assert stored_class("Ostsee Logistik 4,10% 2028/2033") == nil

    for path <- ["priv/demo/README.md", @seed] do
      text = path |> File.read!() |> String.replace(~r/[\s#]+/, " ")

      assert text =~
               "the held security with no asset class is \"Ostsee Logistik 4,10% 2028/2033\"",
             path

      refute text =~ "a delivered position with no price and no asset class", path
      refute text =~ "no quote at all and no asset class", path
    end
  end

  defp stored_class(name) do
    Repo.one!(from(s in Security, where: s.name == ^name, select: s.asset_class))
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
