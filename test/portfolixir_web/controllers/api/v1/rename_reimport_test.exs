defmodule PortfolixirWeb.Api.V1.RenameReimportTest do
  # ADR-0050 Context ("a rename zombie") and §16 invariants 1 and 5, their
  # rename half over the API (L2, #884; risk-tier: import idempotency,
  # ADR-0036). The MCP tools `portfolixir.cash_accounts.update` and
  # `portfolixir.securities_accounts.update` rename through these routes.
  #
  # The byte-identical re-import holds by the hash-first order alone (§3); the
  # drifted one by the former name the rename left on the account (§4), which
  # the preview's prefill and the apply resolve through one function.
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
  #   depot", both answers list the old name in former_names, and the preview
  #   prefills the renamed account and depot for the old names.
  # - Applying the byte-identical export with that prefill creates zero
  #   transactions, cash accounts, depots and securities.
  # - Every row is reported as already imported, with its layer.
  test "a byte-identical re-import after an API rename creates nothing", %{conn: conn} do
    preview = parse!(:exact)
    assert {:ok, %Result{created_transactions: 3}} = Imports.apply(preview, prefilled(preview))

    %{main: main, broker: broker} = rename_over_api!(conn)

    before = counts()
    preview = parse!(:exact)
    mapping = prefilled(preview)

    assert mapping.cash_accounts == %{"Giro" => {:existing, main["id"]}}
    assert %{"Depot" => %{target: {:existing, depot_id}}} = mapping.depots
    assert depot_id == broker["id"]

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

  # User story:
  # As the operator whose agent renamed an imported cash account and depot
  # over the API,
  # I want the next import of a re-export that changed inside Portfolio
  # Performance to create nothing either,
  # so that a rename never books the history a second time, whatever the
  # export's precision.
  #
  # Acceptance criteria:
  # - A drifted export (every number at another precision, so no content hash
  #   matches) prefills the renamed account and depot for the old names.
  # - Applying it creates zero transactions, cash accounts, depots and
  #   securities; every row is reported with the layer economics.
  test "a drifted re-import after an API rename creates nothing", %{conn: conn} do
    {:ok, %Result{created_transactions: 3}} =
      Imports.apply(parse!(:exact), prefilled(parse!(:exact)))

    %{main: main, broker: broker} = rename_over_api!(conn)

    before = counts()
    drifted = parse!(:drifted)
    mapping = prefilled(drifted)

    assert mapping.cash_accounts == %{"Giro" => {:existing, main["id"]}}
    assert %{"Depot" => %{target: {:existing, depot_id}}} = mapping.depots
    assert depot_id == broker["id"]

    assert {:ok, %Result{} = result} = Imports.apply(drifted, mapping)

    assert counts() == before
    assert result.created_transactions == 0
    assert result.created_cash_accounts == 0
    assert result.created_securities_accounts == 0
    assert result.created_securities == 0
    assert result.already_imported == %{hash: 0, retired: 0, economics: 3}
  end

  defp rename_over_api!(conn) do
    giro = Repo.one!(from(c in CashAccount, where: c.name == "Giro"))
    [depot] = Portfolios.list_securities_accounts()

    main =
      conn
      |> patch("/api/v1/cash_accounts/#{giro.id}", %{
        "cash_account" => %{"name" => "Main account"}
      })
      |> json_response(200)
      |> Map.fetch!("data")

    broker =
      conn
      |> patch("/api/v1/securities_accounts/#{depot.id}", %{
        "securities_account" => %{"name" => "Broker depot"}
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert main["former_names"] == ["Giro"]
    assert broker["former_names"] == ["Depot"]

    %{main: main, broker: broker}
  end

  # The drifted variant writes every number at another precision, as a
  # re-export after an edit inside Portfolio Performance would.
  defp parse!(variant) do
    digits =
      case variant do
        :exact -> %{deposit: "1000.00", buy: "500.00", shares: "5", interest: "1.25"}
        :drifted -> %{deposit: "1000.0", buy: "500.000", shares: "5.0", interest: "1.250"}
      end

    body =
      Jason.encode!(%{
        "version" => 1,
        "transactions" => [
          %{
            "type" => "DEPOSIT",
            "account" => "Giro",
            "date" => "2025-01-02",
            "currency" => "EUR",
            "amount" => Jason.Fragment.new(digits.deposit)
          },
          %{
            "type" => "PURCHASE",
            "account" => "Giro",
            "portfolio" => "Depot",
            "date" => "2025-01-10",
            "time" => "10:00",
            "currency" => "EUR",
            "amount" => Jason.Fragment.new(digits.buy),
            "shares" => Jason.Fragment.new(digits.shares),
            "security" => %{
              "name" => "Example Fund",
              "isin" => "DE000EXMPL17",
              "currency" => "EUR"
            }
          },
          %{
            "type" => "INTEREST",
            "account" => "Giro",
            "date" => "2025-03-31",
            "currency" => "EUR",
            "amount" => Jason.Fragment.new(digits.interest)
          }
        ]
      })

    {:ok, preview} = Imports.parse_portfolio_performance(body, filename: "synthetic.json")
    preview
  end

  # The preview's prefill (`ImportsLive`): the shared resolution
  # (`Imports.resolve_accounts/2`) maps an exact live name or a former name to
  # its account, and an unknown name to "+ Create new".
  defp prefilled(preview) do
    %{cash_accounts: cash, depots: depots} = Imports.resolve_accounts(preview)

    %{
      cash_accounts: Map.new(cash, fn {name, resolution} -> {name, choice(resolution, name)} end),
      depots:
        Map.new(depots, fn {name, resolution} ->
          {name,
           %{
             target: choice(resolution, name),
             cash: Mapping.default_cash_for_depot(preview, name)
           }}
        end)
    }
  end

  defp choice({:ok, id, _tier}, _name), do: {:existing, id}
  defp choice(:none, name), do: {:create, name}

  defp counts do
    %{
      cash: Portfolios.count_cash_accounts(),
      depots: length(Portfolios.list_securities_accounts()),
      securities: Catalog.count_securities(),
      transactions: Ledger.count_transactions()
    }
  end
end
