defmodule PortfolixirWeb.PortfolioAccountsLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Portfolios

  defp world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Main",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Giro",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot A"
      })

    %{portfolio: portfolio, cash: cash, depot: depot}
  end

  # User story:
  # As a local portfolio maintainer with overdraft/reserve accounts,
  # I want a per-account liquidity-role selector on the cash-account page,
  # so that I can classify an account (free cash, credit line, reserve) without
  # the API.
  #
  # Acceptance criteria:
  # - Each listed cash account shows a liquidity-role selector defaulting to
  #   free_cash.
  # - Changing the selector stores the new role and updates the rendered state.
  # - The selector renders compact and inline with the account name instead of
  #   inheriting the full-width form-input styling.
  test "sets a cash account's liquidity role", %{conn: conn} do
    %{cash: cash} = world()

    {:ok, view, _html} = live(conn, "/portfolios")

    selector = "#liquidity-role-#{cash.id}"
    form = "#liquidity-role-form-#{cash.id}"

    assert Portfolios.get_cash_account(cash.id).liquidity_role == "free_cash"

    # Drive the form the way the browser does: the account id is carried by the
    # form's hidden input, not hand-fed here. A form-less select did not
    # serialize this, so the role silently failed to persist (#433).
    view
    |> element(form)
    |> render_change(%{"liquidity_role" => "reserve"})

    assert Portfolios.get_cash_account(cash.id).liquidity_role == "reserve"
    assert view |> element(selector) |> render() =~ ~r/value="reserve" selected/

    view
    |> element(form)
    |> render_change(%{"liquidity_role" => "credit_line"})

    assert Portfolios.get_cash_account(cash.id).liquidity_role == "credit_line"
  end

  # User story (ADR-0024, #491):
  # As a local portfolio maintainer,
  # I want one table showing each depot paired with its linked cash account,
  # so that maintaining my account structure feels like one surface instead of
  # two disjoint lists.
  #
  # Acceptance criteria:
  # - A depot renders one row together with its linked cash account and the
  #   account currency.
  # - A cash account no depot links to renders as its own row.
  # - The former separate depot/cash lists are gone.
  test "renders depot/cash pairs and unpaired cash accounts in one table", %{conn: conn} do
    %{portfolio: portfolio, cash: cash, depot: depot} = world()

    {:ok, lone_cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Tagesgeld",
        currency_code: "USD"
      })

    {:ok, view, html} = live(conn, "/portfolios")

    # One paired row carries both names and the cash currency.
    pair_row = view |> element("#account-row-depot-#{depot.id}") |> render()
    assert pair_row =~ "Depot A"
    assert pair_row =~ "Giro"
    assert pair_row =~ "EUR"
    assert pair_row =~ "liquidity-role-#{cash.id}"

    # The unpaired cash account is its own row.
    lone_row = view |> element("#account-row-cash-#{lone_cash.id}") |> render()
    assert lone_row =~ "Tagesgeld"
    assert lone_row =~ "USD"

    # The two separate lists are gone.
    refute html =~ "cash-account-list"
    refute html =~ "securities-account-list"
    assert has_element?(view, "table[data-role='accounts-table']")
  end

  # User story (ADR-0024, #559):
  # As a local portfolio maintainer,
  # I want each account row to show its bucket memberships as chips — the
  # exclusive scope bucket visually distinct from free tags, with the bucket
  # color when one is set,
  # so that the grouping of my wealth is visible where the accounts live.
  #
  # Acceptance criteria:
  # - A scope-dimension bucket renders as a filled chip, a tag bucket as an
  #   outline chip.
  # - A bucket color is applied through a CSS custom property; a colorless
  #   bucket falls back to the neutral accent tokens.
  # - Long bucket names are truncated by CSS while the full name stays
  #   readable through the title attribute.
  test "renders bucket memberships as scope/tag chips with color and title", %{conn: conn} do
    %{cash: cash, depot: depot} = world()

    {:ok, scope} =
      Buckets.create_bucket(Actor.owner_ui(), %{name: "Household", dimension: "scope"})

    {:ok, tag} =
      Buckets.create_bucket(Actor.owner_ui(), %{
        name: "PP Import 2026-07-12 Broker Depot Transfer",
        color: "#0f766e"
      })

    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [scope.id, tag.id])
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), cash, [scope.id])

    {:ok, view, _html} = live(conn, "/portfolios")

    depot_chips = view |> element("#depot-buckets-#{depot.id}") |> render()
    assert depot_chips =~ "bucket-chip--scope"
    assert depot_chips =~ "Household"
    assert depot_chips =~ "--chip-color: #0f766e"
    assert depot_chips =~ ~s(title="PP Import 2026-07-12 Broker Depot Transfer")

    cash_chips = view |> element("#cash-buckets-#{cash.id}") |> render()
    assert cash_chips =~ "Household"
    assert cash_chips =~ "bucket-chip--scope"
  end

  # User story (ADR-0024, #559):
  # As a local portfolio maintainer,
  # I want to add and remove buckets directly on an account row — including
  # creating a new tag inline,
  # so that grouping is a chip edit, not a trip to another page.
  #
  # Acceptance criteria:
  # - A "+" affordance opens a picker listing the not-yet-assigned buckets.
  # - Picking one assigns it through the journaled Buckets context.
  # - The "x" on a chip removes that membership.
  # - Entering a new tag name in the picker creates the bucket and assigns it.
  test "adds and removes buckets as chips, with inline tag creation", %{conn: conn} do
    %{cash: cash, depot: depot} = world()

    {:ok, tag} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Retirement"})

    {:ok, view, _html} = live(conn, "/portfolios")

    # Open the picker on the depot row and add the existing bucket.
    view
    |> element("#depot-buckets-#{depot.id} button[data-role='bucket-add']")
    |> render_click()

    view
    |> element("#bucket-picker-depot-#{depot.id} button[phx-value-bucket='#{tag.id}']")
    |> render_click()

    assert Buckets.depot_default_bucket_ids(depot.id) == [tag.id]

    # Inline tag creation from the same picker.
    view
    |> element("#bucket-create-form-depot-#{depot.id}")
    |> render_submit(%{"bucket_name" => "Kids"})

    assert [%{name: "Kids"} = kids] =
             Enum.filter(Buckets.list_buckets(), &(&1.name == "Kids"))

    assert kids.dimension == "tag"
    assert Enum.sort(Buckets.depot_default_bucket_ids(depot.id)) == Enum.sort([tag.id, kids.id])

    # Remove one chip again.
    view
    |> element(
      "#depot-buckets-#{depot.id} button[data-role='bucket-remove'][phx-value-bucket='#{tag.id}']"
    )
    |> render_click()

    assert Buckets.depot_default_bucket_ids(depot.id) == [kids.id]

    # The cash side of the pair edits its own membership.
    view
    |> element("#cash-buckets-#{cash.id} button[data-role='bucket-add']")
    |> render_click()

    view
    |> element("#bucket-picker-cash-#{cash.id} button[phx-value-bucket='#{tag.id}']")
    |> render_click()

    assert Buckets.cash_account_bucket_ids(cash.id) == [tag.id]
  end

  # User story (ADR-0024 modification 2):
  # As a local portfolio maintainer,
  # I want a clear inline message when I try to put an account into a second
  # scope bucket,
  # so that the exclusive dimension stays understandable instead of failing
  # silently.
  test "adding a second scope bucket surfaces the exclusive-conflict message", %{conn: conn} do
    %{depot: depot} = world()

    {:ok, scope_a} =
      Buckets.create_bucket(Actor.owner_ui(), %{name: "Mine", dimension: "scope"})

    {:ok, scope_b} =
      Buckets.create_bucket(Actor.owner_ui(), %{name: "Partner", dimension: "scope"})

    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [scope_a.id])

    {:ok, view, _html} = live(conn, "/portfolios")

    view
    |> element("#depot-buckets-#{depot.id} button[data-role='bucket-add']")
    |> render_click()

    html =
      view
      |> element("#bucket-picker-depot-#{depot.id} button[phx-value-bucket='#{scope_b.id}']")
      |> render_click()

    assert html =~ "data-role=\"bucket-error\""
    assert html =~ "one scope bucket"
    assert Buckets.depot_default_bucket_ids(depot.id) == [scope_a.id]
  end

  # User story (ADR-0024, #491):
  # As a local portfolio maintainer,
  # I want one polished dialog that creates a depot together with its cash
  # account (with optional initial bucket tags) without any portfolio decision,
  # so that account creation is one coherent flow while the compatibility
  # record is resolved internally.
  #
  # Acceptance criteria:
  # - The page renders no raw inline create forms and no portfolio selector.
  # - The dialog creates the cash account and the depot linked to it in one
  #   flow, bound to the internal default portfolio.
  # - Checked buckets and an inline new tag become the initial membership of
  #   both created records.
  test "creates a depot with its cash account and initial tags via the dialog", %{conn: conn} do
    {:ok, tag} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Household"})

    {:ok, view, html} = live(conn, "/portfolios")

    refute html =~ "portfolio-form"
    refute html =~ "Add to portfolio"
    refute html =~ "Create portfolio"
    refute html =~ "cash-account-form"
    refute html =~ "securities-account-form"

    view |> element("#add-account-button") |> render_click()

    view
    |> element("#account-form-dialog button[phx-value-mode='depot']")
    |> render_click()

    view
    |> form("#account-dialog-form", %{
      "account" => %{
        "depot_name" => "Depot Neu",
        "cash_account_id" => "",
        "cash_name" => "Verrechnungskonto",
        "currency_code" => "EUR",
        "bucket_ids" => [to_string(tag.id)],
        "new_tag" => "Kids"
      }
    })
    |> render_submit()

    assert [cash] = Portfolios.list_cash_accounts()
    assert cash.name == "Verrechnungskonto"
    assert [depot] = Portfolios.list_securities_accounts()
    assert depot.name == "Depot Neu"
    assert depot.cash_account_id == cash.id

    # Internal compatibility binding, never asked for.
    default = Portfolios.get_portfolio(cash.portfolio_id)
    assert default.name == "Default"
    assert depot.portfolio_id == default.id
    assert Portfolios.count_portfolios() == 1

    # Initial buckets landed on both created records.
    kids = Enum.find(Buckets.list_buckets(), &(&1.name == "Kids"))
    assert kids
    assert Enum.sort(Buckets.depot_default_bucket_ids(depot.id)) == Enum.sort([tag.id, kids.id])
    assert Enum.sort(Buckets.cash_account_bucket_ids(cash.id)) == Enum.sort([tag.id, kids.id])
  end

  # The dialog also covers the cash-account-only flow, and an existing
  # installation keeps binding new accounts to its earliest portfolio —
  # deterministic, no new "Default" record appears.
  test "creates a cash-account-only record bound to the earliest portfolio", %{conn: conn} do
    {:ok, first} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Alpha",
        base_currency_code: "EUR"
      })

    {:ok, _b} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Beta",
        base_currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/portfolios")

    view |> element("#add-account-button") |> render_click()

    view
    |> element("#account-form-dialog button[phx-value-mode='cash']")
    |> render_click()

    view
    |> form("#account-dialog-form", %{
      "account" => %{"cash_name" => "New Cash", "currency_code" => "EUR", "new_tag" => ""}
    })
    |> render_submit()

    assert [cash] = Portfolios.list_cash_accounts()
    assert cash.portfolio_id == first.id
    assert Portfolios.count_portfolios() == 2
  end

  # A depot can also link an existing cash account instead of creating one.
  test "the dialog links a depot to an existing cash account", %{conn: conn} do
    %{portfolio: portfolio, cash: cash} = world()

    {:ok, view, _html} = live(conn, "/portfolios")

    view |> element("#add-account-button") |> render_click()

    view
    |> element("#account-form-dialog button[phx-value-mode='depot']")
    |> render_click()

    view
    |> form("#account-dialog-form", %{
      "account" => %{
        "depot_name" => "Zweitdepot",
        "cash_account_id" => to_string(cash.id),
        "new_tag" => ""
      }
    })
    |> render_submit()

    depots = Portfolios.list_securities_accounts()
    assert Enum.any?(depots, &(&1.name == "Zweitdepot" and &1.cash_account_id == cash.id))
    assert Portfolios.count_portfolios() == 1
    assert [_only] = Portfolios.list_cash_accounts()
    assert portfolio.id == hd(depots).portfolio_id
  end

  # Two scope buckets checked in the dialog are rejected before anything is
  # created — the exclusive invariant fails loud and early.
  test "the dialog rejects two initial scope buckets without creating records", %{conn: conn} do
    {:ok, scope_a} =
      Buckets.create_bucket(Actor.owner_ui(), %{name: "Mine", dimension: "scope"})

    {:ok, scope_b} =
      Buckets.create_bucket(Actor.owner_ui(), %{name: "Partner", dimension: "scope"})

    {:ok, view, _html} = live(conn, "/portfolios")

    view |> element("#add-account-button") |> render_click()

    view
    |> element("#account-form-dialog button[phx-value-mode='cash']")
    |> render_click()

    html =
      view
      |> form("#account-dialog-form", %{
        "account" => %{
          "cash_name" => "Cash",
          "currency_code" => "EUR",
          "bucket_ids" => [to_string(scope_a.id), to_string(scope_b.id)],
          "new_tag" => ""
        }
      })
      |> render_submit()

    assert html =~ "one scope bucket"
    assert Portfolios.list_cash_accounts() == []
  end

  # User story (ADR-0024 modification 1):
  # As a local portfolio maintainer,
  # I want a minimal, read-only administration list of every portfolio record,
  # so that portfolios created over the API/MCP can never become invisible
  # writable resources.
  #
  # Acceptance criteria:
  # - A collapsed panel on the Accounts & depots page lists every portfolio
  #   record with name, creation date, source, and bound depot/account counts.
  # - API-created records appear with the API source label.
  # - The panel offers no create or edit controls.
  test "admin panel lists every portfolio record read-only", %{conn: conn} do
    {:ok, ui} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Mine",
        base_currency_code: "EUR"
      })

    {:ok, _api} =
      Portfolios.create_portfolio(Actor.api_token_rw("mcp"), %{
        name: "Ghost",
        base_currency_code: "USD"
      })

    {:ok, _cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: ui.id,
        name: "Cash EUR",
        currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/portfolios")

    panel = view |> element("#portfolio-admin") |> render()
    assert panel =~ "Mine"
    assert panel =~ "Ghost"
    assert panel =~ "API"
    assert panel =~ Date.to_iso8601(Date.utc_today())

    # Read-only: no create or edit affordance inside the panel.
    refute panel =~ "<form"
    refute panel =~ "<button"
    refute panel =~ "<input"
  end

  # User story (ADR-0024, #491):
  # As a local portfolio maintainer whose depots settle against one shared
  # cash account,
  # I want the shared account's controls rendered exactly once,
  # so that later rows read "shared account" instead of duplicating the
  # liquidity selector and chips under conflicting DOM ids.
  test "a shared cash account renders its controls only on the first row", %{conn: conn} do
    %{portfolio: portfolio, cash: cash, depot: depot} = world()

    {:ok, second} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot B"
      })

    {:ok, view, html} = live(conn, "/portfolios")

    # The first claiming row keeps the liquidity selector and cash chips.
    first_row = view |> element("#account-row-depot-#{depot.id}") |> render()
    assert first_row =~ "liquidity-role-#{cash.id}"
    assert first_row =~ "cash-buckets-#{cash.id}"

    # The second row names the sharing instead of duplicating controls.
    second_row = view |> element("#account-row-depot-#{second.id}") |> render()
    assert second_row =~ "shared account"
    refute second_row =~ "liquidity-role-#{cash.id}"

    # No DOM id appears twice.
    assert length(String.split(html, ~s(id="liquidity-role-#{cash.id}"))) == 2
  end

  # User story (ADR-0024, #559):
  # As a local portfolio maintainer,
  # I want the "+" affordance to close an open picker again,
  # so that the chip row toggles instead of stacking pickers.
  test "the bucket picker toggles closed on the second + click", %{conn: conn} do
    %{depot: depot} = world()

    {:ok, view, _html} = live(conn, "/portfolios")

    view
    |> element("#depot-buckets-#{depot.id} button[data-role='bucket-add']")
    |> render_click()

    assert has_element?(view, "#bucket-picker-depot-#{depot.id}")

    view
    |> element("#depot-buckets-#{depot.id} button[data-role='bucket-add']")
    |> render_click()

    refute has_element?(view, "#bucket-picker-depot-#{depot.id}")
  end

  # User story (fix round, robustness):
  # As a local portfolio maintainer,
  # I want malformed or stale chip payloads (a non-numeric id, an account that
  # vanished in another tab) to be ignored,
  # so that a hostile or out-of-date client can neither crash the page nor
  # write an assignment.
  test "malformed and stale chip payloads are ignored without a write", %{conn: conn} do
    %{depot: depot, cash: cash} = world()
    {:ok, tag} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Retirement"})
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [tag.id])

    {:ok, view, _html} = live(conn, "/portfolios")

    # Non-numeric owner id: the picker never opens.
    render_click(view, "open_bucket_picker", %{"owner" => "depot", "id" => "abc"})
    refute has_element?(view, "[data-role='bucket-picker']")

    # Non-numeric bucket ids leave the membership untouched.
    depot_id = to_string(depot.id)
    render_click(view, "add_bucket", %{"owner" => "depot", "id" => depot_id, "bucket" => "abc"})
    render_click(view, "remove_bucket", %{"owner" => "depot", "id" => depot_id, "bucket" => "x"})
    assert Buckets.depot_default_bucket_ids(depot.id) == [tag.id]

    # Vanished owners (depot or cash) are ignored, no crash, no write.
    render_click(view, "add_bucket", %{
      "owner" => "depot",
      "id" => "999999",
      "bucket" => to_string(tag.id)
    })

    render_click(view, "add_bucket", %{
      "owner" => "cash",
      "id" => "999999",
      "bucket" => to_string(tag.id)
    })

    assert Buckets.depot_default_bucket_ids(depot.id) == [tag.id]
    assert Buckets.cash_account_bucket_ids(cash.id) == []
  end

  # User story (fix round, two-tab staleness):
  # As a local portfolio maintainer with two tabs open,
  # I want picking a bucket that was deleted in the other tab to say so,
  # so that the stale picker fails with a refresh hint instead of a crash.
  test "adding a bucket deleted meanwhile shows the refresh hint", %{conn: conn} do
    %{depot: depot} = world()
    {:ok, tag} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Retirement"})

    {:ok, view, _html} = live(conn, "/portfolios")

    view
    |> element("#depot-buckets-#{depot.id} button[data-role='bucket-add']")
    |> render_click()

    # The other tab deletes the bucket while our picker is open.
    {:ok, _} = Buckets.delete_bucket(Actor.owner_ui(), tag)

    html =
      view
      |> element("#bucket-picker-depot-#{depot.id} button[phx-value-bucket='#{tag.id}']")
      |> render_click()

    assert html =~ "data-role=\"bucket-error\""
    assert html =~ "no longer exists"
    assert Buckets.depot_default_bucket_ids(depot.id) == []
  end

  # User story (fix round, tag/scope dimension safety):
  # As a local portfolio maintainer,
  # I want the inline tag creation to refuse a scope bucket's name,
  # so that the exclusive scope dimension is never silently reused as a tag.
  test "inline tag creation refuses a scope bucket's name and bad names", %{conn: conn} do
    %{depot: depot} = world()

    {:ok, _scope} =
      Buckets.create_bucket(Actor.owner_ui(), %{name: "Household", dimension: "scope"})

    {:ok, view, _html} = live(conn, "/portfolios")

    view
    |> element("#depot-buckets-#{depot.id} button[data-role='bucket-add']")
    |> render_click()

    html =
      view
      |> element("#bucket-create-form-depot-#{depot.id}")
      |> render_submit(%{"bucket_name" => "Household"})

    assert html =~ "belongs to a scope bucket"
    assert Buckets.depot_default_bucket_ids(depot.id) == []

    # An over-long tag name fails with the changeset message, no write.
    html =
      view
      |> element("#bucket-create-form-depot-#{depot.id}")
      |> render_submit(%{"bucket_name" => String.duplicate("x", 120)})

    assert html =~ "data-role=\"bucket-error\""
    assert html =~ "should be at most"
    assert Buckets.depot_default_bucket_ids(depot.id) == []
    assert length(Buckets.list_buckets()) == 1
  end

  # User story (ADR-0024 modification 1):
  # As a local portfolio maintainer,
  # I want import- and seed-created portfolio records labeled by their origin,
  # so that the admin list tells me where every compatibility record came from.
  test "admin panel labels import- and seed-created records", %{conn: conn} do
    {:ok, imported} =
      Portfolios.create_portfolio(Actor.import_session("pp-2026-07"), %{
        name: "PP Import",
        base_currency_code: "EUR"
      })

    {:ok, _seeded} =
      Portfolios.create_portfolio(Actor.system_job("portfolio_scope_seed"), %{
        name: "Machine Made",
        base_currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/portfolios")

    panel = view |> element("#portfolio-admin") |> render()
    assert panel =~ "PP Import"
    assert panel =~ "Import"
    assert panel =~ "Machine Made"
    assert panel =~ "Seeded"
    assert imported.name == "PP Import"
  end

  # User story (ADR-0024, #491):
  # As a local portfolio maintainer,
  # I want the creation dialog to close via its X button and to step back to
  # the depot-or-cash choice,
  # so that I can abandon or correct the flow without reloading the page.
  test "the dialog closes via X and steps back to the choice", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/portfolios")

    view |> element("#add-account-button") |> render_click()
    assert has_element?(view, "#account-form-dialog")

    # Into the depot form, then back to the choice step.
    view
    |> element("#account-form-dialog button[phx-value-mode='depot']")
    |> render_click()

    assert has_element?(view, "#account-dialog-form")

    view |> element("#account-dialog-form button.button-ghost") |> render_click()
    refute has_element?(view, "#account-dialog-form")
    assert has_element?(view, "#account-form-dialog button[phx-value-mode='cash']")

    # The X closes the dialog entirely.
    view |> element("#account-form-dialog header button.icon-button") |> render_click()
    refute has_element?(view, "#account-form-dialog")
  end

  # User story (ADR-0024, #491):
  # As a local portfolio maintainer,
  # I want the new-cash-account fields to disappear when I link an existing
  # account,
  # so that the form never asks for a name/currency it would ignore.
  test "linking an existing cash account hides the new-cash fields", %{conn: conn} do
    %{cash: cash} = world()

    {:ok, view, _html} = live(conn, "/portfolios")

    view |> element("#add-account-button") |> render_click()

    view
    |> element("#account-form-dialog button[phx-value-mode='depot']")
    |> render_click()

    assert has_element?(view, "#account-dialog-form input[name='account[cash_name]']")

    view
    |> element("#account-dialog-form")
    |> render_change(%{"account" => %{"cash_account_id" => to_string(cash.id)}})

    refute has_element?(view, "#account-dialog-form input[name='account[cash_name]']")

    view
    |> element("#account-dialog-form")
    |> render_change(%{"account" => %{"cash_account_id" => ""}})

    assert has_element?(view, "#account-dialog-form input[name='account[cash_name]']")
  end

  # User story (ADR-0024, #491):
  # As a local portfolio maintainer,
  # I want a blank depot name rejected before anything is written,
  # so that a failed depot create never leaves a freshly created cash account
  # dangling without its depot.
  test "a blank depot name fails before creating the cash account", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/portfolios")

    view |> element("#add-account-button") |> render_click()

    view
    |> element("#account-form-dialog button[phx-value-mode='depot']")
    |> render_click()

    html =
      view
      |> form("#account-dialog-form", %{
        "account" => %{
          "depot_name" => "   ",
          "cash_account_id" => "",
          "cash_name" => "Verrechnungskonto",
          "currency_code" => "EUR",
          "new_tag" => ""
        }
      })
      |> render_submit()

    assert html =~ "field-error"
    assert html =~ "blank"
    assert Portfolios.list_cash_accounts() == []
    assert Portfolios.list_securities_accounts() == []
  end

  # Changeset errors land on the field that caused them: a malformed currency
  # is reported at the Currency input, and nothing is created.
  test "the dialog maps changeset errors onto the offending field", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/portfolios")

    view |> element("#add-account-button") |> render_click()

    view
    |> element("#account-form-dialog button[phx-value-mode='cash']")
    |> render_click()

    html =
      view
      |> form("#account-dialog-form", %{
        "account" => %{"cash_name" => "Neu", "currency_code" => "EU", "new_tag" => ""}
      })
      |> render_submit()

    assert html =~ "field-error"
    assert html =~ "should be"
    assert Portfolios.list_cash_accounts() == []
  end

  # User story (fix round, tag/scope dimension safety):
  # As a local portfolio maintainer,
  # I want the dialog's inline tag to refuse a scope bucket's name and
  # unusable names,
  # so that the creation flow fails loud before any record is written.
  test "the dialog rejects a scope-named or unusable new tag before creating", %{conn: conn} do
    {:ok, _scope} =
      Buckets.create_bucket(Actor.owner_ui(), %{name: "Household", dimension: "scope"})

    {:ok, view, _html} = live(conn, "/portfolios")

    view |> element("#add-account-button") |> render_click()

    view
    |> element("#account-form-dialog button[phx-value-mode='cash']")
    |> render_click()

    html =
      view
      |> form("#account-dialog-form", %{
        "account" => %{"cash_name" => "Cash", "currency_code" => "EUR", "new_tag" => "Household"}
      })
      |> render_submit()

    assert html =~ "belongs to a scope bucket"
    assert Portfolios.list_cash_accounts() == []

    html =
      view
      |> form("#account-dialog-form", %{
        "account" => %{
          "cash_name" => "Cash",
          "currency_code" => "EUR",
          "new_tag" => String.duplicate("x", 120)
        }
      })
      |> render_submit()

    assert html =~ "The new tag could not be created."
    assert Portfolios.list_cash_accounts() == []
  end

  # A cash-only creation also honors the initial buckets (there is no depot to
  # tag, only the new cash account).
  test "cash-only creation tags the new account with the initial buckets", %{conn: conn} do
    {:ok, tag} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Household"})

    {:ok, view, _html} = live(conn, "/portfolios")

    view |> element("#add-account-button") |> render_click()

    view
    |> element("#account-form-dialog button[phx-value-mode='cash']")
    |> render_click()

    view
    |> form("#account-dialog-form", %{
      "account" => %{
        "cash_name" => "Tagesgeld",
        "currency_code" => "EUR",
        "bucket_ids" => [to_string(tag.id)],
        "new_tag" => ""
      }
    })
    |> render_submit()

    # Synchronize on the parent's success flash before asserting the writes:
    # the dialog notifies the parent asynchronously, which reloads the page.
    assert render(view) =~ "Cash account created"

    assert [cash] = Portfolios.list_cash_accounts()
    assert cash.name == "Tagesgeld"
    assert Buckets.cash_account_bucket_ids(cash.id) == [tag.id]
  end

  # User story:
  # As a German-locale maintainer,
  # I want the accounts surface fully translated,
  # so that the German UI carries the paired-table and chips wording.
  test "translates the accounts surface for the German locale", %{conn: conn} do
    world()

    {:ok, _view, html} = live(conn, "/portfolios?locale=de")

    assert html =~ "Portfoliodatensätze"
    assert html =~ "Depot &amp; Konto anlegen"
    refute html =~ "Add to portfolio"
    refute html =~ "Create portfolio"
  end

  test "renders the cash-quote toggle compact instead of as a full-width form input" do
    app_css = File.read!("priv/static/app.css")

    # Inline next to the account name, not stacked by the global label grid...
    assert app_css =~ ~r/\.cash-quote-toggle\s*\{[^}]*display:\s*inline-flex/s

    # ...and the checkbox must not inherit the 100%-width / 34px form sizing.
    assert app_css =~ ~r/\.cash-quote-toggle input\[type="checkbox"\]\s*\{[^}]*width:\s*14px/s
    assert app_css =~ ~r/\.cash-quote-toggle input\[type="checkbox"\]\s*\{[^}]*min-height:\s*0/s
  end

  # Chip visuals: scope chips are filled, tag chips outlined, both truncate and
  # fall back to the neutral accent tokens when the bucket has no color.
  test "chip styling distinguishes scope from tag and truncates long names" do
    app_css = File.read!("priv/static/app.css")

    assert app_css =~ ~r/\.bucket-chip\s*\{[^}]*--chip-color/s
    assert app_css =~ ~r/\.bucket-chip--scope\s*\{/
    assert app_css =~ ~r/\.bucket-chip__name\s*\{[^}]*text-overflow:\s*ellipsis/s
  end
end
