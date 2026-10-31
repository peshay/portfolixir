defmodule PortfolixirWeb.ImportsSecurityMappingBoundTest do
  # User story (security review 2026-10-12, H45; Sprint 21 γ7, Q1 B): As the
  # operator who drops a Portfolio Performance export naming many
  # securities the catalog does not hold, into an instance whose catalog is
  # large, I want the preview's security mapping to stay small whatever the
  # catalog holds, so that the Imports page renders, and renders again on
  # every return to it, instead of sending the whole catalog once per row.
  #
  # Class: resource exhaustion. Fix: no row carries the catalog; "create" is
  # the row's line, and the remap control opens only when the operator asks,
  # a search loaded on demand (board ux-design-2026-10-27/02-imports-mapping,
  # Q1 B).
  #
  # Acceptance criteria:
  # - A file at the parser's security cap previews against a catalog of a
  #   hundred securities with at most two options per row plus the catalog
  #   once, and its page stays under the bound the file-side cap's own test
  #   keeps for a preview at the cap.
  # - Every later visit renders the parked preview again against the
  #   current catalog within the same bounds, the catalog grown to three
  #   hundred.
  #
  # Synthetic names only; no network.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.PreviewStore
  alias Portfolixir.Portfolios

  @session_token "H45H45H45H45H45H45H45H45"
  @csv_header "Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle"

  # The bound the file-side cap's test keeps for a preview at the cap
  # (`imports_file_errors_test.exs`, "at the cap it renders bounded").
  @preview_bound 2_000_000

  # The mapping the page builds for this file on a fresh instance: the first
  # test checks the upload path parks a mapping, and the second parks this
  # one without the upload.
  @parked_mapping %{
    bucket_tag: "",
    bucket_skip: false,
    cash: %{"Test-Cash" => "create:Test-Cash"},
    depot: %{"Test-Depot" => %{"target" => "create:Test-Depot", "cash" => "pp:Test-Cash"}},
    security: %{},
    remember: %{"cash" => %{}, "depot" => %{}},
    prefill: %{
      "cash" => %{"Test-Cash" => "create:Test-Cash"},
      "depot" => %{"Test-Depot" => "create:Test-Depot"}
    }
  }

  setup %{conn: conn} do
    {:ok, _portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "PP Import Target",
        base_currency_code: "EUR"
      })

    on_exit(fn -> PreviewStore.delete(PreviewStore.key_for(@session_token)) end)
    %{conn: init_test_session(conn, %{"_csrf_token" => @session_token})}
  end

  defp add_catalog!(from, to) do
    for i <- from..to//1 do
      {:ok, _} =
        Catalog.create_security(Actor.owner_ui(), %{
          name: "Catalog Security #{i}",
          currency_code: "EUR",
          asset_class: "equity"
        })
    end

    :ok
  end

  defp file_row(i),
    do: "2024-01-15 10:01:00;Kauf;File Security #{i};1;1,00;1,00;;;1,00;Test-Depot;Test-Cash;;"

  # A file at the parser's security cap: the parser accepts it, one more
  # security is refused.
  defp at_cap_csv! do
    %{securities: cap} = PortfolioPerformance.max_names()
    rows = for i <- 1..cap, do: file_row(i)
    csv = Enum.join([@csv_header | rows], "\n")

    assert {:ok, preview} = PortfolioPerformance.parse(csv, filename: "at-cap.csv")

    assert {:error, :too_many_names} =
             PortfolioPerformance.parse(
               Enum.join([@csv_header | rows ++ [file_row(cap + 1)]], "\n"),
               filename: "over-cap.csv"
             )

    {csv, preview, cap}
  end

  defp count(html, pattern), do: html |> :binary.matches(pattern) |> length()

  defp parked, do: PreviewStore.get(PreviewStore.key_for(@session_token))

  # Harness only, not the application: a sync test shares one sandbox
  # connection between every process, and the page's connected-only dry
  # run holds it while the page's own queries queue; the sandbox proxy drops
  # a waiter after its short default. Production runs a pool. The test's own
  # sandbox proxy waits longer, so the page's queries wait instead of
  # crashing.
  defp widen_sandbox_queue!(owner) do
    %{pid: manager} = Ecto.Adapter.lookup_meta(Portfolixir.Repo)
    %{checkouts: checkouts} = :sys.get_state(manager)
    {:owner, _ref, proxy} = Map.fetch!(checkouts, owner)
    :sys.replace_state(proxy, &%{&1 | timeout: 600_000})
    :ok
  end

  # One visit to /imports while a preview is parked: the dead render the
  # HTTP request does.
  defp dead_render(conn) do
    conn |> get("/imports") |> html_response(200)
  end

  @tag timeout: 300_000
  test "a file at the cap previews without a catalog list per row",
       %{conn: conn, sandbox_owner: owner} do
    widen_sandbox_queue!(owner)
    {csv, _preview, cap} = at_cap_csv!()
    add_catalog!(1, 100)

    {:ok, view, _html} = live(conn, "/imports")

    view
    |> file_input("#pp-import-form", :pp_file, [
      %{name: "at-cap.csv", content: csv, type: "text/csv", last_modified: 1_700_000_000_000}
    ])
    |> render_upload("at-cap.csv")

    render_async(view, 120_000)

    html = render(view)
    assert html =~ "Preview"

    doc = Floki.parse_document!(html)
    # Every option of the securities step, whatever control renders it.
    security_options = Floki.find(doc, "#import-security-mapping option")
    {_preview, mapping} = parked() || {nil, nil}

    # Every file security has its row, and the page parked the preview after
    # its first render, so later visits render it again (the next test).
    assert html =~ "File Security #{cap}"
    assert mapping != nil

    # One row per file security may carry a create/decide pair; the catalog
    # is offered once, not once per row.
    assert length(security_options) <= cap * 2 + 100,
           "security options grow with rows x catalog: #{length(security_options)} options " <>
             "for #{cap} rows against a 100-security catalog"

    # Q1 B: no row carries a catalog list at all.
    assert security_options == []
    assert Floki.find(doc, "#import-security-mapping select") == []

    assert byte_size(html) < @preview_bound
  end

  @tag timeout: 300_000
  test "every later visit renders the parked preview within the same bounds",
       %{conn: conn, sandbox_owner: owner} do
    widen_sandbox_queue!(owner)
    {_csv, preview, cap} = at_cap_csv!()
    :ok = PreviewStore.put(PreviewStore.key_for(@session_token), preview, @parked_mapping)

    add_catalog!(1, 100)
    dead_100 = dead_render(conn)

    add_catalog!(101, 300)
    dead_300 = dead_render(conn)

    # The visit leaves it parked.
    assert parked() != nil

    assert count(dead_300, "<option") <= cap * 2 + 300 + 10,
           "options grow with rows x catalog: #{count(dead_300, "<option")} options " <>
             "for #{cap} rows against a 300-security catalog"

    assert byte_size(dead_100) < @preview_bound
    assert byte_size(dead_300) < @preview_bound

    # The connected page renders the parked preview: every row, no catalog.
    {:ok, view, _html} = live(conn, "/imports")
    render_async(view, 120_000)
    html = render(view)

    assert html =~ "File Security #{cap}"
    assert count(html, "<option") <= 10
    assert byte_size(html) < @preview_bound
  end
end
