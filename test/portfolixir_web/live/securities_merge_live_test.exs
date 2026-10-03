defmodule PortfolixirWeb.SecuritiesMergeLiveTest do
  # ADR-0050 §8, §9, §10 on the securities page (L5b, #608; board
  # 03-security-merge, pick G3-A: the identity choice as two option cards,
  # one consequence line each, never preselected; the flow reuses G2-B's two
  # steps). The merge the page applies is the one the API applies
  # (Portfolixir.Lifecycle); what is pinned here is what the operator sees
  # and sends. Every name, identifier, price and quantity is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Clock
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Repo

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Main", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Girokonto",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot 1"
      })

    %{
      portfolio: portfolio,
      cash: cash,
      depot: depot,
      target: security!("Meridian Global Equity ETF", isin: "XS0000000017"),
      source: security!("Meridian Global Equity ETF", isin: "XS0000000025")
    }
  end

  # User story:
  # As the operator who found a duplicate security,
  # I want "Merge into…" in its row menu to open a first step where I search
  # the target, see every candidate that cannot take the history with its
  # reason, and never the duplicate itself,
  # so that I choose the target among hundreds of securities knowing why the
  # others are out (board 03, step 1).
  #
  # Acceptance criteria:
  # - The row menu lists "Merge into…" after "Mark as benchmark" and before
  #   "Delete", not in the danger colour.
  # - Step 1 of 2 is titled for the source and names its ISIN, currency,
  #   bookings and creation date.
  # - The list is empty until a search; a search lists matching securities,
  #   never the source; one of another currency or benchmark flag is
  #   disabled and names its reason; the only legal target is chosen.
  # - "Continue to preview" goes on to step 2.
  test "step 1 searches the target and names why a candidate cannot take the history", ctx do
    buy!(ctx, ctx.source, "5", "110.00", ~D[2025-02-10])
    buy!(ctx, ctx.target, "10", "100.00", ~D[2025-01-10])
    buy!(ctx, ctx.target, "2", "120.00", ~D[2025-07-01])
    usd = security!("Meridian Global Equity ETF USD", isin: "XS0000000033", currency: "USD")
    bench = security!("Meridian World Index", isin: "XS0000000066", benchmark: true)

    {:ok, view, _html} = live(ctx.conn, "/securities")
    open_menu(view, ctx.source)

    menu = view |> element("#row-menu-#{ctx.source.id}") |> render()
    assert menu =~ ~r/Mark as benchmark.*Merge into….*Delete/s
    refute has_element?(view, "[data-role='menu-merge'].row-context-menu__item--danger")

    view |> element("#row-menu-#{ctx.source.id} [data-role='menu-merge']") |> render_click()

    assert has_element?(view, "#security-merge-dialog h2", "Merge Meridian Global Equity ETF")
    assert has_element?(view, "#security-merge-dialog", "Step 1 of 2 · Target")

    assert view |> element("#security-merge-dialog [data-role='merge-route']") |> render() =~
             "XS0000000025 · EUR · 1 booking · created #{Date.to_iso8601(Clock.today())}"

    refute has_element?(view, "#security-merge-dialog [data-role='merge-target']")

    search(view, "Meridian")

    refute has_element?(view, "#merge-target-#{ctx.source.id}")
    assert has_element?(view, "#merge-target-#{ctx.target.id}:not([disabled])[checked]")

    assert view |> element("[data-role='merge-target'][data-id='#{ctx.target.id}']") |> render() =~
             "2 bookings"

    assert has_element?(view, "#merge-target-#{usd.id}[disabled]")
    assert has_element?(view, "#merge-target-#{bench.id}[disabled]")

    assert view |> element("[data-role='merge-target'][data-id='#{usd.id}']") |> render() =~
             "different currency"

    assert view |> element("[data-role='merge-target'][data-id='#{bench.id}']") |> render() =~
             "only one of the two is a benchmark"

    assert has_element?(view, "#security-merge-dialog", "Not selectable (2)")

    view |> element("#security-merge-dialog [data-role='merge-continue']") |> render_click()
    assert has_element?(view, "#security-merge-dialog", "Step 2 of 2 · Preview")
  end

  # User story:
  # As the operator repairing a duplicate that carries a second ISIN and a
  # second copy of the history,
  # I want the preview of exactly that pair to ask which ISIN stays, as two
  # cards each saying what becomes of the other, nothing preselected, and
  # what to do with the equal bookings,
  # so that I make both decisions myself and see their consequence where I
  # make them (pick G3 = A, ADR-0050 §8, §9).
  #
  # Acceptance criteria:
  # - Source and target stand as two cards, the source's role "Source ·
  #   deleted", each with its ISIN and bookings.
  # - "ISIN afterwards" offers "Keep XS…01" and "Adopt XS…02", each with one
  #   consequence line; neither is checked.
  # - Holdings read as a sum, with the figure if the equal bookings go.
  # - The counts name the moved bookings, the equal ones, the quotes that
  #   fill gaps and the days both have a quote; the colliding manual quote
  #   is listed with both closes.
  # - The confirm is disabled with both missing choices named; choosing
  #   "Adopt" shows the date of the ISIN change prefilled with today.
  test "step 2 asks for the ISIN and the duplicates, nothing preselected", ctx do
    buy!(ctx, ctx.target, "10", "100.00", ~D[2025-01-10])
    buy!(ctx, ctx.target, "2", "120.00", ~D[2025-07-01])
    buy!(ctx, ctx.source, "2", "120.00", ~D[2025-07-01])
    buy!(ctx, ctx.source, "3", "105.00", ~D[2025-02-12])
    quote!(ctx.target, ~D[2025-12-31], "71.40")
    quote!(ctx.source, ~D[2025-12-31], "71.55")
    quote!(ctx.source, ~D[2026-01-02], "72.00")

    {:ok, view, _html} = live(ctx.conn, "/securities")
    to_preview(view, ctx.source, ctx.target)

    pair = view |> element("#security-merge-dialog [data-role='merge-pair']") |> render()
    assert pair =~ "Source · deleted"
    assert pair =~ "Target · stays"
    assert pair =~ "XS0000000025"
    assert pair =~ "XS0000000017"

    identity = view |> element("#security-merge-dialog [data-role='merge-identity-choice']")
    html = render(identity)
    assert html =~ "ISIN afterwards"
    assert html =~ "Keep XS0000000017"
    assert html =~ "XS0000000025 becomes a former ISIN of this security."
    assert html =~ "Adopt XS0000000025"

    assert html =~
             "XS0000000017 becomes a former ISIN; the target carries XS0000000025 afterwards."

    refute has_element?(view, "#security-merge-dialog input[name='merge[identity]'][checked]")
    refute has_element?(view, "#security-merge-dialog input[name='merge[isin_changed_on]']")

    # Each figure inside its own term (review finding M-6), not anywhere in
    # the block.
    sum = view |> element("#security-merge-dialog [data-role='merge-identity']") |> render()

    assert [source_term, target_term, result_term] =
             Regex.scan(~r/<b class="num">([^<]*)<small>/, sum, capture: :all_but_first)

    assert {source_term, target_term, result_term} == {["5"], ["12"], ["17"]}
    assert sum =~ "15 shares if the equal booking is removed"

    # The equal bookings have a two-line form under 720 px beside the table
    # (the closing act, DC-10), so where each stands never scrolls away.
    assert has_element?(view, "[data-role='merge-pairs'] .merge-wide table.merge-table")

    pair_line =
      view |> element("[data-role='merge-pairs'] .merge-lines.merge-narrow li") |> render()

    assert pair_line =~ "2025-07-01"
    assert pair_line =~ "Depot 1"

    counts = view |> element("#security-merge-dialog [data-role='merge-counts']") |> render()
    assert counts =~ ~r/<dt>2<\/dt>\s*<dd>\s*bookings move to the target/
    assert counts =~ ~r/<dt>1<\/dt>\s*<dd>\s*booking is equal in both securities/
    assert counts =~ ~r/<dt>1<\/dt>\s*<dd>\s*quote of the source fills a gap in the target/
    assert counts =~ ~r/<dt>1<\/dt>\s*<dd>\s*day with a quote in both — the target&#39;s applies/

    quotes =
      view |> element("#security-merge-dialog [data-role='merge-quote-collisions']") |> render()

    assert quotes =~ "2025-12-31"
    assert quotes =~ "71.40"
    assert quotes =~ "71.55"

    refute has_element?(view, "#security-merge-dialog input[name='merge[collapse]'][checked]")
    assert has_element?(view, "#security-merge-dialog [data-role='merge-confirm'][disabled]")

    assert view |> element("#security-merge-dialog [data-role='merge-why']") |> render() =~
             "Choice for the ISIN missing · Choice for the equal booking missing"

    choose(view, %{identity: "adopt_source_isin"})

    assert has_element?(
             view,
             "#security-merge-dialog input[name='merge[isin_changed_on]'][value='#{Date.to_iso8601(Clock.today())}']"
           )

    assert has_element?(view, "#security-merge-dialog [data-role='merge-confirm'][disabled]")
    choose(view, %{identity: "adopt_source_isin", collapse: "true"})
    refute has_element?(view, "#security-merge-dialog [data-role='merge-confirm'][disabled]")

    # The result follows the choice (the closing act, UAT-2; DESIGN G2-B),
    # and the line under it names the other answer's figure.
    sum = view |> element("#security-merge-dialog [data-role='merge-identity']") |> render()

    assert [_source, _target, ["15"]] =
             Regex.scan(~r/<b class="num">([^<]*)<small>/, sum, capture: :all_but_first)

    assert sum =~ "17 shares if the equal booking is kept (+2)"

    assert has_element?(
             view,
             "#security-merge-dialog [data-role='merge-confirm']",
             "Merge into Meridian Global Equity ETF"
           )
  end

  # User story:
  # As the operator who made both choices,
  # I want the confirm to apply exactly the plan I read, with my choices,
  # then close, report inline and open the survivor, whose detail says it
  # carries a former ISIN and what it was merged from,
  # so that the repair is visible where I read the security afterwards
  # (board 03, "Danach").
  #
  # Acceptance criteria:
  # - Confirming merges under the preview's digest and both choices: the
  #   source is gone, the target carries the adopted ISIN, the old one is a
  #   former ISIN from the date given, the record names the choices.
  # - The result is reported inline; the survivor's detail opens and its
  #   basis line names the former ISIN and the merge, the merge's date
  #   linking its record in the merge list (Sprint 17 V1, G2-A ⑤).
  test "confirming applies the digest and both choices, and the survivor says so", ctx do
    buy!(ctx, ctx.target, "10", "100.00", ~D[2025-01-10])
    buy!(ctx, ctx.target, "2", "120.00", ~D[2025-07-01])
    buy!(ctx, ctx.source, "2", "120.00", ~D[2025-07-01])
    buy!(ctx, ctx.source, "3", "105.00", ~D[2025-02-12])

    {:ok, view, _html} = live(ctx.conn, "/securities")
    to_preview(view, ctx.source, ctx.target)

    choose(view, %{identity: "adopt_source_isin", collapse: "true", isin_changed_on: "2025-09-15"})

    view |> element("#security-merge-dialog [data-role='merge-confirm']") |> render_click()
    # The merge runs in the background (the closing act, EH-2).
    render_async(view)

    refute Catalog.get_security(ctx.source.id)
    target = Catalog.get_security(ctx.target.id)
    assert target.isin == "XS0000000025"

    assert [%{former_isin: "XS0000000017", changed_on: ~D[2025-09-15]}] =
             Catalog.list_identifier_aliases(target)

    record = Lifecycle.merge_of(:security, ctx.source.id)
    assert record.target_id == ctx.target.id

    assert %{"collapse_key_equal" => true, "identity_choice" => "adopt_source_isin"} =
             record.manifest["choices"]

    refute has_element?(view, "#security-merge-dialog")

    # The target's name sits in <bdi> since #968 (pick H8.8).
    assert has_element?(view, "#securities-action-result bdi", "Meridian Global Equity ETF")

    assert view
           |> element("#securities-action-result")
           |> render()
           |> Floki.parse_fragment!()
           |> Floki.text() =~
             "Merged into Meridian Global Equity ETF: 1 booking moved, 1 duplicate removed. ISIN now XS0000000025."

    assert_patch(view, "/securities/#{ctx.target.id}")

    basis = view |> element("[data-role='overview-basis']") |> render() |> Floki.parse_fragment!()
    words = basis |> Floki.text() |> String.split() |> Enum.join(" ")
    assert words =~ "former ISIN XS0000000017 (until 2025-09-15)"

    assert words =~
             "merged on #{Date.to_iso8601(Clock.today())} from “Meridian Global Equity ETF” (then XS0000000025)"

    # Sprint 17 V1 (G2-A ⑤): the merge's date is the way into its record on
    # Accounts & depots.
    assert Floki.attribute(Floki.find(basis, "a[data-role='overview-merge-link']"), "href") ==
             ["/portfolios?merge=#{record.id}#merge-records"]

    # The basis line is a flex row: its clauses sit in one inline span, so
    # the link does not split the sentence into flex items (closing act γ
    # D5).
    assert [{"p", _attrs, [{"span", span_attrs, _clauses}]}] = basis
    assert {"class", "summary-basis__text"} in span_attrs
  end

  # User story (#1022: the preview reads the buckets it names by id):
  # As the operator merging two securities whose positions sit in buckets,
  # I want the preview to name each bucket it talks about,
  # so that I see which views a merge would change, by name.
  #
  # Acceptance criteria:
  # - A refusal for differing position buckets names the depot and each
  #   side's buckets by name ("no buckets" for none).
  # - A position the merge moves into a depot the target does not hold lists
  #   its buckets by name among the settings the merge carries.
  test "the preview names the buckets of a refused and of a carried position", ctx do
    alias Portfolixir.Buckets
    import Portfolixir.WorldFixtures, only: [printable_bucket!: 1]

    spec = printable_bucket!(%{name: "Speculative #{System.unique_integer([:positive])}"})
    buy!(ctx, ctx.source, "3", "105.00", ~D[2025-02-12])
    buy!(ctx, ctx.target, "10", "100.00", ~D[2025-01-10])
    :ok = Buckets.set_position_override(Actor.owner_ui(), ctx.depot, ctx.source, [spec.id])

    {:ok, view, _html} = live(ctx.conn, "/securities")
    to_preview(view, ctx.source, ctx.target)

    refusal = view |> element("#security-merge-dialog [data-role='merge-refused']") |> render()
    assert refusal =~ "Depot 1 — source: #{spec.name} · target: no buckets"

    {:ok, depot2} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: ctx.portfolio.id,
        cash_account_id: ctx.cash.id,
        name: "Depot 2"
      })

    other = security!("Meridian Global Equity ETF", isin: "XS0000000041")
    buy!(%{ctx | depot: depot2}, other, "4", "101.00", ~D[2025-03-03])
    :ok = Buckets.set_position_override(Actor.owner_ui(), depot2, other, [spec.id])

    {:ok, view, _html} = live(ctx.conn, "/securities")
    to_preview(view, other, ctx.target)

    dialog = view |> element("#security-merge-dialog") |> render()
    assert dialog =~ "Position buckets"
    assert dialog =~ spec.name
  end

  # User story:
  # As the operator who opened the menu on the security that carries the
  # research log,
  # I want the preview to refuse, say why in words, and offer the merge the
  # other way when that one passes,
  # so that I never lose a research entry and still reach the repair
  # (ADR-0044, ADR-0050 §9's reverse direction).
  #
  # Acceptance criteria:
  # - A problem note: the source has research entries (count and last
  #   date), which are never moved or deleted; no confirm.
  # - "Merge the other way" swaps the pair and shows its preview.
  test "a refusal names its reason, and offers the merge the other way when it is real", ctx do
    buy!(ctx, ctx.source, "3", "105.00", ~D[2025-02-12])
    note!(ctx.source, ~D[2026-01-15])

    {:ok, view, _html} = live(ctx.conn, "/securities")
    to_preview(view, ctx.source, ctx.target)

    refusal = view |> element("#security-merge-dialog [data-role='merge-refused']") |> render()

    assert refusal =~
             "Merging is not possible: the source has 1 research entry, the last of 2026-01-15. Research entries are never moved or deleted; a security with entries can only be the target."

    refute has_element?(view, "#security-merge-dialog [data-role='merge-confirm']")

    view |> element("#security-merge-dialog [data-role='merge-other-way']") |> render_click()

    refute has_element?(view, "#security-merge-dialog [data-role='merge-refused']")
    assert has_element?(view, "#security-merge-dialog [data-role='merge-confirm']")

    pair = view |> element("#security-merge-dialog [data-role='merge-pair']") |> render()
    assert pair =~ ~r/Source · deleted.*XS0000000017.*Target · stays.*XS0000000025/s
  end

  # User story:
  # As the operator whose duplicate is read by a policy rule while the other
  # security carries research entries,
  # I want the preview to say that neither direction is possible, naming
  # both reasons and the rule, and to offer no way it cannot keep,
  # so that I know both securities stay as they are (board 03, "keine
  # Richtung möglich").
  test "no direction possible: both reasons, the rule named, no remedy invented", ctx do
    buy!(ctx, ctx.source, "3", "105.00", ~D[2025-02-12])
    rule!(ctx.portfolio, ctx.source, "Single name cap")
    note!(ctx.target, ~D[2026-01-15])

    {:ok, view, _html} = live(ctx.conn, "/securities")
    to_preview(view, ctx.source, ctx.target)

    refusal = view |> element("#security-merge-dialog [data-role='merge-refused']") |> render()
    assert refusal =~ "Merging is not possible: the source is read by policy rules:"
    assert refusal =~ "Single name cap"
    assert refusal =~ "The other way is refused too: the target has 1 research entry"
    assert refusal =~ "No direction is possible; both securities stay unchanged."
    refute has_element?(view, "#security-merge-dialog [data-role='merge-other-way']")
  end

  # User story:
  # As the operator whose duplicate and its twin each carry a split of the
  # same day with other ratios,
  # I want the remedy to say which split to delete,
  # so that I am not told to book a split both already carry (review
  # finding M-3, board 14 ④ and board 03).
  #
  # Acceptance criteria:
  # - The refusal names the day and both ratios, and the remedy says to
  #   delete the split with the wrong ratio in the Transactions tab.
  test "two split ratios on one day name the split to delete", ctx do
    buy!(ctx, ctx.target, "4", "10.00", ~D[2025-01-12])
    buy!(ctx, ctx.source, "2", "10.00", ~D[2025-01-10])
    split!(ctx.portfolio, ctx.source, ~D[2025-03-01], {2, 1})
    split!(ctx.portfolio, ctx.target, ~D[2025-03-01], {3, 1})

    {:ok, view, _html} = live(ctx.conn, "/securities")
    to_preview(view, ctx.source, ctx.target)

    refusal = view |> element("#security-merge-dialog [data-role='merge-refused']") |> render()

    assert refusal =~
             "Remedy: delete the split with the wrong ratio in the Transactions tab, then check again."

    refute refusal =~ "book the split"
  end

  # User story (the closing act, UAT-5 / DC-3):
  # As the operator reading the two-ratios refusal in German,
  # I want the merge's sides called Quelle and Ziel and the conflict said
  # once,
  # so that the refusal neither borrows the allocation column's "Soll" nor
  # repeats itself three times under "Außerdem".
  #
  # Acceptance criteria:
  # - The refusal names the day and both ratios once; no "Außerdem" line
  #   restates a split conflict of that day, and "Soll" appears nowhere.
  # - A split two portfolios book on one day with other ratios is named
  #   with the merge's sides, "(Quelle)" and "(Ziel)".
  test "the German two-ratios refusal says the conflict once, with Quelle and Ziel", ctx do
    buy!(ctx, ctx.target, "4", "10.00", ~D[2025-01-12])
    buy!(ctx, ctx.source, "2", "10.00", ~D[2025-01-10])
    split!(ctx.portfolio, ctx.source, ~D[2025-03-01], {2, 1})
    split!(ctx.portfolio, ctx.target, ~D[2025-03-01], {3, 1})

    {:ok, view, _html} = live(ctx.conn, "/securities?locale=de")
    to_preview(view, ctx.source, ctx.target)

    refusal = view |> element("#security-merge-dialog [data-role='merge-refused']") |> render()

    assert refusal =~ "Zusammenführen nicht möglich"
    assert refusal =~ "2025-03-01"
    refute refusal =~ "Außerdem"
    refute refusal =~ "Soll"
  end

  # Acceptance criteria (the closing act, DC-3): where two portfolios split
  # the two securities on one day with other ratios, the split-event rule
  # names each ratio's side as the merge's side — "(Quelle)" and "(Ziel)",
  # never the allocation column's "(Soll)".
  test "a split two portfolios book with other ratios names the merge's sides", ctx do
    {:ok, second} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Second", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: second.id,
        name: "Second cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: second.id,
        cash_account_id: cash.id,
        name: "Second depot"
      })

    buy!(ctx, ctx.source, "2", "10.00", ~D[2025-01-10])

    buy!(
      %{ctx | portfolio: second, depot: depot, cash: cash},
      ctx.target,
      "4",
      "10.00",
      ~D[2025-01-12]
    )

    split!(ctx.portfolio, ctx.source, ~D[2025-03-01], {2, 1})
    split!(second, ctx.target, ~D[2025-03-01], {3, 1})

    {:ok, view, _html} = live(ctx.conn, "/securities?locale=de")
    to_preview(view, ctx.source, ctx.target)

    refusal = view |> element("#security-merge-dialog [data-role='merge-refused']") |> render()

    assert refusal =~ "splitten die Wertpapiere 2:1 (Quelle) · 3:1 (Ziel)"
    refute refusal =~ "Soll"
  end

  # User story:
  # As the operator of an instance where an imported booking of a duplicate
  # was once re-typed into a split,
  # I want the preview to refuse the merge that would have to move it,
  # naming the split and the remedy,
  # so that the confirm never fails at the database (review finding F3,
  # board 14 ③).
  #
  # Acceptance criteria:
  # - The refusal says the split carries an import hash, names it by date
  #   and number, gives the remedy and offers "Check again".
  test "a split that still carries an import hash is named with its remedy", ctx do
    buy!(ctx, ctx.source, "2", "10.00", ~D[2025-01-10])
    legacy = legacy_split!(ctx, ctx.source, ~D[2025-03-01])

    {:ok, view, _html} = live(ctx.conn, "/securities")
    to_preview(view, ctx.source, ctx.target)

    refusal = view |> element("#security-merge-dialog [data-role='merge-refused']") |> render()

    assert refusal =~
             "a split of the source still carries an import hash from before the import-hash check and cannot be moved."

    assert refusal =~ "Split on 2025-03-01 · no. #{legacy.id}"

    assert refusal =~
             "Remedy: change its kind back to the one it was imported as, or delete it, then check again."

    assert has_element?(view, "#security-merge-dialog [data-role='merge-recheck']")
  end

  # User story (closing act, CR-2):
  # As the operator whose duplicate carries an ISIN that fails its check
  # digit, or a WKN the catalog no longer accepts on a change,
  # I want the preview to refuse the ISIN by name with the way out, and to
  # show a WKN it will not adopt,
  # so that the merge I confirm is never refused by the catalog afterwards.
  #
  # Acceptance criteria:
  # - The refusal names the ISIN and its check digit, says to correct or
  #   clear it on the source, offers "Check again", and no confirm.
  # - Once the ISIN is cleared and the WKN kept, the master data list the
  #   WKN as not adopted, with the WKN's rule.
  test "an ISIN failing its check digit is refused by name; a WKN out of shape is not adopted",
       ctx do
    buy!(ctx, ctx.source, "2", "10.00", ~D[2025-01-10])
    raw_identifiers!(ctx.source, isin: "XS0000004560", wkn: "A1B2C")

    {:ok, view, _html} = live(ctx.conn, "/securities")
    to_preview(view, ctx.source, ctx.target)

    refusal = view |> element("#security-merge-dialog [data-role='merge-refused']") |> render()

    assert refusal =~
             "the source&#39;s ISIN XS0000004560 fails its check digit, and the merge would write it onto the target."

    assert refusal =~
             "Remedy: correct or clear the source&#39;s ISIN in its master data, then check again."

    assert has_element?(view, "#security-merge-dialog [data-role='merge-recheck']")
    refute has_element?(view, "#security-merge-dialog [data-role='merge-confirm']")

    raw_identifiers!(ctx.source, isin: nil, wkn: "A1B2C")
    view |> element("#security-merge-dialog [data-role='merge-recheck']") |> render_click()

    master = view |> element("#security-merge-dialog [data-role='merge-master-data']") |> render()
    assert master =~ "A1B2C"
    assert master =~ "not adopted: a WKN is six letters or digits."
  end

  # User story:
  # As the operator whose duplicate carries a split its twin never booked,
  # I want the refusal to name the split, its ratio and the side lacking it,
  # and the way out,
  # so that I can book the split first and check again (ADR-0028 §2).
  test "a split-event mismatch is named with its date, ratio and side", ctx do
    buy!(ctx, ctx.target, "4", "10.00", ~D[2025-01-12])
    buy!(ctx, ctx.source, "2", "10.00", ~D[2025-01-10])
    split!(ctx.portfolio, ctx.source, ~D[2025-03-01], {2, 1})

    {:ok, view, _html} = live(ctx.conn, "/securities")
    to_preview(view, ctx.source, ctx.target)

    refusal =
      view
      |> element("#security-merge-dialog [data-role='merge-refused']")
      |> render()
      |> String.replace("&#39;", "'")

    assert refusal =~
             "the source's split of 2025-03-01 (2:1) is not a split of the target, which has a booking of 2025-01-12 before it."

    # The remedy names the security that lacks the split (the closing act,
    # UAT-5), not "that side", and the linearity rule of the same day does
    # not say the conflict again.
    assert refusal =~
             "Remedy: book the split of 2025-03-01 (2:1) on XS0000000017 too, or delete the wrong split, then check again."

    refute refusal =~ "Also:"
    refute refusal =~ "on the security that lacks it"

    assert has_element?(view, "#security-merge-dialog [data-role='merge-recheck']")
  end

  # User story:
  # As the operator merging two securities without an ISIN,
  # I want a merge that would leave an identifier leading nowhere refused,
  # naming the identifier, without a remedy the version does not have,
  # so that the next import never creates the source again (ADR-0050 §9).
  test "an identity that would no longer resolve is refused, with no invented remedy", ctx do
    target = security!("Fund A")
    source = security!("Fund B")
    buy!(ctx, source, "1", "10.00", ~D[2025-01-10])

    {:ok, view, _html} = live(ctx.conn, "/securities")
    open_menu(view, source)
    view |> element("#row-menu-#{source.id} [data-role='menu-merge']") |> render_click()
    search(view, "Fund A")
    pick(view, target)
    view |> element("#security-merge-dialog [data-role='merge-continue']") |> render_click()

    refusal = view |> element("#security-merge-dialog [data-role='merge-refused']") |> render()

    assert refusal =~
             "after the merge, an identifier of the two would no longer lead to the target: name “Fund B” (EUR)."

    assert refusal =~ "This version has no way around it; both securities stay unchanged."
  end

  # User story:
  # As the operator whose securities changed while I read the preview,
  # I want the confirm to refuse and show me the new plan, with my choices
  # cleared,
  # so that nothing I did not read is ever written (ADR-0050 §10).
  test "a changed plan re-renders the fresh preview with a notice and clears the choices", ctx do
    buy!(ctx, ctx.target, "10", "100.00", ~D[2025-01-10])
    buy!(ctx, ctx.source, "3", "105.00", ~D[2025-02-12])

    {:ok, view, _html} = live(ctx.conn, "/securities")
    to_preview(view, ctx.source, ctx.target)
    choose(view, %{identity: "keep_target_isin"})

    buy!(ctx, ctx.target, "1", "101.00", ~D[2025-08-01])
    view |> element("#security-merge-dialog [data-role='merge-confirm']") |> render_click()
    # The merge runs in the background (the closing act, EH-2).
    render_async(view)

    assert Catalog.get_security(ctx.source.id)

    assert has_element?(
             view,
             "#security-merge-dialog [data-role='merge-stale']",
             "The securities changed while the preview was open. Nothing was merged; the preview now shows the new state."
           )

    refute has_element?(view, "#security-merge-dialog input[name='merge[identity]'][checked]")
    assert has_element?(view, "#security-merge-dialog [data-role='merge-confirm'][disabled]")

    # The body is scrolled back to the note at its head (the closing act,
    # DC-2).
    assert_push_event(view, "modal:scroll-top", %{id: "security-merge-dialog"})
  end

  # User story:
  # As the operator trying to delete a duplicate that carries bookings,
  # I want "Cannot delete" to offer "Merge into…" beside "Retire instead",
  # so that I find the repair where the bookings stop me (board 03, second
  # entry); not where a rule reads the security, since the merge would be
  # refused as well.
  test "Cannot delete offers Merge into… for bookings, not for a rule", ctx do
    buy!(ctx, ctx.source, "3", "105.00", ~D[2025-02-12])
    ruled = security!("Kestrel Industrial Group NV", isin: "XS0000000041")
    rule!(ctx.portfolio, ruled, "Kestrel cap")

    {:ok, view, _html} = live(ctx.conn, "/securities")
    delete_row(view, ctx.source)

    assert has_element?(view, "#delete-blocked-dialog [data-role='delete-blocked-merge']")

    # Since #918 (pick H8.2 = A) the sentence names the events a merge
    # carries too, and what retiring keeps.
    assert view |> element("#delete-blocked-dialog") |> render() =~
             "If it is a duplicate, “Merge into…” moves its bookings, quotes and events into the other security."

    view |> element("#delete-blocked-dialog [data-role='delete-blocked-merge']") |> render_click()
    refute has_element?(view, "#delete-blocked-dialog")
    assert has_element?(view, "#security-merge-dialog", "Step 1 of 2 · Target")

    view |> element("#security-merge-dialog [data-role='merge-dismiss']") |> render_click()
    delete_row(view, ruled)
    assert has_element?(view, "#delete-blocked-dialog")
    refute has_element?(view, "#delete-blocked-dialog [data-role='delete-blocked-merge']")
  end

  test "speaks German in both steps", ctx do
    buy!(ctx, ctx.target, "2", "120.00", ~D[2025-07-01])
    buy!(ctx, ctx.source, "2", "120.00", ~D[2025-07-01])

    {:ok, view, _html} = live(ctx.conn, "/securities?locale=de")
    open_menu(view, ctx.source)

    assert has_element?(
             view,
             "#row-menu-#{ctx.source.id} [data-role='menu-merge']",
             "Zusammenführen in…"
           )

    view |> element("#row-menu-#{ctx.source.id} [data-role='menu-merge']") |> render_click()

    assert has_element?(
             view,
             "#security-merge-dialog h2",
             "Meridian Global Equity ETF zusammenführen"
           )

    assert has_element?(view, "#security-merge-dialog", "Schritt 1 von 2 · Ziel")

    # A retired twin is out for the security's state, in its own word
    # (the closing act, UAT-6), not the policy rule's "beendet".
    retired = security!("Meridian Global Equity ETF (alt)", isin: "XS0000000033")
    {:ok, _} = Catalog.update_security(Actor.owner_ui(), retired, %{is_retired: true})
    search(view, "Meridian")

    candidate =
      view
      |> element("#security-merge-dialog [data-role='merge-target'][data-id='#{retired.id}']")
      |> render()

    assert candidate =~ "stillgelegt"
    refute candidate =~ "beendet"

    search(view, "Meridian")
    view |> element("#security-merge-dialog [data-role='merge-continue']") |> render_click()

    assert has_element?(view, "#security-merge-dialog", "Schritt 2 von 2 · Vorschau")
    assert has_element?(view, "#security-merge-dialog", "ISIN danach")
    assert has_element?(view, "#security-merge-dialog", "XS0000000017 behalten")

    # The two sides of the sum are the merge's sides, not the allocation's
    # "Soll" column that a bare "Target" translates to elsewhere.
    assert has_element?(view, "[data-role='merge-identity'] i", "Quelle")
    assert has_element?(view, "[data-role='merge-identity'] i", "Ziel")
    refute has_element?(view, "[data-role='merge-identity'] i", "Soll")

    assert has_element?(
             view,
             "#security-merge-dialog [data-role='merge-confirm']",
             "In Meridian Global Equity ETF zusammenführen"
           )
  end

  # -- helpers ----------------------------------------------------------------

  defp open_menu(view, security) do
    view
    |> element(
      ~s(#securities-table button[phx-click="open_row_menu"][phx-value-id="#{security.id}"])
    )
    |> render_click()
  end

  defp delete_row(view, security) do
    open_menu(view, security)

    view
    |> element(~s(#row-menu-#{security.id} button[phx-value-action="delete"]))
    |> render_click()
  end

  defp search(view, query) do
    view
    |> element("#security-merge-dialog form[data-role='merge-search']")
    |> render_change(%{merge: %{q: query}})
  end

  defp pick(view, target) do
    view
    |> element("#security-merge-dialog form[data-role='merge-target-form']")
    |> render_change(%{merge: %{target_id: "#{target.id}"}})
  end

  defp to_preview(view, source, target) do
    open_menu(view, source)
    view |> element("#row-menu-#{source.id} [data-role='menu-merge']") |> render_click()
    search(view, target.name)
    pick(view, target)
    view |> element("#security-merge-dialog [data-role='merge-continue']") |> render_click()
  end

  defp choose(view, choices) do
    view
    |> element("#security-merge-dialog form[data-role='merge-choice-form']")
    |> render_change(%{merge: choices})
  end

  defp security!(name, opts \\ []) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        isin: Keyword.get(opts, :isin),
        currency_code: Keyword.get(opts, :currency, "EUR"),
        asset_class: "etf",
        is_benchmark: Keyword.get(opts, :benchmark, false)
      })

    security
  end

  # Identifiers stored the way a create stores them, where the catalog's
  # rules for a changed identifier do not apply (E25 G23).
  defp raw_identifiers!(security, isin: isin, wkn: wkn) do
    {:ok, _} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'owner_ui', true)")

        Repo.query!("UPDATE securities SET isin = $2, wkn = $3 WHERE id = $1", [
          security.id,
          isin,
          wkn
        ])
      end)

    :ok
  end

  # Written the way the Portfolio Performance importer writes a trade, so
  # two equal bookings of the two securities pair (ADR-0050 §8).
  defp buy!(ctx, security, quantity, price, date) do
    attrs = %{
      portfolio_id: ctx.portfolio.id,
      securities_account_id: ctx.depot.id,
      cash_account_id: ctx.cash.id,
      security_id: security.id,
      type: "buy",
      date: date,
      quantity: quantity,
      price: price,
      currency_code: "EUR"
    }

    {:ok, %{transaction: tx}} =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:transaction, Transaction.import_changeset(%Transaction{}, attrs))
      |> Journal.record(Actor.import_session(),
        resource_type: "transaction",
        operation: :create,
        source: :transaction
      )
      |> Repo.transaction()

    tx
  end

  # The state an old writer could leave: an imported dividend, hashed, whose
  # type a later edit changed to a 2:1 split, with the import-hash kind check
  # re-added NOT VALID by the migration's own step. (This module runs
  # synchronously, so the constraint swap waits for no other test.)
  defp legacy_split!(ctx, security, date) do
    {:ok, dividend} =
      Ledger.create_transaction(
        Actor.import_session(),
        %{
          portfolio_id: ctx.portfolio.id,
          type: "dividend",
          date: date,
          security_id: security.id,
          securities_account_id: ctx.depot.id,
          cash_account_id: ctx.cash.id,
          gross_amount: "1.00",
          currency_code: "EUR"
        },
        import_hash: "synthetic-legacy-split-live"
      )

    Repo.query!("ALTER TABLE transactions DROP CONSTRAINT transactions_import_hash_kind_check")

    Repo.transaction(fn ->
      Repo.query!("SELECT set_config('portfolixir.journal_actor', 'owner_ui', true)")

      Repo.query!(
        """
        UPDATE transactions
        SET type = 'split', split_ratio_numerator = 2, split_ratio_denominator = 1,
            quantity = NULL, price = NULL, gross_amount = NULL, security_amount = NULL,
            settlement_amount = NULL, settlement_fx_rate = NULL, cash_account_id = NULL,
            counter_cash_account_id = NULL, securities_account_id = NULL,
            counter_securities_account_id = NULL
        WHERE id = $1
        """,
        [dividend.id]
      )
    end)

    module = Portfolixir.Repo.Migrations.CreateRetiredImportHashes

    migration =
      case Code.ensure_loaded(module) do
        {:module, module} ->
          module

        {:error, _not_loaded} ->
          [{module, _bytecode}] =
            Code.require_file(
              "priv/repo/migrations/20260925130000_create_retired_import_hashes.exs"
            )

          module
      end

    ExUnit.CaptureLog.capture_log(fn -> migration.add_kind_check(Repo) end)
    Repo.get!(Transaction, dividend.id)
  end

  defp split!(portfolio, security, date, {numerator, denominator}) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        security_id: security.id,
        type: "split",
        date: date,
        currency_code: security.currency_code,
        split_ratio_numerator: numerator,
        split_ratio_denominator: denominator
      })

    tx
  end

  defp quote!(security, date, close) do
    {:ok, _} =
      Catalog.upsert_quotes(Actor.owner_ui(), security.id, [
        %{"date" => Date.to_iso8601(date), "close" => close}
      ])

    :ok
  end

  defp note!(security, as_of) do
    {:ok, note} =
      Knowledge.append_note(Actor.owner_ui(), %{
        security_id: security.id,
        author: "operator",
        kind: "evidence",
        body: "a synthetic finding that must never vanish",
        source_quality: "primary",
        as_of: as_of
      })

    note
  end

  defp rule!(portfolio, security, name) do
    {:ok, rule} =
      PolicyRules.create_rule(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        version: %{
          subject_type: "security",
          security_id: security.id,
          measure: "weight",
          kind: "cap",
          threshold: "12",
          severity: "hard"
        }
      })

    rule
  end
end
