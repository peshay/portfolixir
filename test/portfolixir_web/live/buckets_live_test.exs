defmodule PortfolixirWeb.BucketsLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Portfolios

  defp world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Main", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Giro",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
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
  # I want a Buckets & Views page to create and manage buckets,
  # so that I can tag holdings without touching the API.
  #
  # Acceptance criteria:
  # - Submitting the bucket form creates the bucket through the context.
  # - The new bucket is rendered in the bucket list.
  test "creates a bucket", %{conn: conn} do
    world()

    {:ok, view, _html} = live(conn, "/buckets")

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

    filter = Buckets.view_filter(created.id)
    assert filter.include == [core.id]
    assert filter.exclude == [spec.id]
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
end
