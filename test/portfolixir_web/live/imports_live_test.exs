defmodule PortfolixirWeb.ImportsLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Imports.PreviewStore
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

  # User story:
  # As a local portfolio maintainer confirming a bulk import,
  # I want the confirm button to show a busy state immediately on click
  # and become disabled, so that I get instant feedback that the import
  # is running and cannot accidentally submit twice.
  #
  # Acceptance criteria:
  # - The confirm button carries phx-disable-with="Importing…".
  # - After submit, the button is disabled and the view shows "Importing…".
  # - After the async apply completes, the view renders the :done stage.
  # - A second submit while applying is a no-op (double-submit guard).
  test "confirm button has phx-disable-with and shows busy state while applying, then done",
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

    # Complete the mapping via phx-change so the confirm button becomes enabled.
    # The auto-detected initial mapping leaves Test-Depot-2 without a linked cash
    # account (no account field on SECURITY_TRANSFER rows), so we must supply the
    # full mapping before checking the enabled/disabled state.
    view |> element("form#pp-import-apply") |> render_change(submit_params)

    # Before submit: confirm button is enabled and carries phx-disable-with.
    assert has_element?(
             view,
             "#pp-import-confirm[phx-disable-with='Importing…']"
           )

    refute has_element?(view, "#pp-import-confirm[disabled]")

    # Trigger submit; the handler sets :applying and starts the async task.
    # render_submit returns the intermediate (applying) HTML before the task finishes.
    applying_html = view |> element("form#pp-import-apply") |> render_submit(submit_params)

    # The returned HTML reflects the applying state: button text changes and disabled is set.
    # We assert on applying_html (not `view`) because the async task may complete before
    # has_element? queries live state, making the button no longer disabled.
    assert applying_html =~ "Importing…"
    assert applying_html =~ ~r/id="pp-import-confirm"[^>]*disabled/

    # Wait for the async :apply_import task to complete and handle_async to fire.
    done_html = render_async(view)

    assert done_html =~ "Import complete"
    assert done_html =~ "Created transactions: 13"
    assert done_html =~ "Skipped duplicates: 0"
  end

  # User story (#475):
  # As a maintainer mapping a PP import, I want to know exactly which mapping is
  # still missing while Confirm is disabled, so I do not have to hunt for the
  # empty dropdown behind a dead button.
  #
  # Acceptance criteria:
  # - While the mapping is incomplete, a status hint next to Confirm names the
  #   still-missing item(s) and Confirm is disabled.
  # - Completing the mapping clears the hint and enables Confirm.
  test "names the still-missing mapping next to a disabled Confirm (#475)", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports")
    upload_sample(view)

    # The auto-detected mapping leaves Test-Depot-2 without a linked cash
    # account, so Confirm is disabled and the hint must name what blocks it.
    assert has_element?(view, "#pp-import-confirm[disabled]")
    hint = view |> element("#import-missing-hint") |> render()
    assert hint =~ "Test-Depot-2"

    # The Confirm button is associated with the hint for assistive tech.
    assert has_element?(view, "#pp-import-confirm[aria-describedby='import-missing-hint']")

    # Completing the mapping clears the hint and enables Confirm.
    view
    |> element("form#pp-import-apply")
    |> render_change(%{
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
    })

    refute has_element?(view, "#pp-import-confirm[disabled]")
    refute has_element?(view, "#import-missing-hint")
  end

  # User story:
  # As a maintainer importing a PP export that contains a degenerate zero-amount
  # record (e.g. a 0 EUR tax line), I want the import to finish and tell me which
  # records it skipped (#482), so one bad row does not silently abort the batch.
  test "surfaces zero-amount records skipped during apply (#482)", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports")

    upload_payload(
      view,
      "zero_amount_tax.json",
      File.read!(Path.join(@fixtures, "zero_amount_tax.json")),
      "application/json"
    )

    submit_params = %{
      "portfolio_choice" => "create",
      "portfolio_name" => "Zero Test",
      "portfolio_currency" => "EUR",
      "cash" => %{"Cash" => "create:Cash"},
      "depot" => %{"Depot" => %{"target" => "create:Depot", "cash" => "pp:Cash"}}
    }

    view |> element("form#pp-import-apply") |> render_change(submit_params)
    view |> element("form#pp-import-apply") |> render_submit(submit_params)
    done_html = render_async(view)

    assert done_html =~ "Import complete"
    # deposit + buy + cashless delivery imported; the 0 EUR tax skipped.
    assert done_html =~ "Created transactions: 3"
    assert done_html =~ "unimportable"
    assert done_html =~ "for tax"
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

    view |> element("form#pp-import-apply") |> render_submit(submit_params)
    html = render_async(view)

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

    view |> element("form#pp-import-apply") |> render_submit(submit_params)
    html = render_async(view)

    assert html =~ "Import complete"
    assert length(Ledger.list_transactions_for_portfolio(portfolio.id)) == 13
  end

  # User story:
  # As a local portfolio maintainer mid-way through mapping an import,
  # I want to switch the UI language without losing my uploaded preview or mapping,
  # so that I can continue on the confirmation step in my preferred language
  # without re-uploading the file.
  #
  # Acceptance criteria:
  # - After upload and preview, switching locale (simulated as a remount with a
  #   different locale in the session) keeps the stage at :preview.
  # - The parsed preview data (entry count, format) is still present.
  # - The user-defined mapping is preserved on remount.
  test "switching locale after upload preserves preview and mapping across remount",
       %{conn: conn} do
    _portfolio = setup_portfolio()

    # Locale switches happen inside the same browser session.  We give the
    # session a fixed CSRF token so both LiveView mounts share the same
    # PreviewStore key, mirroring what happens in production where the
    # browser cookie holds the session across a remount.
    #
    # The token must be exactly 24 chars of base64url (18 raw bytes) so that
    # Plug.CSRFProtection.dump_state_from_session/1 considers it valid and
    # leaves it intact.  An invalid-length token causes CSRF protection to
    # generate a fresh random token in its before_send hook, overwriting the
    # seeded value and breaking the key we expect to read from PreviewStore.
    session_token = "AAAAAAAAAAAAAAAAAAAAAAAA"
    conn = init_test_session(conn, %{"_csrf_token" => session_token})

    # First mount — upload and advance to preview.
    {:ok, view, _html} = live(conn, "/imports")
    upload_sample(view)

    html = render(view)
    assert html =~ "Preview"
    assert html =~ "Buy"

    # Change the mapping so we can verify it is preserved after remount.
    view
    |> element("form#pp-import-apply")
    |> render_change(%{
      "portfolio_choice" => "create",
      "portfolio_name" => "My Preserved Portfolio",
      "portfolio_currency" => "EUR",
      "cash" => %{"Test-Cash" => "create:Test-Cash", "Test-Cash-2" => "create:Test-Cash-2"},
      "depot" => %{
        "Test-Depot" => %{"target" => "create:Test-Depot", "cash" => "pp:Test-Cash"},
        "Test-Depot-2" => %{"target" => "create:Test-Depot-2", "cash" => "pp:Test-Cash"}
      }
    })

    # Verify PreviewStore holds the entry under our session token.
    assert {_preview, mapping} = PreviewStore.get(session_token)
    assert mapping.portfolio_name == "My Preserved Portfolio"

    # Simulate locale switch: remount the LiveView on the same session.
    # In production the live_session :browser re-runs LiveLocale.on_mount which
    # calls mount/3 fresh.  Here we re-call live/2 with the same session conn.
    {:ok, view2, html2} = live(conn, "/imports")

    # The user should land back on the preview step, not the empty upload form.
    assert html2 =~ "Preview"
    assert html2 =~ "Buy"

    # The mapping portfolio name should still be present.
    assert render(view2) =~ "My Preserved Portfolio"

    # Cleanup: verify the store entry is deleted after a successful import.
    view2
    |> element("form#pp-import-apply")
    |> render_submit(%{
      "portfolio_choice" => "create",
      "portfolio_name" => "My Preserved Portfolio",
      "portfolio_currency" => "EUR",
      "cash" => %{
        "Test-Cash" => "create:Test-Cash",
        "Test-Cash-2" => "create:Test-Cash-2"
      },
      "depot" => %{
        "Test-Depot" => %{"target" => "create:Test-Depot", "cash" => "pp:Test-Cash"},
        "Test-Depot-2" => %{"target" => "create:Test-Depot-2", "cash" => "pp:Test-Cash"}
      }
    })

    html3 = render_async(view2)

    assert html3 =~ "Import complete"
    assert PreviewStore.get(session_token) == nil
  end

  # User story:
  # As a local portfolio maintainer who accidentally uploads a file
  # from an incompatible Portfolio Performance version,
  # I want the imports page to surface a readable error message,
  # so that I understand why the upload was rejected without seeing
  # an opaque internal error.
  #
  # Acceptance criteria:
  # - Uploading a JSON file with an unsupported version shows an error alert.
  # - The view stays on the idle stage (no preview is rendered).
  test "uploading an unsupported PP version shows a parse error and stays idle",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports")

    upload_payload(
      view,
      "invalid_version.json",
      File.read!(Path.join(@fixtures, "invalid_version.json")),
      "application/json"
    )

    html = render(view)
    assert html =~ "Unsupported PP JSON version"
    assert has_element?(view, "p.alert-error")
    refute html =~ "Preview"
  end

  # User story:
  # As a local portfolio maintainer whose import fails due to a
  # currency mismatch between the imported transactions and an existing
  # cash account, I want the imports page to surface a readable error
  # message and re-enable the confirm button so that I can correct the
  # mapping and retry, without losing my progress.
  #
  # Acceptance criteria:
  # - After async apply returns {:error, reason}, the page stays on the
  #   :preview stage (not :done).
  # - An error alert is rendered with the per-row validation message.
  # - The confirm button is re-enabled (applying resets to false).
  test "async import error surfaces message and re-enables confirm button",
       %{conn: conn} do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Error Test Portfolio", base_currency_code: "EUR"})

    # Create a USD cash account with the same PP name as in sample.json.
    # The sample's first transaction is a EUR buy through "Test-Cash", so
    # mapping it to this USD account triggers the settlement_fx_rate
    # validation failure — the applier returns {:error, reason} for the
    # row and Imports.apply/2 returns {:ok, {:error, reason}}.
    {:ok, usd_cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Test-Cash",
        currency_code: "USD"
      })

    {:ok, usd_depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: usd_cash.id,
        name: "Test-Depot"
      })

    {:ok, view, _html} = live(conn, "/imports")
    upload_sample(view)

    submit_params = %{
      "portfolio_choice" => "existing:#{portfolio.id}",
      "cash" => %{
        "Test-Cash" => "existing:#{usd_cash.id}",
        "Test-Cash-2" => "create:Test-Cash-2"
      },
      "depot" => %{
        "Test-Depot" => %{
          "target" => "existing:#{usd_depot.id}",
          "cash" => "existing:#{usd_cash.id}"
        },
        "Test-Depot-2" => %{
          "target" => "create:Test-Depot-2",
          "cash" => "pp:Test-Cash-2"
        }
      }
    }

    view |> element("form#pp-import-apply") |> render_submit(submit_params)
    html = render_async(view)

    # The import must not have succeeded — we stay on preview, not done.
    refute html =~ "Import complete"
    refute html =~ "Created transactions"

    # An error alert must be visible with the changeset message.
    assert has_element?(view, "p.alert-error")
    assert html =~ "Row"
    assert html =~ "settlement_fx_rate"

    # The confirm button must be re-enabled (applying reset to false).
    refute has_element?(view, "#pp-import-confirm[disabled]")
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
