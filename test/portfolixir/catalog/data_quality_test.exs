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

  defp retire!(security, retired?) do
    {:ok, security} = Catalog.update_security(Actor.owner_ui(), security, %{is_retired: retired?})
    security
  end

  # User story (owner decision 2026-10-05, reversing the closing-act rule that
  # kept a never-priced retired security under missing_quote):
  # As the maintainer whose sold-out and delisted securities stay in the
  # catalog because their bookings do,
  # I want retiring a security to take it out of every catalog-hygiene set,
  # as a benchmark already is,
  # so that the remedy the delete names clears the findings it belongs to
  # instead of one of three.
  #
  # Acceptance criteria:
  # - A retired security is in none of stale_quote, missing_quote and
  #   missing_logo, priced long ago or never priced, with no logo; each
  #   count drops with its list.
  # - Un-retiring puts it back in every set it matches.
  # - A security that is not retired stays where it was.
  test "a retired security leaves stale_quote, missing_quote and missing_logo" do
    %{stale: stale, unpriced: unpriced} = world()
    still_stale = create_security!(name: "Still Stale AG", ticker: "SST")
    put_quote!(still_stale, Date.add(Date.utc_today(), -40), "9")

    retire!(stale, true)
    unpriced = retire!(unpriced, true)

    assert names(DataQuality.list("stale_quote")) == ["Still Stale AG"]
    assert names(DataQuality.list("missing_quote")) == []
    assert names(DataQuality.list("missing_logo")) == ["Still Stale AG"]

    for id <- ~w(stale_quote missing_quote missing_logo) do
      assert DataQuality.count(id) == length(DataQuality.list(id)), id
    end

    retire!(unpriced, false)

    assert names(DataQuality.list("stale_quote")) == ["Still Stale AG", "Unpriced AG"]
    assert names(DataQuality.list("missing_quote")) == ["Unpriced AG"]
    assert names(DataQuality.list("missing_logo")) == ["Still Stale AG", "Unpriced AG"]
  end

  # The securities page loads its rows with the query half alone and applies
  # refine/3 itself (`?dq=missing_logo`), so the retired exclusion must ride
  # the in-memory half too, or the page lists what the dashboard no longer
  # counts.
  test "refine/3 leaves a retired security out of missing_logo on rows loaded with the query half" do
    %{unpriced: unpriced} = world()
    retire!(unpriced, true)

    rows = Catalog.list_securities_with_metrics(logo_status: :missing)

    assert names(DataQuality.refine(rows, "missing_logo")) == ["Stale AG"]

    assert names(DataQuality.refine(rows, "missing_logo")) ==
             names(DataQuality.list("missing_logo"))
  end

  # User story (#789):
  # As a maintainer reading a price on any surface,
  # I want the "stale" question answered by the one predicate the filter and
  # the Wealth finding already use,
  # so that the marker under a price, the chip and the count can never
  # disagree about what stale means.
  #
  # Acceptance criteria:
  # - A date exactly `stale_days` old is not stale; one day older is.
  # - No date (never priced) is not stale — there is no price to mark.
  test "stale_quote?/2 is the filter's threshold applied to one date" do
    today = ~D[2026-09-15]
    days = DataQuality.stale_days()

    refute DataQuality.stale_quote?(Date.add(today, -days), today)
    assert DataQuality.stale_quote?(Date.add(today, -(days + 1)), today)
    refute DataQuality.stale_quote?(nil, today)
  end

  # "Is this price old by now?" is a local-calendar question, so `today` is the
  # caller's to supply from `Portfolixir.Clock`. A one-argument form would
  # answer it in UTC — the wrong day east of UTC, per #609 — and would read the
  # host clock from inside the domain, leaving callers untestable against a
  # frozen date. This pins the absence of that form the way the enum-label
  # meta-tests pin the absence of a raw-value fallback.
  test "stale_quote? has no one-argument form that would answer in UTC" do
    # function_exported?/3 answers false for a module not loaded yet, which
    # made the refute below vacuous and the assert fail whenever this test
    # ran before any other touched the module (seed-dependent).
    Code.ensure_loaded!(DataQuality)
    refute function_exported?(DataQuality, :stale_quote?, 1)
    assert function_exported?(DataQuality, :stale_quote?, 2)
  end
end
