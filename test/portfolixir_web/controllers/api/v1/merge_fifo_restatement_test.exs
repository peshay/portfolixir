defmodule PortfolixirWeb.Api.V1.MergeFifoRestatementTest do
  # The realized gains the app reads are FIFO, one queue per security across
  # every depot (Portfolixir.Portfolios.RealizedGains over
  # Portfolixir.Ledger.TradeMatcher). A security merge pools two queues, so
  # it can restate them; a depot merge cannot. The merge previews state what
  # each does, over the API and on the page. Every name and amount is
  # synthetic.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  setup %{conn: conn} do
    api =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Restatement",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Broker cash",
        currency_code: "EUR"
      })

    %{api: api, ui: conn, portfolio: portfolio, cash: cash}
  end

  # The duplicate ADR-0050 §1 names: the source holds a January lot, the
  # target a February lot and a March sale, in one depot. FIFO over the
  # target alone: the March sale consumes the February lot (10 x 150 -
  # 10 x 200 = -500). FIFO over the pooled queue after the merge: it
  # consumes the January lot instead (10 x 150 - 10 x 100 = +500).
  defp security_merge_world!(ctx) do
    depot = depot!(ctx, "Depot 1")
    target = security!("Harbour Fund")
    source = security!("Harbour Fund")

    trade!(ctx, depot, source, "buy", "10", "100", ~D[2025-01-02])
    trade!(ctx, depot, target, "buy", "10", "200", ~D[2025-02-03])
    trade!(ctx, depot, target, "sell", "10", "150", ~D[2025-03-03])

    %{depot: depot, target: target, source: source}
  end

  # User story (security review 2026-10-12, K11):
  # As the operator or the agent about to merge a duplicate security,
  # I want the preview to state the FIFO realized gains per close year and
  # the open lots' cost of each security before and of the merged one after,
  # so that a merge that cannot be undone never moves the realized gains I
  # read without my having been shown it.
  #
  # Acceptance criteria:
  # - Each outcome of the security merge preview carries fifo_realized: per
  #   close year the source's, the target's and the merged realized result
  #   and the change, and the open lots' cost likewise, as decimal strings.
  # - The after-figure equals GET /api/v1/realized_gains right after the
  #   apply (ADR-0050 §16 invariant 12), per close year and in total.
  # - The holdings figures the preview states stay equal to the holdings
  #   read after the apply.
  test "security merge: the preview's FIFO after-figure is the realized gains read after the apply",
       ctx do
    w = security_merge_world!(ctx)

    before = realized!(ctx)
    preview = security_preview!(ctx, w.source, w.target)
    assert preview["choice_required"] == false
    assert preview["identity_choice_required"] == false
    outcome = preview["outcome_by_collapse_key_equal"]["false"]
    [position] = outcome["positions"]

    # Controls: the app reads -500 before, the preview's target-before agrees.
    assert Decimal.equal?(dec(before["summary"]["realized_total"]), dec("-500"))

    fifo = outcome["fifo_realized"]
    assert is_map(fifo), "the security merge preview states no FIFO realized gains"

    assert [%{"year" => 2025, "currency_code" => "EUR"} = year] = fifo["years"]
    assert year["source"] == nil
    assert Decimal.equal?(dec(year["target"]), dec("-500"))
    assert Decimal.equal?(dec(year["after"]), dec("500"))
    assert Decimal.equal?(dec(year["change"]), dec("1000"))

    # The open lots: the source's January lot before; the target's February
    # lot after. Realized and open cost move by the same amount.
    assert [%{"currency_code" => "EUR"} = open] = fifo["open_lots"]
    assert Decimal.equal?(dec(open["source"]), dec("1000"))
    assert Decimal.equal?(dec(open["target"]), dec("0"))
    assert Decimal.equal?(dec(open["after"]), dec("2000"))
    assert Decimal.equal?(dec(open["change"]), dec("1000"))
    assert fifo["unchanged"] == false

    # Both values of the choice state it (no pair here, so the same).
    assert preview["outcome_by_collapse_key_equal"]["true"]["fifo_realized"] == fifo
    assert preview["fifo_basis"] =~ "FIFO"

    apply_security_merge!(ctx, w.source, w.target, preview)
    after_merge = realized!(ctx)

    # Control: invariant 12 holds for the holdings figures the preview states.
    holding = holding!(ctx, w.depot, w.target)

    for field <- ["quantity", "cost_basis", "avg_cost"],
        do: assert(Decimal.equal?(dec(holding[field]), dec(position["after"][field])), field)

    promised = sum_after(fifo)
    read = dec(after_merge["summary"]["realized_total"])

    assert Decimal.equal?(promised, read),
           "preview promised FIFO realized after = #{promised}; " <>
             "GET /api/v1/realized_gains after the apply = #{read}"

    [%{"year" => 2025, "total" => year_total}] = after_merge["annual"]
    assert Decimal.equal?(dec(year_total), dec(year["after"]))
  end

  # User story (security review 2026-10-12, K11):
  # As the operator reading the merge preview,
  # I want the change it states to be the change the app's realized gains
  # make,
  # so that the headline realized figure moves only by what I was shown.
  #
  # Acceptance criteria:
  # - The sum of the preview's per-year changes equals the change of
  #   GET /api/v1/realized_gains across the apply.
  test "security merge: the app's realized gains change only by what the preview states", ctx do
    w = security_merge_world!(ctx)

    before = realized!(ctx)
    preview = security_preview!(ctx, w.source, w.target)
    fifo = preview["outcome_by_collapse_key_equal"]["false"]["fifo_realized"]
    assert is_map(fifo), "the security merge preview states no FIFO realized gains"

    stated_change =
      Enum.reduce(fifo["years"], Decimal.new(0), &Decimal.add(&2, dec(&1["change"])))

    apply_security_merge!(ctx, w.source, w.target, preview)
    after_merge = realized!(ctx)

    actual_change =
      Decimal.sub(
        dec(after_merge["summary"]["realized_total"]),
        dec(before["summary"]["realized_total"])
      )

    assert Decimal.equal?(stated_change, actual_change),
           "preview states a realized change of #{stated_change}; the app's realized " <>
             "gains moved by #{actual_change} " <>
             "(#{before["summary"]["realized_total"]} -> #{after_merge["summary"]["realized_total"]})"
  end

  # User story (security review 2026-10-12, K11):
  # As the operator merging two depots,
  # I want the depot preview to name its realized column for the moving
  # average it is and to say the FIFO realized gains do not change,
  # so that two figures called "realized" are never read as one.
  #
  # Acceptance criteria:
  # - positions_basis names realized_result a moving-average result and
  #   says the FIFO realized gains do not change, the queue belonging to
  #   the security.
  # - GET /api/v1/realized_gains reads the same before and after the apply.
  test "depot merge: the preview says FIFO realized gains do not change, and they do not", ctx do
    target = depot!(ctx, "Depot T")
    source = depot!(ctx, "Depot S")
    security = security!("Meridian Fund")

    trade!(ctx, source, security, "buy", "10", "100", ~D[2025-01-02])
    trade!(ctx, target, security, "buy", "10", "200", ~D[2025-02-03])
    trade!(ctx, target, security, "sell", "10", "150", ~D[2025-03-03])

    before = realized!(ctx)

    preview =
      ctx.api
      |> get("/api/v1/securities_accounts/#{source.id}/merge_preview?target_id=#{target.id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert preview["choice_required"] == false
    [position] = preview["outcome_by_collapse_key_equal"]["false"]["positions"]
    assert position["security_id"] == security.id

    assert preview["positions_basis"] =~ "moving-average result"
    assert preview["positions_basis"] =~ "FIFO realized gains"
    assert preview["positions_basis"] =~ "do not change"

    assert %{"already_applied" => false} =
             ctx.api
             |> post("/api/v1/securities_accounts/#{source.id}/merge", %{
               target_id: target.id,
               plan_digest: preview["plan_digest"]
             })
             |> json_response(201)

    after_merge = realized!(ctx)

    assert Decimal.equal?(
             dec(after_merge["summary"]["realized_total"]),
             dec(before["summary"]["realized_total"])
           )
  end

  # User story (security review 2026-10-12, K11):
  # As the operator merging two depots on the page,
  # I want the realized column named for its moving average, and a line
  # saying the FIFO realized gains do not change,
  # so that I do not take the column for the realized gains the Income page
  # and the Trades tab read.
  #
  # Acceptance criteria:
  # - The column and the phone line read "Realized (moving avg.)"; no
  #   "Realized gain/loss" stands in the positions.
  # - The basis line says the FIFO realized gains do not change.
  test "depot merge dialog: the realized column is the moving average, FIFO unchanged", ctx do
    target = depot!(ctx, "Depot T")
    source = depot!(ctx, "Depot S")
    security = security!("Meridian Fund")

    trade!(ctx, source, security, "buy", "10", "100", ~D[2025-01-02])
    trade!(ctx, target, security, "buy", "10", "200", ~D[2025-02-03])

    {:ok, view, _html} = live(ctx.ui, "/portfolios")
    view |> element("#account-kebab-#{source.id}") |> render_click()
    view |> element("#account-row-menu-#{source.id} [data-role='menu-merge']") |> render_click()

    view
    |> element("#merge-dialog form[data-role='merge-target-form']")
    |> render_change(%{merge: %{target_id: "#{target.id}"}})

    view |> element("#merge-dialog [data-role='merge-continue']") |> render_click()

    html = view |> element("#merge-dialog") |> render()

    assert has_element?(view, "#merge-dialog table.merge-positions th", "Realized (moving avg.)")

    assert has_element?(
             view,
             "#merge-dialog [data-role='merge-position-line']",
             "Realized (moving avg.)"
           )

    refute html =~ "Realized gain/loss"
    assert html =~ "Realized gains by FIFO"
    assert html =~ "do not change"
  end

  # User story (security review 2026-10-12, K11):
  # As the operator confirming a security merge on the page,
  # I want step 2 to state the FIFO realized gains per close year and the
  # open lots' cost, before and after, under the holdings,
  # so that I confirm from the figure the merge restates.
  #
  # Acceptance criteria:
  # - Step 2 carries the "Realized gains (FIFO)" block with the close year,
  #   source · target → afterwards and the change, and the open lots' row.
  test "security merge dialog: step 2 states the FIFO realized gains the merge restates", ctx do
    w = security_merge_world!(ctx)

    to_security_preview(ctx, w.source, w.target)
    |> then(fn view ->
      html = view |> element("#security-merge-dialog") |> render()

      # Control: step 2, the preview the operator confirms from.
      assert html =~ "Holdings afterwards"
      assert has_element?(view, "#security-merge-dialog [data-role='merge-confirm']")

      assert has_element?(
               view,
               "#security-merge-dialog [data-role='merge-fifo'] .merge-block-head",
               "Realized gains (FIFO)"
             )

      row =
        view
        |> element("#security-merge-dialog [data-role='merge-fifo-year'][data-year='2025']")
        |> render()

      assert row =~ "-500.00"
      assert row =~ "500.00"
      assert row =~ "+1,000.00"

      open = view |> element("#security-merge-dialog [data-role='merge-fifo-open']") |> render()
      assert open =~ "1,000.00 + 0.00"
      assert open =~ "2,000.00"
    end)
  end

  # User story (security review 2026-10-12, K11):
  # As the operator merging a duplicate whose lots do not interleave,
  # I want one line saying the FIFO realized gains do not change,
  # so that a table of zeros does not stand where nothing moves.
  #
  # Acceptance criteria:
  # - The preview's fifo_realized says unchanged true; the page shows the
  #   one line in place of the table.
  test "a security merge that moves no FIFO figure says so in one line", ctx do
    depot = depot!(ctx, "Depot 1")
    target = security!("Harbour Fund")
    source = security!("Harbour Fund")

    trade!(ctx, depot, target, "buy", "10", "200", ~D[2025-02-03])
    trade!(ctx, depot, target, "sell", "10", "150", ~D[2025-03-03])
    trade!(ctx, depot, source, "buy", "10", "100", ~D[2025-04-01])

    preview = security_preview!(ctx, source, target)
    fifo = preview["outcome_by_collapse_key_equal"]["false"]["fifo_realized"]
    assert is_map(fifo), "the security merge preview states no FIFO realized gains"
    assert fifo["unchanged"] == true

    view = to_security_preview(ctx, source, target)

    assert has_element?(
             view,
             "#security-merge-dialog [data-role='merge-fifo']",
             "Realized gains (FIFO) do not change."
           )

    refute has_element?(view, "#security-merge-dialog [data-role='merge-fifo'] table")
  end

  # -- helpers ------------------------------------------------------------------

  defp to_security_preview(ctx, source, target) do
    {:ok, view, _html} = live(ctx.ui, "/securities")

    view
    |> element(
      ~s(#securities-table button[phx-click="open_row_menu"][phx-value-id="#{source.id}"])
    )
    |> render_click()

    view |> element("#row-menu-#{source.id} [data-role='menu-merge']") |> render_click()

    view
    |> element("#security-merge-dialog form[data-role='merge-search']")
    |> render_change(%{merge: %{q: target.name}})

    view
    |> element("#security-merge-dialog form[data-role='merge-target-form']")
    |> render_change(%{merge: %{target_id: "#{target.id}"}})

    view |> element("#security-merge-dialog [data-role='merge-continue']") |> render_click()
    view
  end

  defp sum_after(fifo) do
    Enum.reduce(fifo["years"], Decimal.new(0), fn year, acc ->
      case year["after"] do
        nil -> acc
        value -> Decimal.add(acc, dec(value))
      end
    end)
  end

  defp realized!(ctx) do
    ctx.api |> get("/api/v1/realized_gains") |> json_response(200) |> Map.fetch!("data")
  end

  defp security_preview!(ctx, source, target) do
    ctx.api
    |> get("/api/v1/securities/#{source.id}/merge_preview?target_id=#{target.id}")
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp apply_security_merge!(ctx, source, target, preview) do
    assert %{"already_applied" => false} =
             ctx.api
             |> post("/api/v1/securities/#{source.id}/merge", %{
               target_id: target.id,
               plan_digest: preview["plan_digest"]
             })
             |> json_response(201)
  end

  defp holding!(ctx, depot, security) do
    ctx.api
    |> get("/api/v1/portfolios/#{ctx.portfolio.id}/holdings")
    |> json_response(200)
    |> Map.fetch!("data")
    |> Enum.find(&(&1["securities_account_id"] == depot.id and &1["security_id"] == security.id))
  end

  defp depot!(ctx, name) do
    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: ctx.portfolio.id,
        cash_account_id: ctx.cash.id,
        name: name
      })

    depot
  end

  defp security!(name) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        currency_code: "EUR",
        asset_class: "etf"
      })

    security
  end

  defp trade!(ctx, depot, security, type, quantity, price, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: ctx.portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: ctx.cash.id,
        security_id: security.id,
        type: type,
        date: date,
        quantity: quantity,
        price: price,
        currency_code: "EUR"
      })

    tx
  end

  defp dec(nil), do: flunk("expected a decimal string, got nil")
  defp dec(value) when is_binary(value), do: Decimal.new(value)
end
