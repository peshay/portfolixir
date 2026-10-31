defmodule Portfolixir.Tax.IdentityBackfillBoundsTest do
  # The tax identity backfill over a legacy row it cannot write: a value whose
  # normalised form outgrows its column, and a row the database refuses for
  # any other reason. Copies the raw-insert idiom of identity_backfill_test.exs.
  # async: false: one case adds a constraint inside its sandbox transaction.
  # Every value is synthetic.
  use Portfolixir.DataCase, async: false

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Input.Text
  alias Portfolixir.Tax.Identity
  alias Portfolixir.Tax.IdentityBackfill

  @now ~N[2026-01-15 10:00:00]

  defp job, do: Actor.system_job("tax_identity_backfill")

  # A row as a writer before 2026.10.1 stored it: the value unnormalised.
  defp raw_insert!(table, row) do
    {:ok, id} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test', true)")

        {1, [%{id: id}]} =
          Repo.insert_all(table, [Map.merge(%{inserted_at: @now, updated_at: @now}, row)],
            returning: [:id]
          )

        id
      end)

    id
  end

  defp holder(id), do: Repo.one!(from(p in "tax_profiles", where: p.id == ^id, select: p.holder))

  # User story (security review 2026-10-12, K01):
  # As the operator whose tax records hold a holder that normalisation
  # lengthens past its column,
  # I want the backfill to count the normalised value as the column counts it,
  # so that such a row is reported and kept instead of stopping the upgrade.
  #
  # Acceptance criteria:
  # - A holder of 86 code points whose normalised form is 258 code points
  #   (still 86 graphemes) is refused as too long, nothing is written, and
  #   the row keeps its stored spelling.
  test "a holder whose normalised form outgrows its column is reported as too long, not written" do
    holder = String.duplicate("\u{FB2C}", 86)
    id = raw_insert!("tax_profiles", %{holder: holder, valid_from: ~D[2025-01-01]})

    normalized = Identity.normalize(holder)
    assert String.length(normalized) == 86
    assert Text.codepoint_length(normalized) == 258

    assert {:ok, report} = IdentityBackfill.run(job())
    assert [%{table: "tax_profiles", id: ^id, reason: :too_long}] = report.refused
    assert report.written == []
    assert holder(id) == holder
  end

  # User story (security review 2026-10-12, K01):
  # As the operator upgrading an instance with a tax row the database will
  # not take in its normalised form, for whatever reason,
  # I want that one row reported by table and id and kept as stored,
  # so that no single row can stop the upgrade, and the other rows are still
  # normalised and journaled.
  #
  # Acceptance criteria:
  # - With a constraint that refuses one row's normalised holder, the run
  #   returns `{:ok, report}`: that row is refused, keeps its stored
  #   spelling and leaves no journal entry; the other row is written and
  #   journaled.
  # - The refusal's sentence names the table and the id, never the value.
  test "a row the database refuses is reported by table and id, and the run goes on" do
    refused = raw_insert!("tax_profiles", %{holder: "Refused Holder", valid_from: ~D[2025-01-01]})
    written = raw_insert!("tax_profiles", %{holder: "Kept Holder", valid_from: ~D[2025-01-01]})

    Repo.query!(
      "ALTER TABLE tax_profiles ADD CONSTRAINT identity_backfill_bounds_probe " <>
        "CHECK (holder <> 'Refused Holder') NOT VALID"
    )

    assert {:ok, report} = IdentityBackfill.run(job())
    assert [%{table: "tax_profiles", id: ^refused} = refusal] = report.refused
    assert report.written == [%{table: "tax_profiles", id: written}]

    assert holder(refused) == "Refused Holder"
    assert holder(written) == "Kept Holder"

    journaled =
      Repo.all(
        from(e in "audit_journal",
          where: e.actor_type == "system_job" and e.actor_label == "tax_identity_backfill",
          select: e.resource_id
        )
      )

    assert journaled == [Integer.to_string(written)]

    sentence = IdentityBackfill.describe(refusal)
    assert sentence =~ "tax_profiles ##{refused} keeps its stored holder or institution spelling"
    refute sentence =~ "Refused"
  end
end
