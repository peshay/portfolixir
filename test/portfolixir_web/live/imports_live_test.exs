defmodule PortfolixirWeb.ImportsLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @fixtures Path.expand("../../support/fixtures/portfolio_performance", __DIR__)

  defp sample_json_path, do: Path.join(@fixtures, "sample.json")

  defp upload_payload(view, name, content, type) do
    file_input(view, "#pp-import-form", :pp_file, [
      %{
        name: name,
        content: content,
        type: type,
        last_modified: 1_700_000_000_000
      }
    ])
    |> render_upload(name)
  end

  defp upload_sample(view) do
    upload_payload(view, "sample.json", File.read!(sample_json_path()), "application/json")
  end

  # User story:
  # As a local portfolio maintainer,
  # I want to drag my Portfolio Performance export onto the new
  # /imports page, review and re-map any depots/cash accounts that
  # don't yet exist in Portfolixir, and confirm the import,
  # so that bulk-loading my historical bookkeeping is a single
  # workflow without writing SQL by hand.

  test "renders the dropzone in the idle state", %{conn: conn} do
    {:ok, view, html} = live(conn, "/imports")

    assert html =~ "Imports"
    assert has_element?(view, "form#pp-import-form.import-drop-zone")
    assert has_element?(view, "[phx-hook='PPImportDrop']")
    assert has_element?(view, "input[type='file']")
    assert has_element?(view, "[data-import-file-button]")
  end

  test "auto-upload advances to preview with mapping form", %{conn: conn} do
    _portfolio = setup_portfolio()
    {:ok, view, _html} = live(conn, "/imports")

    upload_sample(view)
    html = render(view)

    assert html =~ "Preview"
    assert html =~ "Buy"
    assert html =~ "Dividend"
    assert has_element?(view, "form#pp-import-apply select[name='portfolio_choice']")
    assert has_element?(view, "form#pp-import-apply select[name=\"cash[Test-Cash]\"]")
    assert has_element?(view, "form#pp-import-apply select[name=\"depot[Test-Depot][target]\"]")
    assert has_element?(view, "form#pp-import-apply select[name=\"depot[Test-Depot][cash]\"]")
  end

  # User story:
  # As a German local portfolio maintainer,
  # I want the import preview to show Portfolio Performance transaction labels,
  # so that the preview reads like the source export instead of raw database keys.
  #
  # Acceptance criteria:
  # - All kind chips render translated labels.
  # - German labels use PP-like names for the 13 supported kinds.
  # - Raw kind keys are not visible in chip text.
  test "german preview renders translated transaction kind labels", %{conn: conn} do
    conn = put_req_header(conn, "accept-language", "de-DE,de;q=0.9,en;q=0.8")

    {:ok, view, _html} = live(conn, "/imports")
    upload_sample(view)

    chips = element(view, ".kind-chips") |> render()

    for label <- [
          "Kauf",
          "Verkauf",
          "Dividende",
          "Zinsen",
          "Einlage",
          "Entnahme",
          "Gebühren",
          "Steuern",
          "Steuererstattung",
          "Umbuchung",
          "Einlieferung",
          "Auslieferung",
          "Wertpapierumbuchung"
        ] do
      assert chips =~ label
    end

    for raw <- [
          "buy",
          "sell",
          "tax_refund",
          "cash_transfer",
          "inbound_delivery",
          "outbound_delivery",
          "security_transfer"
        ] do
      refute chips =~ ~s|<span class="name">#{raw}</span>|
    end
  end

  # User story:
  # As a local portfolio maintainer reviewing an imperfect import,
  # I want parser warnings in a scrollable copyable box,
  # so that I can keep deterministic row-level diagnostics with my source file.
  #
  # Acceptance criteria:
  # - Parser warnings render in an accent-background info box.
  # - A copy button pushes the existing copy-to-clipboard event.
  # - Copied text uses stable `Row N: message` lines.
  test "parser warnings render in a copyable info box", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports")

    upload_payload(
      view,
      "unknown_kind.json",
      File.read!(Path.join(@fixtures, "unknown_kind.json")),
      "application/json"
    )

    assert has_element?(view, "#parser-warnings-box.import-warning-box")
    assert has_element?(view, "#copy-parser-warnings")
    assert has_element?(view, "#parser-warnings-box", "Row 1")
    assert has_element?(view, "#parser-warnings-box", "MYSTERY_KIND")

    view |> element("#copy-parser-warnings") |> render_click()

    assert_push_event(view, "copy-to-clipboard", %{
      text: ~s|Row 1: unknown PP transaction type "MYSTERY_KIND"|
    })
  end

  # User story:
  # As a local portfolio maintainer using accent colors,
  # I want import kind chips to use the selected accent tokens,
  # so that the preview stays consistent with the app theme.
  #
  # Acceptance criteria:
  # - Kind chips use `--color-accent` and `--color-accent-soft`.
  # - The old per-kind hard-coded palette selectors are gone.
  test "kind chips use accent tokens instead of per-family palette rules" do
    app_css = File.read!("priv/static/app.css")
    chip_rule = css_rule(app_css, ".kind-chip")

    assert chip_rule =~ "background: var(--color-accent-soft);"
    assert chip_rule =~ "color: var(--color-accent);"
    refute app_css =~ ".kind-chip[data-family="
  end

  test "confirming with create-new portfolio + auto-mapped accounts creates ledger rows",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports")
    upload_sample(view)

    submit_params = %{
      "portfolio_choice" => "create",
      "portfolio_name" => "PP Import Target",
      "portfolio_currency" => "EUR",
      "cash" => %{
        "Test-Cash" => "create:Test-Cash",
        "Test-Cash-2" => "create:Test-Cash-2"
      },
      "depot" => %{
        "Test-Depot" => %{"target" => "create:Test-Depot", "cash" => "pp:Test-Cash"},
        "Test-Depot-2" => %{"target" => "create:Test-Depot-2", "cash" => "pp:Test-Cash"}
      }
    }

    html = view |> element("form#pp-import-apply") |> render_submit(submit_params)

    assert html =~ "Import complete"
    assert html =~ "Created transactions: 13"
    assert html =~ "Skipped duplicates: 0"

    portfolio = Portfolios.list_portfolios() |> Enum.find(&(&1.name == "PP Import Target"))
    assert portfolio

    assert length(Ledger.list_transactions_for_portfolio(portfolio.id)) == 13
  end

  test "confirming with an existing portfolio reuses it",
       %{conn: conn} do
    portfolio = setup_portfolio()
    {:ok, view, _html} = live(conn, "/imports")
    upload_sample(view)

    submit_params = %{
      "portfolio_choice" => "existing:#{portfolio.id}",
      "cash" => %{
        "Test-Cash" => "create:Test-Cash",
        "Test-Cash-2" => "create:Test-Cash-2"
      },
      "depot" => %{
        "Test-Depot" => %{"target" => "create:Test-Depot", "cash" => "pp:Test-Cash"},
        "Test-Depot-2" => %{"target" => "create:Test-Depot-2", "cash" => "pp:Test-Cash"}
      }
    }

    html = view |> element("form#pp-import-apply") |> render_submit(submit_params)

    assert html =~ "Import complete"
    assert length(Ledger.list_transactions_for_portfolio(portfolio.id)) == 13
  end

  defp setup_portfolio do
    {:ok, p} =
      Portfolios.create_portfolio(%{name: "PP Import Target", base_currency_code: "EUR"})

    p
  end

  defp css_rule(css, selector) do
    escaped_selector = Regex.escape(selector)
    [_, rule] = Regex.run(~r/#{escaped_selector}\s*\{([^}]*)\}/, css)
    rule
  end
end
