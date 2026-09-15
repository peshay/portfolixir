defmodule PortfolixirWeb.WealthKpiBandTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.WorldFixtures

  # User story (#797, review C1 — variant A, picked 2026-09-14):
  # As a local portfolio maintainer reading the Wealth key figures,
  # I want the band composed as two tiers — three lead figures at full size
  # (total, TTWROR, IRR) over four supporting figures at half height — with
  # the currency as a small suffix and every second figure on a sub-line,
  # so that "how much is it, and how has it developed" reads first and no
  # value ever wraps to a second line.
  #
  # Acceptance criteria:
  # - One band section: a lead tier (#kpi-total, #kpi-ttwror, #kpi-irr) and a
  #   support tier (#kpi-securities, #kpi-cash, #kpi-invested, #kpi-multiple).
  #   The seven ids, the ⓘ tooltips and the count-up slots stay.
  # - The currency renders as `<small class="value-suffix">` after the digits.
  #   No value combines two figures with "·" any more: the total's
  #   composition, the cash amount, the net flows and the period gain sit on
  #   sub-lines.
  # - The Allocation & targets tab does not repeat the band: it carries one
  #   summary line (total · cash quote · TTWROR) linking back to Holdings,
  #   keeping the picked view.

  # Securities 8 × 110 = 880, cash 1000 − 800 = 200, total 1,080, cash quote
  # 18.5 %; TTWROR 1,000 → 1,080 with the deposit neutralised = +8.0 %, the
  # period gain +80.00; opening value 0 (everything inside the 1Y window).
  defp world do
    Classifications.ensure_builtins()
    world = WorldFixtures.base_world(name: "Band", cash_name: "Giro", depot_name: "Depot")
    security = WorldFixtures.create_security!(name: "World ETF", ticker: "WLD")
    today = Date.utc_today()
    start = Date.add(today, -10)

    WorldFixtures.deposit!(world, "1000", start)
    WorldFixtures.buy!(world, security, quantity: "8", price: "100", date: start)
    WorldFixtures.put_quotes!(security, [{start, "100"}, {today, "110"}])
    world
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp classes(node), do: node |> Floki.attribute("class") |> Enum.flat_map(&String.split/1)
  defp ids(nodes), do: Enum.flat_map(nodes, &Floki.attribute(&1, "id"))

  defp document(view), do: view |> render() |> Floki.parse_document!()

  test "the band is two tiers: three lead figures over four supporting ones", %{conn: conn} do
    world()

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)
    doc = document(view)

    assert [band] = Floki.find(doc, "section.kpi-band")

    lead = Floki.find(band, ".kpi-band__lead > article.stat")
    assert ids(lead) == ["kpi-total", "kpi-ttwror", "kpi-irr"]
    assert Enum.all?(lead, &("stat--lead" in classes(&1)))

    support = Floki.find(band, ".kpi-band__support > article.stat")
    assert ids(support) == ["kpi-securities", "kpi-cash", "kpi-invested", "kpi-multiple"]
    assert Enum.all?(support, &("stat--compact" in classes(&1)))

    # The currency is a small suffix after the digits; the digits keep their
    # count-up slot and the composition moves to the sub-line.
    total = Floki.find(band, "#kpi-total")
    assert text(Floki.find(total, "strong .value-suffix")) == "EUR"
    assert text(Floki.find(total, "strong")) == "1,080.00 EUR"
    assert [_] = Floki.find(total, ~s(#count-kpi-total[phx-hook="CountUp"]))
    assert text(Floki.find(total, ".stat__sub")) == "Securities 880.00 · Cash 200.00"

    # No value combines two figures any more.
    cash = Floki.find(band, "#kpi-cash")
    assert text(Floki.find(cash, "strong")) == "18.5%"
    assert text(Floki.find(cash, ".stat__sub")) == "200.00 EUR cash"
    assert [_] = Floki.find(cash, "details.metric-tooltip")

    invested = Floki.find(band, "#kpi-invested")
    assert text(Floki.find(invested, "strong")) == "0.00 EUR"
    assert text(Floki.find(invested, ".stat__sub")) == "net flows +1,000.00 EUR"

    securities = Floki.find(band, "#kpi-securities")
    assert text(Floki.find(securities, "strong")) == "880.00 EUR"
    assert [_] = Floki.find(securities, ~s(#count-kpi-securities[phx-hook="CountUp"]))

    ttwror = Floki.find(band, "#kpi-ttwror")
    assert text(Floki.find(ttwror, "strong")) == "+8.0%"
    assert text(Floki.find(ttwror, ".stat__sub")) == "+80.00 EUR in the period"
    assert [_] = Floki.find(ttwror, "details.metric-tooltip")

    # A ten-day window shows the period MWR, and the sub-line says so.
    irr = Floki.find(band, "#kpi-irr")
    assert text(Floki.find(irr, "strong")) == "+8.0%"
    assert text(Floki.find(irr, ".stat__sub")) =~ "not annualized · as of "

    multiple = Floki.find(band, "#kpi-multiple")
    assert text(Floki.find(multiple, "strong")) == "×1.08"
    assert [_] = Floki.find(multiple, "details.metric-tooltip")
  end

  test "the Allocation tab carries one summary line instead of the band", %{conn: conn} do
    world()

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
    render_async(view)
    doc = document(view)

    assert Floki.find(doc, "section.kpi-band") == []
    assert Floki.find(doc, "#kpi-total") == []

    assert [summary] = Floki.find(doc, ~s([data-role="kpi-summary"]))
    line = text(summary)
    assert line =~ "Total incl. cash 1,080.00 EUR"
    assert line =~ "Cash quote 18.5%"
    assert line =~ "TTWROR 1Y +8.0%"
    assert [link] = Floki.find(summary, ~s(a[href="/portfolio"]))
    assert text(link) == "All key figures → Holdings"

    # The link keeps the picked view.
    {:ok, mine} = Buckets.create_view(Actor.owner_ui(), %{name: "Mine", include_all: true})
    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation&view=#{mine.id}")
    render_async(view)
    doc = document(view)

    assert [_] =
             Floki.find(doc, ~s([data-role="kpi-summary"] a[href="/portfolio?view=#{mine.id}"]))

    # German where the page is.
    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation&locale=de")
    render_async(view)
    line = view |> document() |> Floki.find(~s([data-role="kpi-summary"])) |> text()
    assert line =~ "Gesamt inkl. Cash 1.080,00 EUR"
    assert line =~ "Cashquote 18,5%"
    assert line =~ "Alle Kennzahlen → Bestände"
  end
end
