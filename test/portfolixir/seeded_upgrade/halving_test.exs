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
end
