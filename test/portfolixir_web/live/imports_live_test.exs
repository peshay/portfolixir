defmodule PortfolixirWeb.ImportsLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @fixtures Path.expand("../../support/fixtures/portfolio_performance", __DIR__)

  defp sample_json_path, do: Path.join(@fixtures, "sample.json")

  defp upload_sample(view) do
    file_input(view, "#pp-import-form", :pp_file, [
      %{
        name: "sample.json",
        content: File.read!(sample_json_path()),
        type: "application/json",
        last_modified: 1_700_000_000_000
      }
    ])
    |> render_upload("sample.json")
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
    assert html =~ "buy"
    assert html =~ "dividend"
    assert has_element?(view, "form#pp-import-apply select[name='portfolio_choice']")
    assert has_element?(view, "form#pp-import-apply select[name=\"cash[Test-Cash]\"]")
    assert has_element?(view, "form#pp-import-apply select[name=\"depot[Test-Depot][target]\"]")
    assert has_element?(view, "form#pp-import-apply select[name=\"depot[Test-Depot][cash]\"]")
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
end
