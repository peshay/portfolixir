defmodule Portfolixir.Imports.ApplierMappingTest do
  # ADR-0050 §4 and §10 (L2, #884; risk-tier: import idempotency,
  # ADR-0036), the closing act's patch-coverage pass: the mapping an apply
  # takes is validated before anything is written, and the accounts it
  # creates lazily are linked the way the mapping or the documented fallback
  # says. Pinned here:
  #
  #   * a choice of an account in another portfolio, and a mapping of the
  #     wrong shape, are refused by name and write nothing;
  #   * a depot the mapping creates on an existing cash account links to it;
  #   * a depot name two accounts of the portfolio carry fails closed;
  #   * a depot a security transfer creates on its counter leg, with no cash
  #     side in the file, links to the portfolio's first cash account.
  #
  # The exports are synthetic Portfolio Performance JSON; every name, amount
  # and identifier is invented.
  #
  # async: false — the applier's after-commit enrichment runs in a task that
  # needs the shared sandbox connection.
  use Portfolixir.DataCase, async: false

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.SecuritiesAccount

  @fund %{"name" => "Example Fund", "isin" => "DE000EXMPL17", "currency" => "EUR"}

  setup do
    %{portfolio: portfolio!("Import target")}
  end

  # User story:
  # As the operator whose import mapping names an account of another
  # portfolio, or arrives malformed from a client,
  # I want the apply refused by name before anything is written,
  # so that no row books onto an account the import's portfolio does not
  # own, and no half-read mapping is guessed at.
  #
  # Acceptance criteria:
  # - An {:existing, id} choice of another portfolio's cash account answers
  #   {:invalid_account_choice, :cash_account, name, choice}.
  # - A cash choice, a depot choice or a depot's cash reference of an unknown
  #   shape answers invalid_cash_choice, invalid_depot_choice or
  #   invalid_depot_cash_ref, naming it.
  # - None of them writes anything.
  test "a foreign or malformed mapping is refused by name", %{portfolio: portfolio} do
    elsewhere = cash!(portfolio!("Elsewhere"), "Savings abroad")
    preview = parse!(household())
    before = counts()

    mapped = fn cash_choice, depot_spec ->
      Imports.apply(preview, %{
        portfolio: {:existing, portfolio.id},
        cash_accounts: %{"Giro" => cash_choice},
        depots: %{"Depot" => depot_spec}
      })
    end

    create_depot = %{target: {:create, "Depot"}, cash: "Giro"}

    assert mapped.({:existing, elsewhere.id}, create_depot) ==
             {:error, {:invalid_account_choice, :cash_account, "Giro", {:existing, elsewhere.id}}}

    assert mapped.({:existing, "7"}, create_depot) ==
             {:error, {:invalid_cash_choice, "Giro", {:existing, "7"}}}

    assert mapped.({:create, "Giro"}, %{target: {:create, "Depot"}, cash: {:existing, "7"}}) ==
             {:error, {:invalid_depot_cash_ref, {:existing, "7"}}}

    assert mapped.({:create, "Giro"}, %{target: :skip, cash: "Giro"}) ==
             {:error, {:invalid_depot_choice, "Depot", :skip}}

    assert counts() == before
  end

  # User story:
  # As the operator mapping the file's depot to a new depot on the cash
  # account I already keep,
  # I want the new depot linked to that account,
  # so that its trades settle where I said.
  #
  # Acceptance criteria:
  # - A {:create, name} depot with cash {:existing, id} is created under that
  #   name, linked to that cash account; no cash account is created.
  test "a depot created on an existing cash account links to it", %{portfolio: portfolio} do
    main = cash!(portfolio, "Main cash")

    assert {:ok, %Result{created_cash_accounts: 0, created_securities_accounts: 1}} =
             Imports.apply(parse!(household()), %{
               portfolio: {:existing, portfolio.id},
               cash_accounts: %{"Giro" => {:existing, main.id}},
               depots: %{
                 "Depot" => %{target: {:create, "Broker depot"}, cash: {:existing, main.id}}
               }
             })

    assert %SecuritiesAccount{cash_account_id: cash_id} =
             Repo.get_by!(SecuritiesAccount, portfolio_id: portfolio.id, name: "Broker depot")

    assert cash_id == main.id
  end

  # User story:
  # As the operator with two depots of one name from before the guard,
  # I want an import naming that depot refused rather than booked on
  # whichever was read last,
  # so that I choose the depot myself.
  #
  # Acceptance criteria:
  # - The auto-resolving apply answers {:ambiguous_account_name,
  #   :securities_account, name, both ids} and writes nothing.
  test "an ambiguous depot name fails closed", %{portfolio: portfolio} do
    cash = cash!(portfolio, "Giro")

    ids =
      Enum.sort([
        legacy_depot!(portfolio, cash, "Depot").id,
        legacy_depot!(portfolio, cash, "Depot").id
      ])

    before = counts()

    assert {:error, {:ambiguous_account_name, :securities_account, "Depot", ^ids}} =
             Imports.apply(parse!([purchase()]), %{portfolio_id: portfolio.id})

    assert counts() == before
  end

  # User story:
  # As the operator importing a security transfer into a depot the portfolio
  # does not have yet, from a file that names no cash account for it,
  # I want the new depot linked to the portfolio's first cash account, by
  # name,
  # so that the transfer books and I can re-wire the depot afterwards.
  #
  # Acceptance criteria:
  # - The counter depot is created under its file name, linked to the cash
  #   account first by name ("Alpha cash", not the "Zeta cash" the source
  #   depot uses), and the transfer books between the two depots.
  test "a counter depot with no cash side links to the first cash account", %{
    portfolio: portfolio
  } do
    zeta = cash!(portfolio, "Zeta cash")
    alpha = cash!(portfolio, "Alpha cash")
    depot!(portfolio, zeta, "Depot")

    assert {:ok, %Result{created_transactions: 2, created_securities_accounts: 1}} =
             Imports.apply(
               parse!([inbound_delivery("Depot"), security_transfer("Depot", "Depot 2")]),
               %{portfolio_id: portfolio.id}
             )

    assert %SecuritiesAccount{cash_account_id: cash_id} =
             Repo.get_by!(SecuritiesAccount, portfolio_id: portfolio.id, name: "Depot 2")

    assert cash_id == alpha.id
  end

  # --- the export ---------------------------------------------------------------

  defp household do
    [
      %{
        "type" => "DEPOSIT",
        "account" => "Giro",
        "date" => "2025-01-02",
        "currency" => "EUR",
        "amount" => num("1000.00")
      },
      purchase()
    ]
  end

  defp purchase do
    %{
      "type" => "PURCHASE",
      "account" => "Giro",
      "portfolio" => "Depot",
      "date" => "2025-01-10",
      "time" => "10:00",
      "currency" => "EUR",
      "amount" => num("500.00"),
      "shares" => num("5"),
      "security" => @fund
    }
  end

  defp inbound_delivery(depot) do
    %{
      "type" => "INBOUND_DELIVERY",
      "portfolio" => depot,
      "date" => "2025-02-01",
      "currency" => "EUR",
      "amount" => num("300.00"),
      "shares" => num("6"),
      "security" => @fund
    }
  end

  defp security_transfer(from, to) do
    %{
      "type" => "SECURITY_TRANSFER",
      "portfolio" => from,
      "otherPortfolio" => to,
      "date" => "2025-02-15",
      "currency" => "EUR",
      "amount" => num("150.00"),
      "shares" => num("3"),
      "security" => @fund
    }
  end

  defp parse!(rows) do
    body = Jason.encode!(%{"version" => 1, "transactions" => rows})
    {:ok, preview} = Imports.parse_portfolio_performance(body, filename: "synthetic.json")
    preview
  end

  # A JSON number written as its literal digits, never through a float.
  defp num(digits), do: Jason.Fragment.new(digits)

  # --- world --------------------------------------------------------------------

  defp portfolio!(name) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: name, base_currency_code: "EUR"})

    portfolio
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

  defp depot!(portfolio, cash, name) do
    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: name
      })

    depot
  end

  # A duplicate name from before the guard: inserted the way the old writer
  # did, journaled, without the changeset's guard.
  defp legacy_depot!(portfolio, cash, name) do
    {:ok, %{account: account}} =
      Multi.new()
      |> Multi.insert(
        :account,
        Ecto.Changeset.change(%SecuritiesAccount{}, %{
          portfolio_id: portfolio.id,
          cash_account_id: cash.id,
          name: name
        })
      )
      |> Journal.record(Actor.owner_ui(),
        resource_type: "securities_account",
        operation: :create,
        source: :account
      )
      |> Repo.transaction()

    account
  end

  defp counts do
    %{
      cash: Portfolios.count_cash_accounts(),
      depots: Portfolios.count_securities_accounts(),
      securities: Catalog.count_securities(),
      transactions: Ledger.count_transactions()
    }
  end
end
