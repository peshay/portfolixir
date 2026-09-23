defmodule PortfolixirWeb.ColumnPickerConvergenceTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3]

  alias Portfolixir.Classifications

  setup do
    Classifications.ensure_builtins()
    world = base_world(name: "Picker World")
    security = create_security!(name: "Picker Co", ticker: "PKR", isin: "DE000PICKER1")
    deposit!(world, "10000", ~D[2026-01-01])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])
    put_quote!(security, ~D[2026-01-06], "120")
    :ok
  end

  @surfaces [
    {"/transactions", "#tx-column-toggle", "tx-column-picker", "#tx-column-form"},
    {"/portfolio", "#holdings-column-toggle", "holdings-column-picker", "#holdings-column-form"},
    {"/securities", "#toggle-column-popover", "column-picker", "#securities-column-form"}
  ]

  # User story (#850; DESIGN.md → Inventory → Overlays, pick E3 of board
  # ux-design-2026-09-20/03-column-picker):
  # As the operator shaping a table,
  # I want every column picker to be the same popover with its columns
  # grouped,
  # so that choosing columns looks and works alike on every list, and a
  # picker never pushes the table down when it opens.
  #
  # Acceptance criteria:
  # - The transaction history's and Wealth Positions' pickers are
  #   `.popover.column-picker` with role="dialog", an aria-label, a
  #   `.popover-head` heading and the columns in `<fieldset>`/`<legend>`
  #   groups — the securities list's treatment, from one shared component.
  # - A toggle button opens it and reports aria-expanded; the popover closes
  #   from its close button and on Escape.
  # - No column picker in the web layer is a `<details>` any more.
  # - The picked columns still apply through the form, as before.
  test "every column picker is the shared grouped popover, opened by its toggle", %{conn: conn} do
    for {path, toggle, id, form} <- @surfaces do
      {:ok, view, _html} = live(conn, path)
      render_async(view)

      refute has_element?(view, "##{id}"), "#{path}: the picker renders before it is opened"
      assert view |> element(toggle) |> render() =~ ~s(aria-expanded="false")

      view |> element(toggle) |> render_click()

      assert view |> element(toggle) |> render() =~ ~s(aria-expanded="true")

      assert has_element?(
               view,
               ~s(##{id}.popover.column-picker[role="dialog"][aria-label])
             ),
             "#{path}: the picker is not the shared popover"

      assert has_element?(view, "##{id} .popover-head h3")
      assert has_element?(view, "##{id} #{form}")

      legends = view |> render() |> Floki.parse_document!() |> Floki.find("##{id} legend")
      assert length(legends) >= 2, "#{path}: the columns are not grouped"

      view |> element("##{id} [data-role=column-picker-close]") |> render_click()
      refute has_element?(view, "##{id}"), "#{path}: the close button did not close it"

      view |> element(toggle) |> render_click()
      view |> element("##{id}") |> render_keydown(%{"key" => "Escape"})
      refute has_element?(view, "##{id}"), "#{path}: Escape did not close it"
    end
  end

  test "the grouping offers every column the table can show, once", %{conn: conn} do
    for {path, toggle, id, keys} <- [
          {"/transactions", "#tx-column-toggle", "tx-column-picker",
           ~w(date type security quantity price gross_amount fees taxes currency notes)},
          {"/portfolio", "#holdings-column-toggle", "holdings-column-picker",
           ~w(depot security quantity isin wkn currency avg_cost latest_price market_value
              unrealized_pnl_abs unrealized_pnl_pct)}
        ] do
      {:ok, view, _html} = live(conn, path)
      render_async(view)
      view |> element(toggle) |> render_click()

      offered =
        view
        |> render()
        |> Floki.parse_document!()
        |> Floki.find(~s(##{id} input[type="checkbox"]))
        |> Floki.attribute("value")

      assert Enum.sort(offered) == Enum.sort(keys), "#{path} offers #{inspect(offered)}"
    end
  end

  test "the component left the Securities namespace and no picker is a details" do
    assert Code.ensure_loaded?(PortfolixirWeb.ColumnPicker)
    refute Code.ensure_loaded?(PortfolixirWeb.Securities.ColumnPicker)

    for path <- Path.wildcard("lib/portfolixir_web/**/*.ex") do
      refute File.read!(path) =~ ~r/<details[^>]*column-picker/,
             "#{path} still builds a column picker on <details>"
    end
  end
end
