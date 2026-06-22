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
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Repo

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(%{name: "Acme Fund", base_currency_code: "EUR"}, overrides)
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

  describe "guard" do
    test "a direct unactored write to portfolios is refused by the database" do
      assert_raise Postgrex.Error, fn ->
        Repo.insert!(Portfolio.changeset(%Portfolio{}, valid_attrs()))
      end
    end
  end
end
