defmodule Portfolixir.SeededUpgrade.HeldRetiredHashTest do
  # #917, the closing act. The race that
  # 20261006120000_refuse_retiring_a_held_import_hash closes could already have
  # left a hash both live (a transaction holds it) and retired on an instance
  # that ran an earlier release: a booking and a merge's retirement of one hash
  # that ran at once and both committed. The migration neither stops on such
  # an overlap nor repairs it; it names it in the upgrade's log. Replayed here
  # by the seeded-upgrade harness over an instance holding one.
  #
  # async: false -- see Portfolixir.SeededUpgrade, "Where the cases run".
  use ExUnit.Case, async: false

  alias Portfolixir.SeededUpgrade

  @moduletag :seeded_upgrade

  # The migration before the one these cases cover: the schema that still let
  # a held hash be retired.
  @before 20_261_003_120_000

  # User story:
  # As the operator upgrading an instance on which a booking and a merge's
  # retirement of one hash once ran at once and both committed,
  # I want the upgrade to finish and to name the transactions whose hash is
  # also retired,
  # so that the release boots, nothing is deleted behind my back, and I know
  # which rows to look at.
  #
  # Acceptance criteria:
  # - Seeded at the migration before it with a hash a transaction holds and
  #   retired_import_hashes also lists, beside a hash only held and one only
  #   retired, the database migrates to head.
  # - Every seeded transaction and retirement is still there, as it was.
  # - The upgrade's log warns once, naming the count of such hashes and the
  #   transactions that hold them, and saying that both refusals hold from now
  #   on and that the overlap stays as it was; it names neither the
  #   transaction whose hash is only held nor the hash only retired.
  # - From head on, retiring a held hash is refused.
  @tag seeded_upgrade: 20_261_006_120_000
  test "a hash both held and retired does not stop the upgrade, and is named",
       %{seeded_upgrade: migration} do
    upgrade = SeededUpgrade.upgrade!(from: @before, seed: &seed_overlap/1)
    world = upgrade.seeded

    assert migration in upgrade.migrated
    assert List.last(upgrade.migrated) == SeededUpgrade.head()

    assert SeededUpgrade.query!(
             upgrade,
             "SELECT id, import_hash FROM transactions ORDER BY id"
           ).rows == [
             [world.overlap, "synthetic-held-and-retired"],
             [world.held, "synthetic-held-only"]
           ]

    assert SeededUpgrade.query!(
             upgrade,
             "SELECT import_hash FROM retired_import_hashes ORDER BY id"
           ).rows == [["synthetic-held-and-retired"], ["synthetic-retired-only"]]

    assert [warning] =
             upgrade.log
             |> String.split("\n")
             |> Enum.filter(&(&1 =~ "held and retired"))

    assert warning =~ "1 import hash"
    assert warning =~ "transaction ##{world.overlap}"
    refute warning =~ "##{world.held}"
    refute upgrade.log =~ "synthetic-retired-only"
    assert warning =~ "From this release on"
    assert warning =~ "stay as they are"

    error =
      assert_raise Postgrex.Error, fn ->
        SeededUpgrade.journaled!(upgrade, fn ->
          retire!(upgrade, world, "synthetic-held-only", 9_000_002)
        end)
      end

    assert %{postgres: %{constraint: "retired_import_hashes_import_hash_held"}} = error
  end

  # Acceptance criteria:
  # - Over an instance whose held and retired hashes are disjoint, the upgrade
  #   logs no such warning.
  @tag seeded_upgrade: 20_261_006_120_000
  test "without an overlap the upgrade names none", %{seeded_upgrade: migration} do
    upgrade = SeededUpgrade.upgrade!(from: @before, seed: &seed_disjoint/1)

    assert migration in upgrade.migrated
    refute upgrade.log =~ "held and retired"
  end

  # -- seeds: plain SQL, in the shape of the schema before the migration -------

  # A transaction holding a hash a merge also retired (the race), one holding
  # a hash only it holds, and a hash only retired.
  defp seed_overlap(db) do
    world = seed_world(db)
    overlap = insert_transaction!(db, world, "synthetic-held-and-retired")
    held = insert_transaction!(db, world, "synthetic-held-only")
    retire!(db, world, "synthetic-held-and-retired", 9_000_001)
    retire!(db, world, "synthetic-retired-only", 9_000_003)

    Map.merge(world, %{overlap: overlap, held: held})
  end

  defp seed_disjoint(db) do
    world = seed_world(db)
    insert_transaction!(db, world, "synthetic-held-only")
    retire!(db, world, "synthetic-retired-only", 9_000_003)
    world
  end

  defp seed_world(db) do
    portfolio =
      insert!(db, "INSERT INTO portfolios #{row(~w(name base_currency_code))}", [
        "Upgrade Portfolio",
        "EUR"
      ])

    cash =
      insert!(db, "INSERT INTO cash_accounts #{row(~w(portfolio_id name currency_code))}", [
        portfolio,
        "Upgrade Cash",
        "EUR"
      ])

    %{rows: [[record]]} =
      SeededUpgrade.query!(
        db,
        """
        INSERT INTO merge_records
          (kind, source_id, target_id, portfolio_id, source_snapshot, manifest, plan_digest,
           actor_type, inserted_at)
        VALUES ('cash_account', $1, $2, $3, '{}', '{}', 'sha256:synthetic-plan', 'owner_ui', now())
        RETURNING id
        """,
        [cash + 1_000_000, cash, portfolio]
      )

    %{portfolio: portfolio, cash: cash, record: record}
  end

  defp insert_transaction!(db, world, import_hash) do
    insert!(
      db,
      "INSERT INTO transactions " <>
        row(~w(portfolio_id cash_account_id type date currency_code gross_amount import_hash)),
      [
        world.portfolio,
        world.cash,
        "deposit",
        ~D[2026-02-01],
        "EUR",
        Decimal.new("250"),
        import_hash
      ]
    )
  end

  defp retire!(db, world, import_hash, former_transaction_id) do
    SeededUpgrade.query!(
      db,
      """
      INSERT INTO retired_import_hashes
        (import_hash, former_transaction_id, merge_record_id, reason, inserted_at)
      VALUES ($1, $2, $3, 'internal_transfer', now())
      """,
      [import_hash, former_transaction_id, world.record]
    )
  end

  # `(columns..., inserted_at, updated_at) VALUES ($1, ..., now, now)
  # RETURNING id` for an insert of one row.
  defp row(columns) do
    placeholders = Enum.map_join(1..length(columns), ", ", &"$#{&1}")

    "(#{Enum.join(columns, ", ")}, inserted_at, updated_at) " <>
      "VALUES (#{placeholders}, LOCALTIMESTAMP(0), LOCALTIMESTAMP(0)) RETURNING id"
  end

  defp insert!(db, sql, params) do
    %{rows: [[id]]} = SeededUpgrade.query!(db, sql, params)
    id
  end
end
