defmodule Portfolixir.Lifecycle.FreezeTest do
  # ADR-0050 §11 first bullet and §16 invariant 15 (risk-tier: money and
  # identity, ADR-0036): the identity fields freeze once history hangs on
  # them. A cash account's `currency_code` freezes once a transaction (either
  # leg) or a linked depot references it; an account's or a depot's
  # `portfolio_id` freezes once it is referenced; a security's
  # `currency_code` freezes once it has a transaction or a quote. Otherwise a
  # plain edit would silently re-denominate booked history, and a currency
  # flip would slip past the merge's same-currency guard.
  #
  # The freeze sits in the three schemas' `changeset/2`, so every writer that
  # goes through it is covered: the contexts (below), the API and the MCP
  # tools over it (lifecycle_freeze_controller_test.exs, tools.test.ts), the
  # LiveView edit forms and the search dialog's "merge into existing"
  # (lifecycle_freeze_live_test.exs). `test/invariants/identity_freeze_writers_test.exs`
  # sweeps the source for every writer of the three tables.
  #
  # Two writers have no freeze case to show red, stated here rather than
  # invented: the importer never changes matched master data — it creates
  # accounts, depots and securities, and on a matched security writes at most
  # an ISIN change (ADR-0029 §3), never a currency or a portfolio binding —
  # and the seeds (`priv/repo/seeds.exs`) hold no data at all.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecuritySearch.Market
  alias Portfolixir.Catalog.SecuritySearch.SearchResult
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.WorldFixtures

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  defp cash_account!(portfolio, name, currency \\ "EUR") do
    {:ok, account} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: currency
      })

    account
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

  defp portfolio!(name) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: name, base_currency_code: "EUR"})

    portfolio
  end

  defp cash_transfer!(world, from, to) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: from.id,
        counter_cash_account_id: to.id,
        type: "cash_transfer",
        date: ~D[2026-02-02],
        gross_amount: "40",
        currency_code: "EUR"
      })

    tx
  end

  defp security_transfer!(world, from, to, security) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: from.id,
        counter_securities_account_id: to.id,
        security_id: security.id,
        type: "security_transfer",
        date: ~D[2026-02-02],
        quantity: "2",
        currency_code: "EUR"
      })

    tx
  end

  defp updates(resource_type, id) do
    [resource_type: resource_type, operation: :update, resource_id: to_string(id)]
    |> Journal.list_entries()
  end

  describe "a cash account's currency freezes once referenced (§11)" do
    # User story:
    # As the operator (or the agent) keeping a cash account's history honest,
    # I want its currency to stay what its bookings were booked in,
    # so that no edit re-denominates booked history or slips a currency flip
    # past the merge's same-currency guard.
    #
    # Acceptance criteria:
    # - An account a transaction references through either leg, or a depot
    #   links to, refuses a currency change with a field error on
    #   `currency_code` that counts what references it; nothing is written
    #   and nothing journaled.
    # - An unreferenced account's currency still changes.
    # - A referenced account's other fields — name, notes, liquidity role —
    #   still change, and resending the same currency (any case) is no change.
    test "a transaction on either leg, or a linked depot, freezes the currency" do
      world = WorldFixtures.base_world(cash_name: "Giro")
      WorldFixtures.deposit!(world, "100", ~D[2026-01-02])

      # Referenced only as the counter leg of a transfer, and by nothing else.
      counter_only = cash_account!(world.portfolio, "Savings")
      cash_transfer!(world, world.cash, counter_only)

      # Referenced only by a linked depot.
      depot_only = cash_account!(world.portfolio, "Broker Cash")
      depot!(world.portfolio, depot_only, "Broker Depot")

      for {account, counts} <- [
            {world.cash, "1 securities account, 2 transactions"},
            {counter_only, "1 transaction"},
            {depot_only, "1 securities account"}
          ] do
        assert {:error, changeset} =
                 Portfolios.update_cash_account(agent(), account, %{currency_code: "USD"})

        assert errors_on(changeset) == %{
                 currency_code: ["is frozen once referenced (#{counts})"]
               }

        assert Portfolios.get_cash_account(account.id).currency_code == "EUR"
        assert updates("cash_account", account.id) == []
      end
    end

    test "an unreferenced account's currency changes; a referenced one keeps its other fields editable" do
      world = WorldFixtures.base_world(cash_name: "Giro")
      WorldFixtures.deposit!(world, "100", ~D[2026-01-02])
      spare = cash_account!(world.portfolio, "Spare")

      assert {:ok, %CashAccount{currency_code: "USD"}} =
               Portfolios.update_cash_account(agent(), spare, %{currency_code: "usd"})

      assert {:ok, renamed} =
               Portfolios.update_cash_account(agent(), world.cash, %{
                 name: "Giro (main)",
                 notes: "synthetic",
                 liquidity_role: "reserve",
                 currency_code: " eur "
               })

      assert %CashAccount{name: "Giro (main)", liquidity_role: "reserve", currency_code: "EUR"} =
               renamed
    end
  end

  describe "an account's and a depot's portfolio binding freezes once referenced (§11)" do
    # User story:
    # As the maintainer of the composite keys that pin every booking to its
    # portfolio,
    # I want a referenced account or depot never to move to another
    # portfolio,
    # so that a move answers a field error instead of a database crash and
    # booked history stays where it was booked.
    #
    # Acceptance criteria:
    # - A cash account a transaction or a depot references, and a depot a
    #   transaction references through either leg, refuse a `portfolio_id`
    #   change with a field error on `portfolio_id`; nothing is written.
    # - An unreferenced account or depot still moves.
    test "a referenced account or depot refuses a move" do
      world = WorldFixtures.base_world()
      other = portfolio!("Other")
      other_cash = cash_account!(other, "Other Cash")
      security = WorldFixtures.create_security!(name: "Transfer ETF", ticker: "TRF")
      WorldFixtures.buy!(world, security, quantity: "5")

      # A depot referenced only as the counter leg of a security transfer.
      second = depot!(world.portfolio, world.cash, "Second Depot")
      security_transfer!(world, world.depot, second, security)

      assert {:error, changeset} =
               Portfolios.update_cash_account(agent(), world.cash, %{portfolio_id: other.id})

      assert errors_on(changeset) == %{
               portfolio_id: ["is frozen once referenced (2 securities accounts, 1 transaction)"]
             }

      for {depot, counts} <- [{world.depot, "2 transactions"}, {second, "1 transaction"}] do
        assert {:error, changeset} =
                 Portfolios.update_securities_account(agent(), depot, %{
                   portfolio_id: other.id,
                   cash_account_id: other_cash.id
                 })

        assert errors_on(changeset) == %{portfolio_id: ["is frozen once referenced (#{counts})"]}
        assert Portfolios.get_securities_account(depot.id).portfolio_id == world.portfolio.id
      end

      assert Portfolios.get_cash_account(world.cash.id).portfolio_id == world.portfolio.id
    end

    test "an unreferenced account and depot still move" do
      world = WorldFixtures.base_world()
      other = portfolio!("Other")
      other_cash = cash_account!(other, "Other Cash")
      spare = cash_account!(world.portfolio, "Spare")

      assert {:ok, moved} =
               Portfolios.update_cash_account(agent(), spare, %{portfolio_id: other.id})

      assert moved.portfolio_id == other.id

      assert {:ok, moved_depot} =
               Portfolios.update_securities_account(agent(), world.depot, %{
                 portfolio_id: other.id,
                 cash_account_id: other_cash.id
               })

      assert moved_depot.portfolio_id == other.id
    end
  end

  describe "a security's currency freezes once it has a transaction or a quote (§11)" do
    # User story:
    # As the operator (or the agent) keeping a security's prices and bookings
    # comparable,
    # I want its currency to stay what its quotes and bookings are stated in,
    # so that no edit — the form, the API, or a search result merged into it
    # from a listing in another currency — re-denominates its history.
    #
    # Acceptance criteria:
    # - A security with a transaction, or with a quote, refuses a currency
    #   change with a field error on `currency_code` that counts them;
    #   nothing is written and nothing journaled.
    # - Merging a search result from a listing in another currency into such
    #   a security is refused the same way, and none of the listing's other
    #   fields land either.
    # - A security with neither still changes currency; a frozen one keeps
    #   its other fields editable.
    test "a transaction or a quote freezes the currency" do
      world = WorldFixtures.base_world()
      booked = WorldFixtures.create_security!(name: "Booked ETF", ticker: "BKD")
      WorldFixtures.buy!(world, booked)
      WorldFixtures.buy!(world, booked, date: ~D[2026-01-05])

      quoted = WorldFixtures.create_security!(name: "Quoted ETF", ticker: "QTD")
      WorldFixtures.put_quote!(quoted, ~D[2026-01-02], "10")

      for {security, counts} <- [{booked, "2 transactions"}, {quoted, "1 quote"}] do
        assert {:error, changeset} =
                 Catalog.update_security(agent(), security, %{currency_code: "USD"})

        assert errors_on(changeset) == %{
                 currency_code: ["is frozen once referenced (#{counts})"]
               }

        assert Catalog.get_security(security.id).currency_code == "EUR"
        assert updates("security", security.id) == []
      end
    end

    test "a search result from a listing in another currency is not merged into a booked security" do
      world = WorldFixtures.base_world(cash_currency: "USD")

      {:ok, existing} =
        Catalog.create_security(Actor.owner_ui(), %{
          name: "Synthetic Corp.",
          ticker_symbol: "SYN",
          isin: "US0000000SY1",
          currency_code: "USD",
          provider: "portfolio_performance",
          online_id: "us0000000sy1",
          feed: "PORTFOLIO_PERFORMANCE"
        })

      WorldFixtures.buy!(world, existing, currency: "USD")

      result = %SearchResult{
        provider: :portfolio_performance,
        online_id: "us0000000sy1",
        name: "Synthetic Corp.",
        isin: "US0000000SY1",
        ticker_symbol: "SYN",
        currency_code: "USD",
        feed: "PORTFOLIO_PERFORMANCE",
        markets: []
      }

      eur_listing = %Market{
        symbol: "SY1",
        currency_code: "EUR",
        exchange_code: "XETR",
        exchange_name: "Xetra",
        url: "https://synthetic.invalid/quotes/us0000000sy1/xetr"
      }

      assert {:error, changeset} =
               Catalog.merge_search_result(Actor.owner_ui(), existing, result, eur_listing)

      assert errors_on(changeset) == %{
               currency_code: ["is frozen once referenced (1 transaction)"]
             }

      assert %Security{currency_code: "USD", ticker_symbol: "SYN", exchange_code: nil} =
               Catalog.get_security(existing.id)

      # The same listing in the security's own currency merges.
      usd_listing = %{eur_listing | currency_code: "USD", exchange_code: "XNAS", symbol: "SYN"}

      assert {:ok, %Security{currency_code: "USD", exchange_code: "XNAS"}} =
               Catalog.merge_search_result(Actor.owner_ui(), existing, result, usd_listing)
    end

    test "a security with neither changes currency; a frozen one keeps its other fields editable" do
      world = WorldFixtures.base_world()
      fresh = WorldFixtures.create_security!(name: "Fresh ETF", ticker: "FRSH")
      booked = WorldFixtures.create_security!(name: "Booked ETF", ticker: "BKD")
      WorldFixtures.buy!(world, booked)

      assert {:ok, %Security{currency_code: "USD"}} =
               Catalog.update_security(agent(), fresh, %{currency_code: "USD"})

      assert {:ok, %Security{name: "Booked ETF (acc)", note: "synthetic", currency_code: "EUR"}} =
               Catalog.update_security(agent(), booked, %{
                 name: "Booked ETF (acc)",
                 note: "synthetic",
                 currency_code: "eur"
               })
    end
  end

  describe "the freeze is decided at the write, inside its transaction (§11)" do
    # User story:
    # As the maintainer of the freeze,
    # I want the reference check to run when the row is written, under the
    # row's lock, not when the changeset is built,
    # so that a booking that lands between the two cannot be re-denominated
    # by an edit prepared before it.
    #
    # Acceptance criteria:
    # - A currency change built while the account was unreferenced is refused
    #   when it is written after a booking has landed.
    test "a booking that lands after the changeset was built still freezes the write" do
      world = WorldFixtures.base_world(cash_name: "Giro")
      spare = cash_account!(world.portfolio, "Spare")

      changeset = CashAccount.changeset(spare, %{currency_code: "USD"})
      assert changeset.valid?

      cash_transfer!(world, world.cash, spare)

      assert {:error, refused} =
               Repo.transaction(fn ->
                 Repo.query!("SELECT set_config('portfolixir.journal_actor', 'owner_ui', true)")

                 case Repo.update(changeset) do
                   {:ok, updated} -> updated
                   {:error, refused} -> Repo.rollback(refused)
                 end
               end)

      assert errors_on(refused) == %{currency_code: ["is frozen once referenced (1 transaction)"]}
      assert Portfolios.get_cash_account(spare.id).currency_code == "EUR"
    end
  end
end
