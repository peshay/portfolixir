defmodule Portfolixir.LockRace.DefaultPortfolioTest do
  # The internal default portfolio (ADR-0024) on a fresh instance, resolved
  # by the first import while another writer resolves it too (security
  # review 2026-10-12, H54), raced on two real connections by the lock-order
  # harness (#996). The resolution takes a lock of its own, one key for the
  # whole database, in a short transaction that commits the new record
  # before the import opens its long one, so every other writer that
  # resolves the default waits for that commit and then finds the record.
  #
  # The table of every writer's lock order is `Portfolixir.LockTable`.
  #
  # Each case needs a fresh instance, so each gets a scratch database of its
  # own at head. async: false -- the races share the barrier's limits, and
  # need no other test's load on the cores.
  #
  # Every name, figure and date is synthetic.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn

  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.LockRace
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Repo

  @endpoint PortfolixirWeb.Endpoint

  @moduletag :lock_race

  setup do
    db = LockRace.database!()
    Repo.put_dynamic_repo(db.repo)
    %{db: db}
  end

  # The synthetic sample export: 13 bookings on two cash accounts and two
  # depots (applier_test.exs pins 13 for one apply).
  defp sample_preview do
    path = Path.join(File.cwd!(), "test/support/fixtures/portfolio_performance/sample.json")
    {:ok, preview} = PortfolioPerformance.parse(File.read!(path), filename: "sample.json")
    preview
  end

  # The Imports page's apply params on a fresh instance: every file name
  # created, and no :portfolio key (the page never picks one, ADR-0024).
  defp page_params do
    %{
      cash_accounts: %{
        "Test-Cash" => {:create, "Test-Cash"},
        "Test-Cash-2" => {:create, "Test-Cash-2"}
      },
      depots: %{
        "Test-Depot" => %{target: {:create, "Test-Depot"}, cash: "Test-Cash"},
        "Test-Depot-2" => %{target: {:create, "Test-Depot-2"}, cash: "Test-Cash"}
      },
      bucket_tag: nil
    }
  end

  defp import_held_after_default(preview),
    do:
      {fn -> Imports.apply(preview, page_params()) end,
       LockRace.query?(~s(INSERT INTO "portfolios"))}

  defp api_create_cash_account do
    conn =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")
      |> post(
        "/api/v1/cash_accounts",
        Jason.encode!(%{
          "cash_account" => %{"name" => "Synthetic Agent Cash", "currency_code" => "EUR"}
        })
      )

    {conn.status, Jason.decode!(conn.resp_body)}
  end

  # User story (security review 2026-10-12, H54; ADR-0024):
  # As the operator whose agent sets up a cash account while my first import
  # runs,
  # I want both to bind to the one internal default portfolio,
  # so that the account and its later bookings show on the pages that read
  # it.
  #
  # Acceptance criteria:
  # - With the first import held right after it created the default
  #   portfolio, an API cash-account create without a portfolio waits for it.
  # - Afterwards there is one portfolio; the API's account and the import's
  #   accounts are bound to it, and it is the first portfolio.
  test "an account created during the first import binds to the one default portfolio",
       %{db: db} do
    assert Portfolios.count_portfolios() == 0

    {imported, {status, body}} =
      LockRace.race!(db, import_held_after_default(sample_preview()), &api_create_cash_account/0)

    assert {:ok, %Result{created_transactions: 13}} = imported
    assert status == 201, "the API create answered #{status}: #{inspect(body)}"

    assert [%{id: default_id, name: "Default"}] = Portfolios.list_portfolios()
    assert Portfolios.first_portfolio().id == default_id
    assert Repo.get!(CashAccount, body["data"]["id"]).portfolio_id == default_id

    assert CashAccount |> Repo.all() |> Enum.map(& &1.portfolio_id) |> Enum.uniq() ==
             [default_id]
  end

  # User story (security review 2026-10-12, H54; ADR-0050 §2):
  # As the operator confirming the first import in two tabs at once,
  # I want the second to find the default portfolio the first created,
  # so that the file is booked once and a re-import stays a no-op.
  #
  # Acceptance criteria:
  # - With the first import held right after it created the default
  #   portfolio, the second import waits for it.
  # - Afterwards there is one portfolio holding the file's 13 bookings once;
  #   the second import books none and skips all 13 as duplicates.
  test "two first imports of one file leave one default portfolio and one copy of the file",
       %{db: db} do
    assert Portfolios.count_portfolios() == 0
    preview = sample_preview()

    {first, second} =
      LockRace.race!(db, import_held_after_default(preview), fn ->
        Imports.apply(preview, page_params())
      end)

    assert {:ok, %Result{created_transactions: 13}} = first
    assert {:ok, %Result{created_transactions: 0, skipped_duplicates: 13}} = second
    assert [%{id: default_id}] = Portfolios.list_portfolios()
    assert Repo.aggregate(Transaction, :count, :id) == 13

    assert Transaction |> Repo.all() |> Enum.frequencies_by(& &1.portfolio_id) ==
             %{default_id => 13}
  end
end
