defmodule Portfolixir.Catalog.DataQualityTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, buy!: 3, create_security!: 1, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.DataQuality
  alias Portfolixir.Catalog.LogoStore

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

  # User story (#933, review pass 1):
  # As an operator whose instance lost logo files,
  # I want a stored logo whose file is gone listed and counted as without a
  # logo, whatever its lock,
  # so that the Overview's count and the list it links to show me what to
  # fetch or upload again, while my deliberate "no logo" choice stays out.
  #
  # Acceptance criteria:
  # - One predicate: (no path AND not locked) OR file marked missing. A marked
  #   discovered and a marked locked manual logo are in missing_logo; a
  #   present logo and the "no logo" choice are not.
  # - logo_status: :missing is that predicate and :present its complement
  #   among stored paths; the count and the list agree.
  # - A marked retired or benchmark security stays out of missing_logo.
  test "a logo marked file-missing is missing whatever its lock; no logo is not" do
    tmp = Path.join(System.tmp_dir!(), "portfolixir-dq-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    logo! = fn name, attrs, flags ->
      security =
        create_security!(Keyword.merge([name: name, ticker: nil], flags))

      path = "/security_logos/#{security.id}.png"
      {:ok, security} = Catalog.put_logo_attributes(security, Map.put(attrs, "logo_path", path))
      security
    end

    logo!.("Discovered AG", %{"logo_source" => "wikipedia"}, [])
    logo!.("Manual AG", %{"logo_source" => "manual", "logo_locked" => true}, [])
    present = logo!.("Present AG", %{"logo_source" => "wikipedia"}, [])
    File.write!(Path.join(tmp, "#{present.id}.png"), "bytes")
    retired = logo!.("Retired AG", %{"logo_source" => "wikipedia"}, [])
    {:ok, _} = Catalog.update_security(Actor.owner_ui(), retired, %{is_retired: true})

    {:ok, _} =
      Catalog.put_logo_attributes(create_security!(name: "Chosen AG", ticker: nil), %{
        "logo_locked" => true
      })

    _unlocked_without = create_security!(name: "Plain AG", ticker: nil)

    assert {:ok, %{marked: 3}} = LogoStore.reconcile_missing_files(storage_dir: tmp)

    assert names(DataQuality.list("missing_logo")) == ["Discovered AG", "Manual AG", "Plain AG"]
    assert DataQuality.count("missing_logo") == 3

    sorted = fn opts ->
      opts |> Catalog.list_securities() |> Enum.map(& &1.name) |> Enum.sort()
    end

    assert sorted.(logo_status: :missing) ==
             ["Discovered AG", "Manual AG", "Plain AG", "Retired AG"]

    assert sorted.(logo_status: :present) == ["Present AG"]
  end

  # User story (PR #1102, reversing the closing-act rule that kept a
  # never-priced retired security under missing_quote):
  # As the maintainer whose sold-out and delisted securities stay in the
  # catalog because their bookings do,
  # I want retiring a security to take it out of every catalog-hygiene set,
  # as a benchmark already is,
  # so that retiring clears all three of its findings instead of one.
  #
  # Acceptance criteria:
  # - A retired security is in none of stale_quote, missing_quote and
  #   missing_logo, priced long ago or never priced, with no logo; each
  #   count drops with its list.
  # - Reactivated, it is back in every set it matches.
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

  # The securities page loads its rows with its own filters plus
  # list_opts/1 and applies refine/3 itself (`?dq=`), and a paged read cuts
  # its page in SQL: the retired exclusion is a query option, applied before
  # any LIMIT/OFFSET.
  test "list_opts/1 carries the retired exclusion into the query for the three sets" do
    %{unpriced: unpriced} = world()
    retire!(unpriced, true)

    for id <- ~w(stale_quote missing_quote missing_logo) do
      assert Keyword.fetch!(DataQuality.list_opts(id), :is_retired) == false, id
    end

    refute Keyword.has_key?(DataQuality.list_opts("missing_fx"), :is_retired)

    rows = Catalog.list_securities_with_metrics(DataQuality.list_opts("missing_logo"))

    assert names(DataQuality.refine(rows, "missing_logo")) == ["Stale AG"]

    assert names(DataQuality.refine(rows, "missing_logo")) ==
             names(DataQuality.list("missing_logo"))
  end

  # refine/3 is also handed rows a caller loaded with its own options, without
  # the query half; the metric-derived quote sets leave a retired row out
  # there too, so such a caller cannot bring one back.
  test "refine/3 leaves a retired never-priced row out of the quote sets on rows loaded without list_opts/1" do
    %{unpriced: unpriced} = world()
    retire!(unpriced, true)

    rows = Catalog.list_securities_with_metrics()
    today = Date.utc_today()

    assert "Unpriced AG" in names(rows)
    assert names(DataQuality.refine(rows, "stale_quote", today)) == ["Stale AG"]
    assert names(DataQuality.refine(rows, "missing_quote", today)) == []
  end

  # missing_fx is not catalog hygiene: a missing rate path breaks a
  # valuation whatever the security, so a retired one stays in it.
  test "missing_fx keeps a retired security" do
    priced = create_security!(name: "Retired Dollar AG", ticker: "RDA", currency: "USD")
    put_quote!(priced, Date.add(Date.utc_today(), -1), "10")
    retire!(priced, true)

    assert "Retired Dollar AG" in names(DataQuality.list("missing_fx"))
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

  defp security!(attrs) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), Map.merge(%{currency_code: "EUR"}, attrs))

    security
  end

  defp priced!(world, security, price, close) do
    buy!(world, security, quantity: "100", price: price, date: ~D[2026-03-12])
    put_quote!(security, ~D[2026-09-30], close)
    security
  end

  # User story (#1068, D-15; board 01):
  # As the operator whose Overview counts what needs work,
  # I want the bonds the two-scales guard flags, in either direction, as a
  # data-quality set of their own,
  # so that the Overview's count, the securities page's dq=two_scales list
  # and the agent's data_quality=two_scales read are one rule (#705).
  #
  # Acceptance criteria:
  # - two_scales holds, catalog-wide, a classed bond quoted 99.10 beside a
  #   buy at 0.991 (forward), an unclassed security with a maturity date on
  #   the same scales, and a classed bond quoted 0.981 beside a buy at 98.40
  #   (reverse); each has a stored quote and a booked price per unit.
  # - It leaves out an unclassed security with no master data quoted 25
  #   times its buy price, a bond on one scale, and a bond with no quote.
  # - Like missing_fx it is not catalog hygiene: a retired bond and a
  #   benchmark bond stay in it, since their figures are as wrong as before;
  #   the query half adds nothing.
  # - The count, taken without the metrics pass, is the list's length, and a
  #   row with no security is no finding.
  test "two_scales is the guard's set in either direction, catalog-wide" do
    world = base_world()

    forward =
      priced!(
        world,
        security!(%{name: "Kestrel Anleihe 2030 2,75%", asset_class: "bond"}),
        "0.991",
        "99.10"
      )

    priced!(
      world,
      security!(%{name: "Ostsee Logistik 4,10% 2028/2033", maturity_date: "2033-06-30"}),
      "0.991",
      "99.10"
    )

    reverse =
      priced!(
        world,
        security!(%{name: "Birkenhain Wasser Anleihe 2029 1,50%", asset_class: "bond"}),
        "98.40",
        "0.981"
      )

    priced!(world, security!(%{name: "Ostsee Holz"}), "4", "100")

    priced!(
      world,
      security!(%{name: "Musterland Anleihe 2029", asset_class: "bond"}),
      "99.10",
      "98.40"
    )

    unquoted = security!(%{name: "Nordwind Anleihe 2027", asset_class: "bond"})
    buy!(world, unquoted, quantity: "10000", price: "0.99", date: ~D[2026-03-12])

    flagged = [
      "Birkenhain Wasser Anleihe 2029 1,50%",
      "Kestrel Anleihe 2030 2,75%",
      "Ostsee Logistik 4,10% 2028/2033"
    ]

    assert DataQuality.valid?("two_scales")
    assert "two_scales" in DataQuality.ids()
    assert DataQuality.list_opts("two_scales") == []
    assert names(DataQuality.list("two_scales")) == flagged
    assert DataQuality.count("two_scales") == 3

    retire!(reverse, true)
    {:ok, _} = Catalog.update_security(Actor.owner_ui(), forward, %{is_benchmark: true})
    assert names(DataQuality.list("two_scales")) == flagged
    assert DataQuality.count("two_scales") == length(DataQuality.list("two_scales"))

    assert DataQuality.refine([%{}], "two_scales") == []
  end

  # User story (#1101, Sprint 20 plan D-7; board ux-design-2026-10-07/02,
  # pick L2 A):
  # As the operator whose Overview counts what needs work,
  # I want the held securities whose quotes contradict their own bookings
  # as a data-quality set of their own,
  # so that the Overview's count, the securities page's
  # dq=implausible_quote list and the agent's data_quality=implausible_quote
  # read are one rule (#705).
  #
  # Acceptance criteria:
  # - implausible_quote holds a held security bought at 48.20 and quoted
  #   4.87 that day, and keeps it retired or flagged as a benchmark: its
  #   value is as wrong as before. Its query half is the held filter.
  # - It leaves out a security sold out since (its sell at 61.40 beside
  #   618.90 the day before names it while held), a twentyfold riser, a
  #   held security with no quote in any booking's window, and a bond the
  #   two-scales guard names.
  # - The count is the list's length, and a row with no security is no
  #   finding.
  test "implausible_quote is the held securities whose quotes contradict their bookings" do
    world = base_world()

    held = security!(%{name: "Wrenfield Gardens AG"})
    buy!(world, held, quantity: "120", price: "48.20", date: ~D[2026-05-12])
    put_quote!(held, ~D[2026-05-12], "4.87")

    sold_out = security!(%{name: "Arbolia Inc."})
    buy!(world, sold_out, quantity: "10", price: "58.20", date: ~D[2025-11-03])

    Portfolixir.WorldFixtures.sell!(world, sold_out,
      quantity: "10",
      price: "61.40",
      date: ~D[2026-04-03]
    )

    put_quote!(sold_out, ~D[2026-04-02], "618.90")

    riser = security!(%{name: "Halden Robotics AG"})
    buy!(world, riser, quantity: "30", price: "10.00", date: ~D[2024-01-10])
    put_quote!(riser, ~D[2024-01-10], "10.20")
    put_quote!(riser, ~D[2026-10-06], "210.00")

    priced!(world, security!(%{name: "Ostsee Holz"}), "4", "100")

    bond = security!(%{name: "Kestrel Anleihe 2030 2,75%", asset_class: "bond"})
    buy!(world, bond, quantity: "10000", price: "0.985", date: ~D[2026-03-12])
    put_quote!(bond, ~D[2026-03-12], "97.25")

    assert DataQuality.valid?("implausible_quote")
    assert "implausible_quote" in DataQuality.ids()
    assert DataQuality.list_opts("implausible_quote") == [holding_status: :held]
    assert names(DataQuality.list("implausible_quote")) == ["Wrenfield Gardens AG"]
    assert DataQuality.count("implausible_quote") == 1
    assert names(DataQuality.list("two_scales")) == ["Kestrel Anleihe 2030 2,75%"]

    retire!(held, true)
    {:ok, _} = Catalog.update_security(Actor.owner_ui(), held, %{is_benchmark: true})
    assert names(DataQuality.list("implausible_quote")) == ["Wrenfield Gardens AG"]
    assert DataQuality.count("implausible_quote") == 1

    # The in-memory half reads held too: rows loaded without the query half
    # cannot bring the sold-out security back.
    rows = Catalog.list_securities_with_metrics()
    assert names(DataQuality.refine(rows, "implausible_quote")) == ["Wrenfield Gardens AG"]
    assert DataQuality.refine([%{}], "implausible_quote") == []
  end
end
