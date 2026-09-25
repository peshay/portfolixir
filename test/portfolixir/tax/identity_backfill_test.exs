defmodule Portfolixir.Tax.IdentityBackfillTest do
  # E25 S6 (#891) review round, G21: the identity rule tightened in this batch
  # (NFC, format characters removed, every Unicode space collapsed) is applied
  # to every value a write normalises, and the lookups normalise the value they
  # are given. A holder or institution stored before the change under a
  # no-break space, a zero-width character or a decomposed letter was then out
  # of reach of every filter. The migration `normalize_tax_identities`
  # normalises the stored values once, journaled, and reports — never writes,
  # never chooses — a row whose normalised spelling another row of its table
  # already holds under the unique key. Every name is synthetic.
  use Portfolixir.DataCase, async: true

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Tax
  alias Portfolixir.Tax.IdentityBackfill

  @migration "priv/repo/migrations/20260925230000_normalize_tax_identities.exs"
  @now ~N[2026-01-15 10:00:00]

  defp job, do: Actor.system_job("tax_identity_backfill")

  # A row as a writer before this batch stored it: the value unnormalised.
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

  defp snapshot_row(holder, institution, as_of) do
    %{
      holder: holder,
      institution: institution,
      tax_year: 2025,
      as_of: as_of,
      allowance_granted: Decimal.new("500.00"),
      allowance_used: Decimal.new("100.00")
    }
  end

  defp journal_count(resource_type) do
    Repo.aggregate(from(e in "audit_journal", where: e.resource_type == ^resource_type), :count)
  end

  # User story (E25 S6 review round, G21):
  # As the operator whose taxpayer and bank spellings were recorded before
  # the identity rule tightened — a no-break space, a zero-width character,
  # a decomposed letter —
  # I want those rows stored under the one spelling they read as,
  # so that the filters, the roll-ups and the Tax page reach them.
  #
  # Acceptance criteria:
  # - The backfill normalises every stored holder and institution the way a
  #   write does, each row journaled with its before-image.
  # - Afterwards the legacy rows match their filters and a bank recorded
  #   under two such spellings rolls up once.
  # - A second run writes and journals nothing.
  test "stored spellings are normalised, journaled, and reached by the filters" do
    snapshot_id =
      raw_insert!(
        "tax_statement_snapshots",
        snapshot_row("Anna\u{00A0}Muster", "Bank\u{200B} Eins", ~D[2025-06-30])
      )

    _clean =
      raw_insert!(
        "tax_statement_snapshots",
        snapshot_row("Anna Muster", "Bank Eins", ~D[2025-12-31])
      )

    profile_id =
      raw_insert!("tax_profiles", %{holder: "Mu\u{0308}ller", valid_from: ~D[2025-01-01]})

    order_id =
      raw_insert!("allowance_orders", %{
        holder: "Anna\u{2007}Muster",
        institution: "Bank  Eins",
        tax_year: 2025,
        amount_granted: Decimal.new("400.00")
      })

    assert Tax.list_snapshots(holder: "Anna Muster") |> length() == 1

    before = journal_count("tax_statement_snapshot")

    assert {:ok, report} = IdentityBackfill.run(job())
    assert report.refused == []

    assert Enum.sort(Enum.map(report.written, &{&1.table, &1.id})) ==
             Enum.sort([
               {"tax_statement_snapshots", snapshot_id},
               {"tax_profiles", profile_id},
               {"allowance_orders", order_id}
             ])

    assert journal_count("tax_statement_snapshot") == before + 1

    entry =
      Repo.one!(
        from(e in "audit_journal",
          where:
            e.resource_type == "tax_statement_snapshot" and
              e.resource_id == ^to_string(snapshot_id),
          select: %{actor_type: e.actor_type, before: e.before, after: e.after}
        )
      )

    assert entry.actor_type == "system_job"
    assert entry.before["holder"] == "Anna\u{00A0}Muster"
    assert entry.after["holder"] == "Anna Muster"
    assert entry.after["institution"] == "Bank Eins"

    assert Tax.list_snapshots(holder: "Anna Muster") |> length() == 2
    assert [%{holder: "M\u{00FC}ller"}] = Tax.list_profiles("M\u{00FC}ller")

    assert [%{id: ^order_id}] =
             Tax.list_allowance_orders(holder: "Anna Muster", institution: "Bank Eins")

    assert Tax.list_snapshot_holders() == ["Anna Muster"]
    assert [_one_bank] = Tax.holder_summary("Anna Muster", 2025).institutions

    journaled = Repo.aggregate("audit_journal", :count)
    assert {:ok, %{written: [], refused: []}} = IdentityBackfill.run(job())
    assert Repo.aggregate("audit_journal", :count) == journaled
  end

  # User story (E25 S6 review round, G21):
  # As the operator,
  # I want a stored spelling that would become another row's identity named
  # instead of rewritten,
  # so that the upgrade never merges or drops a row on my behalf.
  #
  # Acceptance criteria:
  # - A row whose normalised spelling another row of its table holds under
  #   the unique key is reported with both ids and left as stored.
  # - The migration runs the backfill and logs each refusal; the upgrade
  #   goes on.
  test "a spelling that would collide is reported, never written, and the migration goes on" do
    legacy =
      raw_insert!("tax_profiles", %{holder: "Anna\u{00A0}Muster", valid_from: ~D[2025-01-01]})

    clean = raw_insert!("tax_profiles", %{holder: "Anna Muster", valid_from: ~D[2025-01-01]})

    other =
      raw_insert!("tax_profiles", %{holder: "Bank\u{200B}Kunde", valid_from: ~D[2025-01-01]})

    [{module, _bytecode}] = Code.require_file(@migration)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert :ok = module.up()
      end)

    assert log =~ "tax_profiles ##{legacy}"
    assert log =~ "##{clean}"

    stored = fn id ->
      Repo.one!(from(p in "tax_profiles", where: p.id == ^id, select: p.holder))
    end

    assert stored.(legacy) == "Anna\u{00A0}Muster"
    assert stored.(clean) == "Anna Muster"
    assert stored.(other) == "BankKunde"
  end
end
