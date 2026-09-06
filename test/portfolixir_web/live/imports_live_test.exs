defmodule PortfolixirWeb.ImportsLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Buckets
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
    assert has_element?(view, "form#pp-import-apply input[name='bucket_tag']")
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
    done_html = render_async(view, 1_000)

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
      "cash" => %{"Cash" => "create:Cash"},
      "depot" => %{"Depot" => %{"target" => "create:Depot", "cash" => "pp:Cash"}}
    }

    view |> element("form#pp-import-apply") |> render_change(submit_params)
    view |> element("form#pp-import-apply") |> render_submit(submit_params)
    done_html = render_async(view, 1_000)

    assert done_html =~ "Import complete"
    # deposit + buy + cashless delivery imported; the 0 EUR tax skipped.
    assert done_html =~ "Created transactions: 3"
    assert done_html =~ "unimportable"
    assert done_html =~ "for tax"
  end

  # User story (ADR-0024, epic story 5):
  # As a local portfolio maintainer importing a Portfolio Performance export,
  # I want the preview to offer an editable bucket tag for the accounts it
  # will create — instead of asking me to pick or name a portfolio —
  # so that a fresh import lands already grouped, with nothing to rename
  # afterwards.
  #
  # Acceptance criteria:
  # - The Target-portfolio picker disappears; the portfolio binding happens
  #   internally via Portfolios.default_portfolio/1 (import actor).
  # - The preview shows an editable bucket-tag field, pre-filled with a
  #   date-stamped default, plus a "no tag" skip option.
  # - On apply the NEWLY created depots/cash accounts get the (tag-dimension)
  #   bucket; existing-mapped accounts keep their tags untouched.
  # - A bucket with the entered name is reused, not duplicated.
  # - Re-applying the same file stays a no-op and does not duplicate bucket
  #   assignments; blank tag behaves like skip; no new accounts → no bucket.
  test "preview shows an editable date-stamped bucket tag instead of a portfolio picker",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports")
    upload_sample(view)
    html = render(view)

    # The Target-portfolio picker is gone.
    refute has_element?(view, "select[name='portfolio_choice']")
    refute html =~ "Target portfolio"
    refute html =~ "Create new portfolio"

    # The editable bucket tag is pre-filled with a date-stamped default and
    # offers a skip option.
    default_tag = "PP Import #{Date.utc_today() |> Date.to_iso8601()}"
    assert has_element?(view, "input[name='bucket_tag'][value='#{default_tag}']")
    assert has_element?(view, "input[type='checkbox'][name='bucket_skip']")
    assert html =~ "bucket tag"
  end

  test "confirming binds internally to the default portfolio and tags the new accounts",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports")
    upload_sample(view)

    submit_params = %{
      "bucket_tag" => "PP Import 2026-07-12",
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
    html = render_async(view, 1_000)

    assert html =~ "Import complete"
    assert html =~ "Created transactions: 13"
    assert html =~ "Skipped duplicates: 0"

    # The internal default portfolio was created under the import actor —
    # the admin list shows it with source Import; the user never named it.
    assert [%{name: "Default", source: :import}] =
             Portfolios.portfolio_admin_list() |> Enum.map(&Map.take(&1, [:name, :source]))

    [portfolio] = Portfolios.list_portfolios()
    assert length(Ledger.list_transactions_for_portfolio(portfolio.id)) == 13

    # Every newly created account carries the tag-dimension bucket.
    [bucket] = Buckets.list_buckets()
    assert bucket.name == "PP Import 2026-07-12"
    assert bucket.dimension == "tag"

    for depot <- Portfolios.list_securities_accounts() do
      assert Buckets.depot_default_bucket_ids(depot.id) == [bucket.id]
    end

    for cash <- Portfolios.list_cash_accounts() do
      assert Buckets.cash_account_bucket_ids(cash.id) == [bucket.id]
    end
  end

  # User story (fix round, tag pre-validation):
  # As a local portfolio maintainer importing a PP export,
  # I want a bucket tag that names an existing scope bucket — or exceeds the
  # 100-character bucket limit — rejected BEFORE the apply starts,
  # so that a bad tag never aborts a whole import at the very end with an
  # opaque dump.
  #
  # Acceptance criteria:
  # - A tag equal to a scope bucket's name shows a clear error and applies
  #   nothing (no transactions, page stays on preview).
  # - A 101-character tag is rejected the same way (the input also carries
  #   maxlength="100" as the first line of defence).
  test "a tag naming a scope bucket is rejected before apply", %{conn: conn} do
    {:ok, _scope} =
      Buckets.create_bucket(Portfolixir.Actor.owner_ui(), %{
        name: "Haushalt",
        dimension: "scope"
      })

    {:ok, view, _html} = live(conn, "/imports")
    upload_sample(view)

    submit_params = %{
      "bucket_tag" => "Haushalt",
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

    refute html =~ "Import complete"
    assert has_element?(view, "p.alert-error")
    assert html =~ "scope bucket"
    refute html =~ "%Ecto."

    # Nothing was applied: no transactions, no accounts, no extra bucket.
    assert Ledger.list_transactions() == []
    assert Portfolios.list_securities_accounts() == []
    assert [%{dimension: "scope"}] = Buckets.list_buckets()
  end

  test "a 101-character tag is rejected before apply", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports")
    upload_sample(view)

    # The rendered input carries the maxlength guard.
    assert has_element?(view, "input[name='bucket_tag'][maxlength='100']")

    submit_params = %{
      "bucket_tag" => String.duplicate("x", 101),
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

    refute html =~ "Import complete"
    assert has_element?(view, "p.alert-error")
    assert html =~ "at most 100 characters"

    assert Ledger.list_transactions() == []
    assert Buckets.list_buckets() == []
  end

  test "re-applying the same file is a no-op and does not duplicate bucket assignments",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports")
    upload_sample(view)

    submit_params = %{
      "bucket_tag" => "PP Import",
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
    assert render_async(view, 1_000) =~ "Import complete"

    [bucket] = Buckets.list_buckets()

    # Second run of the same file: everything maps to the now-existing
    # accounts, so nothing new is created and nothing re-tagged.
    cash = Portfolios.list_cash_accounts() |> Map.new(&{&1.name, &1.id})
    depots = Portfolios.list_securities_accounts() |> Map.new(&{&1.name, &1.id})

    second_params = %{
      "bucket_tag" => "PP Import",
      "cash" => %{
        "Test-Cash" => "existing:#{cash["Test-Cash"]}",
        "Test-Cash-2" => "existing:#{cash["Test-Cash-2"]}"
      },
      "depot" => %{
        "Test-Depot" => %{
          "target" => "existing:#{depots["Test-Depot"]}",
          "cash" => "existing:#{cash["Test-Cash"]}"
        },
        "Test-Depot-2" => %{
          "target" => "existing:#{depots["Test-Depot-2"]}",
          "cash" => "existing:#{cash["Test-Cash"]}"
        }
      }
    }

    view |> element("button", "Import another file") |> render_click()
    upload_sample(view)
    view |> element("form#pp-import-apply") |> render_submit(second_params)
    html = render_async(view, 1_000)

    assert html =~ "Import complete"
    assert html =~ "Created transactions: 0"
    assert html =~ "Skipped duplicates: 13"

    assert [%{id: bucket_id}] = Buckets.list_buckets()
    assert bucket_id == bucket.id

    for depot <- Portfolios.list_securities_accounts() do
      assert Buckets.depot_default_bucket_ids(depot.id) == [bucket.id]
    end

    for cash <- Portfolios.list_cash_accounts() do
      assert Buckets.cash_account_bucket_ids(cash.id) == [bucket.id]
    end
  end

  test "accounts mapped to existing records keep their tags; existing bucket names are reused",
       %{conn: conn} do
    portfolio = setup_portfolio()

    {:ok, existing_cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Test-Cash",
        currency_code: "EUR"
      })

    {:ok, existing_depot} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: existing_cash.id,
        name: "Test-Depot"
      })

    {:ok, mine} = Buckets.create_bucket(Portfolixir.Actor.owner_ui(), %{name: "Mine"})

    :ok =
      Buckets.set_depot_default_buckets(Portfolixir.Actor.owner_ui(), existing_depot, [mine.id])

    # The entered tag collides with an existing bucket — it must be reused.
    {:ok, reused} = Buckets.create_bucket(Portfolixir.Actor.owner_ui(), %{name: "Familie"})

    {:ok, view, _html} = live(conn, "/imports")
    upload_sample(view)

    submit_params = %{
      "bucket_tag" => "Familie",
      "cash" => %{
        "Test-Cash" => "existing:#{existing_cash.id}",
        "Test-Cash-2" => "create:Test-Cash-2"
      },
      "depot" => %{
        "Test-Depot" => %{
          "target" => "existing:#{existing_depot.id}",
          "cash" => "existing:#{existing_cash.id}"
        },
        "Test-Depot-2" => %{"target" => "create:Test-Depot-2", "cash" => "pp:Test-Cash-2"}
      }
    }

    view |> element("form#pp-import-apply") |> render_submit(submit_params)
    assert render_async(view, 1_000) =~ "Import complete"

    # No third bucket appeared; the entered name reused "Familie".
    assert Buckets.list_buckets() |> Enum.map(& &1.name) |> Enum.sort() == ["Familie", "Mine"]

    # The existing depot keeps exactly its own tag; only the new depot got tagged.
    assert Buckets.depot_default_bucket_ids(existing_depot.id) == [mine.id]
    assert Buckets.cash_account_bucket_ids(existing_cash.id) == []

    new_depot =
      Portfolios.list_securities_accounts() |> Enum.find(&(&1.name == "Test-Depot-2"))

    assert Buckets.depot_default_bucket_ids(new_depot.id) == [reused.id]
  end

  test "a blank tag and the skip option create no bucket", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports")
    upload_sample(view)

    submit_params = %{
      "bucket_tag" => "Never Created",
      "bucket_skip" => "true",
      "cash" => %{
        "Test-Cash" => "create:Test-Cash",
        "Test-Cash-2" => "create:Test-Cash-2"
      },
      "depot" => %{
        "Test-Depot" => %{"target" => "create:Test-Depot", "cash" => "pp:Test-Cash"},
        "Test-Depot-2" => %{"target" => "create:Test-Depot-2", "cash" => "pp:Test-Cash"}
      }
    }

    # Skip wins over the entered name.
    view |> element("form#pp-import-apply") |> render_submit(submit_params)
    assert render_async(view, 1_000) =~ "Import complete"
    assert Buckets.list_buckets() == []

    for depot <- Portfolios.list_securities_accounts() do
      assert Buckets.depot_default_bucket_ids(depot.id) == []
    end
  end

  test "a blank tag field behaves like skip", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports")
    upload_sample(view)

    submit_params = %{
      "bucket_tag" => "   ",
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
    assert render_async(view, 1_000) =~ "Import complete"
    assert Buckets.list_buckets() == []
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
      "bucket_tag" => "My Preserved Tag",
      "cash" => %{"Test-Cash" => "create:Test-Cash", "Test-Cash-2" => "create:Test-Cash-2"},
      "depot" => %{
        "Test-Depot" => %{"target" => "create:Test-Depot", "cash" => "pp:Test-Cash"},
        "Test-Depot-2" => %{"target" => "create:Test-Depot-2", "cash" => "pp:Test-Cash"}
      }
    })

    # Verify PreviewStore holds the entry under our session token.
    # The store is keyed by a hash of the session token (#768), never the token.
    assert {_preview, mapping} = PreviewStore.get(PreviewStore.key_for(session_token))
    assert mapping.bucket_tag == "My Preserved Tag"

    # Simulate locale switch: remount the LiveView on the same session.
    # In production the live_session :browser re-runs LiveLocale.on_mount which
    # calls mount/3 fresh.  Here we re-call live/2 with the same session conn.
    {:ok, view2, html2} = live(conn, "/imports")

    # The user should land back on the preview step, not the empty upload form.
    assert html2 =~ "Preview"
    assert html2 =~ "Buy"

    # The mapping bucket tag should still be present.
    assert render(view2) =~ "My Preserved Tag"

    # Cleanup: verify the store entry is deleted after a successful import.
    view2
    |> element("form#pp-import-apply")
    |> render_submit(%{
      "bucket_tag" => "My Preserved Tag",
      "cash" => %{
        "Test-Cash" => "create:Test-Cash",
        "Test-Cash-2" => "create:Test-Cash-2"
      },
      "depot" => %{
        "Test-Depot" => %{"target" => "create:Test-Depot", "cash" => "pp:Test-Cash"},
        "Test-Depot-2" => %{"target" => "create:Test-Depot-2", "cash" => "pp:Test-Cash"}
      }
    })

    html3 = render_async(view2, 1_000)

    assert html3 =~ "Import complete"
    assert PreviewStore.get(PreviewStore.key_for(session_token)) == nil
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
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Error Test Portfolio",
        base_currency_code: "EUR"
      })

    # Create a USD cash account with the same PP name as in sample.json.
    # The sample's first transaction is a EUR buy through "Test-Cash", so
    # mapping it to this USD account triggers the settlement_fx_rate
    # validation failure — the applier returns {:error, reason} for the
    # row and Imports.apply/2 returns {:ok, {:error, reason}}.
    {:ok, usd_cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Test-Cash",
        currency_code: "USD"
      })

    {:ok, usd_depot} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: usd_cash.id,
        name: "Test-Depot"
      })

    {:ok, view, _html} = live(conn, "/imports")
    upload_sample(view)

    submit_params = %{
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
    html = render_async(view, 1_000)

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

  # User story (ADR-0029 §2 — the security-mapping override step):
  # As a local portfolio maintainer reviewing an import,
  # I want every to-be-created security listed with its ladder result,
  # ambiguity/veto conflicts to REQUIRE a decision before apply,
  # config-at-risk creations to require a per-row acknowledgment,
  # and the pre-apply inverse check to list configured securities the import
  # does not touch,
  # so that a re-import can never silently duplicate a security or strand my
  # strategy configuration.

  describe "security mapping step (ADR-0029 §2)" do
    defp fixture!(name), do: File.read!(Path.join(@fixtures, name))

    defp create_security!(attrs) do
      {:ok, security} =
        Portfolixir.Catalog.create_security(
          Portfolixir.Actor.owner_ui(),
          Map.merge(%{name: "Example AG", currency_code: "EUR"}, attrs)
        )

      security
    end

    defp attach_assignment!(security) do
      {:ok, classification} =
        Portfolixir.Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{
          name: "Strategy #{System.unique_integer([:positive])}"
        })

      {:ok, category} =
        Portfolixir.Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
          classification_id: classification.id,
          name: "Core"
        })

      {:ok, _} =
        Portfolixir.Classifications.assign_security(
          Portfolixir.Actor.owner_ui(),
          security.id,
          classification.id,
          category.id
        )

      :ok
    end

    defp resolution_key!(fixture_name, finder) do
      {:ok, preview} =
        Portfolixir.Imports.parse_portfolio_performance(fixture!(fixture_name),
          filename: fixture_name
        )

      %{resolutions: resolutions} = Portfolixir.Imports.resolve_securities(preview)
      Enum.find(resolutions, finder).key
    end

    test "plain unambiguous creations stay collapsed as a summary", %{conn: conn} do
      _portfolio = setup_portfolio()
      {:ok, view, _html} = live(conn, "/imports")
      upload_sample(view)

      html = render(view)
      assert has_element?(view, "#import-security-mapping")
      assert has_element?(view, "details[data-role='plain-creates']")
      assert html =~ "2 new securities will be created"
      refute has_element?(view, "[data-role='security-decision']")
      # Plain creations demand no attention: the still-to-map hint (driven by
      # sample.json's unmapped counter depot) lists no security rows.
      refute html =~ "security: "
    end

    test "security count summaries are grammatical for a single item (ngettext)", %{conn: conn} do
      _portfolio = setup_portfolio()

      # Singular create: ambiguous_wkn.json references exactly one security and
      # nothing pre-exists to match it.
      {:ok, view, _html} = live(conn, "/imports")

      upload_payload(
        view,
        "ambiguous_wkn.json",
        fixture!("ambiguous_wkn.json"),
        "application/json"
      )

      html = render(view)
      assert html =~ "1 new security will be created"
      refute html =~ "1 new securities will be created"

      # Singular match: pre-create the one referenced security so it matches via
      # the WKN tier and the matched summary renders in the singular.
      create_security!(%{name: "Ambiguous Fund", wkn: "AMB001", currency_code: "EUR"})
      {:ok, view2, _html} = live(conn, "/imports")

      upload_payload(
        view2,
        "ambiguous_wkn.json",
        fixture!("ambiguous_wkn.json"),
        "application/json"
      )

      html2 = render(view2)
      assert html2 =~ "1 security matches existing records"
      refute html2 =~ "1 securities match existing records"
    end

    test "an ambiguous identifier requires a decision before apply", %{conn: conn} do
      _portfolio = setup_portfolio()
      chosen = create_security!(%{name: "Share Class A", wkn: "AMB001"})
      _other = create_security!(%{name: "Share Class B", wkn: "AMB001"})

      {:ok, view, _html} = live(conn, "/imports")

      upload_payload(
        view,
        "ambiguous_wkn.json",
        fixture!("ambiguous_wkn.json"),
        "application/json"
      )

      html = render(view)
      assert has_element?(view, "[data-role='security-decision']")
      assert html =~ "Share Class A"
      assert has_element?(view, "#pp-import-confirm[disabled]")
      assert html =~ "Still to map before import:"
      assert html =~ "security: Ambiguous Fund"

      key = resolution_key!("ambiguous_wkn.json", &(&1.status == :needs_decision))

      view
      |> element("form#pp-import-apply")
      |> render_change(%{"security" => %{key => %{"choice" => "existing:#{chosen.id}"}}})

      refute has_element?(view, "#pp-import-confirm[disabled]")
    end

    test "a config-at-risk creation requires the per-row acknowledgment", %{conn: conn} do
      _portfolio = setup_portfolio()
      at_risk = create_security!(%{name: "Ambiguous Fund", currency_code: "USD"})
      attach_assignment!(at_risk)

      {:ok, view, _html} = live(conn, "/imports")

      upload_payload(
        view,
        "ambiguous_wkn.json",
        fixture!("ambiguous_wkn.json"),
        "application/json"
      )

      html = render(view)
      assert has_element?(view, "[data-role='security-decision']")
      assert html =~ "strategy configuration"
      assert has_element?(view, "#pp-import-confirm[disabled]")

      key = resolution_key!("ambiguous_wkn.json", &(&1.status == :config_at_risk))

      view
      |> element("form#pp-import-apply")
      |> render_change(%{"security" => %{key => %{"choice" => "create", "ack" => "true"}}})

      refute has_element?(view, "#pp-import-confirm[disabled]")
    end

    test "the pre-apply inverse check lists configured securities the import misses",
         %{conn: conn} do
      portfolio = setup_portfolio()
      leftover = create_security!(%{name: "Leftover AG", isin: "DE000LEFT001"})
      attach_assignment!(leftover)

      {:ok, cash} =
        Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          name: "Cash",
          currency_code: "EUR"
        })

      {:ok, depot} =
        Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          cash_account_id: cash.id,
          name: "Depot"
        })

      {:ok, _} =
        Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          type: "buy",
          date: ~D[2024-01-02],
          currency_code: "EUR",
          security_id: leftover.id,
          securities_account_id: depot.id,
          cash_account_id: cash.id,
          quantity: Decimal.new("1"),
          price: Decimal.new("10"),
          gross_amount: Decimal.new("10")
        })

      {:ok, view, _html} = live(conn, "/imports")
      upload_sample(view)

      html = render(view)
      assert has_element?(view, "#import-unmatched-config")
      assert html =~ "Leftover AG"
      assert html =~ "record the ISIN change"
      # The guidance must also reach the ISIN-less case (crypto), where
      # recording an ISIN change is impossible: rename in-app or remap.
      assert html =~ "rename"
      assert html =~ "remap"
    end

    # User story (2026-07-29, issue #607):
    # As a maintainer importing a small file that adds a few bookings,
    # I want the leftover-configuration check to stay quiet and say why,
    # so that the panel does not bury a real rename under every other
    # configured security in the portfolio.
    #
    # Acceptance criteria:
    # - An incremental file renders no leftover panel.
    # - It renders the reason instead of nothing at all.
    test "an incremental file skips the leftover check and says so", %{conn: conn} do
      portfolio = setup_portfolio()

      # Six transacted, configured securities the sample file does not touch:
      # below half coverage AND above the noise floor, so the check is skipped.
      for index <- 1..6 do
        security = create_security!(%{name: "Configured #{index} AG", isin: "DE000CFG00#{index}"})
        attach_assignment!(security)
        transact!(portfolio, security, index)
      end

      {:ok, view, _html} = live(conn, "/imports")
      upload_sample(view)

      html = render(view)

      refute has_element?(view, "#import-unmatched-config")
      assert has_element?(view, "#import-unmatched-config-skipped")
      assert html =~ "incremental import rather than a full re-export"
      # The panel's own heading is what must be absent; the security names
      # still appear in the remap dropdowns, which is unrelated.
      refute html =~ "Configured securities this import does not touch"
    end

    # User story (2026-07-29, issue #609):
    # As a maintainer importing an export in which a security was renamed,
    # I want the matched preview row to say the file calls it something else,
    # so that the rename is visible even though the import never renames my
    # stored master data (ADR-0029 §2).
    #
    # Acceptance criteria:
    # - The matched row notes the file's name and says the stored one is kept.
    # - The stored security is unchanged.
    test "a matched row notes a name that differs in the file", %{conn: conn} do
      _portfolio = setup_portfolio()
      stored = create_security!(%{name: "Renamed Long Ago AG", isin: "US0378331005"})

      {:ok, view, _html} = live(conn, "/imports")
      upload_sample(view)

      html = render(view)

      assert html =~ "file name: Apple Inc.; stored name kept"
      assert Portfolixir.Catalog.get_security(stored.id).name == "Renamed Long Ago AG"
    end

    defp transact!(portfolio, security, index) do
      {:ok, cash} =
        Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          name: "Cash #{index}",
          currency_code: "EUR"
        })

      {:ok, depot} =
        Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          cash_account_id: cash.id,
          name: "Depot #{index}"
        })

      {:ok, _} =
        Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          type: "buy",
          date: ~D[2024-01-02],
          currency_code: "EUR",
          security_id: security.id,
          securities_account_id: depot.id,
          cash_account_id: cash.id,
          quantity: Decimal.new("1"),
          price: Decimal.new("10"),
          gross_amount: Decimal.new("10")
        })
    end

    test "a failed security creation surfaces a friendly per-field message, not a raw tuple",
         %{conn: conn} do
      _portfolio = setup_portfolio()

      # Two securities share WKN AMB001, so the second file row is ambiguous and
      # the user must decide. The first row plain-creates ISIN DE000COLL001; the
      # user then deliberately forces the ambiguous row to ALSO create with the
      # same ISIN, which collides on the now-live unique ISIN index and makes the
      # applier return {:security_create_failed, changeset}.
      _a = create_security!(%{name: "Share Class A", wkn: "AMB001"})
      _b = create_security!(%{name: "Share Class B", wkn: "AMB001"})

      {:ok, view, _html} = live(conn, "/imports")

      upload_payload(
        view,
        "duplicate_isin_create.json",
        fixture!("duplicate_isin_create.json"),
        "application/json"
      )

      decision_key =
        resolution_key!("duplicate_isin_create.json", &(&1.status == :needs_decision))

      mapping = %{
        "cash" => %{"Test-Cash" => "create:Test-Cash"},
        "depot" => %{
          "Test-Depot" => %{"target" => "create:Test-Depot", "cash" => "pp:Test-Cash"}
        },
        "security" => %{decision_key => %{"choice" => "create"}}
      }

      view |> element("form#pp-import-apply") |> render_change(mapping)
      view |> element("form#pp-import-apply") |> render_submit(mapping)

      html = render_async(view, 1_000)

      # The friendly message names the offending field; the raw tuple leaks
      # neither the tag nor an inspected struct.
      assert html =~ "isin"
      refute html =~ "security_create_failed"
      refute html =~ "Ecto.Changeset"
    end

    test "remapping onto an existing security can record the ISIN change end-to-end",
         %{conn: conn} do
      _portfolio = setup_portfolio()
      acme = create_security!(%{name: "Acme AG", isin: "DE000ACME001", wkn: "ACM111"})

      {:ok, view, _html} = live(conn, "/imports")

      upload_payload(
        view,
        "wrong_ordering_new_identity.json",
        fixture!("wrong_ordering_new_identity.json"),
        "application/json"
      )

      assert has_element?(view, "[data-role='security-decision']")
      assert has_element?(view, "#pp-import-confirm[disabled]")

      key = resolution_key!("wrong_ordering_new_identity.json", &(&1.status == :needs_decision))

      view
      |> element("form#pp-import-apply")
      |> render_change(%{"security" => %{key => %{"choice" => "existing:#{acme.id}"}}})

      # The remap's entry ISIN differs from the security's current ISIN: the
      # record-as-ISIN-change offer appears (override durability).
      assert has_element?(
               view,
               "input[type='checkbox'][name=\"security[#{key}][record_isin_change]\"]"
             )

      view
      |> element("form#pp-import-apply")
      |> render_submit(%{
        "security" => %{
          key => %{"choice" => "existing:#{acme.id}", "record_isin_change" => "true"}
        }
      })

      html = render_async(view, 1_000)
      assert html =~ "Import complete"

      updated = Portfolixir.Catalog.get_security!(acme.id)
      assert updated.isin == "DE000ACME119"
      assert [alias_row] = Portfolixir.Catalog.list_identifier_aliases(updated)
      assert alias_row.former_isin == "DE000ACME001"

      assert [transaction] = Ledger.list_transactions()
      assert transaction.security_id == acme.id
    end
  end

  defp setup_portfolio do
    {:ok, p} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "PP Import Target",
        base_currency_code: "EUR"
      })

    p
  end

  defp css_rule(css, selector) do
    escaped_selector = Regex.escape(selector)
    [_, rule] = Regex.run(~r/#{escaped_selector}\s*\{([^}]*)\}/, css)
    rule
  end

  # User story (#768):
  # As an operator who drops a file larger than the import is sized for,
  # I want the page to say so in words, with the cap,
  # so that I know to split the export rather than wonder why nothing happened.
  #
  # Acceptance criteria:
  # - Over the row cap the view stays on the intake stage and names the cap.
  test "names the row cap when a file is larger than the import is sized for", %{conn: conn} do
    Application.put_env(:portfolixir, :import_max_rows, 1)
    on_exit(fn -> Application.delete_env(:portfolixir, :import_max_rows) end)

    {:ok, view, _html} = live(conn, "/imports")
    upload_sample(view)

    html = render(view)
    assert html =~ "sized for at most 1"
    refute html =~ "pp-mapping-form"
  end

  # User story (#769):
  # As an operator who drops the same export twice,
  # I want the second run to list the rows it skipped in the page's own words,
  # so that "already booked" is a sentence in my language, not an internal reason.
  #
  # Acceptance criteria:
  # - The result stage lists every skipped row with a translated reason.
  test "the second import of one file lists the skipped rows in words", %{conn: conn} do
    mapping = %{
      "cash" => %{"Test-Cash" => "create:Test-Cash", "Test-Cash-2" => "create:Test-Cash-2"},
      "depot" => %{
        "Test-Depot" => %{"target" => "create:Test-Depot", "cash" => "pp:Test-Cash"},
        "Test-Depot-2" => %{"target" => "create:Test-Depot-2", "cash" => "pp:Test-Cash"}
      }
    }

    {:ok, view, _html} = live(conn, "/imports")
    upload_sample(view)
    view |> element("form#pp-import-apply") |> render_submit(mapping)
    assert render_async(view, 1_000) =~ "Created transactions: 13"

    {:ok, view, _html} = live(conn, "/imports")
    upload_sample(view)
    view |> element("form#pp-import-apply") |> render_change(mapping)
    html = view |> element("form#pp-import-apply") |> render_submit()
    html = if html =~ "Import complete", do: html, else: render_async(view, 1_000)

    assert html =~ "Skipped 13 records already booked:"
    assert html =~ "Row 1: an identical row was imported before (stored content hash)"
    refute html =~ "already booked: an"
  end
end
