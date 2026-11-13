defmodule PortfolixirWeb.Browser.ControlBarTest do
  # The shared bar of labelled controls (`PortfolixirWeb.ControlBar.bar/1`;
  # issue 1435, Sprint 29 L1; DESIGN.md "Labelled controls start on one
  # edge"), in a real browser. LiveViewTest renders the server's markup and
  # applies no CSS, so this test boots the endpoint on a free loopback port
  # and drives Chromium through `control_bar.js` with Playwright, as
  # `PortfolixirWeb.Browser.ClosingActLayoutTest` does.
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

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Classifications
  alias Portfolixir.Classifications.Classification
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo
  alias PortfolixirWeb.PreferenceCookieHelpers

  @moduletag :browser
  @moduletag timeout: 180_000

  @script Path.expand("control_bar.js", __DIR__)

  setup do
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
    # "localhost", the endpoint's configured host, so the LiveView socket's
    # origin check passes.
    %{base_url: "http://localhost:#{port}"}
  end

  defp run!(case_name, base_url, ids) do
    argument = Jason.encode!(Map.merge(ids, %{base_url: base_url, case: case_name}))
    {output, status} = System.cmd("node", [@script, argument], stderr_to_stdout: true)

    assert status == 0, "the browser run failed:\n" <> output

    result =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Jason.decode!()

    {result, output}
  end

  defp locales do
    Map.new(["en", "de"], fn locale ->
      {locale,
       "portfolixir_locale"
       |> PreferenceCookieHelpers.cookie_pair(locale)
       |> String.split("=", parts: 2)
       |> List.last()}
    end)
  end

  # Issue 1435 (Sprint 29 L1; board
  # `ux-design-2026-11-12-sprint29/06-control-bar`, inventory §1 row 1).
  #
  # User story:
  # As the operator choosing the stack's level, classification and sort,
  # I want the stacked chart's bar to look exactly as it did once it is
  # built from the shared bar of labelled controls,
  # so that the component every other bar moves to is the one I already
  # know, and nothing on this screen moves.
  #
  # Acceptance criteria:
  # - In English and in German, at 1200 px and at 900 px (no sidebar) the
  #   bar is one line, each control 8 px after its label.
  # - At 1024 px (the sidebar leaves the bar under 760 px) and at 390 px the
  #   bar is the label column (A): every label at the bar's left edge, every
  #   control 10 px after the widest label (±1 px).
  # - At 320 px every label stands above its control, both at the bar's
  #   left edge (B).
  # - No control leaves the bar, and the page never scrolls sideways.
  test "the stacked chart's bar keeps its line, its label column and its labels above",
       %{base_url: base_url} do
    world = base_world(name: "Bar Stack", cash_name: "Giro", depot_name: "Depot")
    deposit!(world, "10000", ~D[2025-01-02])
    owner = Actor.owner_ui()
    {:ok, tree} = Classifications.create_classification(owner, %{name: "Strategy"})

    {:ok, category} =
      Classifications.create_category(owner, %{classification_id: tree.id, name: "Growth"})

    security = create_security!(name: "Synthetic Growth Fund")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2025-01-02])
    put_quotes!(security, [{~D[2025-01-02], "100"}])
    {:ok, _} = Classifications.assign_security(owner, security.id, tree.id, category.id)

    {result, output} =
      run!("stack_bar_layout", base_url, %{
        path: "/portfolio?level=category&tree=#{tree.id}",
        locales: locales()
      })

    assert result == %{"ok" => true}, output
  end

  # --- L2 begin ---
  # Issue 1435 (Sprint 29 L2; board `ux-design-2026-11-12-sprint29/06-control-bar`
  # ① to ④ and its inventory §1, rows 2, 3, 5, 7 to 10): the bars that
  # broke "labelled controls start on one edge" on the review seed, and the
  # two it did not render, moved onto the shared bar. Each walks the review
  # seed (priv/demo/finding_surfaces_seed.exs), as the inventory measured
  # it, in German and in English at 390 and 1200 px.
  #
  # User story:
  # As the operator filtering a list or choosing a comparison, on a phone
  # or a wide window,
  # I want every bar of labelled controls to start its controls on one
  # edge, with each family of chips named,
  # so that I read a bar down one edge instead of hunting for where each
  # control starts and which chips belong together.
  #
  # Acceptance criteria (each bar, each locale, 390 and 1200 px):
  # - Once the bar has more than one row, the first control of every row
  #   and of every labelled group start on one edge (±1 px).
  # - Every labelled control sits after its label on the label's line, or
  #   under it on the label's edge (labels above).
  # - Wertpapiere, Transaktionen, Prognosen and the drift filter name every
  #   chip family with a visible label.
  # - The journal's chips and its form are one bar; the sale's comparison
  #   with „Fester Zins“ puts its labels above at 390 px (board 06 ①, ②).
  # - Wertpapiere's and Transaktionen's rows show at 1200 px (the phone's
  #   filter sheet takes their place at 390 px); every other bar shows at
  #   both widths, Prognosen' on the predictions the seed records and the
  #   drift filter on the seed's plan with the table opened.
  # - The page never scrolls sideways.
  for bar <-
        ~w(journal sale_comparison securities_chips transaction_chips prediction_filters drift_filter) do
    test "the #{bar} bar starts its labelled controls on one edge", %{base_url: base_url} do
      seed!()

      {result, output} =
        run!("migrated_bar", base_url, %{bar: unquote(bar), locales: locales()})

      assert result == %{"ok" => true}, output
    end
  end

  defp seed! do
    conflicts = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      ExUnit.CaptureIO.capture_io(fn -> Code.eval_file("priv/demo/finding_surfaces_seed.exs") end)
    after
      Code.put_compiler_option(:ignore_module_conflict, conflicts)
    end
  end

  # --- L2 end ---

  # --- L3 begin ---
  # Issue 1435 (2), Sprint 29 L3: the walk as a gate. The migrated bars'
  # cases above name each bar; this one names none. It opens every page the
  # router serves on the review seed (every live route, an address for each
  # one that takes a parameter, every area tab and comparison a page links
  # in place), opens each closed disclosure that holds a bar, and measures
  # every bar it finds there: each `.control-bar`, and each older bar of
  # controls (`.filter-chips`, `.toolbar`, ...) that carries a visible
  # label. A bar the component does not draw, or one added tomorrow, is
  # measured without a change here; a route with a parameter this test
  # cannot address fails it until it is given one.
  #
  # A labelled bar is measured across every width from 1440 down to 320
  # px in steps of 8 (and at 390), so a bar that breaks only in a band of
  # widths, at a tablet's 768 px say, is caught; at 390 and 1200 px the
  # plan asked for, and everywhere between.
  #
  # User story:
  # As the owner who trusts CI's browser job instead of reading each
  # screen,
  # I want one walk to measure every bar of labelled controls on every page,
  # at every width, without being told where the bars are,
  # so that a bar that breaks "labelled controls start on one edge", an old
  # one or a new one, fails the build instead of reaching my screen.
  #
  # Acceptance criteria:
  # - Every live route of the router is opened (in German and in English),
  #   with an address for each one that takes a parameter, and every area
  #   tab or comparison a page links in place.
  # - Every `.control-bar` on those pages is found and measured, and so is
  #   every other bar of controls with a visible label, a label set in CSS
  #   included; the eight bars on the component today are among them.
  # - At every width from 1440 to 320 px (steps of 8, and 390), once a bar
  #   has more than one row, the first control of every row and of every
  #   labelled group start on one edge (±1 px); every labelled control sits
  #   after its label on its line or under it on its edge; a bar on the
  #   component names every chip family; no control leaves the bar or the
  #   screen.
  # - A `.control-bar` the walk never sees at any width fails it: a gate
  #   that measured nothing checks nothing.
  # - PR 2's closing act: the sweep also measures at 1680 and 1920 px, on
  #   both sides of every width the stylesheets' media queries switch at,
  #   and on both sides of where a bar on the component crosses its fold or
  #   its floor; any element a control names by aria-labelledby is a label,
  #   a screen reader's label is none; and a labelled control (a select, a
  #   segmented control, a field, a chip family) outside every bar found
  #   fails, unless STRAY_EXCEPTIONS names it with its reason (a form's
  #   fields, one labelled control on its own line), an entry that excuses
  #   nothing failing as stale.
  @tag timeout: 1_200_000
  test "every bar of labelled controls on every page starts its controls on one edge",
       %{base_url: base_url, sandbox_owner: owner} do
    # The walk holds the shared connection for minutes, longer than the
    # sandbox's two-minute ownership timeout: a fresh owner with room for
    # the whole walk replaces the case's, as the privacy walk's does.
    Portfolixir.DataCase.stop_sandbox(owner)
    long_owner = Sandbox.start_owner!(Repo, shared: true, ownership_timeout: 1_200_000)
    on_exit(fn -> Portfolixir.DataCase.stop_sandbox(long_owner) end)

    seed!()
    addresses = shell_addresses()

    {result, output} =
      run!("every_bar", base_url, %{
        addresses: addresses,
        prose_addresses: prose_addresses(),
        locales: locales()
      })

    assert result["ok"] == true, output
    assert result["visited"] >= length(addresses) * 2, output

    found = MapSet.new(result["bars"])

    # crash-bar: the Crashes section on Wealth › Risk (Sprint 29 C6), on
    # the component since Lane L's integration, on the review seed's
    # manual window (step 23).
    for bar <- ~w(stack-bar journal-chips hindsight-compare securities-filter-chips
                  transaction-chips prediction-filters drift-filter crash-bar) do
      assert bar in found, "the walk did not find the bar #{bar}:\n" <> output
    end

    # --- L5 begin ---
    # Issue 1435 (4), Sprint 29 L5 (DESIGN.md I1; inventory §3; board 06
    # ⑤ to ⑩): open prose, read in the same page visits, at 1200 and at
    # 390 px, in German and in English.
    #
    # User story:
    # As the operator reading a screen,
    # I want every free paragraph on it to be one sentence of at most 25
    # words, the method behind the section's ⓘ,
    # so that a screen shows its figures and their basis, and a paragraph
    # of method grown back onto a page fails the build.
    #
    # Acceptance criteria:
    # - No visible free paragraph (a block's inline text, across every
    #   inline element in it, or two blocks set as one) outside an ⓘ, a
    #   data note, a table or a list runs past one sentence or 25 words.
    # - Past it, a paragraph stays only under a registered exception with
    #   its reason (an empty state, an alert, a list of names, a figure's
    #   label), and an exception that excuses nothing fails as stale.
    prose = result["prose"]
    assert prose["checked"] > 0, output
    assert prose["errors"] == [], Enum.join(prose["errors"], "\n")
    # --- L5 end ---
  end

  # The gate's own attack (Sprint 29 plan, the attack lens of Lane L): pages
  # the walk draws itself and measures the way it measures the app's.
  #
  # Acceptance criteria:
  # - A bar whose groups wrap only between 764 and 772 px (one line at 390
  #   and at 1200 px) is caught, and only in that band.
  # - A bar whose labels are set in CSS (`::before`), with controls that
  #   sit neither beside nor under them, is caught for that, its labels
  #   read as labels.
  # - A bar that holds the rule at every width is not.
  # - PR 2's closing act (the attack lens's inputs, each seen slipping
  #   first): a labelled chip bar under a class no list holds is caught as
  #   controls outside every bar; labels named only by aria-labelledby are
  #   read as labels; a family named only by a screen reader's label is
  #   caught as unnamed; a fold set a few pixels too low is caught at its
  #   crossing, and a break in a band narrower than a step (761 to 767,
  #   321 to 327 px) or past 1440 px at the stylesheet's breakpoints; the
  #   strays' exceptions need a reason and go stale.
  test "the walk catches a bar that wraps only at 768 px and a label set in CSS",
       %{base_url: base_url} do
    {result, output} = run!("attack", base_url, %{})

    fixtures = result["fixtures"]
    assert fixtures["sound"]["widths"] == [], output

    assert fixtures["wraps_at_768"]["widths"] != [], output
    assert Enum.all?(fixtures["wraps_at_768"]["widths"], &(&1 in 764..772)), output

    # Caught for what it is: a control away from its label, the label read
    # from CSS, never "a family without a label".
    assert fixtures["css_label"]["widths"] != [], output
    [error] = fixtures["css_label"]["errors"]
    assert error =~ "sits neither after nor under its label „Konto“", output
    refute error =~ "without a visible label", output

    # --- PR 2 closing act begin (the attack lens of Lane L, pr2-l-attack) ---
    # A labelled chip bar under a class no list holds is caught as labelled
    # controls outside every bar, its labels plain elements named by
    # aria-labelledby (a span or a label); in a bar the walk knows, labels
    # named only by aria-labelledby are read as labels.
    for name <- ~w(unlisted_class unlisted_class_label) do
      assert [_ | _] = errors = fixtures[name]["errors"], "#{name} went uncaught:\n" <> output
      assert Enum.all?(errors, &(&1 =~ "outside every bar of labelled controls")), output
      assert Enum.any?(errors, &(&1 =~ "„Konto“")), output
    end

    assert [unnamed] = fixtures["unnamed_labels"]["errors"], output
    assert unnamed =~ "sits neither after nor under its label „Konto“", output

    # A family named only by a screen reader's label has no visible label.
    for name <- ~w(sr_only_family sr_only_label) do
      assert [sr_only] = fixtures[name]["errors"], "#{name} went uncaught:\n" <> output
      assert sr_only =~ "a chip family without a visible label, from „Giro“", output
    end

    # A fold set a few pixels too low is caught where the bar crosses it
    # (the line wraps while the bar is 761 to 766 px wide, 777 to 782 px
    # windows), and only there.
    assert fixtures["fold_crossing"]["widths"] != [], output
    assert Enum.all?(fixtures["fold_crossing"]["widths"], &(&1 in 777..782)), output

    # A break in a band narrower than the sweep's step, or past 1440 px, is
    # caught at the stylesheet's own breakpoints, and only in its band.
    for {name, band} <- [band_761_767: 761..767, band_321_327: 321..327, wide_1441: 1441..1920] do
      widths = fixtures[Atom.to_string(name)]["widths"]
      assert widths != [], "#{name} went uncaught:\n" <> output
      assert Enum.all?(widths, &(&1 in band)), output
    end

    # The controls outside every bar take an exception only with a reason,
    # and one that excuses nothing fails as stale; the one that matches
    # excuses its bar.
    strays = result["strays"]
    refute Enum.any?(strays, &(&1 =~ "outside every bar of labelled controls")), output
    assert Enum.any?(strays, &(&1 =~ "the exception .no-reason gives no reason")), output
    assert Enum.any?(strays, &(&1 =~ "the exception .nowhere excuses no control")), output

    # --- PR 2 closing act end ---
  end

  # --- L5 begin ---
  # The open prose check's own attack (Sprint 29 plan, the attack lens of
  # Lane L): paragraphs the walk draws itself and reads as it reads the
  # app's, with an exception list of its own.
  #
  # Acceptance criteria:
  # - A paragraph of two sentences split into two spans, or into two
  #   blocks set with no spacing between them, is caught.
  # - Two paragraphs with a paragraph's spacing, each one sentence, are not;
  #   nor is one sentence with its German and English abbreviations, nor
  #   two sentences behind an ⓘ or in a data note.
  # - A sentence of 26 words is caught.
  # - An empty state of two sentences is excused; of three, caught.
  # - An exception without a reason is caught, and so is one that excuses
  #   nothing.
  test "the open prose check catches a split paragraph and an exception without a reason",
       %{base_url: base_url} do
    {result, output} = run!("prose_attack", base_url, %{})
    fixtures = result["fixtures"]

    for caught <- ~w(split_spans split_blocks long_sentence empty_state_long) do
      assert length(fixtures[caught]) == 1, "#{caught} went uncaught:\n" <> output
    end

    assert fixtures["split_spans"] |> hd() =~ "2 sentence(s)", output
    assert fixtures["split_blocks"] |> hd() =~ "+ 1 sibling(s)", output

    for sound <- ~w(spaced abbreviations behind_info empty_state) do
      assert fixtures[sound] == [], "#{sound} was caught:\n" <> output
    end

    registry = result["registry"]
    assert Enum.any?(registry, &(&1 =~ "the exception .no-reason gives no reason")), output
    assert Enum.any?(registry, &(&1 =~ "the exception .nowhere excuses no paragraph")), output
  end

  # --- L5 end ---

  # Every live route of the router, as the addresses the walk opens; the
  # walk follows each page's area tabs and comparisons from there.
  defp shell_addresses do
    routes =
      PortfolixirWeb.Router.__routes__()
      |> Enum.filter(&(&1.plug == Phoenix.LiveView.Plug))
      |> Enum.map(& &1.path)
      |> Enum.uniq()

    assert "/" in routes and "/journal" in routes

    Enum.flat_map(routes, fn path ->
      cond do
        not String.contains?(path, ":") ->
          [path | extra_addresses(path)]

        (list = address(path)) != [] ->
          list

        true ->
          flunk("""
          The shell route #{path} takes a parameter the control bar walk has no address for.
          Give it one in address/1 of #{__ENV__.file}, so its bars are measured too.
          """)
      end
    end)
  end

  # Wealth's stacked chart, whose bar shows once the value series stands
  # at a stacked level.
  defp extra_addresses("/portfolio"), do: ["/portfolio?level=category"]
  defp extra_addresses(_path), do: []

  # The seed's most sold security (its Trades tab holds the sale's
  # comparison) and its first classification.
  defp address("/securities/:id") do
    Repo.all(
      from(t in Transaction,
        where: not is_nil(t.security_id) and t.type == "sell",
        group_by: t.security_id,
        order_by: [desc: count(t.id), asc: t.security_id],
        limit: 1,
        select: t.security_id
      )
    )
    |> Enum.map(&"/securities/#{&1}")
  end

  defp address("/classifications/:id") do
    Repo.all(from(c in Classification, order_by: c.id, limit: 1, select: c.id))
    |> Enum.map(&"/classifications/#{&1}")
  end

  defp address(_path), do: []

  # --- L5 begin ---
  # The pages the walk opens for their prose alone, no bar swept and no tab
  # followed: the seed's first bond with its terms entered, whose overview
  # holds the bond strip and its basis line (board 06 ⑩).
  defp prose_addresses do
    bond =
      Repo.all(
        from(s in Security,
          where: not is_nil(s.coupon_rate),
          order_by: s.id,
          limit: 1,
          select: s.id
        )
      )

    assert [_] = bond, "the review seed holds no bond with its terms entered"
    Enum.map(bond, &"/securities/#{&1}")
  end

  # --- L5 end ---
  # --- L3 end ---
end
