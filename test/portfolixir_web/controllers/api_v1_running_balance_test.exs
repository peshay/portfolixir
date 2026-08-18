defmodule PortfolixirWeb.ApiV1RunningBalanceTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @auth {"authorization", "Bearer test-api-token"}

  defp get_json(conn, path) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
    |> get(path)
  end

  defp world do
    w = base_world(name: "Bal", cash_name: "Cash", depot_name: "Depot")

    {:ok, other} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        name: "Other Cash",
        currency_code: "EUR"
      })

    Map.merge(w, %{other: other, security: create_security!(name: "Bal AG", ticker: "BAL")})
  end

  defp book!(w, attrs) do
    {:ok, tx} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        Map.merge(%{portfolio_id: w.portfolio.id, currency_code: "EUR"}, attrs)
      )

    tx
  end

  defp rows(response), do: response |> Map.fetch!("data")

  defp row_for(response, id),
    do: response |> rows() |> Enum.find(&(&1["id"] == id))

  # User story (#414 parity gap, found by the Sprint 7 closing act):
  # As the LLM agent reconciling one account,
  # I want each transaction row to carry the balance that account stood at
  # after it,
  # so that I can follow the money the same way the Transactions page does,
  # instead of re-deriving a fold the app already performs.
  #
  # Acceptance criteria:
  # - `?running_balance_for=<cash_account_id>` attaches `running_balance` to
  #   every row, as a Decimal STRING (AR-11).
  # - A row that does not move that account carries `null`, never a repeat of
  #   the previous figure.
  # - The fold covers the account's WHOLE history, so a narrowed read does not
  #   restate the opening balance as zero.
  # - The response states which account the balances belong to.
  # - An unknown or non-numeric account is a field-specific 422.
  test "each row carries the balance the account stood at after it", %{conn: conn} do
    w = world()

    deposit =
      book!(w, %{
        cash_account_id: w.cash.id,
        type: "deposit",
        date: ~D[2026-01-01],
        gross_amount: "1000"
      })

    fee =
      book!(w, %{
        cash_account_id: w.cash.id,
        type: "fee",
        date: ~D[2026-02-01],
        gross_amount: "10"
      })

    theirs =
      book!(w, %{
        cash_account_id: w.other.id,
        type: "deposit",
        date: ~D[2026-03-01],
        gross_amount: "500"
      })

    response =
      get_json(conn, "/api/v1/transactions?running_balance_for=#{w.cash.id}")
      |> json_response(200)

    assert row_for(response, deposit.id)["running_balance"] == "1000"
    assert row_for(response, fee.id)["running_balance"] == "990"

    # Not this account's row: absent rather than repeating 990, which would
    # read as "nothing happened here".
    assert row_for(response, theirs.id)["running_balance"] == nil

    # The payload says whose balances these are.
    assert response["running_balance_basis"]["cash_account_id"] == w.cash.id
  end

  test "the fold covers the whole history even when the read is narrowed", %{conn: conn} do
    w = world()

    book!(w, %{
      cash_account_id: w.cash.id,
      type: "deposit",
      date: ~D[2026-01-01],
      gross_amount: "1000"
    })

    fee =
      book!(w, %{
        cash_account_id: w.cash.id,
        type: "fee",
        date: ~D[2026-02-01],
        gross_amount: "10"
      })

    # Narrowed by date to the fee alone: its balance must still be 990, not
    # -10. `from` is a filter the listing actually supports, which is the point
    # -- the fold must survive the caller's own narrowing.
    response =
      get_json(conn, "/api/v1/transactions?running_balance_for=#{w.cash.id}&from=2026-02-01")
      |> json_response(200)

    assert [row] = rows(response)
    assert row["id"] == fee.id
    assert row["running_balance"] == "990"
  end

  test "an unknown or non-numeric account is a field-specific 422", %{conn: conn} do
    world()

    assert get_json(conn, "/api/v1/transactions?running_balance_for=abc") |> json_response(422) ==
             %{"errors" => %{"running_balance_for" => ["is invalid"]}}

    assert get_json(conn, "/api/v1/transactions?running_balance_for=9999999")
           |> json_response(422) ==
             %{"errors" => %{"running_balance_for" => ["is invalid"]}}
  end

  test "without the parameter the rows are unchanged", %{conn: conn} do
    w = world()

    book!(w, %{
      cash_account_id: w.cash.id,
      type: "deposit",
      date: ~D[2026-01-01],
      gross_amount: "1000"
    })

    response = get_json(conn, "/api/v1/transactions") |> json_response(200)

    refute Map.has_key?(hd(rows(response)), "running_balance")
    refute Map.has_key?(response, "running_balance_basis")
  end
end
