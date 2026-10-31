defmodule PortfolixirWeb.TwinNamesSweepTest do
  # Sprint 21 γ8, board ux-design-2026-10-09/08-shared-copy, N14 (#1155):
  # the twin-name rule of DESIGN.md → "Twin names" (`SecurityNames`, issue
  # 1057) on the surfaces Sprint 19 did not reach. Two securities stored under
  # one name each carry the identifier that tells them apart after the name
  # (`.twin-id`, ISIN, else WKN, else the number); a unique name stays bare.
  # Every name and identifier is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Clock
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.WorldFixtures

  # ISINs are unique instance-wide and async modules write at the same time
  # (#1018): these are this module's own.
  @arbolia_a "XSG8TWIN0002"
  @arbolia_b "XSG8TWIN0010"
  @larkspur "XSG8TWIN0028"

  defp security!(name, isin) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        isin: isin,
        currency_code: "EUR",
        asset_class: "equity"
      })

    security
  end

  # "Arbolia Inc." twice (two ISINs) and "Larkspur Rail AG" once, each bought
  # and partly sold, quoted at both ends, in one category of a plan.
  defp twin_world do
    world = WorldFixtures.base_world(name: "Twins", cash_name: "Giro", depot_name: "Depot")
    start = Date.add(Clock.today(), -20)
    sold = Date.add(Clock.today(), -5)

    arbolia_a = security!("Arbolia Inc.", @arbolia_a)
    arbolia_b = security!("Arbolia Inc.", @arbolia_b)
    larkspur = security!("Larkspur Rail AG", @larkspur)

    WorldFixtures.deposit!(world, "10000", start)

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core",
        color: "#2563eb"
      })

    for security <- [arbolia_a, arbolia_b, larkspur] do
      WorldFixtures.buy!(world, security, quantity: "4", price: "100", date: start)
      WorldFixtures.sell!(world, security, quantity: "1", price: "110", date: sold)
      WorldFixtures.put_quotes!(security, [{start, "100"}, {Clock.today(), "110"}])

      {:ok, _} =
        Classifications.assign_security(
          Actor.owner_ui(),
          security.id,
          classification.id,
          core.id
        )
    end

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), world.portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.6"}
      ])

    {:ok, _} = Portfolios.set_cash_target(Actor.owner_ui(), world.portfolio, Decimal.new("0.4"))

    Map.put(world, :classification, classification)
  end

  defp settle(view), do: Enum.each(1..4, fn _round -> render_async(view) end)

  # The text of every element `selector` matches, its whitespace squeezed.
  # The test DOM drops a whitespace-only text node between two elements (the
  # space between a `<bdi>` name and its `.twin-id`), so the parts are joined
  # by a space, as the browser shows them.
  defp texts(view, selector) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(selector)
    |> Enum.map(&(&1 |> Floki.text(sep: " ") |> String.split() |> Enum.join(" ")))
  end

  defp tagged?(texts),
    do:
      Enum.sort(texts) == [
        "Arbolia Inc. ISIN #{@arbolia_a}",
        "Arbolia Inc. ISIN #{@arbolia_b}"
      ]

  # User story (#1155, Sprint 21 γ8; board 08, N14, the tables):
  # As the operator reading my bookings, my closed trades and my allocation,
  # I want two securities stored under one name told apart where they are
  # listed,
  # so that the history, the trades and the allocation never read as one
  # security printed twice.
  #
  # Acceptance criteria:
  # - The history's security cell and its phone row: each twin's name carries
  #   its ISIN (`.twin-id`, a visually hidden "ISIN" before the value); the
  #   unique name stays bare. Decided over the loaded history.
  # - Cash flow → closed trades, the table and its phone rows, the same.
  # - Wealth's allocation tree position rows and the flat positions, the same.
  # - The Overview's "Closed trades" card, the same.
  test "the history, the trades, the allocation and the Overview tag a twin", %{conn: conn} do
    world = twin_world()

    {:ok, history, _html} = live(conn, "/transactions")

    cells = texts(history, "#transaction-list [data-role='history-security']")
    assert cells |> Enum.filter(&(&1 =~ "Arbolia")) |> Enum.uniq() |> tagged?()
    assert "Larkspur Rail AG" in cells

    phone = texts(history, "#transaction-phone-rows [data-role='phone-subject']")
    assert phone |> Enum.filter(&(&1 =~ "Arbolia")) |> Enum.uniq() |> tagged?()
    assert "Larkspur Rail AG" in phone

    {:ok, trades, _html} = live(conn, "/cashflow?tab=realized")
    settle(trades)

    names = texts(trades, "[data-role='realized-trade'] [data-role='trade-name']")
    assert names |> Enum.filter(&(&1 =~ "Arbolia")) |> tagged?()
    assert "Larkspur Rail AG" in names

    phone = texts(trades, "#realized-trades-phone-rows .phone-row__name")
    assert phone |> Enum.filter(&(&1 =~ "Arbolia")) |> tagged?()
    assert "Larkspur Rail AG" in phone

    {:ok, flat, _html} =
      live(
        conn,
        "/portfolio?tab=allocation&classification=#{world.classification.id}&alloc=positions"
      )

    settle(flat)

    names = texts(flat, "[data-role='flat-position'] [data-role='position-name']")
    assert names |> Enum.filter(&(&1 =~ "Arbolia")) |> tagged?()
    assert "Larkspur Rail AG" in names

    {:ok, tree, _html} =
      live(conn, "/portfolio?tab=allocation&classification=#{world.classification.id}")

    settle(tree)
    tree |> element(~s(.drift-table [data-role="toggle-positions"])) |> render_click()

    names = texts(tree, "[data-role='allocation-position'] [data-role='position-name']")
    assert names |> Enum.filter(&(&1 =~ "Arbolia")) |> tagged?()
    assert "Larkspur Rail AG" in names

    {:ok, overview, _html} = live(conn, "/")
    settle(overview)

    # The card's name line carries its "sold …" sub-line after the name.
    names = texts(overview, "#dashboard-trades [data-role='closed-trade'] .attention-name")
    assert Enum.any?(names, &String.starts_with?(&1, "Arbolia Inc. ISIN #{@arbolia_a} sold"))
    assert Enum.any?(names, &String.starts_with?(&1, "Arbolia Inc. ISIN #{@arbolia_b} sold"))
    assert Enum.any?(names, &String.starts_with?(&1, "Larkspur Rail AG sold"))
  end
end
