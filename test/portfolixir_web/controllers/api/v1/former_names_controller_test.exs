defmodule PortfolixirWeb.Api.V1.FormerNamesControllerTest do
  # ADR-0050 §4 over the API (L2, #884; risk-tier: import idempotency,
  # ADR-0036): a cash account's and a depot's former names are listed on
  # their payloads, a rename says on its answer which case applied, the name
  # guard answers 422, and a former name is removed journaled with
  # DELETE .../former_names?name=. The MCP tools call these routes and say the
  # same in their descriptions (mcp-server/test/tools.test.ts).
  use PortfolixirWeb.ConnCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios

  setup %{conn: conn} do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Household",
        base_currency_code: "EUR"
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn, portfolio: portfolio}
  end

  # User story:
  # As the agent renaming an imported account over the API,
  # I want the answer to list the names the account keeps answering to,
  # so that I can tell whether an import that still names the old one books
  # here.
  #
  # Acceptance criteria:
  # - A rename's 200 answer lists the previous name in former_names; GET and
  #   the index list it too, for a cash account and for a depot.
  # - While another account of the kind still carries the previous name as
  #   its live name, former_names stays empty.
  test "former names are on every account payload", %{conn: conn, portfolio: portfolio} do
    cash = cash!(portfolio, "Giro")
    depot = depot!(portfolio, "Depot", cash)

    assert %{"data" => %{"name" => "Main account", "former_names" => ["Giro"]}} =
             conn
             |> patch("/api/v1/cash_accounts/#{cash.id}", %{cash_account: %{name: "Main account"}})
             |> json_response(200)

    assert %{"data" => %{"former_names" => ["Giro"]}} =
             conn |> get("/api/v1/cash_accounts/#{cash.id}") |> json_response(200)

    assert %{"data" => [%{"former_names" => ["Giro"]}]} =
             conn |> get("/api/v1/cash_accounts") |> json_response(200)

    assert %{"data" => %{"former_names" => ["Depot"], "cash_account" => %{"former_names" => _}}} =
             conn
             |> patch("/api/v1/securities_accounts/#{depot.id}", %{
               securities_account: %{name: "Broker depot"}
             })
             |> json_response(200)

    assert %{"data" => [%{"former_names" => ["Depot"]}]} =
             conn |> get("/api/v1/securities_accounts") |> json_response(200)

    # Two live accounts of one name from before the guard: renaming one keeps
    # nothing, because the name still resolves to the other.
    savings = legacy_cash!(portfolio, "Savings")
    _twin = legacy_cash!(portfolio, "Savings")

    assert %{"data" => %{"former_names" => []}} =
             conn
             |> patch("/api/v1/cash_accounts/#{savings.id}", %{cash_account: %{name: "Reserve"}})
             |> json_response(200)
  end

  # User story:
  # As the agent creating or renaming accounts over the API,
  # I want a name another account already answers to refused,
  # so that I never re-route an old export onto a new account.
  #
  # Acceptance criteria:
  # - POST with another account's live or former name answers 422 on name.
  # - PATCH to another account's former name answers 422 on name.
  # - Nothing is written.
  test "the name guard answers 422", %{conn: conn, portfolio: portfolio} do
    giro = cash!(portfolio, "Giro")
    savings = cash!(portfolio, "Savings")
    {:ok, _main} = Portfolios.update_cash_account(Actor.owner_ui(), giro, %{name: "Main account"})

    for name <- ["Main account", "Giro"] do
      assert %{"errors" => %{"name" => [_message]}} =
               conn
               |> post("/api/v1/cash_accounts", %{
                 cash_account: %{portfolio_id: portfolio.id, name: name, currency_code: "EUR"}
               })
               |> json_response(422)
    end

    assert %{"errors" => %{"name" => [message]}} =
             conn
             |> patch("/api/v1/cash_accounts/#{savings.id}", %{cash_account: %{name: "Giro"}})
             |> json_response(422)

    assert message =~ "is a former name of cash account ##{giro.id}"
    assert Portfolios.count_cash_accounts() == 2
  end

  # User story:
  # As the agent who no longer wants an old name routed to an account,
  # I want to remove it from the account's former names over the API,
  # so that an import naming it creates a new account again — and I want the
  # removal on the record.
  #
  # Acceptance criteria:
  # - DELETE /api/v1/cash_accounts/:id/former_names?name=Giro answers 200
  #   with the account, its former_names without the name; the removal is
  #   journaled under the API token with before and after.
  # - The depot twin does the same.
  # - A name the account does not carry answers 404; a missing name 422; an
  #   unknown account 404.
  test "a former name is removed, journaled", %{conn: conn, portfolio: portfolio} do
    giro = cash!(portfolio, "Giro")
    {:ok, main} = Portfolios.update_cash_account(Actor.owner_ui(), giro, %{name: "Main account"})
    depot = depot!(portfolio, "Depot", main)

    {:ok, broker} =
      Portfolios.update_securities_account(Actor.owner_ui(), depot, %{name: "Broker depot"})

    assert %{"data" => %{"id" => id, "former_names" => []}} =
             conn
             |> delete("/api/v1/cash_accounts/#{main.id}/former_names?name=Giro")
             |> json_response(200)

    assert id == main.id

    [entry | _] = Journal.list_entries(resource_type: "cash_account", resource_id: "#{main.id}")
    assert entry.actor_type == :api_token_rw
    assert entry.before["former_names"] == ["Giro"]
    assert entry.after["former_names"] == []

    assert %{"data" => %{"former_names" => []}} =
             conn
             |> delete("/api/v1/securities_accounts/#{broker.id}/former_names?name=Depot")
             |> json_response(200)

    assert %{"errors" => %{"detail" => detail}} =
             conn
             |> delete("/api/v1/cash_accounts/#{main.id}/former_names?name=Giro")
             |> json_response(404)

    assert detail =~ "not a former name"

    assert %{"errors" => %{"name" => ["can't be blank"]}} =
             conn
             |> delete("/api/v1/cash_accounts/#{main.id}/former_names")
             |> json_response(422)

    conn
    |> delete("/api/v1/cash_accounts/999999999/former_names?name=Giro")
    |> json_response(404)
  end

  # User story (E25 S7 review round, S7E-6):
  # As the agent removing a former name stored before invisible characters
  # were refused,
  # I want the removal to take the name the way the MCP companion hands it to
  # me — each invisible character spelled [U+XXXX] —
  # so that a legacy name I can read is a name I can remove.
  #
  # Acceptance criteria:
  # - DELETE .../former_names?name= removes the stored former name whose
  #   escaped spelling is the name given, for a cash account and a depot, and
  #   journals it like any removal.
  # - A former name stored with those very letters is matched as written
  #   first; a name matching neither answers 404 as before.
  test "a legacy former name is removed by its escaped spelling",
       %{conn: conn, portfolio: portfolio} do
    hidden = "Giro" <> <<0x200B::utf8>>
    cash = cash!(portfolio, "Main account")
    depot = depot!(portfolio, "Broker depot", cash)
    put_former_names!(cash, [hidden, "Giro[U+200B]x"])
    put_former_names!(depot, ["Depot" <> <<0x202E::utf8>>])

    assert %{"data" => %{"former_names" => ["Giro[U+200B]x"]}} =
             conn
             |> delete(
               "/api/v1/cash_accounts/#{cash.id}/former_names?" <>
                 URI.encode_query(%{"name" => "Giro[U+200B]"})
             )
             |> json_response(200)

    [entry | _] = Journal.list_entries(resource_type: "cash_account", resource_id: "#{cash.id}")
    assert entry.before["former_names"] == [hidden, "Giro[U+200B]x"]
    assert entry.after["former_names"] == ["Giro[U+200B]x"]

    # The letters as written match the name stored with those letters.
    assert %{"data" => %{"former_names" => []}} =
             conn
             |> delete(
               "/api/v1/cash_accounts/#{cash.id}/former_names?" <>
                 URI.encode_query(%{"name" => "Giro[U+200B]x"})
             )
             |> json_response(200)

    assert %{"data" => %{"former_names" => []}} =
             conn
             |> delete(
               "/api/v1/securities_accounts/#{depot.id}/former_names?" <>
                 URI.encode_query(%{"name" => "Depot[U+202E]"})
             )
             |> json_response(200)

    conn
    |> delete(
      "/api/v1/cash_accounts/#{cash.id}/former_names?" <>
        URI.encode_query(%{"name" => "Giro[U+200C]"})
    )
    |> json_response(404)
  end

  # A former name stored before the text rule, written past the changeset
  # the way the old writer did.
  defp put_former_names!(%schema{} = account, names) do
    resource_type =
      if schema == Portfolixir.Portfolios.CashAccount,
        do: "cash_account",
        else: "securities_account"

    {:ok, _} =
      Ecto.Multi.new()
      |> Ecto.Multi.update(:account, Ecto.Changeset.change(account, former_names: names))
      |> Journal.record(Actor.owner_ui(),
        resource_type: resource_type,
        operation: :update,
        source: :account,
        before: account
      )
      |> Portfolixir.Repo.transaction()
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

  defp depot!(portfolio, name, cash) do
    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: name
      })

    depot
  end

  # A duplicate name from before the guard, inserted the way the old writer
  # did.
  defp legacy_cash!(portfolio, name) do
    {:ok, %{account: account}} =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(
        :account,
        Ecto.Changeset.change(%Portfolixir.Portfolios.CashAccount{}, %{
          portfolio_id: portfolio.id,
          name: name,
          currency_code: "EUR"
        })
      )
      |> Journal.record(Actor.owner_ui(),
        resource_type: "cash_account",
        operation: :create,
        source: :account
      )
      |> Portfolixir.Repo.transaction()

    account
  end
end
