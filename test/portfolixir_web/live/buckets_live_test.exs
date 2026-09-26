defmodule PortfolixirWeb.BucketsLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Portfolios

  defp world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Main",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Giro",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot"
      })

    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{name: "ACME", currency_code: "EUR"})

    %{portfolio: portfolio, cash: cash, depot: depot, security: security}
  end

  # Row actions live in the row menu (issue 802): open the kebab of the row
  # of `kind` ("view" or "bucket") with `id`, then click the menu item.
  defp menu_click(view, kind, id, event) do
    view
    |> element(~s(button.row-actions__kebab[phx-value-kind="#{kind}"][phx-value-id="#{id}"]))
    |> render_click()

    view
    |> element(~s([role="menu"] button[phx-click="#{event}"][phx-value-id="#{id}"]))
    |> render_click()
  end

  # User story:
  # As a local portfolio maintainer,
  # I want a views management page to create and manage buckets,
  # so that I can tag holdings without touching the API.
  #
  # Acceptance criteria:
  # - Submitting the bucket form creates the bucket through the context.
  # - The new bucket is rendered in the bucket list.
  test "creates a bucket", %{conn: conn} do
    world()

    {:ok, view, _html} = live(conn, "/buckets")

    # ADR-0024 modification 6: the management surface is about views; buckets
    # are the tags views filter on, managed here and from account-row chips.
    assert view |> element("#app-topbar-title") |> render() =~ "Views"

    html =
      view
      |> form("#bucket-form", bucket: %{name: "Retirement"})
      |> render_submit()

    assert html =~ "Retirement"
    assert Enum.any?(Buckets.list_buckets(), &(&1.name == "Retirement"))
  end

  # User story:
  # As a local portfolio maintainer,
  # I want to create a view and pick its include/exclude buckets,
  # so that I can scope my analytics to part of my wealth.
  #
  # Acceptance criteria:
  # - Creating a view stores it through the context.
  # - The bucket picker writes the chosen include/exclude sets and the
  #   include_all toggle, with exclude winning.
  test "creates a view and edits its include/exclude buckets", %{conn: conn} do
    world()
    {:ok, core} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})
    {:ok, spec} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Speculative"})

    {:ok, view, _html} = live(conn, "/buckets")

    view
    |> form("#view-form", view: %{name: "No speculation"})
    |> render_submit()

    created = Enum.find(Buckets.list_views(), &(&1.name == "No speculation"))
    assert created

    # Open the bucket picker modal for the view.
    menu_click(view, "view", created.id, "edit_view_buckets")

    assert has_element?(view, "#view-bucket-modal")

    # Flip include_all off so the include checklist appears (live preview).
    view
    |> form("#view-bucket-form", %{"include_all" => "false"})
    |> render_change()

    # Pick include Core, exclude Speculative.
    view
    |> form("#view-bucket-form", %{
      "include_all" => "false",
      "include" => ["#{core.id}"],
      "exclude" => ["#{spec.id}"]
    })
    |> render_submit()

    {:ok, filter} = Buckets.view_filter(created.id)
    assert filter.include == [core.id]
    assert filter.exclude == [spec.id]
  end

  # User story (fix round, matches-nothing views):
  # As a local portfolio maintainer,
  # I want the Views page to flag a view whose resolution matches no accounts,
  # so that I fix its bucket set instead of wondering about a silent 0 total.
  #
  # Acceptance criteria:
  # - A view whose only include bucket was deleted carries the
  #   "matches no accounts" hint; views that still match do not.
  test "flags a view whose resolution matches no accounts", %{conn: conn} do
    %{depot: depot} = world()

    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Orphan"})

    {:ok, orphaned} =
      Buckets.create_view(Actor.owner_ui(), %{name: "Orphaned", include_all: false})

    :ok = Buckets.set_view_buckets(Actor.owner_ui(), orphaned, [bucket.id], [])

    {:ok, live_bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Live"})
    {:ok, living} = Buckets.create_view(Actor.owner_ui(), %{name: "Living", include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), living, [live_bucket.id], [])
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [live_bucket.id])

    # Deleting the only include bucket empties the orphaned view's resolution.
    {:ok, _} = Buckets.delete_bucket(Actor.owner_ui(), bucket)

    {:ok, view, _html} = live(conn, "/buckets")

    assert has_element?(view, "#view-#{orphaned.id} [data-role='view-matches-nothing']")
    refute has_element?(view, "#view-#{living.id} [data-role='view-matches-nothing']")
  end

  test "renames and deletes a bucket", %{conn: conn} do
    world()
    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})

    {:ok, view, _html} = live(conn, "/buckets")

    menu_click(view, "bucket", bucket.id, "edit_bucket")

    view
    |> form("#bucket-#{bucket.id} form", bucket: %{name: "Foundation"})
    |> render_submit()

    assert Buckets.get_bucket(bucket.id).name == "Foundation"

    menu_click(view, "bucket", bucket.id, "delete_bucket")

    assert Buckets.get_bucket(bucket.id) == nil
  end

  # User story (E25 S6 review round, G19):
  # As the operator deleting a bucket that someone else removed a moment ago,
  # I want to be told it is gone,
  # so that a delete never fails without a word.
  #
  # Acceptance criteria:
  # - The page names the gone bucket in its failure message and shows the
  #   list as stored.
  test "a bucket deleted meanwhile is named as gone", %{conn: conn} do
    world()
    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})

    {:ok, view, _html} = live(conn, "/buckets")

    view
    |> element(
      ~s(button.row-actions__kebab[phx-value-kind="bucket"][phx-value-id="#{bucket.id}"])
    )
    |> render_click()

    {:ok, _} = Buckets.delete_bucket(Actor.owner_ui(), bucket)

    html =
      view
      |> element(~s([role="menu"] button[phx-click="delete_bucket"][phx-value-id="#{bucket.id}"]))
      |> render_click()

    assert html =~ "That bucket no longer exists."
    refute has_element?(view, "#bucket-#{bucket.id}")
  end

  test "renames and deletes a view", %{conn: conn} do
    world()
    {:ok, v} = Buckets.create_view(Actor.owner_ui(), %{name: "Old"})

    {:ok, view, _html} = live(conn, "/buckets")

    menu_click(view, "view", v.id, "edit_view")

    view
    |> form("#view-#{v.id} form", view: %{name: "New"})
    |> render_submit()

    assert Buckets.get_view(v.id).name == "New"

    menu_click(view, "view", v.id, "delete_view")
    assert Buckets.get_view(v.id) == nil
  end

  # User story:
  # As a local portfolio maintainer,
  # I want clear error feedback when a bucket or view cannot be saved,
  # so that a duplicate or blank name does not silently fail.
  #
  # Acceptance criteria:
  # - A blank bucket name surfaces a validation error toast.
  # - A blank view name surfaces a validation error toast.
  test "blank bucket and view names surface validation errors", %{conn: conn} do
    world()

    {:ok, view, _html} = live(conn, "/buckets")

    html =
      view
      |> form("#bucket-form", bucket: %{name: ""})
      |> render_submit()

    assert html =~ "name can&#39;t be blank"
    assert has_element?(view, "[data-role='overlap-hint']")

    html =
      view
      |> form("#view-form", view: %{name: ""})
      |> render_submit()

    assert html =~ "name can&#39;t be blank"
  end

  test "renaming a bucket to a duplicate name surfaces a validation error", %{conn: conn} do
    world()
    {:ok, _taken} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Taken"})
    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})

    {:ok, view, _html} = live(conn, "/buckets")

    menu_click(view, "bucket", bucket.id, "edit_bucket")

    html =
      view
      |> form("#bucket-#{bucket.id} form", bucket: %{name: "Taken"})
      |> render_submit()

    assert html =~ "name has already been taken"
    # The original record is unchanged and editing mode stays open.
    assert Buckets.get_bucket(bucket.id).name == "Core"
  end

  test "renaming a view to a duplicate name surfaces a validation error", %{conn: conn} do
    world()
    {:ok, _taken} = Buckets.create_view(Actor.owner_ui(), %{name: "Taken"})
    {:ok, v} = Buckets.create_view(Actor.owner_ui(), %{name: "Old"})

    {:ok, view, _html} = live(conn, "/buckets")

    menu_click(view, "view", v.id, "edit_view")

    html =
      view
      |> form("#view-#{v.id} form", view: %{name: "Taken"})
      |> render_submit()

    assert html =~ "name has already been taken"
    assert Buckets.get_view(v.id).name == "Old"
  end

  test "cancelling bucket and view edits closes the inline forms", %{conn: conn} do
    world()
    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})
    {:ok, v} = Buckets.create_view(Actor.owner_ui(), %{name: "Income"})

    {:ok, view, _html} = live(conn, "/buckets")

    menu_click(view, "bucket", bucket.id, "edit_bucket")

    assert has_element?(view, "#bucket-#{bucket.id} form[phx-submit='rename_bucket']")

    view |> element("button[phx-click='cancel_edit_bucket']") |> render_click()
    refute has_element?(view, "#bucket-#{bucket.id} form[phx-submit='rename_bucket']")

    menu_click(view, "view", v.id, "edit_view")
    assert has_element?(view, "#view-#{v.id} form[phx-submit='rename_view']")

    view |> element("button[phx-click='cancel_edit_view']") |> render_click()
    refute has_element?(view, "#view-#{v.id} form[phx-submit='rename_view']")
  end

  test "the bucket picker modal can be closed without saving", %{conn: conn} do
    world()
    {:ok, v} = Buckets.create_view(Actor.owner_ui(), %{name: "Income"})

    {:ok, view, _html} = live(conn, "/buckets")

    menu_click(view, "view", v.id, "edit_view_buckets")

    assert has_element?(view, "#view-bucket-modal")

    view |> element("#view-bucket-modal button", "Cancel") |> render_click()
    refute has_element?(view, "#view-bucket-modal")
  end

  # User story:
  # As a local portfolio maintainer,
  # I want a stale bucket id to fail cleanly instead of crashing,
  # so that a concurrent delete only produces a friendly error.
  #
  # Acceptance criteria:
  # - Saving a view's buckets with a non-existent bucket id shows the
  #   "bucket no longer exists" error and leaves the view's filter empty.
  test "saving view buckets with a stale bucket id surfaces a friendly error", %{conn: conn} do
    world()
    # A real bucket makes the include checkbox input render; deleting it behind
    # the open modal makes the submitted id stale, driving the
    # {:error, :bucket_ids} concurrent-delete branch.
    {:ok, core} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})
    {:ok, v} = Buckets.create_view(Actor.owner_ui(), %{name: "Income"})

    {:ok, view, _html} = live(conn, "/buckets")

    menu_click(view, "view", v.id, "edit_view_buckets")

    # Reveal the include checklist so its input name exists.
    view |> form("#view-bucket-form", %{"include_all" => "false"}) |> render_change()

    {:ok, _} = Buckets.delete_bucket(Actor.owner_ui(), core)

    html =
      view
      |> form("#view-bucket-form", %{
        "include_all" => "false",
        "include" => ["#{core.id}"]
      })
      |> render_submit()

    assert html =~ "That bucket no longer exists"
    {:ok, filter} = Buckets.view_filter(v.id)
    assert filter.include == []
    assert filter.exclude == []
  end

  test "the include-all toggle live-previews the include checklist", %{conn: conn} do
    world()
    {:ok, _core} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})
    {:ok, v} = Buckets.create_view(Actor.owner_ui(), %{name: "Income"})

    {:ok, view, _html} = live(conn, "/buckets")

    menu_click(view, "view", v.id, "edit_view_buckets")

    # include_all defaults on, so the include checklist is hidden.
    refute has_element?(view, "#view-bucket-form legend", "Include buckets")

    view
    |> form("#view-bucket-form", %{"include_all" => "false"})
    |> render_change()

    assert has_element?(view, "#view-bucket-form legend", "Include buckets")
  end

  # User story:
  # As a local portfolio maintainer,
  # I want acting on a bucket or view that was deleted elsewhere to be a no-op,
  # so that a stale page never crashes when I click a stale control.
  #
  # Acceptance criteria:
  # - Renaming, deleting, or editing the buckets of an already-deleted record is
  #   a silent no-op (the page stays mounted, no error toast).
  test "renaming a vanished bucket or view is a silent no-op", %{conn: conn} do
    world()
    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})
    {:ok, v} = Buckets.create_view(Actor.owner_ui(), %{name: "Income"})

    {:ok, view, _html} = live(conn, "/buckets")

    # Enter edit mode while the records still exist, so the inline forms render.
    menu_click(view, "bucket", bucket.id, "edit_bucket")

    menu_click(view, "view", v.id, "edit_view")

    # They vanish behind the open page.
    {:ok, _} = Buckets.delete_bucket(Actor.owner_ui(), bucket)
    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), v)

    # Renaming the now-missing bucket/view is a no-op (no crash, no error toast).
    html =
      view
      |> form("#bucket-#{bucket.id} form", bucket: %{name: "Foundation"})
      |> render_submit()

    refute html =~ "status-toast"

    html =
      view
      |> form("#view-#{v.id} form", view: %{name: "New"})
      |> render_submit()

    refute html =~ "status-toast"
    assert has_element?(view, "#buckets-workspace")
  end

  # A vanished bucket's delete is named since the E25 S6 review round ("a
  # bucket deleted meanwhile is named as gone"); the edit-buckets control of
  # a vanished view stays a no-op.
  test "deleting or editing-buckets of a vanished bucket or view never crashes",
       %{conn: conn} do
    world()
    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})
    {:ok, v} = Buckets.create_view(Actor.owner_ui(), %{name: "Income"})

    {:ok, view, _html} = live(conn, "/buckets")

    # Records vanish behind the open (non-edit-mode) page, so the delete and
    # edit-buckets controls are still rendered with valid integer ids.
    {:ok, _} = Buckets.delete_bucket(Actor.owner_ui(), bucket)
    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), v)

    menu_click(view, "view", v.id, "edit_view_buckets")

    refute has_element?(view, "#view-bucket-modal")

    menu_click(view, "bucket", bucket.id, "delete_bucket")

    assert has_element?(view, "#buckets-workspace")
  end

  test "saving the bucket picker for a vanished view is a no-op", %{conn: conn} do
    world()
    {:ok, v} = Buckets.create_view(Actor.owner_ui(), %{name: "Income"})

    {:ok, view, _html} = live(conn, "/buckets")

    menu_click(view, "view", v.id, "edit_view_buckets")

    assert has_element?(view, "#view-bucket-modal")

    # The view vanishes behind the open modal.
    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), v)

    html =
      view
      |> form("#view-bucket-form", %{"include_all" => "true"})
      |> render_submit()

    refute html =~ "status-toast"
    assert has_element?(view, "#buckets-workspace")
  end

  test "creating a bucket with no color keeps the bucket colorless", %{conn: conn} do
    world()

    {:ok, view, _html} = live(conn, "/buckets")

    view
    |> form("#bucket-form", bucket: %{name: "Plain", color: ""})
    |> render_submit()

    plain = Enum.find(Buckets.list_buckets(), &(&1.name == "Plain"))
    assert plain
    assert plain.color == nil
  end

  # User story (#802):
  # As a local portfolio maintainer opening the Views page,
  # I want the page to read list-first — each view's row saying what it does
  # and what it covers, each bucket's row carrying its colour and where it is
  # used — with the explanation behind an ⓘ and the forms behind "+",
  # so that the page is a reading surface, not a tutorial with forms.
  #
  # Acceptance criteria:
  # - No paragraph above the first section; each heading carries a basis line
  #   and an ⓘ holding the two-step explanation.
  # - View rows show the rule (include/exclude buckets as chips) and the
  #   covered total / positions / accounts; the "Everything" row is marked
  #   as the default; bucket rows show swatch and usage.
  # - Row actions sit in the row menu; both create forms are closed
  #   disclosures opened by "+"; the assignment section is gone and its edit
  #   path is the account row on Accounts & depots (link in the basis line).
  describe "read-first rows (#802)" do
    alias Portfolixir.WorldFixtures

    defp text(nodes),
      do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

    # Two depots on one cash account: "Depot" holds ACME (100) and BETA (50),
    # "Crypto Depot" holds COIN (30) under the Crypto bucket; 1,000 cash.
    defp seeded do
      world = WorldFixtures.base_world(name: "Main", cash_name: "Giro", depot_name: "Depot")
      acme = WorldFixtures.create_security!(name: "ACME", ticker: "ACME")
      beta = WorldFixtures.create_security!(name: "BETA", ticker: "BETA")
      coin = WorldFixtures.create_security!(name: "COIN", ticker: "COIN")
      WorldFixtures.deposit!(world, "1000", ~D[2026-01-02], [])
      WorldFixtures.buy!(world, acme, quantity: "1", price: "90", date: ~D[2026-01-05])
      WorldFixtures.buy!(world, beta, quantity: "1", price: "40", date: ~D[2026-01-05])
      WorldFixtures.put_quote!(acme, Date.utc_today(), "100")
      WorldFixtures.put_quote!(beta, Date.utc_today(), "50")
      WorldFixtures.put_quote!(coin, Date.utc_today(), "30")

      %{depot: crypto_depot} =
        WorldFixtures.add_depot(world.portfolio,
          depot_name: "Crypto Depot",
          cash_name: "Crypto Cash"
        )

      {:ok, _} =
        Portfolixir.Ledger.create_transaction(Actor.owner_ui(), %{
          portfolio_id: world.portfolio.id,
          securities_account_id: crypto_depot.id,
          security_id: coin.id,
          type: "inbound_delivery",
          date: ~D[2026-01-06],
          quantity: "1",
          currency_code: "EUR"
        })

      {:ok, crypto} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Crypto", color: "#f59e0b"})
      {:ok, household} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Household"})
      :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), crypto_depot, [crypto.id])

      {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Without crypto"})
      :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [], [crypto.id])

      Map.merge(world, %{
        crypto: crypto,
        household: household,
        view: view,
        crypto_depot: crypto_depot,
        acme: acme
      })
    end

    test "list-first: no paragraph, basis lines and ⓘ per heading, forms behind +", %{
      conn: conn
    } do
      seeded()
      {:ok, live, html} = live(conn, "/buckets")
      doc = Floki.parse_document!(html)

      assert Floki.find(doc, ~s([data-role="how-it-works"])) == []
      assert Floki.find(doc, ".workspace-page p.section-hint") == []
      assert Floki.find(doc, ".workspace-page p.muted") == []
      assert Floki.find(doc, "#assignment-section") == []

      assert text(Floki.find(doc, ~s([data-role="views-info"] p))) =~ "Create buckets"
      assert [_] = Floki.find(doc, ~s([data-role="buckets-info"] [data-role="overlap-hint"]))
      assert text(Floki.find(doc, ~s([data-role="views-basis"]))) =~ "view switcher"
      assert text(Floki.find(doc, ~s([data-role="buckets-basis"]))) =~ "not a sum"

      # Views before buckets: the list the switcher shows comes first.
      assert :binary.match(html, ~s(id="views-section")) |> elem(0) <
               :binary.match(html, ~s(id="buckets-section")) |> elem(0)

      # Both forms behind "+", closed by default.
      assert [_] = Floki.find(doc, "#view-form-panel[hidden] #view-form")
      assert [_] = Floki.find(doc, "#bucket-form-panel[hidden] #bucket-form")
      live |> element(~s(button[aria-controls="view-form-panel"])) |> render_click()
      opened = Floki.parse_document!(render(live))
      assert Floki.find(opened, "#view-form-panel[hidden]") == []

      assert [_] =
               Floki.find(
                 opened,
                 ~s(button[aria-controls="view-form-panel"][aria-expanded="true"])
               )
    end

    test "view rows say what they do and what they cover; Everything is the default", %{
      conn: conn
    } do
      %{view: view} = seeded()
      {:ok, _live, html} = live(conn, "/buckets")
      doc = Floki.parse_document!(html)

      everything = Floki.find(doc, "#view-everything")
      assert [_] = Floki.find(everything, ~s([data-role="view-default"]))
      assert text(Floki.find(everything, ~s([data-role="view-rule"]))) =~ "no filters"
      figures = text(Floki.find(everything, ~s([data-role="view-figures"])))
      # 870 cash left after the two buys + 100 + 50 + 30; three positions in
      # two depots plus two cash accounts.
      assert figures =~ "1,050.00"
      assert figures =~ "3 positions"
      assert figures =~ "4 accounts"

      row = Floki.find(doc, "#view-#{view.id}")
      rule = Floki.find(row, ~s([data-role="view-rule"]))
      assert text(rule) =~ "except"
      assert text(Floki.find(rule, ".badge")) == "Crypto"
      figures = text(Floki.find(row, ~s([data-role="view-figures"])))
      assert figures =~ "1,020.00"
      assert figures =~ "2 positions"
      assert figures =~ "3 accounts"
      assert Floki.find(row, ~s([data-role="view-default"])) == []
    end

    test "bucket rows carry swatch and usage; the basis line points at the account row", %{
      conn: conn
    } do
      %{
        crypto: crypto,
        household: household,
        crypto_depot: crypto_depot,
        depot: depot,
        acme: acme
      } =
        seeded()

      # A direct override: ACME in the main depot tagged Household by hand.
      :ok = Buckets.set_position_override(Actor.owner_ui(), depot, acme, [household.id])

      {:ok, _live, html} = live(conn, "/buckets")
      doc = Floki.parse_document!(html)

      crypto_row = Floki.find(doc, "#bucket-#{crypto.id}")
      assert [swatch] = Floki.find(crypto_row, ".cat-swatch")
      assert Floki.attribute(swatch, "style") == ["background:#f59e0b"]
      usage = text(Floki.find(crypto_row, ~s([data-role="bucket-usage"])))
      assert usage =~ "Default on Crypto Depot"
      assert usage =~ "1 position inherits"

      household_row = Floki.find(doc, "#bucket-#{household.id}")
      usage = text(Floki.find(household_row, ~s([data-role="bucket-usage"])))
      assert usage =~ "1 position directly: ACME"
      assert usage =~ "no default"

      basis = Floki.find(doc, ~s([data-role="assignment-basis"]))
      assert [_] = Floki.find(basis, ~s(a[href="/portfolios"]))
      # The accounts without a default bucket are named; the crypto depot is not.
      assert text(basis) =~ "Depot"
      assert text(basis) =~ "Giro"
      refute text(basis) =~ crypto_depot.name <> ","
    end

    test "row actions sit in the row menu", %{conn: conn} do
      %{view: view, crypto: crypto} = seeded()
      {:ok, live, html} = live(conn, "/buckets")
      doc = Floki.parse_document!(html)

      assert Floki.find(doc, ~s(#view-#{view.id} button[phx-click="delete_view"])) == []
      assert Floki.find(doc, ~s(#bucket-#{crypto.id} button[phx-click="delete_bucket"])) == []

      live
      |> element(~s(button.row-actions__kebab[phx-value-kind="view"][phx-value-id="#{view.id}"]))
      |> render_click()

      menu = Floki.parse_document!(render(live)) |> Floki.find(~s([role="menu"]))
      assert text(menu) =~ "Edit buckets"
      assert text(menu) =~ "Rename"
      assert [_] = Floki.find(menu, ~s(button[phx-click="delete_view"][data-confirm]))

      live
      |> element(
        ~s(button.row-actions__kebab[phx-value-kind="bucket"][phx-value-id="#{crypto.id}"])
      )
      |> render_click()

      menu = Floki.parse_document!(render(live)) |> Floki.find(~s([role="menu"]))
      assert text(menu) =~ "Rename"
      assert [_] = Floki.find(menu, ~s(button[phx-click="delete_bucket"][data-confirm]))
    end

    # User story (E25 S6, G19, decision T-10; board 12, before/after):
    # As the operator deleting a bucket some positions carry as their own,
    # I want the confirm to say that a position whose only specific bucket
    # this is stays at "no buckets (excluded)",
    # so that I know it will not start inheriting its depot's buckets and
    # appear in views it was not in.
    #
    # Acceptance criteria:
    # - The bucket delete's confirm keeps the removal sentence and adds the
    #   board's sentence, in the words the position itself shows.
    test "the bucket delete confirm says an emptied position stays excluded", %{conn: conn} do
      %{crypto: crypto} = seeded()
      {:ok, live, _html} = live(conn, "/buckets")

      live
      |> element(
        ~s(button.row-actions__kebab[phx-value-kind="bucket"][phx-value-id="#{crypto.id}"])
      )
      |> render_click()

      [button] =
        Floki.parse_document!(render(live))
        |> Floki.find(~s([role="menu"] button[phx-click="delete_bucket"]))

      [confirm] = Floki.attribute(button, "data-confirm")
      assert confirm =~ "It is removed from every assignment and view."

      assert confirm =~
               "A position whose only specific bucket is this one stays at " <>
                 "“no buckets (excluded)” and does not inherit from its depot."
    end
  end

  # User story (#836):
  # As a local portfolio maintainer using a screen reader,
  # I want a view's or bucket's actions button to announce whether its menu
  # is open,
  # so that I hear "collapsed" or "expanded" instead of nothing at all.
  #
  # Acceptance criteria:
  # - Both row kebabs render `aria-expanded="false"` closed and `"true"` open,
  #   never a valueless attribute and never no attribute at all.
  test "the view and bucket row kebabs render aria-expanded as a string in both states",
       %{conn: conn} do
    world()
    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})
    {:ok, saved} = Buckets.create_view(Actor.owner_ui(), %{name: "Everything", include_all: true})

    {:ok, view, _html} = live(conn, "/buckets")

    for kebab <- ["#view-kebab-#{saved.id}", "#bucket-kebab-#{bucket.id}"] do
      assert view |> element(kebab) |> render() =~ ~s(aria-expanded="false")

      view |> element(kebab) |> render_click()
      assert view |> element(kebab) |> render() =~ ~s(aria-expanded="true")
    end
  end
end
