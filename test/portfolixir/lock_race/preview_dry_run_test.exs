defmodule Portfolixir.LockRace.PreviewDryRunTest do
  # The import preview's dry run (ADR-0050 as amended on 2026-10-09) against
  # the writers it shares the database with, raced on two real connections by
  # the lock-order harness (#996), where every lock has its production scope.
  # The dry run judges a file the way the apply would, but a preview that is
  # only being looked at must hold no lock another writer waits for: it
  # simulates what the run would create in memory and inserts nothing.
  #
  # The table of every writer's lock order is `Portfolixir.LockTable`.
  #
  # async: false -- the races share the barrier's limits, and need no other
  # test's load on the cores.
  #
  # Every name, figure and identifier is synthetic.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Isin
  alias Portfolixir.Imports
  alias Portfolixir.Ledger
  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.RetiredImportHash
  alias Portfolixir.LockRace
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Repo
  alias Portfolixir.ScratchDatabase

  @endpoint PortfolixirWeb.Endpoint

  @moduletag :lock_race

  setup_all do
    db = LockRace.database!()

    # The one portfolio of the scratch database: `Imports.reimport_counts/1`,
    # called as the Imports page calls it, binds to the first portfolio.
    portfolio =
      ScratchDatabase.run(db, fn ->
        {:ok, portfolio} =
          Portfolios.create_portfolio(Actor.owner_ui(), %{
            name: "Synthetic Import Target",
            base_currency_code: "EUR"
          })

        portfolio
      end)

    %{db: db, portfolio: portfolio}
  end

  setup %{db: db} do
    Repo.put_dynamic_repo(db.repo)
    :ok
  end

  # User story (security review 2026-10-12, H53):
  # As the operator whose agent sets up a cash account while I look at an
  # import preview,
  # I want the agent's write to pass the preview's dry run,
  # so that looking at a file never makes another writer wait or fail.
  #
  # Acceptance criteria:
  # - The dry run held inside its run, after the first row's hash check: an
  #   agent's cash-account create in the portfolio does not wait for it, and
  #   succeeds.
  test "an agent's cash-account create in the portfolio passes the dry run",
       %{db: db, portfolio: portfolio} do
    preview = preview!(file(3, 2, "XS", 100))

    {_counts, created} =
      LockRace.race!(
        db,
        {fn -> Imports.reimport_counts(preview) end, after_hash_checks(1)},
        fn ->
          Portfolios.create_cash_account(Actor.api_token_rw("synthetic-agent"), %{
            portfolio_id: portfolio.id,
            name: "Agent Cash",
            currency_code: "EUR"
          })
        end,
        second: :passes
      )

    assert {:ok, %CashAccount{name: "Agent Cash"}} = created
  end

  # User story (security review 2026-10-12, H53):
  # As the operator whose agent records a security while I look at an import
  # preview of a file with securities new to the catalog,
  # I want the agent's write to pass the preview's dry run,
  # so that a preview never holds the identifier writers of the whole
  # instance.
  #
  # Acceptance criteria:
  # - The dry run held after a row whose security it would create: an
  #   agent's POST /api/v1/securities with an unrelated ISIN does not wait
  #   for it, and answers 201.
  test "an agent's security create with an unrelated ISIN passes the dry run", %{db: db} do
    preview = preview!(file(3, 2, "XS", 200))

    {_counts, status} =
      LockRace.race!(
        db,
        {fn -> Imports.reimport_counts(preview) end, after_hash_checks(2)},
        fn -> api_create_security(isin("XF", 701)) end,
        second: :passes
      )

    assert status == 201
  end

  # User story (security review 2026-10-12, H53):
  # As the operator merging accounts of another portfolio while an import
  # preview is open,
  # I want the merge's hash retirement to pass the preview's dry run,
  # so that a preview never holds a lock a merge in any portfolio needs.
  #
  # Acceptance criteria:
  # - The dry run held after a row it would book: a retirement of an import
  #   hash in another portfolio does not wait for it, and succeeds.
  test "a merge's hash retirement in another portfolio passes the dry run", %{db: db} do
    {:ok, other} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Other Synthetic",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: other.id,
        name: "Other Synthetic Cash",
        currency_code: "EUR"
      })

    {:ok, record} =
      Lifecycle.record_merge(Actor.owner_ui(), %{
        kind: "cash_account",
        source_id: cash.id + 1_000_000,
        target_id: cash.id,
        portfolio_id: other.id,
        source_snapshot: %{"name" => "Other Synthetic Cash (old)"},
        manifest: %{},
        plan_digest: "sha256:synthetic-plan"
      })

    preview = preview!(file(0, 3, "XS", 300))

    {_counts, retired} =
      LockRace.race!(
        db,
        {fn -> Imports.reimport_counts(preview) end, after_hash_checks(2)},
        fn ->
          Lifecycle.retire_import_hash(Actor.owner_ui(), %{
            import_hash: "synthetic-preview-retired",
            former_transaction_id: 9_000_053,
            merge_record_id: record.id,
            reason: "internal_transfer"
          })
        end,
        second: :passes
      )

    assert {:ok, %RetiredImportHash{}} = retired
  end

  # User story (security review 2026-10-12, H53):
  # As the operator whose agent records a security while I look at the
  # preview of a long file,
  # I want the agent's write to answer while the preview is still counting,
  # so that nothing the preview does holds up the agent.
  #
  # Acceptance criteria:
  # - The dry run of a file that creates many securities runs as the Imports
  #   page runs it, unpaused. An agent's POST /api/v1/securities with an
  #   unrelated ISIN, sent once the dry run is past a row that creates a
  #   security, answers 201 before the dry run answers.
  @tag timeout: 120_000
  test "an agent's security create answers while a preview is still counted", %{db: db} do
    preview = preview!(realistic_file(40, 10, 400, "XS"))
    parent = self()

    {:ok, dry_run} =
      Task.start(fn ->
        ScratchDatabase.run(db, fn ->
          observe_hash_checks(parent, 2)
          counts = Imports.reimport_counts(preview)
          send(parent, {:dry_run_answered, System.monotonic_time(), counts.total})
        end)
      end)

    assert_receive {:hash_checks_reached, ^dry_run}, 30_000

    status = api_create_security(isin("XF", 702))
    agent_answered = System.monotonic_time()

    assert status == 201
    assert_receive {:dry_run_answered, dry_run_answered, %{new: new}}, 90_000
    assert new > 0
    assert agent_answered < dry_run_answered
  end

  # --- the dry run's progress ----------------------------------------------------------

  # A pause predicate: past the dry run's `n`th per-row hash check, a query
  # only the run of the apply sends (the first pass reads every row's hashes
  # in one query per table).
  defp after_hash_checks(n) do
    fn metadata ->
      if hash_check?(metadata) do
        count = Process.get(:preview_hash_checks, 0) + 1
        Process.put(:preview_hash_checks, count)
        count == n
      else
        false
      end
    end
  end

  defp hash_check?(%{query: query}) when is_binary(query),
    do: String.starts_with?(query, ~s(SELECT TRUE FROM "transactions"))

  defp hash_check?(_metadata), do: false

  # Tells `parent` once the calling process has sent its `n`th per-row hash
  # check.
  defp observe_hash_checks(parent, n) do
    me = self()
    handler = "preview-dry-run-#{inspect(me)}"

    :ok =
      :telemetry.attach(
        handler,
        [:portfolixir, :repo, :query],
        &__MODULE__.count_hash_check/4,
        %{process: me, parent: parent, n: n}
      )
  end

  @doc false
  def count_hash_check(_event, _measurements, metadata, %{process: process} = config) do
    if self() == process and hash_check?(metadata) do
      count = Process.get(:preview_hash_checks, 0) + 1
      Process.put(:preview_hash_checks, count)
      if count == config.n, do: send(config.parent, {:hash_checks_reached, process})
    end
  end

  # --- the agent ---------------------------------------------------------------------

  defp api_create_security(isin) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> post(
      "/api/v1/securities",
      Jason.encode!(%{
        "security" => %{
          "name" => "Unrelated Agent Fund #{isin}",
          "isin" => isin,
          "currency_code" => "EUR"
        }
      })
    )
    |> Map.fetch!(:status)
  end

  # User story (#1205, Sprint 21 α7; ADR-0053 A12; the H53 review of the
  # correction's confirm):
  # As the operator who confirms a correction while my agent renames
  # another cash account of the same portfolio,
  # I want the confirm to wait for the rename and correct every line it
  # listed, the one found by its figures too,
  # so that a confirmed correction is never silently cut down to the lines
  # found by their hashes.
  #
  # Acceptance criteria:
  # - K23's world: the sale stored under the old reading (120.00, the
  #   refund 25.00 beside it), its re-export drifted by a minute; the
  #   correction lists it by its figures, with a confirm.
  # - The confirm, raced against a rename of another cash account of the
  #   portfolio that holds the account-identity lock, waits for it, then
  #   corrects the sale: 120.00 → 95.00, Race-Cash 1,120.00; nothing is
  #   listed afterwards.
  test "the correction's confirm waits for a rename in flight and corrects the line found by its figures",
       %{db: db} do
    security = %{"name" => "Race Arbolia Inc.", "isin" => isin("XQ", 1), "currency" => "EUR"}

    sale = fn time ->
      %{
        "type" => "SALE",
        "account" => "Race-Cash",
        "portfolio" => "Race-Depot",
        "date" => "2026-06-15",
        "time" => time,
        "currency" => "EUR",
        "amount" => num("120.00"),
        "shares" => num("10"),
        "security" => security,
        "units" => [
          %{"type" => "FEE", "amount" => num("5.00")},
          %{"type" => "TAX", "amount" => num("-25.00")}
        ]
      }
    end

    history = [
      %{
        "type" => "DEPOSIT",
        "account" => "Race-Cash",
        "date" => "2026-03-02",
        "currency" => "EUR",
        "amount" => num("1100.00")
      },
      %{
        "type" => "PURCHASE",
        "account" => "Race-Cash",
        "portfolio" => "Race-Depot",
        "date" => "2026-03-03",
        "time" => "10:00",
        "currency" => "EUR",
        "amount" => num("100.00"),
        "shares" => num("10"),
        "security" => security
      }
    ]

    {portfolio, other, drifted} =
      ScratchDatabase.run(db, fn ->
        {:ok, portfolio} =
          Portfolios.create_portfolio(Actor.owner_ui(), %{
            name: "Synthetic Correction Target",
            base_currency_code: "EUR"
          })

        # As the importer booked it before ADR-0053's amendment: the sale's
        # cash cell whole, priced the old way, the refund beside it.
        stored = preview!(history ++ [sale.("15:30")])

        old_reading =
          Enum.map(stored.entries, fn entry ->
            %{entry | gross_amount: entry.hash_amount, price: entry.hash_price || entry.price}
          end)

        {:ok, _} = Imports.apply(%{stored | entries: old_reading}, %{portfolio_id: portfolio.id})

        {:ok, other} =
          Portfolios.create_cash_account(Actor.owner_ui(), %{
            portfolio_id: portfolio.id,
            name: "Race-Other",
            currency_code: "EUR"
          })

        drifted = preview!(history ++ [sale.("15:31")])

        assert [%{row: 3, state: :confirm, match: :figures}] =
                 Imports.cash_corrections(drifted, portfolio_id: portfolio.id)

        {portfolio, other, drifted}
      end)

    {{:ok, _renamed}, corrected} =
      LockRace.race!(
        db,
        {fn ->
           Portfolios.update_cash_account(Actor.owner_ui(), other, %{name: "Race-Other 2"})
         end, &LockRace.lock?/1},
        fn ->
          Imports.correct_cash(Imports.correction_actor(), drifted, portfolio_id: portfolio.id)
        end
      )

    assert {:ok, [%{row: 3, match: :figures}]} = corrected

    ScratchDatabase.run(db, fn ->
      cash = Enum.find(Portfolios.list_cash_accounts(), &(&1.name == "Race-Cash"))

      assert [portfolio_id: portfolio.id]
             |> Ledger.cash_balances()
             |> Map.fetch!(cash.id)
             |> Decimal.equal?(Decimal.new("1120"))

      assert Imports.cash_corrections(drifted, portfolio_id: portfolio.id) == []
    end)
  end

  # --- files -------------------------------------------------------------------------

  # A synthetic ISIN with a valid check digit.
  defp isin(prefix, n) do
    base = prefix <> String.pad_leading(Integer.to_string(n), 9, "0")
    Enum.find_value(0..9, fn d -> if Isin.valid?(base <> "#{d}"), do: base <> "#{d}" end)
  end

  defp num(digits), do: Jason.Fragment.new(digits)

  defp purchase(security_n, row_n, prefix) do
    %{
      "type" => "PURCHASE",
      "account" => "Synthetic Cash",
      "portfolio" => "Synthetic Depot",
      "date" => Date.to_iso8601(Date.add(~D[2015-01-05], row_n)),
      "currency" => "EUR",
      "amount" => num("#{100 + row_n}.25"),
      "shares" => num("1"),
      "security" => %{
        "name" => "Synthetic Fund #{security_n}",
        "isin" => isin(prefix, security_n),
        "currency" => "EUR"
      }
    }
  end

  defp deposit(row_n) do
    %{
      "type" => "DEPOSIT",
      "account" => "Synthetic Cash",
      "date" => Date.to_iso8601(Date.add(~D[2000-01-03], rem(row_n, 8_000))),
      "currency" => "EUR",
      "amount" => num("#{row_n}.01")
    }
  end

  # `buys` purchases, each of its own new security, then `deposits` deposits.
  defp file(buys, deposits, prefix, offset) do
    Enum.map(1..buys//1, &purchase(offset + &1, &1, prefix)) ++
      Enum.map(1..deposits//1, &deposit(offset + &1))
  end

  # `securities` new securities bought `per_security` times each (a savings
  # plan), then `deposits` deposits.
  defp realistic_file(securities, per_security, deposits, prefix) do
    purchases =
      for round <- 0..(per_security - 1), s <- 1..securities do
        purchase(1_000 + s, round * securities + s, prefix)
      end

    purchases ++ Enum.map(1..deposits, &deposit(50_000 + &1))
  end

  defp preview!(rows) do
    body = Jason.encode!(%{"version" => 1, "transactions" => rows})
    {:ok, preview} = Imports.parse_portfolio_performance(body, filename: "synthetic.json")
    preview
  end
end
