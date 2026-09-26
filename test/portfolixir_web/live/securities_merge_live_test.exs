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

    sum = view |> element("#security-merge-dialog [data-role='merge-identity']") |> render()
    assert sum =~ "5"
    assert sum =~ "12"
    assert sum =~ "17"
    assert sum =~ "15 shares if the equal booking is removed"

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
  #   basis line names the former ISIN and the merge.
  test "confirming applies the digest and both choices, and the survivor says so", ctx do
    buy!(ctx, ctx.target, "10", "100.00", ~D[2025-01-10])
    buy!(ctx, ctx.target, "2", "120.00", ~D[2025-07-01])
    buy!(ctx, ctx.source, "2", "120.00", ~D[2025-07-01])
    buy!(ctx, ctx.source, "3", "105.00", ~D[2025-02-12])

    {:ok, view, _html} = live(ctx.conn, "/securities")
    to_preview(view, ctx.source, ctx.target)

    choose(view, %{identity: "adopt_source_isin", collapse: "true", isin_changed_on: "2025-09-15"})

    view |> element("#security-merge-dialog [data-role='merge-confirm']") |> render_click()

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

    assert view |> element("#securities-action-result") |> render() =~
             "Merged into Meridian Global Equity ETF: 1 booking moved, 1 duplicate removed. ISIN now XS0000000025."

    assert_patch(view, "/securities/#{ctx.target.id}")

    basis = view |> element("[data-role='overview-basis']") |> render()
    assert basis =~ "former ISIN XS0000000017 (until 2025-09-15)"

    assert basis =~
             "merged on #{Date.to_iso8601(Clock.today())} from “Meridian Global Equity ETF” (then XS0000000025)"
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

    assert refusal =~
             "Remedy: book the split on that side first, or delete the wrong split, then check again."

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

    assert Catalog.get_security(ctx.source.id)

    assert has_element?(
             view,
             "#security-merge-dialog [data-role='merge-stale']",
             "The securities changed while the preview was open. Nothing was merged; the preview now shows the new state."
           )

    refute has_element?(view, "#security-merge-dialog input[name='merge[identity]'][checked]")
    assert has_element?(view, "#security-merge-dialog [data-role='merge-confirm'][disabled]")
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

    assert view |> element("#delete-blocked-dialog") |> render() =~
             "If it is a duplicate, “Merge into…” moves its bookings and quotes into the other security."

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

    search(view, "Meridian")
    view |> element("#security-merge-dialog [data-role='merge-continue']") |> render_click()

    assert has_element?(view, "#security-merge-dialog", "Schritt 2 von 2 · Vorschau")
    assert has_element?(view, "#security-merge-dialog", "ISIN danach")
    assert has_element?(view, "#security-merge-dialog", "XS0000000017 behalten")

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
