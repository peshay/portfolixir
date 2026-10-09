defmodule PortfolixirWeb.NamedRecordRefusalTest do
  # #965: the domain's refusals of the ISIN-change, alias and account-name
  # writes name another record by its kind and id for the agent, its stored
  # name only as data. The operator's screens keep the sentence they showed,
  # the stored name in it: these pins hold each sentence byte for byte, as
  # the Imports page states a refused changeset (`FieldLabel`), and as the
  # security merge dialog states a refused write. Every name is synthetic.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.IdentifierAliases
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.FieldLabel
  alias PortfolixirWeb.NamedRecordRefusal

  defp security!(name, isin) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{name: name, isin: isin, currency_code: "EUR"})

    security
  end

  defp cash!(portfolio, name) do
    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: "EUR"
      })

    cash
  end

  # User story (#965):
  # As the operator reading why an import's ISIN change, a security or an
  # account it creates was refused,
  # I want the Imports page to keep naming the other record as it did,
  # by its name and its number,
  # so that keeping the agent's sentences free of stored names changes
  # nothing on my screen.
  #
  # Acceptance criteria:
  # - Each refusal reads, on the Imports page, the sentence it read before
  #   #965, byte for byte.
  test "the Imports page states each named refusal as it did" do
    live = security!("Lindwurm Holding", "XS0000400019")
    renamed = security!("Kranich Werke", "XS0000400027")
    {:ok, _} = Catalog.record_isin_change(Actor.owner_ui(), renamed, "XS0000400035")
    changing = security!("Plain Fund", "XS0000400043")

    {:error, live_isin} = Catalog.record_isin_change(Actor.owner_ui(), changing, "XS0000400019")

    assert FieldLabel.changeset_message(live_isin) ==
             ~s|New ISIN is already the current ISIN of "Lindwurm Holding" (security ##{live.id})|

    {:error, aliased} = Catalog.record_isin_change(Actor.owner_ui(), changing, "XS0000400027")

    assert FieldLabel.changeset_message(aliased) ==
             ~s|New ISIN is recorded as a former ISIN of "Kranich Werke" (security ##{renamed.id})|

    {:error, created} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "New Fund",
        isin: "XS0000400027",
        currency_code: "EUR"
      })

    assert FieldLabel.changeset_message(created) ==
             ~s|ISIN is recorded as a former ISIN of "Kranich Werke" (security ##{renamed.id}); | <>
               "delete that alias or record an ISIN change instead"

    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Household",
        base_currency_code: "EUR"
      })

    holder = cash!(portfolio, "Giro")

    {:ok, holder} =
      Portfolios.update_cash_account(Actor.owner_ui(), holder, %{name: "Hauptkonto"})

    {:error, named} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Giro",
        currency_code: "EUR"
      })

    assert FieldLabel.changeset_message(named) ==
             ~s|Name is a former name of cash account ##{holder.id} ("Hauptkonto"): an import | <>
               "naming it books there. Remove it from that account's former names first"

    legacy = cash!(portfolio, "Reserve")
    twin = cash!(portfolio, "Spare")

    {:ok, %{account: legacy}} =
      Ecto.Multi.new()
      |> Ecto.Multi.update(:account, Ecto.Changeset.change(legacy, former_names: ["Spare"]))
      |> Journal.record(Actor.owner_ui(),
        resource_type: "cash_account",
        operation: :update,
        source: :account,
        before: legacy
      )
      |> Repo.transaction()

    {:error, kept} =
      Portfolios.update_cash_account(Actor.owner_ui(), legacy, %{name: "Reserve 2"})

    assert FieldLabel.changeset_message(kept) ==
             ~s|Former names include "Spare", the name of cash account ##{twin.id} in this portfolio|

    # A depot's former name, and a former name another account carries as a
    # former name, on a move to another portfolio.
    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: holder.id,
        name: "Broker"
      })

    {:ok, depot} =
      Portfolios.update_securities_account(Actor.owner_ui(), depot, %{name: "Hauptdepot"})

    {:error, depot_named} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: holder.id,
        name: "Broker"
      })

    assert FieldLabel.changeset_message(depot_named) ==
             ~s|Name is a former name of securities account ##{depot.id} ("Hauptdepot"): an | <>
               "import naming it books there. Remove it from that account's former names first"

    {:ok, other} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Other", base_currency_code: "EUR"})

    {:ok, there} =
      Portfolios.update_cash_account(Actor.owner_ui(), cash!(other, "Bank"), %{name: "Bank 2"})

    {:ok, here} =
      Portfolios.update_cash_account(Actor.owner_ui(), cash!(portfolio, "Bank"), %{name: "Bank 3"})

    {:error, moved} =
      Portfolios.update_cash_account(Actor.owner_ui(), here, %{portfolio_id: other.id})

    assert FieldLabel.changeset_message(moved) ==
             ~s|Former names include "Bank", a former name of cash account ##{there.id} in this | <>
               "portfolio"
  end

  # Acceptance criteria:
  # - The merge's refusal to record an ISIN still live on another security,
  #   which the security merge dialog states field and message, reads as it
  #   did, the security's name in it.
  test "the security merge dialog's refused ISIN reads as it did" do
    live = security!("Lindwurm Holding", "XS0000400019")
    target = security!("Plain Fund", "XS0000400043")

    {:error, changeset} =
      IdentifierAliases.record_merged_isin(Actor.owner_ui(), target, "XS0000400019")

    assert [former_isin: error] = changeset.errors
    {message, opts} = NamedRecordRefusal.screen(error)

    sentence =
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)

    assert sentence ==
             ~s|is still the current ISIN of "Lindwurm Holding" (security ##{live.id})|
  end
end
