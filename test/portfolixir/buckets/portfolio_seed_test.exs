defmodule Portfolixir.Buckets.PortfolioSeedTest do
  @moduledoc """
  Pins the ADR-0024 portfolio -> bucket/view seed (epic story 2, modifications
  2 and 6) by driving the context functions the data migration calls, inside
  the sandbox (the migrator itself cannot run under the Ecto SQL sandbox; the
  DDL round trip is exercised by `mix ecto.rollback` / `mix ecto.migrate`).

  All money assertions are exact `Decimal` — never float tolerance.
  """
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [
      base_world: 1,
      add_depot: 2,
      create_security!: 1,
      buy!: 3,
      deposit!: 4
    ]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Fx
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios.Valuation

  @seed_actor Actor.system_job("portfolio_scope_seed")

  # User story (ADR-0024 modifications 2 + 6, epic story 2):
  # As a local portfolio maintainer upgrading to the buckets/views model,
  # I want my existing portfolios converted into one exclusive scope bucket
  # plus one editable view each, with every depot and cash account assigned,
  # so that nothing I grouped is lost.
  #
  # Acceptance criteria:
  # - Per portfolio: one scope-dimension bucket (same name) and one view (same
  #   name, include_all false, including exactly that bucket) are created,
  #   both marked with the portfolio id as seed linkage.
  # - Every depot and cash account of the portfolio is assigned to its bucket;
  #   pre-existing tag buckets on an account are kept, not replaced.
  # - Seeded buckets and assignments produce audit-journal entries under the
  #   seeding actor (ADR-0017); views stay unjournaled (ADR-0018 §5).
  # - Re-running the seed is a no-op (no new records, no new journal entries).
  test "seeds one scope bucket + one view per portfolio and assigns its accounts" do
    alpha = base_world(name: "Alpha", cash_name: "Alpha Cash", depot_name: "Alpha Depot")
    beta = base_world(name: "Beta", cash_name: "Beta Cash", depot_name: "Beta Depot")

    # A pre-existing user tag on one depot must survive the seeding merge.
    {:ok, krypto} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Krypto"})
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), alpha.depot, [krypto.id])

    assert {:ok, %{buckets_created: 2, views_created: 2, accounts_tagged: 4}} =
             Buckets.seed_portfolio_scope_buckets(@seed_actor)

    %{buckets: buckets, views: views} = Buckets.migration_summary()

    alpha_bucket = Enum.find(buckets, &(&1.source_portfolio_id == alpha.portfolio.id))
    beta_bucket = Enum.find(buckets, &(&1.source_portfolio_id == beta.portfolio.id))
    alpha_view = Enum.find(views, &(&1.source_portfolio_id == alpha.portfolio.id))
    beta_view = Enum.find(views, &(&1.source_portfolio_id == beta.portfolio.id))

    assert %{name: "Alpha", dimension: "scope"} = alpha_bucket
    assert %{name: "Beta", dimension: "scope"} = beta_bucket
    assert %{name: "Alpha", include_all: false} = alpha_view
    assert %{name: "Beta", include_all: false} = beta_view

    assert Buckets.view_filter(alpha_view.id) ==
             {:ok, %{include: [alpha_bucket.id], exclude: []}}

    # Assignments: the seeded scope bucket is added, the user tag is kept.
    assert Enum.sort(Buckets.depot_default_bucket_ids(alpha.depot.id)) ==
             Enum.sort([krypto.id, alpha_bucket.id])

    assert Buckets.cash_account_bucket_ids(alpha.cash.id) == [alpha_bucket.id]
    assert Buckets.depot_default_bucket_ids(beta.depot.id) == [beta_bucket.id]
    assert Buckets.cash_account_bucket_ids(beta.cash.id) == [beta_bucket.id]

    # Journaled per ADR-0017 under the seeding actor: 2 bucket creates plus
    # one aggregate assignment entry per tagged account.
    bucket_creates =
      Journal.list_entries(resource_type: "bucket", operation: :create)
      |> Enum.filter(&(&1.actor_type == :system_job))

    assert length(bucket_creates) == 2
    assert Enum.all?(bucket_creates, &(&1.actor_label == "portfolio_scope_seed"))

    depot_entries = Journal.list_entries(resource_type: "depot_bucket_assignment")
    cash_entries = Journal.list_entries(resource_type: "cash_account_bucket_assignment")
    assert Enum.count(depot_entries, &(&1.actor_type == :system_job)) == 2
    assert Enum.count(cash_entries, &(&1.actor_type == :system_job)) == 2

    # Idempotency: the second run creates nothing and journals nothing new.
    journal_count_before = length(Journal.list_entries([]))

    assert {:ok, %{buckets_created: 0, views_created: 0, accounts_tagged: 0}} =
             Buckets.seed_portfolio_scope_buckets(@seed_actor)

    assert length(Journal.list_entries([])) == journal_count_before
    assert length(Buckets.migration_summary().buckets) == 2
    assert length(Buckets.migration_summary().views) == 2
  end

  # User story (ADR-0024 modification 6, epic story 2):
  # As a local portfolio maintainer who reverts the upgrade,
  # I want the migration rollback to remove ONLY what the seed created,
  # so that my own buckets, views and assignments survive a downgrade.
  #
  # Acceptance criteria:
  # - Rollback deletes seeded buckets (cascading their assignments and view
  #   links) and seeded views; user-created records are untouched.
  # - Rollback then re-seeding restores the seeded shape (roundtrip-safe).
  test "rollback removes only seeded records and re-seeding restores them" do
    world = base_world(name: "Alpha", cash_name: "Alpha Cash", depot_name: "Alpha Depot")

    {:ok, user_bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Krypto"})
    {:ok, user_view} = Buckets.create_view(Actor.owner_ui(), %{name: "Strategie"})
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), world.depot, [user_bucket.id])

    assert {:ok, _} = Buckets.seed_portfolio_scope_buckets(@seed_actor)
    assert length(Buckets.list_buckets()) == 2
    assert length(Buckets.list_views()) == 2

    assert :ok = Buckets.rollback_portfolio_scope_seed(@seed_actor)

    # Only the user records remain, including the user's assignment.
    assert [%{id: bucket_id}] = Buckets.list_buckets()
    assert bucket_id == user_bucket.id
    assert [%{id: view_id}] = Buckets.list_views()
    assert view_id == user_view.id
    assert Buckets.depot_default_bucket_ids(world.depot.id) == [user_bucket.id]

    assert Buckets.migration_summary() == %{migrated?: false, buckets: [], views: []}

    # Roundtrip: re-seeding after rollback restores the seeded shape.
    assert {:ok, %{buckets_created: 1, views_created: 1, accounts_tagged: 2}} =
             Buckets.seed_portfolio_scope_buckets(@seed_actor)

    assert %{migrated?: true, buckets: [seeded_bucket], views: [_]} = Buckets.migration_summary()

    assert Enum.sort(Buckets.depot_default_bucket_ids(world.depot.id)) ==
             Enum.sort([user_bucket.id, seeded_bucket.id])
  end

  # User story (ADR-0024 modification 6, epic story 2):
  # As a local portfolio maintainer whose bucket or view names collide with a
  # portfolio name,
  # I want the seed to pick a deterministic fallback name instead of failing,
  # so that the upgrade migration never aborts halfway.
  #
  # Acceptance criteria:
  # - A name collision with an existing (user) bucket or view falls back to
  #   "<name> (Portfolio)" deterministically.
  test "falls back to a deterministic name when a portfolio name is taken" do
    _world = base_world(name: "Krypto", cash_name: "K Cash", depot_name: "K Depot")

    {:ok, _} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Krypto"})
    {:ok, _} = Buckets.create_view(Actor.owner_ui(), %{name: "Krypto"})

    assert {:ok, %{buckets_created: 1, views_created: 1}} =
             Buckets.seed_portfolio_scope_buckets(@seed_actor)

    assert %{buckets: [bucket], views: [view]} = Buckets.migration_summary()
    assert bucket.name == "Krypto (Portfolio)"
    assert view.name == "Krypto (Portfolio)"
  end

  # User story (fix round, seed naming robustness):
  # As a local portfolio maintainer with clashing portfolio names,
  # I want the seed to keep numbering fallback names until a free one exists,
  # so that the migration never aborts on a name collision.
  #
  # Acceptance criteria:
  # - Three same-named portfolios seed three distinct bucket/view pairs
  #   ("<name>", "<name> (Portfolio)", "<name> (Portfolio 2)").
  # - A pre-existing user bucket already named "<name> (Portfolio)" pushes the
  #   seed to the next numbered variant instead of failing.
  test "numbers fallback names until a free bucket AND view name is found" do
    base_world(name: "Krypto", cash_name: "C1", depot_name: "D1")
    base_world(name: "Krypto", cash_name: "C2", depot_name: "D2")
    base_world(name: "Krypto", cash_name: "C3", depot_name: "D3")

    assert {:ok, %{buckets_created: 3, views_created: 3, accounts_tagged: 6}} =
             Buckets.seed_portfolio_scope_buckets(@seed_actor)

    %{buckets: buckets, views: views} = Buckets.migration_summary()

    assert Enum.map(buckets, & &1.name) == [
             "Krypto",
             "Krypto (Portfolio)",
             "Krypto (Portfolio 2)"
           ]

    assert Enum.map(views, & &1.name) == [
             "Krypto",
             "Krypto (Portfolio)",
             "Krypto (Portfolio 2)"
           ]
  end

  test "a pre-existing user bucket named \"<name> (Portfolio)\" pushes to the next number" do
    _world = base_world(name: "Krypto", cash_name: "K Cash", depot_name: "K Depot")

    {:ok, _} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Krypto"})
    {:ok, _} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Krypto (Portfolio)"})

    assert {:ok, %{buckets_created: 1, views_created: 1}} =
             Buckets.seed_portfolio_scope_buckets(@seed_actor)

    assert %{buckets: [bucket], views: [view]} = Buckets.migration_summary()
    assert bucket.name == "Krypto (Portfolio 2)"
    assert view.name == "Krypto (Portfolio 2)"
  end

  # User story (fix round, over-long portfolio names):
  # As a local portfolio maintainer with a portfolio name longer than the
  # 100-character bucket/view limit,
  # I want the seed to truncate the base name before suffixing,
  # so that the migration never fails changeset validation.
  test "truncates portfolio names longer than the 100-char bucket/view limit" do
    long_name = String.duplicate("N", 120)
    base_world(name: long_name, cash_name: "L Cash", depot_name: "L Depot")

    assert {:ok, %{buckets_created: 1, views_created: 1}} =
             Buckets.seed_portfolio_scope_buckets(@seed_actor)

    assert %{buckets: [bucket], views: [view]} = Buckets.migration_summary()
    assert bucket.name == String.duplicate("N", 100)
    assert view.name == bucket.name
    assert String.length(bucket.name) <= 100
  end

  # User story (fix round, re-seed tolerance):
  # As a local portfolio maintainer who assigned my own scope bucket to an
  # account after a rollback,
  # I want a re-seed to skip that account instead of crashing,
  # so that my scope decision wins and the summary tells me what was skipped.
  #
  # Acceptance criteria:
  # - The account keeps its existing scope bucket; the seed counts it under
  #   `skipped_existing_scope`.
  test "re-seed skips accounts that already carry a different scope bucket" do
    world = base_world(name: "Alpha", cash_name: "A Cash", depot_name: "A Depot")

    {:ok, own_scope} =
      Buckets.create_bucket(Actor.owner_ui(), %{name: "Eigene Scope", dimension: "scope"})

    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), world.depot, [own_scope.id])

    assert {:ok,
            %{
              buckets_created: 1,
              views_created: 1,
              accounts_tagged: 1,
              skipped_existing_scope: 1
            }} = Buckets.seed_portfolio_scope_buckets(@seed_actor)

    # The user's scope assignment survived untouched; only the cash account
    # was tagged with the seeded bucket.
    assert Buckets.depot_default_bucket_ids(world.depot.id) == [own_scope.id]

    %{buckets: [seeded_bucket]} = Buckets.migration_summary()
    assert Buckets.cash_account_bucket_ids(world.cash.id) == [seeded_bucket.id]
  end

  # User story (fix round, restore-after-migrate installs):
  # As a local portfolio maintainer who migrated an empty database and
  # restored my data afterwards,
  # I want `mix portfolixir.seed_scope_buckets` to create the missing
  # bucket/view pairs on demand,
  # so that the restored portfolios get the same migration as everyone else.
  # (The task is a thin wrapper over this exact function + actor.)
  test "re-running the seed after a data restore creates the missing pairs" do
    # The upgrade migration ran against an empty database: nothing to seed.
    assert {:ok, %{buckets_created: 0, views_created: 0, accounts_tagged: 0}} =
             Buckets.seed_portfolio_scope_buckets(@seed_actor)

    # The user restores their data afterwards…
    base_world(name: "Restored", cash_name: "R Cash", depot_name: "R Depot")

    # …and the task's underlying call seeds exactly the missing pair.
    assert {:ok, %{buckets_created: 1, views_created: 1, accounts_tagged: 2}} =
             Buckets.seed_portfolio_scope_buckets(@seed_actor)

    assert %{migrated?: true, buckets: [%{name: "Restored"}], views: [%{name: "Restored"}]} =
             Buckets.migration_summary()
  end

  # User story (fix round, migration notice after rollback):
  # As a local portfolio maintainer who rolled the seed back,
  # I want a later re-seed to be announced again on the Wealth page,
  # so that a stale dismissal never hides a fresh migration.
  test "rollback clears the dismissed-notice flag so a re-seed announces again" do
    base_world(name: "Alpha", cash_name: "A Cash", depot_name: "A Depot")

    assert {:ok, _} = Buckets.seed_portfolio_scope_buckets(@seed_actor)
    :ok = Portfolixir.Settings.dismiss_migration_notice()
    assert Portfolixir.Settings.migration_notice_dismissed?()

    assert :ok = Buckets.rollback_portfolio_scope_seed(@seed_actor)

    refute Portfolixir.Settings.migration_notice_dismissed?()
  end

  # User story (ADR-0024 kill criterion / epic story 2 equivalence proof):
  # As a local portfolio maintainer,
  # I want each seeded view's total to be Decimal-identical to its portfolio's
  # total,
  # so that the migration changes presentation, never a single number.
  #
  # Acceptance criteria:
  # - After seeding, `Valuation.for_view/2` of each seeded view (in the
  #   portfolio's base currency) equals `Valuation.for_portfolio/2` —
  #   Decimal-identical totals, same pricing fallbacks, same EUR-hub FX.
  # - The seeded views' totals add up to the "everything" total (exclusivity
  #   preserves additivity).
  test "each seeded view's valuation total is Decimal-identical to its portfolio's" do
    alpha = base_world(name: "Alpha", cash_name: "Alpha Cash", depot_name: "Alpha Depot")

    alpha_usd =
      add_depot(alpha.portfolio,
        currency: "USD",
        cash_name: "Alpha USD Cash",
        depot_name: "Alpha USD Depot"
      )

    alpha_usd_world = %{portfolio: alpha.portfolio, depot: alpha_usd.depot, cash: alpha_usd.cash}

    beta = base_world(name: "Beta", cash_name: "Beta Cash", depot_name: "Beta Depot")

    eur_sec = create_security!(name: "Euro Co.", ticker: "EURC", asset_class: "equity")

    usd_sec =
      create_security!(name: "US Co.", ticker: "USCO", currency: "USD", asset_class: "equity")

    # No quote and no price override: valued via the latest-trade-price fallback.
    trade_sec = create_security!(name: "Trade-Priced Co.", ticker: "TRDP", asset_class: "equity")

    # 1 EUR = 1.25 USD (ECB semantics), the EUR-hub rate used by valuation.
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-06-01],
          rate: "1.25",
          source: "manual"
        }
      ])

    deposit!(alpha, "1000", ~D[2026-01-01], [])
    buy!(alpha, eur_sec, quantity: "3", price: "111.11")
    deposit!(alpha_usd_world, "1500", ~D[2026-01-01], currency: "USD")
    buy!(alpha_usd_world, usd_sec, quantity: "10", price: "100", currency: "USD")
    deposit!(beta, "300", ~D[2026-01-01], [])
    buy!(beta, trade_sec, quantity: "4", price: "25")

    prices = %{eur_sec.id => Decimal.new("111.11"), usd_sec.id => Decimal.new("100")}

    assert {:ok, _} = Buckets.seed_portfolio_scope_buckets(@seed_actor)

    %{views: views} = Buckets.migration_summary()

    totals =
      for portfolio <- [alpha.portfolio, beta.portfolio] do
        view = Enum.find(views, &(&1.source_portfolio_id == portfolio.id))
        today = Valuation.for_portfolio(portfolio.id, prices: prices)

        seeded =
          Valuation.for_view(view.id,
            prices: prices,
            base_currency: portfolio.base_currency_code
          )

        assert Decimal.equal?(seeded.total_value, today.total_value)
        assert Decimal.equal?(seeded.total_cash, today.total_cash)
        assert Decimal.equal?(seeded.total_with_cash, today.total_with_cash)
        assert seeded.unvalued_count == today.unvalued_count
        assert seeded.trade_priced_count == today.trade_priced_count

        # The exclusive dimension never overlaps.
        assert seeded.overlap.overlapping? == false

        seeded.total_with_cash
      end

    # Alpha: 333.33 + 800 positions, 666.67 + 400 cash; Beta: 100 + 200.
    [alpha_total, beta_total] = totals
    assert Decimal.equal?(alpha_total, Decimal.new("2200"))
    assert Decimal.equal?(beta_total, Decimal.new("300"))

    # Additivity: the seeded views sum to the everything total.
    everything = Valuation.for_view(nil, prices: prices)

    summed = Enum.reduce(totals, Decimal.new("0"), &Decimal.add(&2, &1))
    assert Decimal.equal?(summed, everything.total_with_cash)
    assert Decimal.equal?(summed, Decimal.new("2500"))
  end
end
