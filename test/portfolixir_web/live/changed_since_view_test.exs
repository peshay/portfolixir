defmodule PortfolixirWeb.ChangedSinceViewTest do
  # Issue #731: the `?since=` delta read (FR-38) shipped agent-only in Sprint
  # 6; this is its human view under the two-way coverage rule. The URL
  # parameter mirrors the API parameter — same name, same accepted forms,
  # same strictly-after-updated_at semantics — and the surface states the one
  # property that makes a delta read honest: deletions are not represented.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  # Test-only clock control (same shape as api_v1_delta_reads_test.exs):
  # backdate a row's updated_at so the cut has something on both sides. The
  # journal guard requires an actor for any write.
  defp backdate!(table, id, naive) when table in ["transactions", "securities"] do
    Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test_backdate', true)")
    Repo.query!("UPDATE #{table} SET updated_at = $1 WHERE id = $2", [naive, id])
  end

  # User story (issue #731):
  # As a local portfolio maintainer,
  # I want the transaction history to answer "what changed since <cut>?" from
  # the same `since` the agent polls with,
  # so that I can see the delta the agent saw — without mistaking it for a
  # complete picture.
  #
  # Acceptance criteria:
  # - `/transactions?since=<ISO>` shows only rows with updated_at strictly
  #   after the cut — the record-change instant, not the booking date.
  # - The surface states that deletions are not shown, and that the cut is by
  #   record change rather than booking date.
  # - The visible set is exactly what the API's `updated_since` query returns
  #   (one semantics, two surfaces).
  test "transactions ?since= narrows the history to rows changed after the cut", %{conn: conn} do
    world = WorldFixtures.base_world()
    old = WorldFixtures.deposit!(world, "100.00", ~D[2026-01-02])
    new = WorldFixtures.deposit!(world, "250.00", ~D[2026-01-03])
    backdate!("transactions", old.id, ~N[2026-01-02 08:00:00])

    {:ok, view, _html} = live(conn, "/transactions?since=2026-02-01")

    assert has_element?(view, "tr[data-transaction='#{new.id}']")
    refute has_element?(view, "tr[data-transaction='#{old.id}']")

    note = view |> element("#transaction-since-note") |> render()
    assert note =~ "2026-02-01"
    assert note =~ "Deletions are not shown"
    assert note =~ "not booking date"

    # Parity with the agent's read: the rows the view keeps are the rows the
    # API's updated_since cut returns.
    api_ids =
      Ledger.list_transactions(updated_since: ~N[2026-02-01 00:00:00]) |> Enum.map(& &1.id)

    assert Enum.sort(api_ids) == Enum.sort([new.id])
  end

  # User story (issue #731):
  # As a local portfolio maintainer,
  # I want one-tap presets for the changed-since cut,
  # so that "what changed this week?" does not require me to type a
  # timestamp.
  #
  # Acceptance criteria:
  # - The chips patch the URL with a concrete ISO date (the same value an
  #   agent could use), so the view stays shareable.
  # - Toggling the active chip clears the filter.
  test "transactions changed-since chips ride the URL as toggles", %{conn: conn} do
    world = WorldFixtures.base_world()
    WorldFixtures.deposit!(world, "100.00", ~D[2026-01-02])

    {:ok, view, _html} = live(conn, "/transactions")

    view |> element("#changed-since-chips-7d") |> render_click()
    expected = Date.utc_today() |> Date.add(-7) |> Date.to_iso8601()
    assert_patch(view, "/transactions?since=#{expected}")

    assert view |> element("#changed-since-chips-7d") |> render() =~ ~s(aria-pressed="true")

    view |> element("#changed-since-chips-7d") |> render_click()
    assert_patch(view, "/transactions")
    refute has_element?(view, "#transaction-since-note")
  end

  # User story (issue #731):
  # As a local portfolio maintainer,
  # I want a garbled `since` to degrade to the full history instead of
  # crashing or silently filtering,
  # so that a stale or mistyped link never lies about the data.
  #
  # Acceptance criteria:
  # - An unparseable `since` applies no cut and renders no delta note.
  test "a garbled since degrades to the unfiltered history", %{conn: conn} do
    world = WorldFixtures.base_world()
    old = WorldFixtures.deposit!(world, "100.00", ~D[2026-01-02])
    backdate!("transactions", old.id, ~N[2026-01-02 08:00:00])

    {:ok, view, _html} = live(conn, "/transactions?since=lots")

    assert has_element?(view, "tr[data-transaction='#{old.id}']")
    refute has_element?(view, "#transaction-since-note")
  end

  # User story (issue #731):
  # As a local portfolio maintainer,
  # I want the securities list to answer "what changed since <cut>?",
  # so that a catalog sync's delta is visible to me, not only to the agent.
  #
  # Acceptance criteria:
  # - `/securities?since=<ISO>` lists only securities changed after the cut.
  # - The surface states that deletions are not shown.
  # - The cut survives other list interactions (it is part of the URL state
  #   like every other list filter).
  test "securities ?since= narrows the list and survives list interactions", %{conn: conn} do
    old = WorldFixtures.create_security!(name: "Old Equity", ticker: "OLD")
    new = WorldFixtures.create_security!(name: "New Equity", ticker: "NEW")
    backdate!("securities", Catalog.get_security(old.id).id, ~N[2026-01-02 08:00:00])

    {:ok, view, _html} = live(conn, "/securities?since=2026-02-01")

    assert has_element?(view, "#security-row-#{new.id}")
    refute has_element?(view, "#security-row-#{old.id}")

    note = view |> element("#securities-since-note") |> render()
    assert note =~ "2026-02-01"
    assert note =~ "Deletions are not shown"

    # The cut is URL state: another patching interaction (a #717 filter
    # chip) keeps it.
    view |> element("#sec-chip-held") |> render_click()
    path = assert_patch(view)
    assert path =~ "since=2026-02-01"
  end

  # User story (issue #731):
  # As a local portfolio maintainer,
  # I want the securities chips to behave exactly like the transactions ones,
  # so that the changed-since pattern reads as one control, not two.
  #
  # Acceptance criteria:
  # - The chips patch the URL; toggling the active chip clears the cut.
  # - A garbled since degrades to the full list without a note.
  test "securities changed-since chips ride the URL and garbled since degrades", %{conn: conn} do
    old = WorldFixtures.create_security!(name: "Old Equity", ticker: "OLD")
    backdate!("securities", old.id, ~N[2026-01-02 08:00:00])

    {:ok, view, _html} = live(conn, "/securities")

    view |> element("#changed-since-chips-30d") |> render_click()
    expected = Date.utc_today() |> Date.add(-30) |> Date.to_iso8601()
    path = assert_patch(view)
    assert path =~ "since=#{expected}"

    view |> element("#changed-since-chips-30d") |> render_click()
    path = assert_patch(view)
    refute path =~ "since="

    {:ok, view, _html} = live(conn, "/securities?since=lots")
    assert has_element?(view, "#security-row-#{old.id}")
    refute has_element?(view, "#securities-since-note")
  end
end
