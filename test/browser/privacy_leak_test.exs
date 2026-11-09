defmodule PortfolixirWeb.Browser.PrivacyLeakTest do
  # The privacy mode's leak test (Sprint 26 P3, I22, FR-51; plan D-1 exit
  # criterion 3, D-4, D-5). LiveViewTest reads the server's markup but runs
  # no script, applies no CSS and cannot press a detail tab's button or see
  # what a hook draws, so this test boots the endpoint on a free loopback
  # port, seeds the review seed (priv/demo/finding_surfaces_seed.exs, so each
  # page has real amounts to hide) and drives Chromium through
  # `privacy_leak.js` with Playwright.
  #
  # The pages are the router's: every live route of the shell, with an
  # address for each one that takes a parameter. A new shell route is walked
  # without a change here; one with a parameter this test cannot address
  # fails it until it is given one. The walker follows each page's area tabs,
  # presses each detail tab and clicks each view a page links in place
  # (Cash flow's facets, "After the sale"'s comparison modes, any link that
  # names a tab), so a new tab is walked too. A step that did not render --
  # an error status, a crashed LiveView, a click that did not arrive --
  # fails the walk as a leak does: a crashed page shows no figure and
  # proves nothing (Sprint 26 closing act).
  #
  # Excluded from the test job (test/test_helper.exs): it needs Node, the
  # Playwright test/browser/package-lock.json pins and its Chromium, which
  # CI's `browser` job installs. Run it with
  #
  #     mix test test/browser --only browser
  #
  # async: false -- the sandbox is shared, so the LiveView processes the
  # browser's requests start read the world this test seeds. Synthetic data
  # only, no external network: the browser talks to 127.0.0.1.
  use PortfolixirWeb.ConnCase, async: false

  import Ecto.Query
  import ExUnit.CaptureIO

  alias Ecto.Adapters.SQL.Sandbox
  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Classifications.Classification
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.Bonds
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.Performance.Bands
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Predictions
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  @moduletag :browser
  @moduletag timeout: 1_800_000

  @script Path.expand("privacy_leak.js", __DIR__)
  @seed "priv/demo/finding_surfaces_seed.exs"

  # The figures that stay in the mode (plan D-5: percentages, dates, counts
  # and ratios), where a decimal comma alone would read as an amount; each
  # with its reason.
  @plain_selectors [
    # Risk's metric cards: volatility and drawdown in percent (the sign in
    # its own element), a risk-adjusted return and a correlation are ratios
    # of returns, never amounts.
    "[data-role^='risk-metric-']",
    # The predictions' calibration report: a Brier score, its standard
    # error and its 0.25 reference, a sharpness and a probability band's
    # bounds (0,50-0,59) are ratios of probabilities; the rest is percent
    # and counts (fix round of the closing act, P-fix 2).
    "#prediction-calibration",
    "[data-role='prediction-bands']",
    "[data-role='prediction-groups']",
    # The journal's stored ratios (a probability, a weight, an exchange
    # rate, a tax rate) read as stored, a raw decimal in a table cell; its
    # amounts, prices and quantities are bars (closing act, finding S2).
    "[data-figure='ratio']"
  ]

  # Data attributes whose value is an amount when it is a number; a chart's
  # coordinates and heights are ratios and stay (board 02).
  # The stacked chart's legend rows carry `data-end-value` (I23).
  @amount_data "^(data|phx-value)-(count-to|total|amount|value|end-value|price|quantity|close|balance|sum|cost|net|gain|income|cash)$"

  # An input whose name or id says it holds an amount or a quantity.
  @amount_name "amount|price|quantity|balance|cost|fees|taxes|allowance|nominal|close|gross"

  # Views a page offers inside a tab that the mode changes (P2).
  @extra_clicks ["#portfolio-performance button[phx-value-mode='value']"]

  # The file the import preview's open state drops: its row 5 carries a
  # Gesamtpreis that contradicts its Betrag, so the preview shows a warning
  # quoting the file's figures (the privacy lens of the closing act).
  @warning_csv Path.expand("../../priv/demo/pp_csv_gesamtpreis_demo.csv", __DIR__)

  setup %{sandbox_owner: owner} do
    # The walk holds the shared connection for minutes, longer than the
    # sandbox's two-minute ownership timeout: a fresh owner with room for
    # the whole walk replaces the case's.
    Portfolixir.DataCase.stop_sandbox(owner)

    long_owner =
      Sandbox.start_owner!(Repo, shared: true, ownership_timeout: 1_800_000)

    on_exit(fn -> Portfolixir.DataCase.stop_sandbox(long_owner) end)

    server =
      PortfolixirWeb.TestListener.start!(
        {Bandit,
         plug: PortfolixirWeb.Endpoint,
         scheme: :http,
         ip: {127, 0, 0, 1},
         port: 0,
         startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    seed!()
    predict!()
    overdraw!()
    # "localhost", the endpoint's configured host, so the LiveView socket's
    # origin check passes.
    %{base_url: "http://localhost:#{port}"}
  end

  # User story (P3):
  # As the operator who switched the privacy mode on before sharing my
  # screen,
  # I want no page of the shell to show an amount or a quantity, whatever
  # tab I open, in either theme, on the desk or on the phone,
  # so that the mode can be trusted without checking every page first.
  #
  # Acceptance criteria:
  # - The walk turns the mode on through the switch in the top bar, and the
  #   address keeps no choice.
  # - Every live route of the router is walked, each area tab a page links,
  #   each detail tab it offers and each view it links in place (Wealth's
  #   stacked chart's levels and a filtered category too, with a band that
  #   changes sign, #1433, and the TTWROR series' lines at a level and
  #   under a filter, FR-57), in the
  #   light and the dark theme, at 1200 and 390 px, on the review seed and
  #   three synthetic predictions.
  # - Any step that answers an error status, crashes its LiveView or does
  #   not arrive where it was sent fails the test.
  # - It fails on any figure in a currency or quantity in the visible text,
  #   in hidden text, in an attribute (a native tooltip, an accessible name,
  #   an amount-valued data attribute, a hidden figure's markup put into an
  #   attribute), in a chart's payload, and in the page source the server
  #   sent.
  # - A live route with a parameter the walk has no address for fails the
  #   test.
  # - The declared open states are opened by their own clicks and read the
  #   same way (the privacy lens of the closing act): the transaction delete
  #   dialog, the booking drawer on a buy, the notes-only drawer, the depot
  #   and the cash-account merge dialogs, the balance dialog, the security
  #   logo dialog and an import preview with a warning row. A state that
  #   does not open fails the test. The booking drawer edits stored figures
  #   and keeps them (DESIGN.md, "Forms keep their values"), so an enabled
  #   control's value is not read there; a disabled one's is, and so is
  #   everything else. The bar's markup inside an attribute and the stand-in
  #   text „••••“ on the screen fail the test in every state.
  test "no page of the shell shows an amount or a quantity while the privacy mode is on", %{
    base_url: base_url
  } do
    urls = shell_urls()
    file = Path.join(System.tmp_dir!(), "privacy-leak-#{System.unique_integer([:positive])}.json")

    File.write!(
      file,
      Jason.encode!(%{
        urls: urls,
        plainSelectors: @plain_selectors,
        amountData: @amount_data,
        amountName: @amount_name,
        extraClicks: @extra_clicks,
        openStates: open_states()
      })
    )

    on_exit(fn -> File.rm(file) end)

    {output, status} = System.cmd("node", [@script, base_url, file], stderr_to_stdout: true)

    assert status == 0, "the browser run failed:\n" <> output

    result =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Jason.decode!()

    assert result["ok"] == true,
           "#{result["error"]}:\n" <>
             Enum.map_join(result["findings"] || [], "\n", fn f ->
               "  #{f["page"]} · #{f["where"]} · #{f["hit"]} · #{f["context"]}"
             end)

    # Every address at least, in two themes at two widths (the area and
    # detail tabs come on top).
    assert result["visited"] >= length(urls) * 4,
           "the walk read #{result["visited"]} views of #{length(urls)} addresses"
  end

  # The open states the walk opens after the pages (the privacy lens of the
  # closing act): a dialog, a drawer or a flow's step, each with the clicks
  # that open it on the review seed, the element that shows it open, and
  # whether it is a form that edits stored figures. A new dialog that shows
  # figures belongs here.
  defp open_states do
    buy = newest(["buy"])

    notes_only =
      newest(
        ~w(cash_transfer balance_adjustment inbound_delivery outbound_delivery security_transfer)
      )

    cash = Repo.one(from(c in CashAccount, order_by: c.id, limit: 1))
    depot = Repo.one(from(d in SecuritiesAccount, order_by: d.id, limit: 1))
    security = Repo.one(from(t in Transaction, where: t.id == ^buy.id, select: t.security_id))

    assert buy && notes_only && cash && depot && security,
           "the review seed has no buy, notes-only booking, account or security to open states on"

    tx_menu = fn tx -> "#tx-kebab-#{tx.id}, #tx-phone-kebab-#{tx.id}" end

    [
      %{
        name: "transaction delete dialog",
        url: "/transactions",
        steps: [%{click: tx_menu.(buy)}, %{click: "#tx-delete-#{buy.id}"}],
        open: "#booking-delete-dialog"
      },
      %{
        name: "booking drawer, a buy",
        url: "/transactions",
        steps: [%{click: tx_menu.(buy)}, %{click: "#tx-edit-#{buy.id}"}],
        open: "#booking-drawer",
        allowFormValues: true
      },
      %{
        name: "notes-only drawer",
        url: "/transactions",
        steps: [%{click: tx_menu.(notes_only)}, %{click: "#tx-edit-#{notes_only.id}"}],
        open: "#booking-drawer #note-form"
      },
      %{
        name: "depot merge dialog",
        url: "/portfolios",
        steps: [
          %{click: "#account-kebab-#{depot.id}"},
          %{click: "#account-row-menu-#{depot.id} [data-role='menu-merge']"}
        ],
        open: "#merge-dialog"
      },
      %{
        name: "cash-account merge dialog",
        url: "/portfolios",
        steps: [
          %{click: "#cash-kebab-#{cash.id}"},
          %{click: "#cash-row-menu-#{cash.id} [data-role='menu-merge']"}
        ],
        open: "#merge-dialog"
      },
      %{
        name: "balance dialog",
        url: "/portfolios",
        steps: [%{click: "#set-balance-#{cash.id}"}],
        open: "#balance-dialog",
        allowFormValues: true
      },
      %{
        name: "security logo dialog",
        url: "/securities",
        steps: [
          %{click: "#row-kebab-#{security}, #phone-kebab-#{security}"},
          %{click: "#row-menu-#{security} button[phx-value-action='manage_logo']"}
        ],
        open: "#logo-override-dialog"
      },
      %{
        name: "import preview with a warning row",
        url: "/imports",
        steps: [%{upload: ["input[name='pp_file']", @warning_csv]}],
        open: "#parser-warnings-box"
      }
    ]
  end

  # The newest booking of one of `types`, so it stands on the history's
  # first page.
  defp newest(types) do
    Repo.one(
      from(t in Transaction,
        where: t.type in ^types,
        order_by: [desc: t.date, desc: t.id],
        limit: 1
      )
    )
  end

  # Every live route of the router, as the addresses the walk opens.
  defp shell_urls do
    routes =
      PortfolixirWeb.Router.__routes__()
      |> Enum.filter(&(&1.plug == Phoenix.LiveView.Plug))
      |> Enum.map(& &1.path)
      |> Enum.uniq()

    assert "/" in routes and "/portfolio" in routes

    Enum.flat_map(routes, &addresses/1)
  end

  defp addresses(path) do
    if String.contains?(path, ":") do
      case address(path) do
        [] ->
          flunk("""
          The shell route #{path} takes a parameter this leak test has no address for.
          Give it one in addresses/1 of #{__ENV__.file}, so the privacy mode is checked there too.
          """)

        list ->
          list
      end
    else
      [path | extra_addresses(path)]
    end
  end

  # The journal's newest page on the seed holds quotes and predictions; its
  # bookings, with their prices, quantities and fees, are walked by kind
  # (closing act of Sprint 26: the journal leaked them unseen).
  defp extra_addresses("/journal"), do: ["/journal?resource_type=transaction"]

  # Wealth's stacked chart (I23; Sprint 27 plan D-8, carry-forward 2): the
  # value series' category stack, from which the walker follows the bar's
  # levels, the breadcrumb and one category drilled into (`inPageLinks` in
  # privacy_leak.js).
  # The value series opens at „Kategorien“ (FR-56), so the single value
  # line, „Gesamt“, is an address of its own. The TTWROR series keeps the
  # bar since FR-57 (Sprint 28 S4): its lines at „Kategorien“, from which
  # the walker follows its levels and one filter too.
  defp extra_addresses("/portfolio"),
    do: [
      "/portfolio?level=category",
      "/portfolio?level=total",
      "/portfolio?level=category&scale=ttwror"
    ]

  defp extra_addresses(_path), do: []

  # The two most traded securities, the first bond and a bond priced on two
  # scales each way; a classification.
  defp address("/securities/:id") do
    traded =
      Repo.all(
        from(t in Transaction,
          where: not is_nil(t.security_id) and t.type in ["buy", "sell"],
          group_by: t.security_id,
          order_by: [desc: count(t.id), asc: t.security_id],
          limit: 2,
          select: t.security_id
        )
      )

    # By id: a pick without an order is whichever row the table's storage
    # returns first, so the walk once read a different bond from run to
    # run, and saw the reverse two-scales note leak only when it read that
    # one (Sprint 27 closing act, browser job). Both directions' notes are
    # walked every time.
    bonds =
      Repo.all(from(s in Security, where: s.asset_class == "bond", order_by: s.id, select: s.id))

    two_scales =
      bonds
      |> Bonds.two_scales_findings()
      |> Enum.uniq_by(& &1.direction)
      |> Enum.map(& &1.security_id)

    (traded ++ Enum.take(bonds, 1) ++ two_scales)
    |> Enum.uniq()
    |> Enum.map(&"/securities/#{&1}")
  end

  defp address("/classifications/:id") do
    Classification
    |> limit(1)
    |> select([c], c.id)
    |> Repo.all()
    |> Enum.map(&"/classifications/#{&1}")
  end

  defp address(_path), do: []

  # The review seed records no prediction, and a page that lists one
  # crashed in the mode once unseen (Sprint 26 closing act): the most traded
  # security gets three, synthetic — one resolving 30 days ago, one open,
  # one an agent's — so /predictions and the security's Predictions tab
  # have rows to walk.
  defp predict! do
    security_id =
      Repo.one(
        from(t in Transaction,
          where: not is_nil(t.security_id) and t.type in ["buy", "sell"],
          group_by: t.security_id,
          order_by: [desc: count(t.id), asc: t.security_id],
          limit: 1,
          select: t.security_id
        )
      )

    today = Portfolixir.Clock.today()
    earlier = DateTime.new!(Date.add(today, -200), ~T[12:00:00.000000], "Etc/UTC")

    for {actor, attrs, opts} <- [
          {Actor.owner_ui(), %{"probability" => "0.70", "resolves_on" => Date.add(today, -30)},
           [now: earlier]},
          {Actor.owner_ui(), %{"probability" => "0.65", "resolves_on" => Date.add(today, 60)},
           []},
          {Actor.api_token_rw("leak-agent"),
           %{
             "probability" => "0.55",
             "direction" => "underperform",
             "model" => "model-synthetic-1",
             "resolves_on" => Date.add(today, -20)
           }, [now: earlier]}
        ] do
      attrs =
        Map.merge(
          %{"security_id" => security_id, "direction" => "outperform", "benchmark" => "rate:0"},
          attrs
        )
        |> Map.update!("resolves_on", &Date.to_iso8601/1)

      {:ok, _prediction} = Predictions.create_prediction(actor, attrs, opts)
    end
  end

  # --- Sprint 28 S6 begin ---
  # A band that changes sign inside the 1Y window (#1426; #1433, D-A2): a
  # synthetic buy forty days ago for more than the cash ever held in the
  # window, paid by a deposit two days later, so the stacked chart's cash
  # band dips below zero and the walk reads its part below the zero line at
  # every stacked level. Checked on the bands read, so a seed that changes
  # cannot leave the state unwalked unnoticed.
  defp overdraw! do
    base = Portfolixir.Portfolios.first_portfolio().base_currency_code

    {depot, cash} =
      Repo.one(
        from(d in SecuritiesAccount,
          join: c in CashAccount,
          on: c.id == d.cash_account_id,
          where: c.currency_code == ^base,
          order_by: d.id,
          limit: 1,
          select: {d, c}
        )
      )

    cash_values = fn ->
      {:ok, bands} = Bands.for_view(nil, period: "1y", base_currency: base, level: :security)
      bands.bands |> Enum.find(%{values: []}, &(&1.kind == :cash)) |> Map.fetch!(:values)
    end

    most = Enum.max([Decimal.new(0) | cash_values.()], Decimal)
    amount = most |> Decimal.add(1000) |> Decimal.round(0, :up)
    on = Date.add(Portfolixir.Clock.today(), -40)

    security =
      WorldFixtures.create_security!(
        name: "Synthetic Overdraw Fund",
        ticker: "SOVF",
        currency: base
      )

    WorldFixtures.put_quotes!(security, [{on, "100"}])
    world = %{portfolio: %{id: depot.portfolio_id}, depot: depot, cash: cash}

    WorldFixtures.buy!(world, security,
      quantity: amount |> Decimal.div(100) |> Decimal.round(0, :up) |> Decimal.to_string(),
      price: "100",
      date: on
    )

    WorldFixtures.deposit!(
      %{portfolio: %{id: cash.portfolio_id}, cash: cash},
      amount |> Decimal.mult(2) |> Decimal.to_string(),
      Date.add(on, 2)
    )

    assert Enum.any?(cash_values.(), &Decimal.negative?/1),
           "the overdraft did not take the stack's cash band below zero"
  end

  # --- Sprint 28 S6 end ---

  defp seed! do
    conflicts = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      capture_io(fn -> Code.eval_file(@seed) end)
    after
      Code.put_compiler_option(:ignore_module_conflict, conflicts)
    end
  end
end
