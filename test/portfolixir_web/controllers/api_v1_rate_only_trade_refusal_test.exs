defmodule PortfolixirWeb.ApiV1RateOnlyTradeRefusalTest do
  # Risk-tier (ADR-0036, money): every fixture is an exact Decimal, and each
  # test pins one identity of the cash a cross-currency trade books.
  use PortfolixirWeb.ConnCase

  import Ecto.Query, only: [from: 2]
  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1, deposit!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.SettlementGuard
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp post_json(path, body), do: build_conn() |> api_conn() |> post(path, Jason.encode!(body))
  defp patch_json(path, body), do: build_conn() |> api_conn() |> patch(path, Jason.encode!(body))

  setup do
    world = base_world(name: "Rate Only", cash_name: "EUR Cash", depot_name: "Rate Depot")
    security = create_security!(name: "US Rate Co", ticker: "USRT", currency: "USD")
    deposit!(world, Decimal.new("10000"), ~D[2026-03-01])
    {:ok, world: Map.put(world, :security, security)}
  end

  defp eur_balance(w) do
    Ledger.cash_balances(portfolio_id: w.portfolio.id) |> Map.get(w.cash.id, Decimal.new(0))
  end

  defp trade_count(w) do
    Repo.aggregate(
      from(t in Transaction,
        where: t.portfolio_id == ^w.portfolio.id and t.type in ["buy", "sell"]
      ),
      :count
    )
  end

  # A USD-priced trade through the depot's EUR account; the cash account is
  # derived from the depot.
  defp trade(w, type, extra) do
    Map.merge(
      %{
        "portfolio_id" => w.portfolio.id,
        "securities_account_id" => w.depot.id,
        "security_id" => w.security.id,
        "type" => type,
        "date" => "2026-04-01",
        "quantity" => "10",
        "price" => "100",
        "currency_code" => "USD"
      },
      extra
    )
  end

  defp correct_buy(w) do
    trade(w, "buy", %{
      "security_amount" => "1000",
      "settlement_amount" => "900",
      "settlement_fx_rate" => "0.9",
      "gross_amount" => "900"
    })
  end

  # Refused on gross_amount, nothing stored, the EUR cash untouched.
  defp assert_refused(conn, w, before_balance, before_count) do
    assert %{"errors" => %{"gross_amount" => [message]}} = json_response(conn, 422)
    assert message =~ "cross-currency trade"
    assert Decimal.equal?(eur_balance(w), before_balance)
    assert trade_count(w) == before_count
    message
  end

  # User story (security review 2026-10-12, H35):
  # As the operator whose agent books a USD security through a EUR cash account,
  # I want a cross-currency buy or sell that carries a settlement rate but
  # neither its cash amount nor its settlement amount refused until it carries
  # the cash the broker settled,
  # so that the security currency's units are never booked as the account's
  # cash and the documented 422 on gross_amount holds for every shape.
  #
  # Acceptance criteria:
  # - A buy or sell with only settlement_fx_rate (and optionally
  #   security_amount) answers 422 on gross_amount; nothing is stored and the
  #   EUR cash does not move.
  # - The message names the cash quantity × price with fees and taxes would
  #   have booked (exactly 1000 here).
  # - An update that clears both amounts on a stored cross-currency trade is
  #   refused the same way, whether the amounts are sent as null or as "".
  # - The read-only violations list names a stored rate-only trade with its
  #   booked cash (1000), the cash its own rate implies (900) and the
  #   difference (100), exactly.
  # - A trade with a settlement amount but no cash amount, and one with no
  #   rate at all, keep their existing refusals.
  describe "a cross-currency trade with a rate and neither amount" do
    test "a buy at rate 0.9 is refused on gross_amount", %{world: w} do
      before_balance = eur_balance(w)
      before_count = trade_count(w)

      conn =
        post_json("/api/v1/transactions", %{
          "transaction" => trade(w, "buy", %{"settlement_fx_rate" => "0.9"})
        })

      message = assert_refused(conn, w, before_balance, before_count)
      assert message =~ "(1000)"
    end

    test "a buy at rate 0.006 is refused on gross_amount", %{world: w} do
      before_balance = eur_balance(w)
      before_count = trade_count(w)

      conn =
        post_json("/api/v1/transactions", %{
          "transaction" => trade(w, "buy", %{"settlement_fx_rate" => "0.006"})
        })

      assert_refused(conn, w, before_balance, before_count)
    end

    test "a sell with only the rate is refused on gross_amount", %{world: w} do
      assert post_json("/api/v1/transactions", %{"transaction" => correct_buy(w)}).status == 201
      before_balance = eur_balance(w)
      assert Decimal.equal?(before_balance, Decimal.new("9100"))
      before_count = trade_count(w)

      conn =
        post_json("/api/v1/transactions", %{
          "transaction" =>
            trade(w, "sell", %{"date" => "2026-04-02", "settlement_fx_rate" => "0.9"})
        })

      message = assert_refused(conn, w, before_balance, before_count)
      assert message =~ "(1000)"
    end

    test "a buy with security_amount and the rate but no settlement_amount is refused",
         %{world: w} do
      before_balance = eur_balance(w)
      before_count = trade_count(w)

      conn =
        post_json("/api/v1/transactions", %{
          "transaction" =>
            trade(w, "buy", %{"security_amount" => "1000", "settlement_fx_rate" => "0.9"})
        })

      assert_refused(conn, w, before_balance, before_count)
    end

    test "an update clearing both amounts with null is refused", %{world: w} do
      created = post_json("/api/v1/transactions", %{"transaction" => correct_buy(w)})
      id = json_response(created, 201)["data"]["id"]
      assert Decimal.equal?(eur_balance(w), Decimal.new("9100"))

      conn =
        patch_json("/api/v1/transactions/#{id}", %{
          "transaction" => %{"gross_amount" => nil, "settlement_amount" => nil}
        })

      assert %{"errors" => %{"gross_amount" => [_message]}} = json_response(conn, 422)
      assert Decimal.equal?(eur_balance(w), Decimal.new("9100"))
      assert Decimal.equal?(Repo.get!(Transaction, id).gross_amount, Decimal.new("900"))
    end

    test "an update clearing both amounts with empty strings is refused", %{world: w} do
      created = post_json("/api/v1/transactions", %{"transaction" => correct_buy(w)})
      id = json_response(created, 201)["data"]["id"]

      conn =
        patch_json("/api/v1/transactions/#{id}", %{
          "transaction" => %{"gross_amount" => "", "settlement_amount" => ""}
        })

      assert %{"errors" => %{"gross_amount" => [_message]}} = json_response(conn, 422)
      assert Decimal.equal?(eur_balance(w), Decimal.new("9100"))
    end

    test "the read-only check lists a stored rate-only trade with its exact figures",
         %{world: w} do
      # A row as a writer before the refusal left it: rate only, neither a
      # cash amount nor a settlement amount, inserted with the journal actor
      # set, as the guard's own test does for a legacy row.
      {:ok, tx} =
        Repo.transaction(fn ->
          {type, _label} = Actor.to_columns(Actor.owner_ui())
          Repo.query!("SELECT set_config('portfolixir.journal_actor', $1, true)", [type])

          Repo.insert!(%Transaction{
            portfolio_id: w.portfolio.id,
            securities_account_id: w.depot.id,
            cash_account_id: w.cash.id,
            security_id: w.security.id,
            type: "buy",
            date: ~D[2026-04-01],
            quantity: Decimal.new("10"),
            price: Decimal.new("100"),
            fees: Decimal.new("0"),
            taxes: Decimal.new("0"),
            currency_code: "USD",
            settlement_fx_rate: Decimal.new("0.9")
          })
        end)

      assert Decimal.equal?(eur_balance(w), Decimal.new("9000"))

      assert [row] = Enum.filter(SettlementGuard.violations(), &(&1.id == tx.id))
      assert Decimal.equal?(row.booked_cash, Decimal.new("1000"))
      assert Decimal.equal?(row.expected_cash, Decimal.new("900"))
      assert Decimal.equal?(row.difference, Decimal.new("100"))

      # Read-only: the stored row is unchanged.
      stored = Repo.get!(Transaction, tx.id)
      assert is_nil(stored.gross_amount)
      assert is_nil(stored.settlement_amount)
    end
  end

  # A row as a writer before the refusal left it: a USD buy through the EUR
  # account with a rate and neither amount, written past the changeset with
  # the journal actor set.
  defp stored_rate_only_buy!(w) do
    {:ok, tx} =
      Repo.transaction(fn ->
        {type, _label} = Actor.to_columns(Actor.owner_ui())
        Repo.query!("SELECT set_config('portfolixir.journal_actor', $1, true)", [type])

        Repo.insert!(%Transaction{
          portfolio_id: w.portfolio.id,
          securities_account_id: w.depot.id,
          cash_account_id: w.cash.id,
          security_id: w.security.id,
          type: "buy",
          date: ~D[2026-04-01],
          quantity: Decimal.new("10"),
          price: Decimal.new("100"),
          fees: Decimal.new("0"),
          taxes: Decimal.new("0"),
          currency_code: "USD",
          settlement_fx_rate: Decimal.new("0.9")
        })
      end)

    tx
  end

  defp more_accounts(w) do
    usd =
      WorldFixtures.add_depot(w.portfolio,
        cash_currency: "USD",
        cash_name: "USD Cash",
        depot_name: "USD Depot"
      )

    eur = WorldFixtures.add_depot(w.portfolio, cash_name: "EUR Cash 2", depot_name: "EUR Depot 2")
    %{usd: usd, eur: eur}
  end

  # A buy in the account's own currency with a rate stored beside it and no
  # amounts: accepted, it books its own currency's cash.
  defp same_currency_rate_only_buy!(w) do
    conn =
      post_json("/api/v1/transactions", %{
        "transaction" =>
          trade(w, "buy", %{"currency_code" => "EUR", "settlement_fx_rate" => "0.9"})
      })

    json_response(conn, 201)["data"]["id"]
  end

  defp patch_tx(id, attrs),
    do: patch_json("/api/v1/transactions/#{id}", %{"transaction" => attrs})

  # User story (security review 2026-10-12, H35; the ADR-0015 amendment of
  # 2026-10-09, point 1):
  # As the operator whose agent edits a stored trade,
  # I want an update that changes the trade's currency, its cash account or
  # its depot checked by the settlement guard as an insert is,
  # so that no edit leaves a cross-currency trade with a rate and neither
  # amount behind.
  #
  # Acceptance criteria:
  # - A same-currency trade with a rate and no amounts answers 422 on
  #   gross_amount when a PATCH changes only its currency_code, or only its
  #   cash_account_id to an account of another currency; the row is unchanged.
  # - A stored rate-only cross-currency trade answers 422 on gross_amount when
  #   a PATCH changes only its securities_account_id.
  # - A trade that carries its amounts passes the settlement check on the
  #   same PATCHes as before.
  describe "an update that changes the currency, the account or the depot" do
    test "a currency change on a same-currency rate-only trade is refused", %{world: w} do
      id = same_currency_rate_only_buy!(w)
      assert Decimal.equal?(eur_balance(w), Decimal.new("9000"))

      conn = patch_tx(id, %{"currency_code" => "USD"})

      assert %{"errors" => %{"gross_amount" => [message]}} = json_response(conn, 422)
      assert message =~ "(1000)"
      assert Repo.get!(Transaction, id).currency_code == "EUR"
      assert Decimal.equal?(eur_balance(w), Decimal.new("9000"))
    end

    test "a move to an account of another currency is refused", %{world: w} do
      %{usd: usd} = more_accounts(w)
      id = same_currency_rate_only_buy!(w)

      conn = patch_tx(id, %{"cash_account_id" => usd.cash.id})

      assert %{"errors" => %{"gross_amount" => [_message]}} = json_response(conn, 422)
      assert Repo.get!(Transaction, id).cash_account_id == w.cash.id
    end

    test "a depot change on a stored rate-only trade is refused", %{world: w} do
      %{eur: eur} = more_accounts(w)
      tx = stored_rate_only_buy!(w)

      conn = patch_tx(tx.id, %{"securities_account_id" => eur.depot.id})

      assert %{"errors" => %{"gross_amount" => [_message]}} = json_response(conn, 422)
      assert Repo.get!(Transaction, tx.id).securities_account_id == w.depot.id
    end

    test "a trade that carries its amounts passes the same updates", %{world: w} do
      %{eur: eur} = more_accounts(w)

      id =
        json_response(post_json("/api/v1/transactions", %{"transaction" => correct_buy(w)}), 201)[
          "data"
        ]["id"]

      assert %{"data" => _} =
               json_response(patch_tx(id, %{"securities_account_id" => eur.depot.id}), 200)

      assert %{"data" => _} =
               json_response(patch_tx(id, %{"cash_account_id" => eur.cash.id}), 200)

      assert %{"data" => %{"currency_code" => "EUR"}} =
               json_response(patch_tx(id, %{"currency_code" => "EUR"}), 200)

      assert Decimal.equal?(Repo.get!(Transaction, id).gross_amount, Decimal.new("900"))
    end
  end

  describe "the refusals that already held" do
    test "a buy with a settlement amount and no cash amount answers 422 on gross_amount",
         %{world: w} do
      before_balance = eur_balance(w)

      conn =
        post_json("/api/v1/transactions", %{
          "transaction" =>
            trade(w, "buy", %{"settlement_amount" => "900", "settlement_fx_rate" => "0.9"})
        })

      assert %{"errors" => %{"gross_amount" => [message]}} = json_response(conn, 422)
      assert message =~ "(1000)"
      assert message =~ "(900)"
      assert Decimal.equal?(eur_balance(w), before_balance)
    end

    test "a buy with no rate at all answers 422 on settlement_fx_rate", %{world: w} do
      conn = post_json("/api/v1/transactions", %{"transaction" => trade(w, "buy", %{})})

      assert %{
               "errors" => %{
                 "settlement_fx_rate" => ["is required for a cross-currency settlement"]
               }
             } = json_response(conn, 422)
    end
  end
end
