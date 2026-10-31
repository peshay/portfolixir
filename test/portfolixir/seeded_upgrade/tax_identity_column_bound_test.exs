defmodule Portfolixir.SeededUpgrade.TaxIdentityColumnBoundTest do
  # The tax identity normalisation (20260925230000) over legacy spellings a
  # release before 2026.10.1 could store: a value within its varchar(255)
  # column whose normalised form no longer fits it. Every value is synthetic.
  #
  # async: false -- see Portfolixir.SeededUpgrade, "Where the cases run".
  use ExUnit.Case, async: false

  alias Portfolixir.SeededUpgrade

  @moduletag :seeded_upgrade

  # The last migration the 0.14.0 release shipped: an upgrade from 0.14.0
  # replays every later migration over its rows.
  @release_0_14_0 20_260_919_120_000

  # 86 x U+FB2C: 86 code points as stored; normalised (NFC), 258.
  @expanding_holder String.duplicate("\u{FB2C}", 86)
  # 128 x U+0344: 128 code points as stored; normalised (NFC), 256.
  @expanding_institution String.duplicate("\u{0344}", 128)
  # 85 x U+FB2C: normalised, exactly 255 code points, which fits.
  @fitting_holder String.duplicate("\u{FB2C}", 85)

  # User story (security review 2026-10-12, K01):
  # As the operator upgrading an instance, or restoring an older backup into
  # a current release, whose tax records hold a holder or an institution that
  # normalisation lengthens past its column,
  # I want the identity normalisation to report and keep such a row,
  # so that the release boots and I correct the row on the Tax page, as the
  # deployment guide promises.
  #
  # Acceptance criteria:
  # - Seeded at 0.14.0's last migration with a profile holder and an
  #   allowance order institution that fit their column as stored but not
  #   once normalised (counted in code points, as the column counts), the
  #   database migrates to head.
  # - Both rows keep their stored spelling, and the upgrade's log names each
  #   by table and id as one that would outgrow its column.
  @tag seeded_upgrade: 20_260_925_230_000
  test "the tax identity normalisation reports and keeps a spelling that would outgrow its column",
       %{seeded_upgrade: migration} do
    for value <- [@expanding_holder, @expanding_institution] do
      assert length(String.codepoints(value)) <= 255
      nfc = :unicode.characters_to_nfc_binary(value)
      assert String.length(nfc) <= 255
      assert length(String.codepoints(nfc)) > 255
    end

    upgrade =
      SeededUpgrade.upgrade!(
        from: @release_0_14_0,
        seed: fn db ->
          %{
            profile:
              insert!(db, "INSERT INTO tax_profiles " <> row(~w(holder valid_from)), [
                @expanding_holder,
                ~D[2026-01-01]
              ]),
            order:
              insert!(
                db,
                "INSERT INTO allowance_orders " <>
                  row(~w(holder institution tax_year amount_granted)),
                ["Synthetic Holder", @expanding_institution, 2026, Decimal.new("500")]
              )
          }
        end
      )

    rows = upgrade.seeded

    assert migration in upgrade.migrated
    assert List.last(upgrade.migrated) == SeededUpgrade.head()

    assert column(upgrade, "tax_profiles", "holder", rows.profile) == @expanding_holder

    assert column(upgrade, "allowance_orders", "institution", rows.order) ==
             @expanding_institution

    assert upgrade.log =~
             "tax_profiles ##{rows.profile} keeps its stored holder or institution spelling: " <>
               "normalised, it would outgrow its column"

    assert upgrade.log =~
             "allowance_orders ##{rows.order} keeps its stored holder or institution spelling: " <>
               "normalised, it would outgrow its column"
  end

  # User story (security review 2026-10-12, K01):
  # As the operator upgrading an instance whose tax records hold a spelling
  # that normalises to exactly its column's width,
  # I want that row normalised like any other,
  # so that the bound refuses only what the column cannot hold.
  #
  # Acceptance criteria:
  # - Seeded at 0.14.0's last migration with a profile holder whose
  #   normalised form is exactly 255 code points, the database migrates to
  #   head and the row holds the normalised form.
  @tag seeded_upgrade: 20_260_925_230_000
  test "the tax identity normalisation writes a spelling that normalises to exactly its column's width" do
    upgrade =
      SeededUpgrade.upgrade!(
        from: @release_0_14_0,
        seed: fn db ->
          insert!(db, "INSERT INTO tax_profiles " <> row(~w(holder valid_from)), [
            @fitting_holder,
            ~D[2026-01-01]
          ])
        end
      )

    stored = column(upgrade, "tax_profiles", "holder", upgrade.seeded)

    assert List.last(upgrade.migrated) == SeededUpgrade.head()
    assert stored == :unicode.characters_to_nfc_binary(@fitting_holder)
    assert length(String.codepoints(stored)) == 255
  end

  # `(columns..., inserted_at, updated_at) VALUES ($1, ..., now, now)
  # RETURNING id`, as the repository's seeded cases build it.
  defp row(columns) do
    placeholders = Enum.map_join(1..length(columns), ", ", &"$#{&1}")

    "(#{Enum.join(columns, ", ")}, inserted_at, updated_at) " <>
      "VALUES (#{placeholders}, LOCALTIMESTAMP(0), LOCALTIMESTAMP(0)) RETURNING id"
  end

  defp insert!(db, sql, params) do
    %{rows: [[id]]} = SeededUpgrade.query!(db, sql, params)
    id
  end

  defp column(db, table, column, id) do
    %{rows: [[value]]} =
      SeededUpgrade.query!(db, "SELECT #{column} FROM #{table} WHERE id = $1", [id])

    value
  end
end
