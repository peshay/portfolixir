defmodule PortfolixirWeb.MergedAwayRedirectLiveTest do
  # ADR-0050 §12 (L5a): "/securities/:id and a benchmark parameter naming a
  # merged-away security redirect to the survivor with a notice" — board 03's
  # note for an old link, and board 13's for the Wealth page. Every name is
  # synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Lifecycle
  alias Portfolixir.WorldFixtures

  # User story:
  # As the operator following an old link to a security that was merged
  # into another,
  # I want to land on the security its history lives on now, told once why,
  # so that a bookmark never ends on an empty page or a silent swap.
  #
  # Acceptance criteria:
  # - /securities/<merged-away id> patches to /securities/<survivor>, keeping
  #   the detail tab, and opens the survivor's detail.
  # - The detail says the link led to a security merged into this one, with
  #   the merge's date; the note has a dismiss and is gone after the next
  #   navigation.
  # - A merge chain is followed to its live end; an id no merge names still
  #   selects nothing.
  test "an old security link lands on the survivor with a note", %{conn: conn} do
    first = security!("Chain Fund")
    second = security!("Chain Fund")
    merge!(first, second)
    last = security!("Chain Fund")
    merge!(second, last)
    today = Portfolixir.Clock.today() |> Date.to_iso8601()

    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, "/securities/#{first.id}?tab=chart")

    assert to == "/securities/#{last.id}?merged_from=#{first.id}&tab=chart"
    {:ok, view, _html} = live(conn, to)
    assert has_element?(view, "#security-detail-pane h2", "Chain Fund")

    assert view |> element("#security-detail-pane [data-role='merged-notice']") |> render() =~
             "The link led to a security that was merged into this one on #{today}."

    view |> element("#security-detail-pane [data-role='merged-notice'] button") |> render_click()
    refute has_element?(view, "[data-role='merged-notice']")

    {:ok, view, _html} = live(conn, "/securities/999999999")
    refute has_element?(view, "#security-detail-pane")

    {:ok, view, _html} = live(conn, to <> "&locale=de")

    assert view |> element("[data-role='merged-notice']") |> render() =~
             "Der Link führte zu einem Wertpapier, das am #{Calendar.strftime(Portfolixir.Clock.today(), "%d.%m.%Y")} hierher zusammengeführt wurde."

    # A crafted merged_from without a merge behind it notes nothing.
    {:ok, view, _html} = live(conn, "/securities/#{last.id}?merged_from=#{last.id}")
    assert has_element?(view, "#security-detail-pane")
    refute has_element?(view, "[data-role='merged-notice']")
  end

  # User story:
  # As the operator whose benchmark was merged into another security,
  # I want the Wealth page to compare against the survivor and say so once,
  # so that the comparison neither vanishes silently nor swaps behind my
  # back.
  #
  # Acceptance criteria:
  # - /portfolio?benchmark[]=security:<merged-away id> redirects to the same
  #   page naming the survivor, and the page remembers the survivor.
  # - The performance section notes that the benchmark named a security
  #   merged into the survivor, with the date; it can be dismissed.
  # - The note is not shown without a merge behind it, whatever the URL says.
  test "a benchmark naming a merged-away security redirects to the survivor", %{conn: conn} do
    world = seed_world()
    source = benchmark!("Bench ETF", world)
    target = benchmark!("Bench ETF", world)
    merge!(source, target)
    today = Portfolixir.Clock.today() |> Date.to_iso8601()

    path = "/portfolio?benchmark[]=security:#{source.id}"
    conn = get(conn, path)

    assert {:error, {:redirect, %{to: to}}} = live(conn, path)
    assert to =~ "security%3A#{target.id}"
    refute to =~ "security%3A#{source.id}"

    conn = get(conn, to)
    {:ok, view, _html} = live(conn, to)
    render_async(view)

    assert has_element?(view, "[data-role='benchmark-chip']", "Bench ETF")

    assert view |> element("[data-role='benchmark-merged']") |> render() =~
             "The benchmark named a security that was merged into “Bench ETF” on #{today}; the comparison now uses it."

    view |> element("[data-role='benchmark-merged'] button") |> render_click()
    refute has_element?(view, "[data-role='benchmark-merged']")

    # Remembered: the next visit carries the survivor and no note.
    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)
    assert has_element?(view, "[data-role='benchmark-chip']", "Bench ETF")
    refute has_element?(view, "[data-role='benchmark-merged']")

    # A crafted notice parameter without a merge behind it shows nothing.
    {:ok, view, _html} = live(conn, "/portfolio?benchmark_merged=#{target.id}")
    refute has_element?(view, "[data-role='benchmark-merged']")
  end

  # User story:
  # As the operator opening a bookmarked Wealth link whose benchmark was
  # merged away since,
  # I want the redirect to keep the period, the view and every other
  # choice of the link,
  # so that only the benchmark changes.
  #
  # Acceptance criteria (review finding M-8):
  # - The redirect keeps period, from, to, year, classification, alloc,
  #   drift and positions as the link gave them, names the survivor, and
  #   drops only the selectors it replaces.
  test "the survivor redirect keeps every other parameter of the link", %{conn: conn} do
    world = seed_world()
    source = benchmark!("Bench ETF", world)
    target = benchmark!("Bench ETF", world)
    merge!(source, target)

    kept = %{
      "tab" => "performance",
      "period" => "custom",
      "from" => Date.to_iso8601(world.start),
      "to" => Date.to_iso8601(world.today),
      "year" => "2025",
      "classification" => "asset_class",
      "alloc" => "value",
      "drift" => "5",
      "positions" => "all"
    }

    path =
      "/portfolio?" <>
        URI.encode_query(Map.to_list(kept) ++ [{"benchmark[]", "security:#{source.id}"}])

    conn = get(conn, path)
    assert {:error, {:redirect, %{to: to}}} = live(conn, path)

    query = to |> URI.parse() |> Map.fetch!(:query) |> URI.query_decoder() |> Enum.to_list()

    for {key, value} <- kept do
      assert {key, value} in query, "#{key} kept"
    end

    assert {"benchmark[]", "security:#{target.id}"} in query
    refute {"benchmark[]", "security:#{source.id}"} in query
  end

  defp seed_world do
    Classifications.ensure_builtins()
    world = WorldFixtures.base_world(name: "Mein Depot", cash_name: "Giro", depot_name: "Depot")
    held = WorldFixtures.create_security!(name: "World ETF", ticker: "WLD")
    today = Portfolixir.Clock.today()
    start = Date.add(today, -20)
    WorldFixtures.put_quotes!(held, [{start, "100"}, {Date.add(today, -1), "120"}])
    WorldFixtures.deposit!(world, "1000", start)
    WorldFixtures.buy!(world, held, quantity: "10", price: "100", date: start)
    Map.merge(world, %{start: start, today: today})
  end

  defp benchmark!(name, world) do
    security = WorldFixtures.create_security!(name: name, ticker: nil)
    {:ok, security} = Catalog.update_security(Actor.owner_ui(), security, %{is_benchmark: true})
    WorldFixtures.put_quotes!(security, [{world.start, "50"}, {Date.add(world.today, -1), "55"}])
    security
  end

  defp security!(name), do: WorldFixtures.create_security!(name: name, ticker: nil)

  defp merge!(source, target) do
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    {:ok, _record, :applied} =
      Lifecycle.merge_security(Actor.owner_ui(), source.id, target.id, %{
        plan_digest: preview.plan_digest,
        collapse_key_equal: false
      })
  end
end
