defmodule Portfolixir.Tax.IdentityFoldingTest do
  # E25 S6 (#891), G21 and G22: the tax context keys three tables on the
  # free-text holder and institution. Lookups folded the stored side with
  # PostgreSQL's lower() and the value with Elixir's String.downcase/1, which
  # disagree on some letters; normalisation left non-breaking spaces,
  # decomposed letters and invisible format characters in place; and the
  # trim-budget roll-ups and the Tax page's taxpayer picker iterated raw
  # holder spellings. Now both sides are folded by the database with the
  # lower() of the unique indexes, the roll-ups are grouped by that
  # database-computed key, the identities are enumerated in SQL with one
  # display spelling each, and Identity.normalize/1 composes (NFC), removes
  # format characters, splits on every Unicode space and leaves a value that
  # is only such characters empty, which the changesets refuse.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Tax
  alias Portfolixir.Tax.Identity

  defp owner, do: Actor.owner_ui()

  defp snapshot!(holder, institution, as_of, overrides \\ %{}) do
    {:ok, snapshot} =
      Tax.create_snapshot(
        owner(),
        Map.merge(
          %{
            institution: institution,
            holder: holder,
            tax_year: 2025,
            as_of: as_of,
            allowance_granted: Decimal.new("500.00"),
            allowance_used: Decimal.new("100.00"),
            loss_pot_equities: Decimal.new("1000.00")
          },
          overrides
        ),
        today: ~D[2026-01-15]
      )

    snapshot
  end

  # User story:
  # As the operator typing a taxpayer or a bank the way it comes out of a
  # statement — a non-breaking space, a decomposed umlaut, an invisible
  # character copied along —
  # I want it stored as the one spelling it reads as,
  # so that it matches the rows already recorded for that identity.
  #
  # Acceptance criteria:
  # - normalize/1 composes to NFC, removes format characters, and collapses
  #   every run of Unicode spaces to one space, trimmed.
  # - A value that is only spaces and format characters is refused as blank
  #   on the profile, the allowance order and the statement snapshot.
  test "normalize composes, strips format characters and splits on every Unicode space" do
    assert Identity.normalize("Mu\u{0308}ller") == "Müller"
    assert Identity.normalize("Anna\u{00A0}\u{2007}\u{202F} Muster\u{3000}") == "Anna Muster"
    assert Identity.normalize("Bank\u{200B} Eins\u{2060}\u{00AD}") == "Bank Eins"
    assert Identity.normalize(" \u{200B}\u{00A0}\u{FEFF} ") == ""

    blank = " \u{200B}\u{00A0}\u{FEFF} "

    assert {:error, changeset} =
             Tax.create_profile(owner(), %{holder: blank, valid_from: ~D[2020-01-01]})

    assert %{holder: [_]} = errors_on(changeset)

    assert {:error, changeset} =
             Tax.put_allowance_order(owner(), %{
               holder: "Owner",
               institution: blank,
               tax_year: 2025,
               amount_granted: Decimal.new("1000.00")
             })

    assert %{institution: [_]} = errors_on(changeset)

    assert {:error, changeset} =
             Tax.create_snapshot(
               owner(),
               %{institution: "Bank", holder: blank, tax_year: 2025, as_of: ~D[2025-12-31]},
               today: ~D[2026-01-15]
             )

    assert %{holder: [_]} = errors_on(changeset)
  end

  # User story:
  # As the operator re-recording an allowance order for a bank whose name
  # starts with a capital dotted I,
  # I want the second write to update the first,
  # so that the database's own case rule, not a second one, decides what is
  # the same bank.
  #
  # Acceptance criteria:
  # - A lookup of a holder or institution folds both sides with the
  #   database's lower(): a second put of the same order updates it, and a
  #   filter by any case spelling finds the row.
  test "both sides are folded by the database" do
    attrs = %{
      holder: "Owner",
      institution: "İstanbul Bank",
      tax_year: 2025,
      amount_granted: Decimal.new("1000.00")
    }

    assert {:ok, first} = Tax.put_allowance_order(owner(), attrs)

    assert {:ok, second} =
             Tax.put_allowance_order(owner(), %{attrs | amount_granted: Decimal.new("801.00")})

    assert second.id == first.id
    assert [_one] = Tax.list_allowance_orders(institution: "İSTANBUL BANK")

    snapshot!("Owner", "İstanbul Bank", ~D[2025-06-30])
    assert [_one] = Tax.list_snapshots(institution: "İstanbul Bank")
    assert %{} = Tax.latest_snapshot("İstanbul Bank", "owner", 2025)
  end

  # User story (G22):
  # As the operator whose statements carry one taxpayer in several
  # spellings,
  # I want one trim budget and one picker entry for that taxpayer,
  # so that the budget is neither split nor counted twice.
  #
  # Acceptance criteria:
  # - Snapshots under case, space-variant and decomposed spellings of one
  #   holder list one holder, with one display spelling.
  # - That holder's roll-up counts each institution once, whatever the case
  #   of its name, from its latest statement: a later statement under
  #   another case spelling of the same bank replaces the earlier one.
  test "spellings of one holder and one institution roll up once" do
    snapshot!("Anna Muster", "Bank Eins", ~D[2025-06-30])

    snapshot!("ANNA\u{00A0}MUSTER", "BANK EINS", ~D[2025-09-30], %{
      allowance_used: Decimal.new("300.00")
    })

    snapshot!("anna muster", "Bank Zwei", ~D[2025-08-31])
    snapshot!("Mu\u{0308}ller", "Bank Eins", ~D[2025-08-31])
    snapshot!("müller", "Bank Eins", ~D[2025-09-30])

    assert Tax.list_snapshot_holders() |> length() == 2
    assert "Müller" in Tax.list_snapshot_holders() or "müller" in Tax.list_snapshot_holders()

    summary = Tax.holder_summary("Anna Muster", 2025)
    assert length(summary.institutions) == 2
    assert summary.complete?
    # Bank Eins counts its later statement (used 300), Bank Zwei its only one.
    assert Decimal.equal?(summary.allowance_used, Decimal.new("400.00"))
    assert Decimal.equal?(summary.loss_pot_equities, Decimal.new("2000.00"))

    assert %{institutions: [_one]} = Tax.holder_summary("MÜLLER", 2025)
  end

  # Acceptance criteria:
  # - An allowance order for an institution counts as covered by a statement
  #   under another case spelling of it, so the roll-up is complete.
  test "an order's institution is covered by a statement under another spelling" do
    {:ok, _} =
      Tax.put_allowance_order(owner(), %{
        holder: "Owner",
        institution: "İstanbul Bank",
        tax_year: 2025,
        amount_granted: Decimal.new("1000.00")
      })

    snapshot!("owner", "istanbul bank", ~D[2025-06-30])

    summary = Tax.holder_summary("Owner", 2025)
    assert summary.complete?
    assert summary.missing_institutions == []
  end
end
