defmodule PortfolixirWeb.AccountsMergeLiveTest do
  # ADR-0050 §7, §8, §10 on Accounts & depots (L5a, #328; board
  # 02-merge-preview, pick G2-B: two steps, the target first, then the
  # preview of exactly that pair). The merge the page applies is the one the
  # API applies (Portfolixir.Lifecycle); what is pinned here is what the
  # operator sees and sends. Every name, amount and quantity is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Main", base_currency_code: "EUR"})

    %{portfolio: portfolio}
  end

  describe "a cash account" do
    setup ctx do
      source = cash!(ctx.portfolio, "Tagesgeld (alt)")
      target = cash!(ctx.portfolio, "Tagesgeld")
      Map.merge(ctx, %{source: source, target: target})
    end

    # User story:
    # As the operator merging an obsolete cash account,
    # I want the first step to list every account with the reason it cannot
    # take the history, when it cannot,
    # so that I choose the target knowing why the others are out.
    #
    # Acceptance criteria:
    # - "Merge into…" opens step 1 of 2 titled for the source, with the
    #   source's currency, role, buckets, bookings and balance on one line.
    # - Every other cash account is listed; one of another currency,
    #   liquidity role or bucket set is disabled and names each reason.
    # - The only legal target is chosen; "Continue to preview" goes on.
    # - With no legal target the step says so and offers only Close.
    test "step 1 lists every target, and the reason for each one that cannot be chosen", ctx do
      {:ok, short} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Kurzfrist"})
      usd = cash!(ctx.portfolio, "Broker USD", "USD")
      credit = cash!(ctx.portfolio, "Kreditrahmen")

      {:ok, _} =
        Portfolios.update_cash_account(Actor.owner_ui(), credit, %{liquidity_role: "credit_line"})

      giro = cash!(ctx.portfolio, "Girokonto")
      :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), giro, [short.id])
      book!(ctx, ctx.source, "deposit", "100.00", ~D[2025-01-02])

      {:ok, view, _html} = live(ctx.conn, "/portfolios")
      open_merge(view, ctx.source)

      assert has_element?(view, "#merge-dialog h2", "Merge Tagesgeld (alt)")
      assert has_element?(view, "#merge-dialog", "Step 1 of 2 · Target")

      assert view |> element("#merge-dialog [data-role='merge-route']") |> render() =~
               "EUR · Free cash · Buckets: none · 1 booking · 100.00 EUR"

      assert has_element?(view, "#merge-target-#{ctx.target.id}:not([disabled])[checked]")

      for {account, reason} <- [
            {usd, "different currency"},
            {credit, "different liquidity role"},
            {giro, "different buckets"}
          ] do
        assert has_element?(view, "#merge-target-#{account.id}[disabled]")

        assert view |> element("[data-role='merge-target'][data-id='#{account.id}']") |> render() =~
                 reason
      end

      assert has_element?(view, "#merge-dialog", "Not selectable (3)")

      assert has_element?(
               view,
               "#merge-dialog",
               "Selectable: same currency, same liquidity role, same buckets."
             )

      view |> element("#merge-dialog [data-role='merge-continue']") |> render_click()
      assert has_element?(view, "#merge-dialog", "Step 2 of 2 · Preview")

      # No account meets the conditions for the USD account.
      view |> element("#merge-dialog [data-role='merge-dismiss']") |> render_click()
      refute has_element?(view, "#merge-dialog")
      open_merge(view, usd)
      assert has_element?(view, "#merge-dialog", "No account meets the conditions.")
      refute has_element?(view, "#merge-dialog [data-role='merge-continue']")
      assert has_element?(view, "#merge-dialog [data-role='merge-close']")
    end

    # User story:
    # As the operator about to merge,
    # I want the preview of exactly that pair: both balances as a sum, the
    # counts, every restated balance anchor, and the equal bookings with a
    # choice nothing preselects,
    # so that I confirm what the plan digest covers and decide the
    # duplicates myself.
    #
    # Acceptance criteria:
    # - Step 2 states source + target = balance after, and the balance if the
    #   equal bookings are removed.
    # - It counts the bookings that move, the transfers dropped, the anchors
    #   restated and the equal bookings.
    # - Each restated anchor reads date, account, stated, + other account,
    #   after.
    # - The equal bookings are listed; the two options each state the
    #   balance after; neither is checked, and the confirm is disabled with
    #   its reason until one is chosen.
    # - The former-name note and the deletion warning are shown.
    test "step 2 is the preview of exactly that pair, with the duplicate choice unset", ctx do
      rows = example!(ctx)
      {:ok, view, _html} = live(ctx.conn, "/portfolios")
      to_preview(view, ctx.source, ctx.target)

      route = view |> element("#merge-dialog [data-role='merge-route']") |> render()
      assert route =~ "Tagesgeld (alt)"
      assert route =~ "→"

      identity = view |> element("#merge-dialog [data-role='merge-identity']") |> render()
      assert identity =~ "902.50"
      assert identity =~ "807.50"
      assert identity =~ "1,710.00"
      assert identity =~ "1,702.50 EUR if the 2 equal bookings are removed"

      counts = view |> element("#merge-dialog [data-role='merge-counts']") |> render()
      # The source's five bookings other than the transfer move (the anchor
      # among them, restated); the transfer between the two is dropped.
      assert counts =~ ~r/<dt>5<\/dt>\s*<dd>\s*bookings move to Tagesgeld/
      assert counts =~ ~r/<dt>1<\/dt>\s*<dd>\s*transfer between the two accounts is dropped/
      assert counts =~ ~r/<dt>2<\/dt>\s*<dd>\s*set balances are adjusted/
      assert counts =~ ~r/<dt>2<\/dt>\s*<dd>\s*bookings are equal in both accounts/

      anchor =
        view
        |> element("[data-role='restated-anchor'][data-id='#{rows.s_anchor.id}']")
        |> render()

      assert anchor =~ "2025-04-30"
      assert anchor =~ "Tagesgeld (alt)"
      assert anchor =~ "900.00"
      assert anchor =~ "712.40"
      assert anchor =~ "1,612.40"

      pairs = view |> element("#merge-dialog [data-role='merge-pairs']") |> render()
      assert pairs =~ "2025-03-31"
      assert pairs =~ "12.40"

      refute has_element?(view, "#merge-dialog input[name='merge[collapse]'][checked]")
      assert has_element?(view, "#merge-dialog [data-role='merge-confirm'][disabled]")

      assert has_element?(
               view,
               "#merge-dialog [data-role='merge-why']",
               "Choice for 2 equal bookings missing"
             )

      assert has_element?(view, "#merge-dialog [data-role='collapse-true']", "1,702.50 EUR")
      assert has_element?(view, "#merge-dialog [data-role='collapse-false']", "1,710.00 EUR")

      assert has_element?(
               view,
               "#merge-dialog",
               "“Tagesgeld (alt)” becomes a former name of Tagesgeld. An import that names this account books to Tagesgeld afterwards."
             )

      assert has_element?(
               view,
               "#merge-dialog",
               "Tagesgeld (alt) is deleted afterwards. This cannot be undone; every changed booking is journaled."
             )
    end

    # User story:
    # As the operator who chose what to do with the duplicates,
    # I want the confirm to apply exactly the plan I read, with my choice,
    # so that the merge I approved is the merge that happens.
    #
    # Acceptance criteria:
    # - Choosing an option enables "Merge into <target>".
    # - Confirming merges under the preview's digest and the choice: the
    #   source is gone, the target carries the balance the option stated, the
    #   merge record names the choice and the operator.
    # - The dialog closes and the result is reported inline above the table.
    test "confirming applies the digest and the choice, and reports inline", ctx do
      example!(ctx)
      {:ok, view, _html} = live(ctx.conn, "/portfolios")
      to_preview(view, ctx.source, ctx.target)

      view
      |> element("#merge-dialog form[data-role='merge-choice-form']")
      |> render_change(%{merge: %{collapse: "true"}})

      refute has_element?(view, "#merge-dialog [data-role='merge-confirm'][disabled]")
      view |> element("#merge-dialog [data-role='merge-confirm']") |> render_click()

      refute Portfolios.get_cash_account(ctx.source.id)
      assert Decimal.equal?(Ledger.cash_balances()[ctx.target.id], Decimal.new("1702.50"))

      record = Lifecycle.merge_of(:cash_account, ctx.source.id)
      assert record.target_id == ctx.target.id
      assert record.manifest["choices"] == %{"collapse_key_equal" => true}
      assert record.actor_type == :owner_ui

      refute has_element?(view, "#merge-dialog")

      assert view |> element("#accounts-result") |> render() =~
               "Merged Tagesgeld (alt) into Tagesgeld: 3 bookings moved, 3 removed."
    end

    # User story:
    # As the operator whose accounts changed while I read the preview,
    # I want the confirm to refuse and show me the new plan,
    # so that nothing I did not read is ever written.
    #
    # Acceptance criteria:
    # - A booking added after the preview makes the confirm answer with the
    #   fresh preview and an attention note; nothing is merged.
    # - The note says what changed; the choice made before is cleared and
    #   the confirm waits for a new one.
    test "a changed plan re-renders the fresh preview with a notice and clears the choice", ctx do
      example!(ctx)
      {:ok, view, _html} = live(ctx.conn, "/portfolios")
      to_preview(view, ctx.source, ctx.target)

      view
      |> element("#merge-dialog form[data-role='merge-choice-form']")
      |> render_change(%{merge: %{collapse: "false"}})

      book!(ctx, ctx.target, "deposit", "50.00", ~D[2025-08-01])
      view |> element("#merge-dialog [data-role='merge-confirm']") |> render_click()

      assert Portfolios.get_cash_account(ctx.source.id)

      assert has_element?(
               view,
               "#merge-dialog [data-role='merge-stale']",
               "The accounts changed while the preview was open. Nothing was merged; the preview now shows the new state."
             )

      assert has_element?(
               view,
               "#merge-dialog",
               "Changed since opening: balance of Tagesgeld 807.50 → 857.50 EUR"
             )

      assert view |> element("#merge-dialog [data-role='merge-identity']") |> render() =~
               "1,760.00"

      refute has_element?(view, "#merge-dialog input[name='merge[collapse]'][checked]")
      assert has_element?(view, "#merge-dialog [data-role='merge-confirm'][disabled]")
    end

    test "Back returns to step 1 with the target kept", ctx do
      example!(ctx)
      {:ok, view, _html} = live(ctx.conn, "/portfolios")
      to_preview(view, ctx.source, ctx.target)

      view |> element("#merge-dialog [data-role='merge-back']") |> render_click()
      assert has_element?(view, "#merge-dialog", "Step 1 of 2 · Target")
      assert has_element?(view, "#merge-target-#{ctx.target.id}[checked]")
    end

    test "speaks German in both steps", ctx do
      example!(ctx)
      usd = cash!(ctx.portfolio, "Broker USD", "USD")
      {:ok, view, _html} = live(ctx.conn, "/portfolios?locale=de")
      open_merge(view, ctx.source)

      assert has_element?(view, "#merge-dialog h2", "Tagesgeld (alt) zusammenführen")
      assert has_element?(view, "#merge-dialog", "Schritt 1 von 2 · Ziel")
      assert has_element?(view, "#merge-dialog", "Ziel — bekommt alle Buchungen")

      assert view |> element("[data-role='merge-target'][data-id='#{usd.id}']") |> render() =~
               "andere Währung"

      view |> element("#merge-dialog [data-role='merge-continue']") |> render_click()
      assert has_element?(view, "#merge-dialog", "Schritt 2 von 2 · Vorschau")

      assert has_element?(
               view,
               "#merge-dialog [data-role='merge-why']",
               "Wahl für 2 gleiche Buchungen fehlt"
             )

      assert has_element?(
               view,
               "#merge-dialog [data-role='merge-confirm']",
               "In Tagesgeld zusammenführen"
             )
    end

    # The preview's cash half, worked: deposits on both, one transfer between
    # them, two equal interest bookings, an anchor on each side and a fee.
    defp example!(ctx) do
      %{
        s_deposit: book!(ctx, ctx.source, "deposit", "1000.00", ~D[2025-01-02]),
        t_deposit: book!(ctx, ctx.target, "deposit", "500.00", ~D[2025-01-03]),
        transfer: transfer!(ctx, "200.00", ~D[2025-02-01]),
        s_interest: book!(ctx, ctx.source, "interest", "12.40", ~D[2025-03-31]),
        t_interest: book!(ctx, ctx.target, "interest", "12.40", ~D[2025-03-31]),
        s_anchor: anchor!(ctx.source, "900.00", ~D[2025-04-30]),
        t_anchor: anchor!(ctx.target, "800.00", ~D[2025-05-31]),
        s_fee: book!(ctx, ctx.source, "fee", "5.00", ~D[2025-06-15]),
        s_interest_late: book!(ctx, ctx.source, "interest", "7.50", ~D[2025-07-31]),
        t_interest_late: book!(ctx, ctx.target, "interest", "7.50", ~D[2025-07-31])
      }
    end
  end

  describe "a depot" do
    setup ctx do
      cash_t = cash!(ctx.portfolio, "Broker cash")
      cash_s = cash!(ctx.portfolio, "Broker cash 2")

      Map.merge(ctx, %{
        cash_t: cash_t,
        cash_s: cash_s,
        target: depot!(ctx.portfolio, cash_t, "Depot 1"),
        source: depot!(ctx.portfolio, cash_s, "Depot 2"),
        meridian: security!("Meridian Global Equity ETF", "MRDN"),
        kestrel: security!("Kestrel Industrial Group NV", "KSTL"),
        heron: security!("Heron Solar AG", "HRN")
      })
    end

    # User story:
    # As the operator merging two depots at one broker,
    # I want the preview to show each affected position's quantity,
    # moving-average cost and realized result before and after, and the
    # rounding a split leaves once the positions combine,
    # so that I see what the merge restates before I confirm.
    #
    # Acceptance criteria:
    # - Step 2 lists every position the source holds: quantity as source +
    #   target → after, cost and realized result as source · target → after,
    #   "—" where the target holds none.
    # - A split whose combined rounding differs from the two rounded apart
    #   is listed with its date, ratio and both figures.
    # - Without equal bookings there is no choice and the confirm is enabled;
    #   the former-name note says the target keeps its own cash account.
    test "step 2 shows the affected positions before and after and the split rounding", ctx do
      buy!(ctx, ctx.target, ctx.cash_t, ctx.meridian, "60", "80.00", ~D[2025-01-10])
      buy!(ctx, ctx.source, ctx.cash_s, ctx.meridian, "40", "90.00", ~D[2025-02-10])
      buy!(ctx, ctx.source, ctx.cash_s, ctx.kestrel, "25", "41.20", ~D[2025-02-15])
      buy!(ctx, ctx.target, ctx.cash_t, ctx.heron, "1", "10.00", ~D[2025-01-10])
      buy!(ctx, ctx.source, ctx.cash_s, ctx.heron, "1", "10.00", ~D[2025-01-12])

      {:ok, [_split]} =
        Splits.book_split(Actor.owner_ui(), %{
          security_id: ctx.heron.id,
          date: ~D[2025-03-01],
          ratio_numerator: 1,
          ratio_denominator: 3
        })

      {:ok, view, _html} = live(ctx.conn, "/portfolios")
      to_preview(view, ctx.source, ctx.target)

      meridian =
        view |> element("[data-role='merge-position'][data-id='#{ctx.meridian.id}']") |> render()

      assert meridian =~ "40 + 60"
      assert meridian =~ "100"
      assert meridian =~ "90.00 · 80.00"
      assert meridian =~ "84.00"

      kestrel =
        view |> element("[data-role='merge-position'][data-id='#{ctx.kestrel.id}']") |> render()

      assert kestrel =~ "25 + 0"
      assert kestrel =~ "41.20 · —"

      rounding = view |> element("#merge-dialog [data-role='merge-rounding']") |> render()
      assert rounding =~ "Heron Solar AG"
      assert rounding =~ "2025-03-01"
      assert rounding =~ "0.666667"
      assert rounding =~ "0.666666"

      refute has_element?(view, "#merge-dialog input[name='merge[collapse]']")
      refute has_element?(view, "#merge-dialog [data-role='merge-confirm'][disabled]")
      assert has_element?(view, "#merge-dialog [data-role='merge-confirm']", "Merge into Depot 1")

      assert has_element?(
               view,
               "#merge-dialog",
               "Depot 1 keeps its cash account; the cash account of Depot 2 stays an account of its own."
             )

      view |> element("#merge-dialog [data-role='merge-confirm']") |> render_click()
      refute Portfolios.get_securities_account(ctx.source.id)
      assert Lifecycle.merge_of(:securities_account, ctx.source.id)
    end

    # User story:
    # As the operator whose depots hold a position in different buckets,
    # I want the preview to refuse, naming the position and both bucket
    # sets, with the remedy and a way to check again,
    # so that a merge never moves history between views behind my back.
    #
    # Acceptance criteria:
    # - Step 2 shows a problem note naming the position and the buckets on
    #   each side, the remedy and "Check again"; there is no confirm.
    # - Once the buckets agree, "Check again" shows the preview.
    test "step 2 refuses a position whose buckets differ, naming it", ctx do
      buy!(ctx, ctx.target, ctx.cash_t, ctx.meridian, "60", "80.00", ~D[2025-01-10])
      buy!(ctx, ctx.source, ctx.cash_s, ctx.meridian, "40", "90.00", ~D[2025-02-10])
      {:ok, spec} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Spekulativ"})
      :ok = Buckets.set_position_override(Actor.owner_ui(), ctx.source, ctx.meridian, [spec.id])

      {:ok, view, _html} = live(ctx.conn, "/portfolios")
      to_preview(view, ctx.source, ctx.target)

      refusal = view |> element("#merge-dialog [data-role='merge-refused']") |> render()
      assert refusal =~ "Merging is not possible"
      assert refusal =~ "Meridian Global Equity ETF"
      assert refusal =~ "Depot 2: Spekulativ"
      assert refusal =~ "Depot 1: no buckets"
      refute has_element?(view, "#merge-dialog [data-role='merge-confirm']")

      :ok = Buckets.clear_position_override(Actor.owner_ui(), ctx.source, ctx.meridian)
      view |> element("#merge-dialog [data-role='merge-recheck']") |> render_click()
      refute has_element?(view, "#merge-dialog [data-role='merge-refused']")
      assert has_element?(view, "#merge-dialog [data-role='merge-confirm']")
    end
  end

  # -- helpers ----------------------------------------------------------------

  defp open_merge(view, %Portfolixir.Portfolios.CashAccount{id: id}) do
    view |> element("#cash-kebab-#{id}") |> render_click()
    view |> element("#cash-row-menu-#{id} [data-role='menu-merge']") |> render_click()
  end

  defp open_merge(view, %Portfolixir.Portfolios.SecuritiesAccount{id: id}) do
    view |> element("#account-kebab-#{id}") |> render_click()
    view |> element("#account-row-menu-#{id} [data-role='menu-merge']") |> render_click()
  end

  defp to_preview(view, source, target) do
    open_merge(view, source)

    view
    |> element("#merge-dialog form[data-role='merge-target-form']")
    |> render_change(%{merge: %{target_id: "#{target.id}"}})

    view |> element("#merge-dialog [data-role='merge-continue']") |> render_click()
  end

  defp cash!(portfolio, name, currency \\ "EUR") do
    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: currency
      })

    cash
  end

  defp depot!(portfolio, cash, name) do
    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: name
      })

    depot
  end

  defp security!(name, ticker) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        ticker_symbol: ticker,
        currency_code: "EUR",
        asset_class: "etf"
      })

    security
  end

  defp book!(ctx, account, type, amount, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: ctx.portfolio.id,
        cash_account_id: account.id,
        type: type,
        date: date,
        gross_amount: amount,
        currency_code: "EUR"
      })

    tx
  end

  defp transfer!(ctx, amount, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: ctx.portfolio.id,
        cash_account_id: ctx.source.id,
        counter_cash_account_id: ctx.target.id,
        type: "cash_transfer",
        date: date,
        gross_amount: amount,
        currency_code: "EUR"
      })

    tx
  end

  defp anchor!(account, amount, date) do
    {:ok, tx} = Ledger.set_cash_balance(Actor.owner_ui(), account, %{date: date, amount: amount})
    tx
  end

  # Written the way the Portfolio Performance importer writes a trade.
  defp buy!(ctx, depot, cash, security, quantity, price, date) do
    attrs = %{
      portfolio_id: ctx.portfolio.id,
      securities_account_id: depot.id,
      cash_account_id: cash.id,
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
end
