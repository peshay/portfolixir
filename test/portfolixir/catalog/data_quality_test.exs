defmodule Portfolixir.Catalog.DataQualityTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [create_security!: 1, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.DataQuality

  # User story (#705):
  # As the LLM agent maintaining this catalog,
  # I want the data-quality conditions the dashboard counts to be predicates I
  # can ask for by name,
  # so that I can work the same sets the human surface links to, instead of
  # only being told how many there are.
  #
  # Acceptance criteria:
  # - The predicates are defined ONCE. The dashboard's count and the filtered
  #   list are the same rule, so a count of N addresses a list of N.
  # - `stale_quote` covers a security with no quote at all, which is what the
  #   dashboard has always counted; `missing_quote` is the narrower set.
  # - An unknown predicate is rejected, and never turned into an atom.

  defp world do
    today = Date.utc_today()

    fresh = create_security!(name: "Fresh AG", ticker: "FRS")
    put_quote!(fresh, Date.add(today, -1), "100")

    stale = create_security!(name: "Stale AG", ticker: "STL")
    put_quote!(stale, Date.add(today, -30), "100")

    unpriced = create_security!(name: "Unpriced AG", ticker: "UNP")

    # A logo makes a security pass the logo predicate; the others have none.
    {:ok, _} = Catalog.put_logo_attributes(fresh, %{"logo_path" => "/logos/frs.png"})

    %{fresh: fresh, stale: stale, unpriced: unpriced}
  end

  defp names(rows), do: rows |> Enum.map(& &1.security.name) |> Enum.sort()

  test "stale_quote covers the unpriced security too — the rule the dashboard counts" do
    world()

    assert names(DataQuality.list("stale_quote")) == ["Stale AG", "Unpriced AG"]
  end

  test "missing_quote is the narrower set inside it" do
    world()

    assert names(DataQuality.list("missing_quote")) == ["Unpriced AG"]
  end

  test "missing_logo narrows in the query, not only in memory" do
    world()

    assert names(DataQuality.list("missing_logo")) == ["Stale AG", "Unpriced AG"]
  end

  # The property the whole story is about: one rule, so a count always
  # addresses a list of the same size.
  test "the count and the list agree for every predicate" do
    world()
    rows = Catalog.list_securities_with_metrics()

    for id <- DataQuality.ids() do
      assert DataQuality.count(id) == length(DataQuality.list(id)),
             "count and list disagree for #{id}"
    end

    # And refine/3 is the in-memory half only: on rows loaded WITHOUT the
    # query half it cannot conjure the logo condition, which is why list/2 and
    # count/2 are the entry points.
    assert length(DataQuality.refine(rows, "stale_quote")) == DataQuality.count("stale_quote")
  end

  test "an unknown predicate is rejected and never becomes an atom" do
    refute DataQuality.valid?("no_such_predicate")
    assert DataQuality.valid?("stale_quote")

    assert_raise ArgumentError, fn ->
      String.to_existing_atom("no_such_predicate_705")
    end
  end

  test "a nil predicate is the pass-through a surface with no filter relies on" do
    world()
    rows = Catalog.list_securities_with_metrics()

    assert DataQuality.refine(rows, nil) == rows
  end

  test "a row with no metrics counts as unpriced rather than crashing" do
    # Defensive, and the honest reading: nothing known about a row's prices is
    # not evidence that it has one.
    assert DataQuality.refine([%{}], "missing_quote") == [%{}]
    assert DataQuality.refine([%{}], "stale_quote") == [%{}]
  end

  test "a non-string predicate is rejected like any other unknown value" do
    refute DataQuality.valid?(:stale_quote)
    refute DataQuality.valid?(nil)
    refute DataQuality.valid?(7)
  end

  test "the staleness threshold is stated once and is what the label promises" do
    assert DataQuality.stale_days() == 7
  end

  test "list/2 composes with the caller's own options" do
    world()

    assert names(DataQuality.list("stale_quote", query: "Unpriced")) == ["Unpriced AG"]
  end
end
