defmodule Portfolixir.PortfoliosJournalTest do
  use Portfolixir.DataCase, async: true

  # User story:
  # As an operator who let an agent write financial data,
  # I want every committed portfolio write recorded in the append-only journal,
  # so that any create or edit of a portfolio is attributable and reversible by
  # inspection (FR-28 / NFR-2, ADR-0017, Portfolios slice of the rollout).
  #
  # Acceptance criteria:
  # - create_portfolio/2 records exactly one create entry attributed to the actor.
  # - update_portfolio/3 records an update entry with before and after snapshots.
  # - A rejected changeset commits nothing and journals nothing.
  # - The `portfolios` table is guard-armed: a write that bypasses the journaled
  #   context path (no actor) is refused by the database.

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(%{name: "Acme Fund", base_currency_code: "EUR"}, overrides)
  end

  defp cash_attrs(portfolio, overrides \\ %{}) do
    Map.merge(
      %{portfolio_id: portfolio.id, name: "Main Cash", currency_code: "EUR"},
      overrides
    )
  end

  describe "create_portfolio/2" do
    test "records exactly one create entry attributed to the actor" do
      actor = Actor.api_token_rw("token-9")
      {:ok, portfolio} = Portfolios.create_portfolio(actor, valid_attrs(%{name: "Created Fund"}))

      assert [entry] = Journal.list_entries(resource_type: "portfolio")
      assert entry.operation == :create
      assert entry.actor_type == :api_token_rw
      assert entry.actor_label == "token-9"
      assert entry.resource_type == "portfolio"
      assert entry.resource_id == to_string(portfolio.id)
      assert entry.before == nil
      assert entry.after["name"] == "Created Fund"
      assert entry.after["base_currency_code"] == "EUR"
    end

    test "a rejected changeset commits nothing and journals nothing" do
      actor = Actor.owner_ui()
      assert {:error, %Ecto.Changeset{}} = Portfolios.create_portfolio(actor, %{name: ""})
      assert Journal.list_entries(resource_type: "portfolio") == []
      assert Portfolios.count_portfolios() == 0
    end
  end

  describe "update_portfolio/3" do
    test "records an update entry with before and after snapshots" do
      actor = Actor.owner_ui()
      {:ok, portfolio} = Portfolios.create_portfolio(actor, valid_attrs(%{name: "Before Name"}))

      {:ok, _updated} = Portfolios.update_portfolio(actor, portfolio, %{name: "After Name"})

      assert [update] = Journal.list_entries(resource_type: "portfolio", operation: :update)
      assert update.actor_type == :owner_ui
      assert update.before["name"] == "Before Name"
      assert update.after["name"] == "After Name"
      assert update.resource_id == to_string(portfolio.id)
    end
  end

  describe "cash account writes" do
    setup do
      {:ok, portfolio} =
        Portfolios.create_portfolio(Actor.owner_ui(), valid_attrs(%{name: "Accounts Co"}))

      %{portfolio: portfolio}
    end

    test "create_cash_account/2 records a create entry attributed to the actor", %{
      portfolio: portfolio
    } do
      actor = Actor.api_token_rw("cash-token")
      {:ok, cash} = Portfolios.create_cash_account(actor, cash_attrs(portfolio))

      assert [entry] = Journal.list_entries(resource_type: "cash_account", operation: :create)
      assert entry.actor_type == :api_token_rw
      assert entry.actor_label == "cash-token"
      assert entry.resource_id == to_string(cash.id)
      assert entry.before == nil
      assert entry.after["name"] == "Main Cash"
    end

    test "update_cash_account/3 records before and after", %{portfolio: portfolio} do
      {:ok, cash} = Portfolios.create_cash_account(Actor.owner_ui(), cash_attrs(portfolio))

      {:ok, _} =
        Portfolios.update_cash_account(Actor.owner_ui(), cash, %{name: "Renamed Cash"})

      assert [entry] = Journal.list_entries(resource_type: "cash_account", operation: :update)
      assert entry.before["name"] == "Main Cash"
      assert entry.after["name"] == "Renamed Cash"
    end

    test "delete_cash_account/2 journals the deletion with a before snapshot", %{
      portfolio: portfolio
    } do
      {:ok, cash} = Portfolios.create_cash_account(Actor.owner_ui(), cash_attrs(portfolio))

      {:ok, _} = Portfolios.delete_cash_account(Actor.owner_ui(), cash)

      assert [entry] = Journal.list_entries(resource_type: "cash_account", operation: :delete)
      assert entry.resource_id == to_string(cash.id)
      assert entry.before["name"] == "Main Cash"
      assert Portfolios.get_cash_account(cash.id) == nil
    end

    test "a direct unactored write to cash_accounts is refused by the database", %{
      portfolio: portfolio
    } do
      assert_raise Postgrex.Error, fn ->
        Repo.insert!(CashAccount.changeset(%CashAccount{}, cash_attrs(portfolio)))
      end
    end
  end

  describe "securities account writes" do
    setup do
      world = WorldFixtures.base_world(name: "Depot Co")
      %{world: world}
    end

    test "create_securities_account/2 records a create entry", %{world: world} do
      actor = Actor.api_token_rw("depot-token")

      {:ok, depot} =
        Portfolios.create_securities_account(actor, %{
          portfolio_id: world.portfolio.id,
          cash_account_id: world.cash.id,
          name: "Second Depot"
        })

      assert entry =
               Journal.list_entries(resource_type: "securities_account", operation: :create)
               |> Enum.find(&(&1.resource_id == to_string(depot.id)))

      assert entry.actor_label == "depot-token"
      assert entry.after["name"] == "Second Depot"
    end

    test "delete_securities_account/2 journals the deletion", %{world: world} do
      {:ok, depot} =
        Portfolios.create_securities_account(Actor.owner_ui(), %{
          portfolio_id: world.portfolio.id,
          cash_account_id: world.cash.id,
          name: "Throwaway Depot"
        })

      {:ok, _} = Portfolios.delete_securities_account(Actor.owner_ui(), depot)

      assert Journal.list_entries(resource_type: "securities_account", operation: :delete)
             |> Enum.any?(&(&1.resource_id == to_string(depot.id)))
    end

    test "a direct unactored write to securities_accounts is refused", %{world: world} do
      assert_raise Postgrex.Error, fn ->
        Repo.insert!(
          SecuritiesAccount.changeset(%SecuritiesAccount{}, %{
            portfolio_id: world.portfolio.id,
            cash_account_id: world.cash.id,
            name: "Bypass"
          })
        )
      end
    end
  end

  describe "guard" do
    test "a direct unactored write to portfolios is refused by the database" do
      assert_raise Postgrex.Error, fn ->
        Repo.insert!(Portfolio.changeset(%Portfolio{}, valid_attrs()))
      end
    end
  end
end
