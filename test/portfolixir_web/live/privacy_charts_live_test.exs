defmodule PortfolixirWeb.PrivacyChartsLiveTest do
  # Sprint 26 P2 (I22, FR-51; board 02 "charts in the privacy mode", look
  # C): while the mode is on, a euro axis becomes percent of the window's
  # start, built on the server (SecurityChart's percent view), the security
  # chart is held in its percent view, and no tooltip, title or payload
  # names an amount or a quantity. The walk over every page is
  # test/browser/privacy_leak_test.exs.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures
  import PortfolixirWeb.PreferenceCookieHelpers

  alias Portfolixir.Actor
  alias Portfolixir.Ledger

  # A position bought at 42.10 with quotes over a window, a dividend of
  # 123.45, all in EUR.
  setup do
    world = base_world(name: "Privacy Charts")
    deposit!(world, "5000", ~D[2026-01-02])
    security = create_security!(name: "Chart Fixture AG", ticker: "CFX")
    buy!(world, security, quantity: "30", price: "42.10", date: ~D[2026-01-05])

    put_quotes!(security, [
      {~D[2026-01-05], "42.10"},
      {~D[2026-01-20], "44.55"},
      {~D[2026-02-10], "47.80"},
      {~D[2026-03-02], "46.25"}
    ])

    {:ok, _dividend} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        type: "dividend",
        portfolio_id: world.portfolio.id,
        security_id: security.id,
        cash_account_id: world.cash.id,
        gross_amount: "123.45",
        currency_code: "EUR",
        date: ~D[2026-02-15]
      })

    {:ok, _tree} =
      Portfolixir.Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    %{security: security}
  end

  defp masked_conn, do: build_conn() |> put_preference_cookie("portfolixir_privacy", "on")

  defp payloads(html) do
    ~r/<script type="application\/json" data-chart-payload[^>]*>(.*?)<\/script>/s
    |> Regex.scan(html, capture: :all_but_first)
    |> Enum.map(fn [json] -> Jason.decode!(json) end)
  end

  defp axis_labels(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(".chart-axis-y")
    |> Enum.map(&String.trim(LazyHTML.text(&1)))
  end

  # User story (P2):
  # As the operator showing a security's chart in the privacy mode,
  # I want the chart held in its percent view and its trades without a
  # quantity or price,
  # so that the line still tells the story and no figure reaches the screen.
  #
  # Acceptance criteria:
  # - The "Percent" toggle is pressed and locked, titled "Always on in
  #   privacy mode"; the log scale is off and locked with it.
  # - Every axis label is a percentage; no payload point names a price.
  # - A trade's payload carries no quantity and no price, and its tooltip
  #   line keeps the kind and hides both figures.
  test "the security chart is held in its percent view and its trades name no figure", %{
    security: security
  } do
    {:ok, view, _html} = masked_conn() |> live("/securities/#{security.id}?tab=chart")
    html = render(view)

    toggle = view |> element("#toggle-percent-mode") |> render()
    assert toggle =~ ~s(aria-pressed="true")
    assert toggle =~ "disabled"
    assert toggle =~ "Always on in privacy mode"
    assert view |> element("#toggle-log") |> render() =~ "disabled"

    labels = axis_labels(html)
    assert labels != []
    assert Enum.all?(labels, &String.ends_with?(&1, "%")), inspect(labels)

    [payload | _] = payloads(html)
    assert payload["mode"] == "percent"

    assert Enum.all?(payload["points"], fn [_, display | _] -> String.ends_with?(display, "%") end)

    [trade] = payload["txs"]
    refute Map.has_key?(trade, "quantity")
    refute Map.has_key?(trade, "price")
    refute trade["label"] =~ ~r/\d/
    assert trade["label"] =~ "Buy"

    refute html =~ "42.10"
    refute html =~ "47.80"
  end

  # User story (P2):
  # As the operator reading Wealth's performance in the privacy mode,
  # I want the value series in percent of the window's start, said to
  # include deposits,
  # so that I see its shape without its amount and do not take it for a
  # return.
  #
  # Acceptance criteria:
  # - The series' toggle reads "Value (%)".
  # - Its axis labels are percentages, a line under the chart says the
  #   value counts deposits and withdrawals, and each tooltip reads
  #   "TTWROR · Value +x%".
  # - The TTWROR series keeps its percent axis, and its tooltip's amount is
  #   the placeholder text.
  test "Wealth's value series is drawn in percent of the window's start" do
    {:ok, view, _html} = masked_conn() |> live("/portfolio")
    render_async(view)

    assert view |> element("#portfolio-performance button[phx-value-mode='value']") |> render() =~
             "Value (%)"

    [ttwror] = payloads(render(view))

    assert Enum.all?(ttwror["points"], fn [_, display | _] ->
             display =~ "· ••••" and not (display =~ ~r/\d{1,3}(,\d{3})*\.\d{2} EUR/)
           end)

    view |> element("#portfolio-performance button[phx-value-mode='value']") |> render_click()

    # The single line is the level „Gesamt“; „Kategorien“ is the default
    # (FR-56).
    html = view |> element("[data-role='stack-level'] a[data-level='total']") |> render_click()

    labels = axis_labels(html)
    assert labels != [] and Enum.all?(labels, &String.ends_with?(&1, "%")), inspect(labels)
    assert html =~ "deposits and withdrawals included"

    [value] = payloads(html)
    assert value["mode"] == "percent"
    assert Enum.all?(value["points"], fn [_, display | _] -> display =~ ~r/% · Value [+-]?\d/ end)
    refute html =~ "EUR</text>"
  end

  # User story (P2):
  # As the operator reading Cash flow's income bars in the privacy mode,
  # I want the bars to keep their heights and lose their amounts,
  # so that the years still compare while no amount is shown.
  #
  # Acceptance criteria:
  # - A bar's native tooltip keeps its year and its series and names no
  #   amount; the amount under a bar is the placeholder.
  test "Cash flow's bars keep their heights and name no amount" do
    {:ok, view, _html} = masked_conn() |> live("/cashflow")
    html = render_async(view)

    titles =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("svg title")
      |> Enum.map(&String.trim(LazyHTML.text(&1)))

    assert "2026 · Dividends" in titles, inspect(titles)
    refute Enum.any?(titles, &String.ends_with?(&1, ":")), inspect(titles)
    refute Enum.any?(titles, &(&1 =~ ~r/\d+\.\d{2}/)), inspect(titles)
    refute html =~ "123.45"
  end
end
