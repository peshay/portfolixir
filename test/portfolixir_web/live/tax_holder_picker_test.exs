defmodule PortfolixirWeb.TaxHolderPickerTest do
  # E25 S6 (#891), G22: the Tax page's taxpayer picker listed every raw
  # holder spelling, so case variants of one taxpayer were two entries, each
  # with its own partial trim budget. It now lists one entry per identity,
  # the database's fold of the holder, with the scope's own spelling in the
  # place of its identity's entry.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Tax

  defp record!(holder, institution, as_of) do
    {:ok, snapshot} =
      Tax.create_snapshot(
        Actor.owner_ui(),
        %{
          institution: institution,
          holder: holder,
          tax_year: 2025,
          as_of: as_of,
          allowance_granted: Decimal.new("1000.00"),
          allowance_used: Decimal.new("400.00"),
          loss_pot_equities: Decimal.new("2500.00")
        },
        today: ~D[2026-01-15]
      )

    snapshot
  end

  # User story:
  # As the operator whose statements name one taxpayer in two spellings,
  # I want one entry for that taxpayer in the picker, carrying one budget,
  # so that I neither pick half a budget nor see a person twice.
  #
  # Acceptance criteria:
  # - Statements under "Anna Muster" and "ANNA MUSTER" give one picker entry;
  #   opened under either spelling, the entry is the scope's spelling, marked
  #   current, and the budget rolls both banks up.
  test "case spellings of one taxpayer are one picker entry with one budget", %{conn: conn} do
    record!("Anna Muster", "Bank Eins", ~D[2025-06-30])
    record!("ANNA MUSTER", "Bank Zwei", ~D[2025-09-30])

    {:ok, view, _html} = live(conn, "/tax?holder=anna%20muster&year=2025")

    entries =
      view
      |> element("[data-role='tax-holders']")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("a")

    assert length(entries) == 1
    assert [entry] = entries
    assert Floki.text(entry) =~ "anna muster"
    assert Floki.attribute(entry, "aria-current") == ["true"]

    summary = Tax.holder_summary("anna muster", 2025)
    assert length(summary.institutions) == 2
  end
end
