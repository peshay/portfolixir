defmodule PortfolixirWeb.TaxExplanationsLiveTest do
  # Sprint 23 Lane I, board `ux-design-2026-11-03-sprint23-i1` on Steuern
  # (I1, variant R with Sprint 22's Q1 corrections): nothing moves into an
  # ⓘ; every note clamps and keeps its button below the cut. Every name and
  # figure is invented.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Tax

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  # A statement whose withheld tax does not match its reconstruction (a
  # finding), dated so it is stale, beside an order at an institution with
  # no statement (the roll-up is incomplete).
  defp seed! do
    {:ok, _snapshot} =
      Tax.create_snapshot(
        Actor.owner_ui(),
        %{
          institution: "Example Bank",
          holder: "Owner",
          tax_year: 2025,
          as_of: ~D[2025-12-31],
          taxable_income: Decimal.new("12000.00"),
          allowance_granted: Decimal.new("1000.00"),
          allowance_used: Decimal.new("1000.00"),
          loss_pot_equities: Decimal.new("2500.00"),
          withholding_tax_credited: Decimal.new("200.00"),
          capital_gains_tax_withheld: Decimal.new("2000.00"),
          solidarity_surcharge_withheld: Decimal.new("140.25")
        },
        today: ~D[2026-01-15]
      )

    {:ok, _} =
      Tax.put_allowance_order(Actor.owner_ui(), %{
        holder: "Owner",
        institution: "Other Bank",
        tax_year: 2025,
        amount_granted: "500.00"
      })
  end

  # User story (I1, board ③ on Steuern):
  # As the operator reading the tax budget and my recorded statements,
  # I want each note cut to two lines with its button below the cut,
  # so that the budget and the statements read as their figures and the
  # remedy stays one press away.
  #
  # Acceptance criteria:
  # - `budget-stale` and `budget-incomplete` clamp (`data-note--clamped`,
  #   each with its own id); the stale note's text keeps "Stale — …" and
  #   „Record a new statement“ sits in its actions, not in its text.
  # - Each `statement-finding` clamps with an id of its own; its text keeps
  #   the finding ("… reconstructed from the statement …", "… Re-check the
  #   figure against the statement."), its control („Check against the
  #   statement“) sits in its actions.
  # - Nothing moves: the budget's basis line keeps its as-of date and its
  #   institution.
  test "both notes clamp with their buttons below the cut", %{conn: conn} do
    seed!()

    {:ok, _live, html} = live(conn, "/tax?holder=Owner&year=2025")
    doc = Floki.parse_document!(html)

    stale = Floki.find(doc, ~s([data-role="budget-stale"].data-note--clamped))
    assert [_] = stale
    assert [_] = Floki.attribute(stale, "id")
    assert text(Floki.find(stale, ".data-note__text")) =~ ~r/^Stale — /
    assert Floki.find(stale, ".data-note__text button") == []

    assert [_] =
             Floki.find(stale, ".data-note__actions button[phx-click=open_statement_form]")

    assert [_] = Floki.find(doc, ~s([data-role="budget-incomplete"].data-note--clamped))

    findings = Floki.find(doc, ~s([data-role="statement-finding"]))
    assert findings != []

    ids = Enum.flat_map(findings, &Floki.attribute(&1, "id"))
    assert length(ids) == length(findings)
    assert ids == Enum.uniq(ids)

    assert text(Floki.find(findings, ".data-note__text")) =~ "reconstructed from the statement"

    for finding <- findings do
      assert Floki.attribute(finding, "class") |> List.first() =~ "data-note--clamped"
      assert text(Floki.find(finding, ".data-note__text")) =~ "against the statement."
      assert Floki.find(finding, ".data-note__text button") == []
      assert [_] = Floki.find(finding, ".data-note__actions button[phx-click]")
    end

    basis = text(Floki.find(doc, ~s([data-role="budget-basis"])))
    assert basis =~ "2025-12-31"
    assert basis =~ "Example Bank"
  end
end
