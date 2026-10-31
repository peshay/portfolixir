defmodule Portfolixir.Imports.ReimportCountsMappingTest do
  # Board 07 ② of the 2026-10-09 pass, pick N20 A (#1180; close to the risk
  # tier, import idempotency): the preview's dry run counts a file under the
  # operator's mapping, and its count is the apply's own. The equality is
  # pinned here on the context, and end to end on the page in
  # `PortfolixirWeb.ImportsRecountLiveTest`. Every name, amount and
  # identifier is synthetic.
  use Portfolixir.DataCase, async: true

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Imports
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Repo

  @fund %{"name" => "Example Fund", "isin" => "DE000EXMPL17", "currency" => "EUR"}

  # User story (#1180, Sprint 21 γ7, pick N20 A): As the operator who maps a
  # file name onto an existing account in the preview, I want the dry run to
  # count the file under my mapping, so that the count the row shows is
  # what the confirm then skips and books.
  #
  # Acceptance criteria:
  # - Under the operator's mapping ("Tagesgeld Extra" onto Tagesgeld), the
  #   dry run counts the renamed account's three stored bookings as already
  #   imported and its one new interest payment as new, where the count
  #   under the prefill reads all four new.
  # - The apply of the same file under the same mapping skips exactly the
  #   rows the dry run counts already imported (5) and books exactly the
  #   rows it counts new (1): `skipped_duplicates` and
  #   `created_transactions` equal the dry run's totals, and the rows the
  #   apply lists as duplicates under the name are the dry run's count for
  #   it.
  # - The dry run writes nothing: no transaction, account or name is added
  #   by it.
  test "the dry run under the operator's mapping counts what the apply then skips and books" do
    portfolio = portfolio!()
    {:ok, _} = Imports.apply(parse!(history()), %{portfolio_id: portfolio.id})

    drop =
      history(savings: "Tagesgeld Extra") ++ [interest("Tagesgeld Extra", "1.40", "2026-03-31")]

    preview = parse!(drop)
    params = mapping(portfolio, %{"Tagesgeld Extra" => named!(CashAccount, "Tagesgeld")})

    prefilled = Imports.reimport_counts(preview, portfolio_id: portfolio.id)
    assert prefilled.cash_accounts["Tagesgeld Extra"].new == 4

    before = world()

    counted =
      Imports.reimport_counts(preview,
        portfolio_id: portfolio.id,
        mapping: Map.delete(params, :portfolio)
      )

    assert world() == before

    assert %{hash: 0, retired: 0, economics: 3, internal_transfer: 0, new: 1} =
             counted.cash_accounts["Tagesgeld Extra"]

    assert %{hash: 2, retired: 0, economics: 3, new: 1} = counted.total

    assert {:ok, result} = Imports.apply(preview, params)

    assert result.skipped_duplicates ==
             counted.total.hash + counted.total.retired + counted.total.economics

    assert result.created_transactions == counted.total.new

    savings_rows =
      for entry <- preview.entries,
          "Tagesgeld Extra" in [entry.pp_account_name, entry.pp_counter_account_name],
          do: entry.source_row

    skipped_under_name = Enum.count(result.duplicate_entries, &(&1.row in savings_rows))
    counts = counted.cash_accounts["Tagesgeld Extra"]
    assert skipped_under_name == counts.hash + counts.retired + counts.economics
  end

  # --- the world ---------------------------------------------------------------

  defp mapping(portfolio, overrides) do
    cash = %{
      "Test-Cash" => {:existing, named!(CashAccount, "Test-Cash").id}
    }

    cash =
      Enum.reduce(overrides, cash, fn {name, account}, acc ->
        Map.put(acc, name, {:existing, account.id})
      end)

    %{
      portfolio: {:existing, portfolio.id},
      cash_accounts: cash,
      depots: %{
        "Depot Muster" => %{
          target: {:existing, named!(SecuritiesAccount, "Depot Muster").id},
          cash: "Test-Cash"
        }
      },
      remember: %{cash_accounts: %{"Tagesgeld Extra" => false}, depots: %{}}
    }
  end

  defp history(names \\ []) do
    savings = Keyword.get(names, :savings, "Tagesgeld")

    [
      %{
        "type" => "DEPOSIT",
        "account" => "Test-Cash",
        "date" => "2026-01-02",
        "currency" => "EUR",
        "amount" => num("2000.00")
      },
      %{
        "type" => "CASH_TRANSFER",
        "account" => "Test-Cash",
        "otherAccount" => savings,
        "date" => "2026-01-05",
        "currency" => "EUR",
        "amount" => num("500.00")
      },
      %{
        "type" => "PURCHASE",
        "account" => "Test-Cash",
        "portfolio" => "Depot Muster",
        "date" => "2026-01-15",
        "time" => "10:00",
        "currency" => "EUR",
        "amount" => num("1000.00"),
        "shares" => num("10"),
        "security" => @fund
      },
      interest(savings, "1.25", "2026-01-31"),
      interest(savings, "1.30", "2026-02-28")
    ]
  end

  defp interest(account, amount, date) do
    %{
      "type" => "INTEREST",
      "account" => account,
      "date" => date,
      "currency" => "EUR",
      "amount" => num(amount)
    }
  end

  defp num(digits), do: Jason.Fragment.new(digits)

  defp parse!(rows) do
    body = Jason.encode!(%{"version" => 1, "transactions" => rows})
    {:ok, preview} = Imports.parse_portfolio_performance(body, filename: "synthetic.json")
    preview
  end

  defp portfolio! do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "PP Import Target",
        base_currency_code: "EUR"
      })

    portfolio
  end

  defp named!(schema, name), do: Repo.one!(from(a in schema, where: a.name == ^name))

  defp world do
    %{
      transactions: Repo.aggregate(Portfolixir.Ledger.Transaction, :count),
      cash:
        Repo.all(from(c in CashAccount, select: {c.id, c.name, c.former_names}, order_by: c.id)),
      depots: Repo.aggregate(SecuritiesAccount, :count)
    }
  end
end
