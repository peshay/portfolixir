defmodule Portfolixir.Lifecycle.DeleteLockCycleTest do
  # ADR-0050 §11 (risk-tier: audit, ADR-0036), #954: the hardened delete takes
  # the merge's lock order, depots before the security, but a writer outside
  # that order can still close a lock cycle, which PostgreSQL breaks by
  # aborting one side with deadlock_detected. The delete answers that abort
  # the way the merges do: a clean refusal, nothing deleted, nothing
  # journaled, never a 500.
  #
  # The cycle is simulated by a trigger that raises deadlock_detected on the
  # row's delete. It is DDL on a shared table inside the test's sandbox
  # transaction, so this module runs alone (async: false).
  use PortfolixirWeb.ConnCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  # User story:
  # As the agent deleting a security while another writer holds its locks,
  # I want a delete that loses a lock cycle to answer a clean refusal,
  # so that I read the security again instead of meeting a server error.
  #
  # Acceptance criteria:
  # - A security delete the database aborts with deadlock_detected answers
  #   {:error, :raced}: the security stays, and nothing is journaled.
  # - A cash-account and a depot delete answer the same.
  # - A delete whose lock wait hits the session's lock_timeout answers the
  #   same.
  # - Any other database error still raises.
  test "a delete that loses a lock cycle answers raced and deletes nothing" do
    world = WorldFixtures.base_world()
    security = WorldFixtures.create_security!(name: "Cycle Fund", ticker: "CYF")

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "Cycle Cash",
        currency_code: "EUR",
        liquidity_role: "free_cash"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        name: "Cycle Depot"
      })

    lose_lock_cycles_on(["securities", "cash_accounts", "securities_accounts"])
    before = length(Journal.list_entries())

    assert Catalog.delete_security(Actor.owner_ui(), security) == {:error, :raced}
    assert Portfolios.delete_cash_account(Actor.owner_ui(), cash) == {:error, :raced}
    assert Portfolios.delete_securities_account(Actor.owner_ui(), depot) == {:error, :raced}

    assert Catalog.get_security(security.id)
    assert Portfolios.get_cash_account(cash.id)
    assert Portfolios.get_securities_account(depot.id)
    assert length(Journal.list_entries()) == before

    fail_deletes_on("securities", "55P03")

    assert Catalog.delete_security(Actor.owner_ui(), security) == {:error, :raced}
    assert Catalog.get_security(security.id)

    fail_deletes_on("securities", "22012")

    assert_raise Postgrex.Error, fn -> Catalog.delete_security(Actor.owner_ui(), security) end
  end

  # User story:
  # As the agent deleting a security over the API while another writer holds
  # its locks,
  # I want the lost race answered 409 in the error envelope,
  # so that I retry after reading the security again.
  #
  # Acceptance criteria:
  # - DELETE /api/v1/securities/:id, /cash_accounts/:id and
  #   /securities_accounts/:id that lose a lock cycle answer 409 with
  #   errors.detail naming the race and that nothing was deleted; each row
  #   stays.
  test "a delete that loses a lock cycle answers 409 over the API", %{conn: conn} do
    world = WorldFixtures.base_world()
    security = WorldFixtures.create_security!(name: "Cycle Api Fund", ticker: "CAF")

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "Cycle Api Cash",
        currency_code: "EUR",
        liquidity_role: "free_cash"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        name: "Cycle Api Depot"
      })

    lose_lock_cycles_on(["securities", "cash_accounts", "securities_accounts"])

    for {path, noun} <- [
          {"/api/v1/securities/#{security.id}", "security"},
          {"/api/v1/cash_accounts/#{cash.id}", "cash account"},
          {"/api/v1/securities_accounts/#{depot.id}", "securities account"}
        ] do
      assert %{"errors" => %{"detail" => detail}} =
               conn |> delete(path) |> json_response(409)

      assert detail =~ "#{noun} changed while it was being deleted"
      assert detail =~ "nothing was deleted"
    end

    assert Catalog.get_security(security.id)
    assert Portfolios.get_cash_account(cash.id)
    assert Portfolios.get_securities_account(depot.id)
  end

  # A BEFORE DELETE trigger that raises the given SQLSTATE: the database's own
  # answer to a lost lock cycle (40P01), or another error, at the row's delete.
  defp lose_lock_cycles_on(tables), do: Enum.each(tables, &fail_deletes_on(&1, "40P01"))

  defp fail_deletes_on(table, sqlstate) do
    Repo.query!("""
    CREATE OR REPLACE FUNCTION test_fail_delete_#{sqlstate}() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'synthetic failure' USING ERRCODE = '#{sqlstate}';
    END $$ LANGUAGE plpgsql
    """)

    Repo.query!("DROP TRIGGER IF EXISTS test_fail_delete ON #{table}")

    Repo.query!("""
    CREATE TRIGGER test_fail_delete BEFORE DELETE ON #{table}
    FOR EACH ROW EXECUTE FUNCTION test_fail_delete_#{sqlstate}()
    """)
  end
end
