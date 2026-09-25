defmodule PortfolixirWeb.Api.V1.RenameReimportTest do
  # ADR-0050 Context ("a rename zombie") and §16 invariants 1 and 5, their
  # rename half over the API (L2, #884; risk-tier: import idempotency,
  # ADR-0036). The MCP tools `portfolixir.cash_accounts.update` and
  # `portfolixir.securities_accounts.update` rename through these routes.
  #
  # This file pins the byte-identical re-import. The drifted re-import after a
  # rename needs the former-name tier of §4 and is pinned beside it when that
  # tier lands.
  #
  # async: false — the applier's after-commit enrichment runs in a task that
  # needs the shared sandbox connection.
  use PortfolixirWeb.ConnCase, async: false

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.Mapping
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Repo

  setup %{conn: conn} do
    {:ok, _portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Import target",
        base_currency_code: "EUR"
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  # User story:
  # As the operator whose agent renamed an imported cash account and depot
  # over the API,
  # I want the next import of the same export to create nothing,
  # so that a rename never leaves an empty "zombie" account under the old
  # name, and never books the history a second time.
  #
  # Acceptance criteria:
  # - After PATCH renames "Giro" to "Main account" and "Depot" to "Broker
  #   depot", the preview prefills "+ Create new" for both old names.
  # - Applying the byte-identical export with that prefill creates zero
  #   transactions, cash accounts, depots and securities.
  # - Every row is reported as already imported, with its layer.
  test "a byte-identical re-import after an API rename creates nothing", %{conn: conn} do
    preview = parse!()
    assert {:ok, %Result{created_transactions: 3}} = Imports.apply(preview, prefilled(preview))

    giro = Repo.one!(from(c in CashAccount, where: c.name == "Giro"))
    [depot] = Portfolios.list_securities_accounts()

    conn
    |> patch("/api/v1/cash_accounts/#{giro.id}", %{"cash_account" => %{"name" => "Main account"}})
    |> json_response(200)

    conn
    |> patch("/api/v1/securities_accounts/#{depot.id}", %{
      "securities_account" => %{"name" => "Broker depot"}
    })
    |> json_response(200)

    before = counts()
    preview = parse!()
    mapping = prefilled(preview)

    assert mapping.cash_accounts == %{"Giro" => {:create, "Giro"}}
    assert %{"Depot" => %{target: {:create, "Depot"}}} = mapping.depots

    assert {:ok, %Result{} = result} = Imports.apply(preview, mapping)

    assert counts() == before
    assert result.created_transactions == 0
    assert result.created_cash_accounts == 0
    assert result.created_securities_accounts == 0
    assert result.created_securities == 0
    assert result.already_imported == %{hash: 3, retired: 0, economics: 0}

    assert Enum.map(result.duplicate_entries, &{&1.row, &1.layer}) ==
             [{1, :hash}, {2, :hash}, {3, :hash}]
  end

  defp parse! do
    body =
      Jason.encode!(%{
        "version" => 1,
        "transactions" => [
          %{
            "type" => "DEPOSIT",
            "account" => "Giro",
            "date" => "2025-01-02",
            "currency" => "EUR",
            "amount" => Jason.Fragment.new("1000.00")
          },
          %{
            "type" => "PURCHASE",
            "account" => "Giro",
            "portfolio" => "Depot",
            "date" => "2025-01-10",
            "time" => "10:00",
            "currency" => "EUR",
            "amount" => Jason.Fragment.new("500.00"),
            "shares" => Jason.Fragment.new("5"),
            "security" => %{
              "name" => "Example Fund",
              "isin" => "DE000EXMPL01",
              "currency" => "EUR"
            }
          },
          %{
            "type" => "INTEREST",
            "account" => "Giro",
            "date" => "2025-03-31",
            "currency" => "EUR",
            "amount" => Jason.Fragment.new("1.25")
          }
        ]
      })

    {:ok, preview} = Imports.parse_portfolio_performance(body, filename: "synthetic.json")
    preview
  end

  # The preview's prefill (`ImportsLive.initial_mapping_for/2`): an exact live
  # name maps to its account, any other name to "+ Create new".
  defp prefilled(preview) do
    cash_by_name = Map.new(Portfolios.list_cash_accounts(), &{&1.name, &1.id})
    depot_by_name = Map.new(Portfolios.list_securities_accounts(), &{&1.name, &1.id})

    %{
      cash_accounts:
        Map.new(Mapping.unique_cash_pp_names(preview), &{&1, choice(cash_by_name, &1)}),
      depots:
        Map.new(Mapping.unique_depot_pp_names(preview), fn name ->
          {name,
           %{
             target: choice(depot_by_name, name),
             cash: Mapping.default_cash_for_depot(preview, name)
           }}
        end)
    }
  end

  defp choice(by_name, name) do
    case Map.fetch(by_name, name) do
      {:ok, id} -> {:existing, id}
      :error -> {:create, name}
    end
  end

  defp counts do
    %{
      cash: Portfolios.count_cash_accounts(),
      depots: length(Portfolios.list_securities_accounts()),
      securities: Catalog.count_securities(),
      transactions: Ledger.count_transactions()
    }
  end
end
