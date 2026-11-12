defmodule Portfolixir.Catalog.BenchmarkSecurityTest do
  # Sprint 29 B1 (#1416; ADR-0046's amendment of 2026-11-07): the one rule
  # every read that takes benchmark=security:<id> applies, and the crash
  # benchmark of ADR-0058 §1 after it. Every name and figure is synthetic.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, put_quote!: 3, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.BenchmarkSecurity
  alias Portfolixir.Lifecycle

  defp flagged!(opts) do
    security = create_security!(opts)
    {:ok, flagged} = Catalog.update_security(Actor.owner_ui(), security, %{is_benchmark: true})
    flagged
  end

  # A security with no identifier, so a merge meets no identifier veto.
  defp bare!(name) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{name: name, currency_code: "EUR"})

    security
  end

  defp merge!(source, target) do
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    {:ok, _record, :applied} =
      Lifecycle.merge_security(Actor.owner_ui(), source.id, target.id, %{
        plan_digest: preview.plan_digest
      })
  end

  # User story (#1416; ADR-0046's amendment of 2026-11-07, point 1):
  # As the operator who wants the fund I hold as my benchmark,
  # I want any security with a stored quote to be accepted as a benchmark,
  # flagged or not,
  # so that the fund stays bookable and in every data-quality check while it
  # is my comparison's reference.
  #
  # Acceptance criteria:
  # - A held fund that is not flagged, with one stored quote, resolves.
  # - A flagged security with a stored quote resolves, as before.
  # - An unheld, unflagged security with a stored quote resolves.
  # - A security without a stored quote is refused as :no_quote, flagged or
  #   not.
  # - An id no row and no merge names is :not_found.
  test "any security with a stored quote is a benchmark, flagged or not" do
    world = base_world(name: "Synthetic Bench Rule")
    held = create_security!(name: "Synthetic Held Fund", ticker: "SHF")
    buy!(world, held, quantity: "3", price: "50", date: ~D[2025-03-03])
    put_quote!(held, ~D[2025-03-03], "50")

    index = flagged!(name: "Synthetic Broad Index", ticker: "SBX")
    put_quote!(index, ~D[2025-03-03], "200")

    unheld = create_security!(name: "Synthetic Watched Fund", ticker: "SWF")
    put_quote!(unheld, ~D[2025-03-03], "10")

    assert {:ok, %{id: id}} = BenchmarkSecurity.resolve(held.id)
    assert id == held.id
    assert {:ok, %{is_benchmark: true}} = BenchmarkSecurity.resolve(index.id)
    assert {:ok, %{is_benchmark: false}} = BenchmarkSecurity.resolve(unheld.id)

    unquoted = create_security!(name: "Synthetic Unquoted Fund", ticker: "SUF")
    unquoted_flagged = flagged!(name: "Synthetic Unquoted Index", ticker: "SUI")

    assert BenchmarkSecurity.resolve(unquoted.id) == {:error, :no_quote}
    assert BenchmarkSecurity.resolve(unquoted_flagged.id) == {:error, :no_quote}
    assert BenchmarkSecurity.resolve(999_999_999) == {:error, :not_found}
  end

  # Acceptance criteria (ADR-0046's amendment, point 1; #959):
  # - A merged-away id is refused naming the survivor when the survivor is
  #   itself a benchmark by the rule (a stored quote), flagged or not.
  # - A survivor without a stored quote is no benchmark: the refusal is
  #   :not_found, naming nothing.
  test "a merged-away id names a survivor the rule accepts, and only such a one" do
    target = bare!("Synthetic Harbour Fund")
    source = bare!("Synthetic Harbour Fund")
    put_quote!(target, ~D[2025-03-03], "20")
    merge!(source, target)

    assert BenchmarkSecurity.resolve(source.id) == {:error, {:merged_into, target.id}}

    bare_target = bare!("Synthetic Bare Fund")
    bare_source = bare!("Synthetic Bare Fund")
    merge!(bare_source, bare_target)

    assert BenchmarkSecurity.resolve(bare_source.id) == {:error, :not_found}
  end

  # User story (ADR-0046's amendment, point 4):
  # As the agent reading a comparison,
  # I want to know which kind of security the benchmark is,
  # so that I can tell a reference index from a fund the operator holds.
  #
  # Acceptance criteria:
  # - standing/1 answers :flagged for a flagged security, held or not; :held
  #   for an unflagged security held today; :unheld for one that is not, a
  #   security sold out included.
  test "standing names a flagged, a held and an unheld security" do
    world = base_world(name: "Synthetic Standing")
    held = create_security!(name: "Synthetic Held Fund", ticker: "SHF")
    buy!(world, held, quantity: "3", price: "50", date: ~D[2025-03-03])

    sold = create_security!(name: "Synthetic Sold Fund", ticker: "SSF")
    buy!(world, sold, quantity: "2", price: "40", date: ~D[2025-03-03])
    sell!(world, sold, quantity: "2", price: "45", date: ~D[2025-04-01])

    held_index = flagged!(name: "Synthetic Held Index", ticker: "SHI")
    buy!(world, held_index, quantity: "1", price: "200", date: ~D[2025-03-03])

    assert BenchmarkSecurity.standing(held) == :held
    assert BenchmarkSecurity.standing(sold) == :unheld
    assert BenchmarkSecurity.standing(create_security!(name: "Synthetic Plain")) == :unheld
    assert BenchmarkSecurity.standing(held_index) == :flagged

    assert BenchmarkSecurity.standing(flagged!(name: "Synthetic Index", ticker: "SIX")) ==
             :flagged
  end

  # --- Sprint 29 B2 begin ---
  # User story (#1416, B2; ADR-0046's amendment of 2026-11-07, point 3;
  # ADR-0058 F5; board 02, Q1 A):
  # As the operator choosing a benchmark on a screen,
  # I want the picker to offer the flagged benchmarks first and then the
  # securities I hold today, each only when the rule would accept it,
  # so that everything I can tick compares, and nothing that compares for
  # an agent is missing from my screen's short list.
  #
  # Acceptance criteria:
  # - choices/0 answers two lists by name: :flagged, the flagged securities
  #   with a stored quote; :held, the unflagged securities held today in any
  #   depot with a stored quote.
  # - A flagged security that is also held is listed once, under :flagged.
  # - A held security without a stored quote, a flagged one without a
  #   stored quote, an unheld unflagged one and a sold-out one are offered
  #   in neither list.
  # - Every security offered resolves under resolve/1.
  test "choices offers the quoted flagged securities, then the quoted held ones, by name" do
    world = base_world(name: "Synthetic Picker")

    held_b = create_security!(name: "Synthetic Held B", ticker: "SHB")
    held_a = create_security!(name: "Synthetic Held A", ticker: "SHA")
    unquoted_held = create_security!(name: "Synthetic Held Unquoted", ticker: "SHU")
    sold = create_security!(name: "Synthetic Sold Out", ticker: "SSO")
    watched = create_security!(name: "Synthetic Watched", ticker: "SWA")
    index_z = flagged!(name: "Synthetic Index Z", ticker: "SIZ")
    held_index = flagged!(name: "Synthetic Index H", ticker: "SIH")
    unquoted_index = flagged!(name: "Synthetic Index Unquoted", ticker: "SIU")

    for security <- [held_b, held_a, unquoted_held, sold, held_index] do
      buy!(world, security, quantity: "2", price: "10", date: ~D[2025-03-03])
    end

    sell!(world, sold, quantity: "2", price: "11", date: ~D[2025-04-01])

    for security <- [held_b, held_a, sold, watched, index_z, held_index] do
      put_quote!(security, ~D[2025-03-03], "10")
    end

    choices = BenchmarkSecurity.choices()

    assert Enum.map(choices.flagged, & &1.name) == ["Synthetic Index H", "Synthetic Index Z"]
    assert Enum.map(choices.held, & &1.name) == ["Synthetic Held A", "Synthetic Held B"]

    offered = choices.flagged ++ choices.held
    refute Enum.any?(offered, &(&1.id in [unquoted_held.id, unquoted_index.id]))
    refute Enum.any?(offered, &(&1.id in [sold.id, watched.id]))

    for security <- offered do
      assert {:ok, %{id: id}} = BenchmarkSecurity.resolve(security.id)
      assert id == security.id
    end
  end

  # --- Sprint 29 B2 end ---

  # The closing act (#1416, #1421): a stored close of 0 is no price (a
  # legacy row from before the plausibility bounds), as every return read
  # treats it. A security whose only closes are 0 is no benchmark: refused
  # as :no_quote and not offered, so the crash read never answers
  # `detected: []` with no reason over a series that has no price at all.
  test "a security whose only stored close is 0 is no benchmark and is not offered" do
    world = base_world(name: "Synthetic Zero World")
    zero = flagged!(name: "Synthetic Zero Index", ticker: "SZI")
    held_zero = create_security!(name: "Synthetic Zero Held", ticker: "SZH")
    buy!(world, held_zero, quantity: "1", price: "10", date: ~D[2025-01-02])
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.transaction(fn ->
      Repo.query!("SELECT set_config('portfolixir.journal_actor', 'synthetic-test', true)")

      Repo.insert_all(
        "security_quotes",
        for security <- [zero, held_zero] do
          %{
            security_id: security.id,
            date: ~D[2024-01-02],
            close: Decimal.new(0),
            source: "auto",
            inserted_at: now,
            updated_at: now
          }
        end
      )
    end)

    assert BenchmarkSecurity.resolve(zero.id) == {:error, :no_quote}
    assert BenchmarkSecurity.resolve(held_zero.id) == {:error, :no_quote}

    choices = BenchmarkSecurity.choices()
    refute Enum.any?(choices.flagged ++ choices.held, &(&1.id in [zero.id, held_zero.id]))

    put_quote!(zero, ~D[2024-01-03], "10")
    assert {:ok, %{id: id}} = BenchmarkSecurity.resolve(zero.id)
    assert id == zero.id
  end
end
