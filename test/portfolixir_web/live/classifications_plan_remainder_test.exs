defmodule PortfolixirWeb.ClassificationsPlanRemainderTest do
  # Sprint 18 pick H8.4 = A (#969; board ux-design-2026-10-02/08-dialogs-copy;
  # ADR-0040 §3, DESIGN.md D3): a plan that allocates less than 100 % is a
  # choice, not a mistake. The plan editor's Σ carries no mark under 100 %,
  # and the gap is the table's last row, "Not allocated", muted and not
  # editable. ✓ means exactly 100 %; ✗ and the warning colour stay above it.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures, only: [base_world: 0]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications

  defp live_drained(conn, path) do
    {:ok, view, html} = live(conn, path)
    render_async(view)
    {:ok, view, html}
  end

  defp plan_world do
    world = base_world()

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    [equity, bonds] =
      for name <- ["Equity", "Bonds"] do
        {:ok, category} =
          Classifications.create_category(Actor.owner_ui(), %{
            classification_id: classification.id,
            name: name
          })

        category
      end

    Map.merge(world, %{classification: classification, equity: equity, bonds: bonds})
  end

  defp type(view, equity, bonds, {e, b, cash}) do
    view
    |> element("#soll-plan-form")
    |> render_change(%{
      "weights" => %{"#{equity.id}" => e, "#{bonds.id}" => b},
      "cash_target" => cash
    })

    view
  end

  defp sum_row(view), do: view |> element("tr.soll-row--sum") |> render()

  # User story (#969; pick H8.4 = A, board 08-dialogs-copy):
  # As the operator keeping part of a plan deliberately unallocated,
  # I want the plan editor to show the gap as a plain remainder row instead
  # of an error,
  # so that a deliberate choice does not render like a mistake (ADR-0040 §3).
  #
  # Acceptance criteria:
  # - Under 100 % the Σ shows the sum with no glyph and no warning class,
  #   and a last row "Not allocated" carries 100 − Σ, muted, in the same
  #   tabular slot, with no input.
  # - At exactly 100 % the Σ reads "100% ✓" and there is no remainder row.
  # - Above 100 % nothing changes: the warning class and ✗, no remainder row.
  # - On a German page the row reads "Nicht verteilt" and the figure "4,5%".
  test "a sum under 100 % shows a muted remainder row and no mark", %{conn: conn} do
    %{classification: classification, equity: equity, bonds: bonds} = plan_world()

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")
    view |> element("button[phx-click='create_soll_plan']") |> render_click()

    # 55 + 25 + 12 = 92 → 8 % not allocated.
    type(view, equity, bonds, {"55", "25", "12"})

    sum = sum_row(view)
    assert sum =~ "92%"
    refute sum =~ "is-target-mismatch"
    refute sum =~ "soll-bad"
    refute sum =~ "soll-ok"

    assert has_element?(view, "tfoot tr.soll-row--remainder:last-child")
    remainder = view |> element("tr.soll-row--remainder") |> render()
    assert remainder =~ "Not allocated"
    assert view |> element("[data-role='soll-remainder']") |> render() =~ "8%"
    refute remainder =~ "<input"
    refute remainder =~ "is-target-mismatch"

    # Exactly 100 → ✓, no remainder row.
    type(view, equity, bonds, {"55", "25", "20"})
    assert sum_row(view) =~ "soll-ok"
    refute sum_row(view) =~ "is-target-mismatch"
    refute has_element?(view, "tr.soll-row--remainder")

    # Above 100 → the warning, unchanged, and no remainder row.
    type(view, equity, bonds, {"55", "29", "20"})
    assert sum_row(view) =~ "104%"
    assert sum_row(view) =~ "is-target-mismatch"
    assert sum_row(view) =~ "soll-bad"
    refute has_element?(view, "tr.soll-row--remainder")

    css = File.read!("priv/static/app.css")
    assert css =~ ~r/\.soll-row--remainder th\s*\{[^}]*color:\s*var\(--color-text-muted\)/
  end

  test "the remainder row reads in German, in the page's number format", %{conn: conn} do
    %{classification: classification, equity: equity, bonds: bonds} = plan_world()

    conn = Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")
    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")
    view |> element("button[phx-click='create_soll_plan']") |> render_click()

    type(view, equity, bonds, {"55.5", "30", "10"})

    assert view |> element("tr.soll-row--remainder") |> render() =~ "Nicht verteilt"
    assert view |> element("[data-role='soll-remainder']") |> render() =~ "4,5%"
  end
end
