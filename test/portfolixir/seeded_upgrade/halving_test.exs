defmodule Portfolixir.SeededUpgrade.HalvingTest do
  # ADR-0059 §4 and ADR-0048's amendment of 2026-11-12 (Sprint 29 H1,
  # FR-58): the migrations that bind a security to a block chain and give an
  # event its chain height, each run over the rows an upgrading instance
  # holds (docs/development/guide.md, "Upgrade migrations over legacy
  # rows"). Every value is synthetic.
  #
  # async: false -- see Portfolixir.SeededUpgrade, "Where the cases run".
  use ExUnit.Case, async: false

  alias Portfolixir.SeededUpgrade

  @moduletag :seeded_upgrade

  # The migration before the binding, and the binding itself.
  @before_binding 20_261_112_153_000
  @binding 20_261_112_200_000
  @halving_kind 20_261_112_200_100

  # User story (ADR-0059 §4):
  # As the operator upgrading an instance that holds securities,
  # I want the binding column added without a guess,
  # so that every stored security reads unbound until I or my agent bind it.
  #
  # Acceptance criteria:
  # - Seeded with two securities, one of them a coin whose provider id is
  #   "bitcoin", the database migrates through the binding and both read
  #   halving_chain null.
  # - After the upgrade "bitcoin" is stored and "zcash" is refused by the
  #   database's check.
  @tag seeded_upgrade: 20_261_112_200_000
  test "the binding adds an unbound column and checks the registry's names",
       %{seeded_upgrade: migration} do
    upgrade =
      SeededUpgrade.upgrade!(from: @before_binding, to: @binding, seed: &seed_securities/1)

    assert upgrade.migrated == [migration]

    assert %{rows: [[nil], [nil]]} =
             SeededUpgrade.query!(upgrade, "SELECT halving_chain FROM securities ORDER BY id")

    [coin | _] = upgrade.seeded

    SeededUpgrade.journaled!(upgrade, fn ->
      SeededUpgrade.query!(
        upgrade,
        "UPDATE securities SET halving_chain = 'bitcoin' WHERE id = $1",
        [coin]
      )
    end)

    error =
      assert_raise Postgrex.Error, fn ->
        SeededUpgrade.journaled!(upgrade, fn ->
          SeededUpgrade.query!(
            upgrade,
            "UPDATE securities SET halving_chain = 'zcash' WHERE id = $1",
            [coin]
          )
        end)
      end

    assert %{postgres: %{constraint: "securities_halving_chain_check"}} = error
  end

  defp seed_securities(db) do
    for {name, online_id} <- [{"Coin", "bitcoin"}, {"Fund", nil}] do
      %{rows: [[id]]} =
        SeededUpgrade.query!(
          db,
          """
          INSERT INTO securities (name, currency_code, provider, online_id, inserted_at, updated_at)
          VALUES ($1, 'EUR', 'coingecko', $2, LOCALTIMESTAMP(0), LOCALTIMESTAMP(0))
          RETURNING id
          """,
          [name, online_id]
        )

      id
    end
  end

  # User story (ADR-0048's amendment of 2026-11-12, items 1 and 2):
  # As the operator upgrading an instance whose calendar holds events,
  # I want the kind halving and its height added without touching them,
  # so that every stored event keeps its kind and a null height, and a
  # halving can only ever be stored with one height per security.
  #
  # Acceptance criteria:
  # - Seeded with an earnings and a guidance event, the database migrates
  #   through the halving kind; both keep their kind and read chain_height
  #   null.
  # - After the upgrade a halving at 840000 is stored; a second at the same
  #   height on the same security, a halving without a height and an
  #   earnings event with one are refused by the database.
  @tag seeded_upgrade: 20_261_112_200_100
  test "the halving kind keeps every stored event and holds one row per height",
       %{seeded_upgrade: migration} do
    upgrade = SeededUpgrade.upgrade!(from: @binding, to: @halving_kind, seed: &seed_events/1)

    assert upgrade.migrated == [migration]
    security = upgrade.seeded

    assert %{rows: [["earnings", nil], ["guidance_update", nil]]} =
             SeededUpgrade.query!(
               upgrade,
               "SELECT kind, chain_height FROM security_events ORDER BY kind"
             )

    SeededUpgrade.journaled!(upgrade, fn ->
      insert_event!(upgrade, security, "halving", 840_000)
    end)

    for {kind, height, constraint} <- [
          {"halving", 840_000, "security_events_security_id_chain_height_index"},
          {"halving", nil, "security_events_chain_height_check"},
          {"earnings", 840_000, "security_events_chain_height_check"}
        ] do
      error =
        assert_raise Postgrex.Error, fn ->
          SeededUpgrade.journaled!(upgrade, fn ->
            insert_event!(upgrade, security, kind, height)
          end)
        end

      assert %{postgres: %{constraint: ^constraint}} = error
    end
  end

  defp seed_events(db) do
    [security] = seed_securities(db) |> Enum.take(1)

    for kind <- ["earnings", "guidance_update"] do
      SeededUpgrade.query!(
        db,
        """
        INSERT INTO security_events
          (security_id, kind, date, timing, source_quality, inserted_at, updated_at)
        VALUES ($1, $2, '2026-10-01', 'exact', 'primary', LOCALTIMESTAMP(0), LOCALTIMESTAMP(0))
        """,
        [security, kind]
      )
    end

    security
  end

  defp insert_event!(db, security, kind, height) do
    SeededUpgrade.query!(
      db,
      """
      INSERT INTO security_events
        (security_id, kind, chain_height, date, timing, source_quality, inserted_at, updated_at)
      VALUES ($1, $2, $3, '2019-08-05', 'exact', 'primary', LOCALTIMESTAMP(0), LOCALTIMESTAMP(0))
      """,
      [security, kind, height]
    )
  end
end
