defmodule PortfolixirWeb.ViewsExplanationsLiveTest do
  # Sprint 23 Lane I, board `ux-design-2026-11-03-sprint23-i1` on Ansichten
  # (I1, variant R; the board's reading 2, ⑥): a method line that the
  # heading's ⓘ already says leaves without a copy. Every name is invented.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.WorldFixtures

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  # User story (I1, board ⑥ on Ansichten):
  # As the operator managing views and buckets,
  # I want each heading to carry its explanation once, behind its ⓘ,
  # so that the lists start under their headings without a line that
  # repeats the ⓘ.
  #
  # Acceptance criteria:
  # - `[data-role=views-basis]` and `[data-role=buckets-basis]` are gone.
  # - The „Views“ ⓘ still says a view is a saved include/exclude filter over
  #   buckets that the view switcher on Wealth offers; the „Buckets“ ⓘ still
  #   says buckets are overlapping tags whose figures are never a sum.
  # - The assignment line stays whole: its pointer „→ Accounts & depots“ and
  #   the accounts without a default bucket ("Depot 1, Girokonto have no
  #   default bucket.").
  test "the two basis lines leave, the headings' ⓘ keep their meaning", %{conn: conn} do
    WorldFixtures.base_world(name: "Muster", cash_name: "Girokonto", depot_name: "Depot 1")

    {:ok, _live, html} = live(conn, "/buckets")
    doc = Floki.parse_document!(html)

    assert Floki.find(doc, ~s([data-role="views-basis"])) == []
    assert Floki.find(doc, ~s([data-role="buckets-basis"])) == []

    views_info = text(Floki.find(doc, ~s(#views-section [data-role="views-info"] p)))
    assert views_info =~ "a saved include/exclude filter over buckets"
    assert views_info =~ "the view switcher on the Wealth page"

    buckets_info = text(Floki.find(doc, ~s(#buckets-section [data-role="buckets-info"] p)))
    assert buckets_info =~ "overlapping tags"
    assert buckets_info =~ "never be read as a sum"

    assignment = Floki.find(doc, ~s([data-role="assignment-basis"]))
    assert text(assignment) =~ "Default buckets are set on the account row → Accounts & depots"
    assert text(assignment) =~ "have no default bucket."
    assert [_] = Floki.find(assignment, ~s(a[href="/portfolios"]))
  end
end
