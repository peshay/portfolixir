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
    view
    |> element("button[phx-value-id='#{created.id}'][phx-click='edit_view_buckets']")
    |> render_click()

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

    view
    |> element("button[phx-value-id='#{bucket.id}'][phx-click='edit_bucket']")
    |> render_click()

    view
    |> form("#bucket-#{bucket.id} form", bucket: %{name: "Foundation"})
    |> render_submit()

    assert Buckets.get_bucket(bucket.id).name == "Foundation"

    view
    |> element("button[phx-value-id='#{bucket.id}'][phx-click='delete_bucket']")
    |> render_click()

    assert Buckets.get_bucket(bucket.id) == nil
  end

  test "renames and deletes a view", %{conn: conn} do
    world()
    {:ok, v} = Buckets.create_view(Actor.owner_ui(), %{name: "Old"})

    {:ok, view, _html} = live(conn, "/buckets")

    view |> element("button[phx-value-id='#{v.id}'][phx-click='edit_view']") |> render_click()

    view
    |> form("#view-#{v.id} form", view: %{name: "New"})
    |> render_submit()

    assert Buckets.get_view(v.id).name == "New"

    view |> element("button[phx-value-id='#{v.id}'][phx-click='delete_view']") |> render_click()
    assert Buckets.get_view(v.id) == nil
  end

  test "assigns a bucket set to a cash account", %{conn: conn} do
    %{cash: cash} = world()
    {:ok, reserve} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Reserve"})

    {:ok, view, _html} = live(conn, "/buckets")

    view
    |> form("#cash-assignment-#{cash.id} form", %{"bucket_ids" => ["#{reserve.id}"]})
    |> render_submit()

    assert Buckets.cash_account_bucket_ids(cash.id) == [reserve.id]
  end

  # User story:
  # As a local portfolio maintainer,
  # I want to set a default bucket set on a depot,
  # so that positions in that depot inherit a sensible scope.
  #
  # Acceptance criteria:
  # - Submitting the depot form writes the depot's default bucket ids.
  test "assigns a default bucket set to a depot", %{conn: conn} do
    %{depot: depot} = world()
    {:ok, core} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})

    {:ok, view, _html} = live(conn, "/buckets")

    view
    |> form("#depot-assignment-#{depot.id} form", %{"bucket_ids" => ["#{core.id}"]})
    |> render_submit()

    assert Buckets.depot_default_bucket_ids(depot.id) == [core.id]
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

    view
    |> element("button[phx-value-id='#{bucket.id}'][phx-click='edit_bucket']")
    |> render_click()

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

    view |> element("button[phx-value-id='#{v.id}'][phx-click='edit_view']") |> render_click()

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

    view
    |> element("button[phx-value-id='#{bucket.id}'][phx-click='edit_bucket']")
    |> render_click()

    assert has_element?(view, "#bucket-#{bucket.id} form[phx-submit='rename_bucket']")

    view |> element("button[phx-click='cancel_edit_bucket']") |> render_click()
    refute has_element?(view, "#bucket-#{bucket.id} form[phx-submit='rename_bucket']")

    view |> element("button[phx-value-id='#{v.id}'][phx-click='edit_view']") |> render_click()
    assert has_element?(view, "#view-#{v.id} form[phx-submit='rename_view']")

    view |> element("button[phx-click='cancel_edit_view']") |> render_click()
    refute has_element?(view, "#view-#{v.id} form[phx-submit='rename_view']")
  end

  test "the bucket picker modal can be closed without saving", %{conn: conn} do
    world()
    {:ok, v} = Buckets.create_view(Actor.owner_ui(), %{name: "Income"})

    {:ok, view, _html} = live(conn, "/buckets")

    view
    |> element("button[phx-value-id='#{v.id}'][phx-click='edit_view_buckets']")
    |> render_click()

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

    view
    |> element("button[phx-value-id='#{v.id}'][phx-click='edit_view_buckets']")
    |> render_click()

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

  test "saving depot defaults with a stale bucket id surfaces a friendly error", %{conn: conn} do
    %{depot: depot} = world()
    {:ok, core} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})

    {:ok, view, _html} = live(conn, "/buckets")

    {:ok, _} = Buckets.delete_bucket(Actor.owner_ui(), core)

    html =
      view
      |> form("#depot-assignment-#{depot.id} form", %{"bucket_ids" => ["#{core.id}"]})
      |> render_submit()

    assert html =~ "That bucket no longer exists"
    assert Buckets.depot_default_bucket_ids(depot.id) == []
  end

  test "saving cash-account buckets with a stale bucket id surfaces a friendly error",
       %{conn: conn} do
    %{cash: cash} = world()
    {:ok, core} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})

    {:ok, view, _html} = live(conn, "/buckets")

    {:ok, _} = Buckets.delete_bucket(Actor.owner_ui(), core)

    html =
      view
      |> form("#cash-assignment-#{cash.id} form", %{"bucket_ids" => ["#{core.id}"]})
      |> render_submit()

    assert html =~ "That bucket no longer exists"
    assert Buckets.cash_account_bucket_ids(cash.id) == []
  end

  test "the include-all toggle live-previews the include checklist", %{conn: conn} do
    world()
    {:ok, _core} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})
    {:ok, v} = Buckets.create_view(Actor.owner_ui(), %{name: "Income"})

    {:ok, view, _html} = live(conn, "/buckets")

    view
    |> element("button[phx-value-id='#{v.id}'][phx-click='edit_view_buckets']")
    |> render_click()

    # include_all defaults on, so the include checklist is hidden.
    refute has_element?(view, "#view-bucket-form legend", "Include buckets")

    view
    |> form("#view-bucket-form", %{"include_all" => "false"})
    |> render_change()

    assert has_element?(view, "#view-bucket-form legend", "Include buckets")
  end

  # User story:
  # As a local portfolio maintainer with no accounts yet,
  # I want the assignment section to explain what to create first,
  # so that an empty install does not look broken (and never asks for a
  # portfolio — ADR-0024).
  #
  # Acceptance criteria:
  # - With no depots/cash accounts the assignment section shows the
  #   create-first hint, pointing at depot + cash account.
  test "with no accounts the assignment section shows the create-first hint", %{conn: conn} do
    {:ok, view, html} = live(conn, "/buckets")

    assert html =~ "Create a depot and a cash account to assign buckets."
    refute html =~ "Create a portfolio"
    refute has_element?(view, "#depot-assignment-list")
  end

  test "a cash account without any depot shows the depot list's empty state",
       %{conn: conn} do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Empty",
        base_currency_code: "EUR"
      })

    {:ok, _cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Solo Cash",
        currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/buckets")

    assert has_element?(view, "#depot-assignment-list .hint", "No depots yet.")
    assert has_element?(view, "#cash-assignment-list", "Solo Cash")
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
    view
    |> element("button[phx-value-id='#{bucket.id}'][phx-click='edit_bucket']")
    |> render_click()

    view |> element("button[phx-value-id='#{v.id}'][phx-click='edit_view']") |> render_click()

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

  test "deleting or editing-buckets of a vanished bucket or view is a silent no-op",
       %{conn: conn} do
    world()
    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})
    {:ok, v} = Buckets.create_view(Actor.owner_ui(), %{name: "Income"})

    {:ok, view, _html} = live(conn, "/buckets")

    # Records vanish behind the open (non-edit-mode) page, so the delete and
    # edit-buckets controls are still rendered with valid integer ids.
    {:ok, _} = Buckets.delete_bucket(Actor.owner_ui(), bucket)
    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), v)

    view
    |> element("button[phx-value-id='#{bucket.id}'][phx-click='delete_bucket']")
    |> render_click()

    view
    |> element("button[phx-value-id='#{v.id}'][phx-click='edit_view_buckets']")
    |> render_click()

    refute has_element?(view, "#view-bucket-modal")
    assert has_element?(view, "#buckets-workspace")
  end

  test "saving the bucket picker for a vanished view is a no-op", %{conn: conn} do
    world()
    {:ok, v} = Buckets.create_view(Actor.owner_ui(), %{name: "Income"})

    {:ok, view, _html} = live(conn, "/buckets")

    view
    |> element("button[phx-value-id='#{v.id}'][phx-click='edit_view_buckets']")
    |> render_click()

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
end
