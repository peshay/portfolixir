defmodule Portfolixir.Lifecycle.FormerNamesBackfillTest do
  # ADR-0050 §4 third bullet (L2, #884; risk-tier: import idempotency,
  # ADR-0036): the migration that adds `former_names` replays every journaled
  # rename of a cash account or a depot, in journal order, through the writer
  # rules — renaming back consumes a name, a name another live account of the
  # kind in the portfolio carries is not recorded — and reports, never writes,
  # a name the guard would refuse. The accounts and every name are synthetic.
  #
  # A rename "from before the migration" is seeded the way the old writer
  # made it: the name changed and the change journaled, nothing else.
  use Portfolixir.DataCase, async: true

  import ExUnit.CaptureLog

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Lifecycle.FormerNamesBackfill
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount

  @migration "priv/repo/migrations/20260925150100_backfill_account_former_names.exs"

  defp job, do: Actor.system_job("former_names_backfill")

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Household",
        base_currency_code: "EUR"
      })

    %{portfolio: portfolio}
  end

  describe "the column (§4 second bullet)" do
    test "both account tables carry former_names text[] NOT NULL DEFAULT '{}'" do
      for table <- ~w(cash_accounts securities_accounts) do
        %{rows: [[data_type, nullable, default]]} =
          Repo.query!(
            """
            SELECT data_type, is_nullable, column_default
            FROM information_schema.columns
            WHERE table_name = $1 AND column_name = 'former_names'
            """,
            [table]
          )

        assert data_type == "ARRAY"
        assert nullable == "NO"
        # Ecto writes the empty-array default as ARRAY[]::text[], which is '{}'.
        assert default =~ ~r/^(ARRAY\[\]|'\{\}')::text\[\]$/
      end
    end
  end

  describe "the backfill replays the journaled renames (§4 third bullet)" do
    # User story:
    # As the operator whose agent renamed an imported account before former
    # names existed,
    # I want the upgrade to remember the old name on the renamed account,
    # so that a later export that still names it books there instead of on a
    # new account.
    #
    # Acceptance criteria:
    # - A journaled rename of a cash account and of a depot leaves the previous
    #   name as a former name of the renamed row.
    # - Each written row is journaled once, under the backfill's system actor,
    #   with its before and after.
    # - A second run writes nothing.
    test "a journaled rename from before the migration becomes a former name, journaled", %{
      portfolio: portfolio
    } do
      giro = cash!(portfolio, "Giro")
      depot = depot!(portfolio, "Depot", giro)

      old_rename!(giro, "Main account")
      old_rename!(depot, "Broker depot")

      assert reload(giro).former_names == []
      assert reload(depot).former_names == []

      assert {:ok, report} = FormerNamesBackfill.run(job())

      assert reload(giro).former_names == ["Giro"]
      assert reload(depot).former_names == ["Depot"]
      assert report.refused == []

      assert Enum.sort_by(report.written, & &1.kind) == [
               %{kind: :cash_account, account_id: giro.id, former_names: ["Giro"]},
               %{kind: :securities_account, account_id: depot.id, former_names: ["Depot"]}
             ]

      for {resource_type, id} <- [{"cash_account", giro.id}, {"securities_account", depot.id}] do
        assert [entry] =
                 Journal.list_entries(
                   resource_type: resource_type,
                   resource_id: to_string(id),
                   actor_type: :system_job
                 )

        assert entry.operation == :update
        assert entry.actor_label == "former_names_backfill"
        assert entry.before["former_names"] == []
        assert [_old_name] = entry.after["former_names"]
      end

      assert {:ok, %{written: [], refused: []}} = FormerNamesBackfill.run(job())
    end

    # User story:
    # As the operator who renamed an account and later renamed it back,
    # I want the backfill to follow the renames in the order they were made,
    # so that a name the account carries again is not also a former name.
    #
    # Acceptance criteria:
    # - Giro → Main account → Giro → Household leaves Main account and Giro,
    #   in the order they were given up; the name renamed back to is consumed
    #   on the way.
    # - Giro → Main account → Giro leaves Main account only.
    test "renaming back consumes a name, in journal order", %{portfolio: portfolio} do
      a = cash!(portfolio, "Giro")
      a = a |> old_rename!("Main account") |> old_rename!("Giro") |> old_rename!("Household")

      b = cash!(portfolio, "Savings")
      b |> old_rename!("Savings (old)") |> old_rename!("Savings")

      assert {:ok, %{refused: []}} = FormerNamesBackfill.run(job())

      assert reload(a).former_names == ["Main account", "Giro"]
      assert reload(b).former_names == ["Savings (old)"]
    end

    # User story:
    # As the operator whose next import after a rename created a zombie
    # account under the old name,
    # I want the backfill to leave that name with the zombie and tell me,
    # so that I can repair it by merging the zombie into the renamed account.
    #
    # Acceptance criteria:
    # - A name another live account of the kind in the portfolio carries is
    #   not recorded, and the report names the account and the holder.
    # - A name two renamed accounts gave up goes to the earlier rename; the
    #   later one is reported and not written.
    # - Another portfolio's accounts and the other kind do not count.
    # - The migration logs every refusal.
    test "a name the guard would refuse is reported, never written", %{portfolio: portfolio} do
      renamed = cash!(portfolio, "Giro") |> old_rename!("Main account")
      zombie = cash!(portfolio, "Giro")

      first = cash!(portfolio, "Savings") |> old_rename!("Savings EUR")
      second = cash!(portfolio, "Savings") |> old_rename!("Reserve")

      # The same names elsewhere never refuse: a depot is another kind, and
      # another portfolio's accounts are another scope.
      depot = depot!(portfolio, "Depot", zombie) |> old_rename!("Broker depot")
      _depot_named_like_the_cash = depot!(portfolio, "Savings", zombie)

      {:ok, other_portfolio} =
        Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Other", base_currency_code: "EUR"})

      _elsewhere = cash!(other_portfolio, "Savings")

      log = capture_log(fn -> run_migration() end)

      assert reload(renamed).former_names == []
      assert reload(zombie).former_names == []
      assert reload(first).former_names == ["Savings"]
      assert reload(second).former_names == []
      assert reload(depot).former_names == ["Depot"]

      assert refused_in?(%{account_id: renamed.id, name: "Giro"}, log)
      assert refused_in?(%{account_id: second.id, name: "Savings"}, log)

      {:ok, report} = FormerNamesBackfill.run(job())
      assert report.written == []

      assert Enum.sort_by(report.refused, & &1.account_id) == [
               %{
                 kind: :cash_account,
                 account_id: renamed.id,
                 name: "Giro",
                 reason: :live_name_of_another_account,
                 holder_id: zombie.id
               },
               %{
                 kind: :cash_account,
                 account_id: second.id,
                 name: "Savings",
                 reason: :former_name_of_another_account,
                 holder_id: first.id
               }
             ]
    end

    # User story:
    # As the operator who had two accounts of one name before the name guard
    # existed, and renamed them one after the other,
    # I want the backfill to decide each rename by the names live at that
    # moment, as the writer rule would have,
    # so that the old name lands on the account the rule gives it, and a
    # drifted re-import books onto that account rather than onto the other.
    #
    # Acceptance criteria:
    # - While another account still carries the previous name as its live
    #   name, a rename records nothing, even when that other account is
    #   renamed away later.
    # - The later rename, once no other account carries the name, keeps it,
    #   and nothing is refused.
    test "a rename is replayed against the names live at its moment", %{portfolio: portfolio} do
      first = legacy_cash!(portfolio, "Twin")
      second = legacy_cash!(portfolio, "Twin")

      old_rename!(first, "Twin A")
      old_rename!(second, "Twin B")

      assert {:ok, report} = FormerNamesBackfill.run(job())

      assert reload(first).former_names == []
      assert reload(second).former_names == ["Twin"]
      assert report.refused == []

      assert report.written == [
               %{kind: :cash_account, account_id: second.id, former_names: ["Twin"]}
             ]
    end

    test "an account created before the journal was armed carries its first previous name from the start",
         %{portfolio: portfolio} do
      first = unjournaled_cash!(portfolio, "Twin")
      second = unjournaled_cash!(portfolio, "Twin")

      old_rename!(first, "Twin A")
      old_rename!(second, "Twin B")

      assert {:ok, %{refused: []}} = FormerNamesBackfill.run(job())

      assert reload(first).former_names == []
      assert reload(second).former_names == ["Twin"]
    end

    test "a rename of an account deleted since is skipped", %{portfolio: portfolio} do
      gone = cash!(portfolio, "Giro") |> old_rename!("Main account")

      # The hardened delete reads its referencing columns with
      # String.to_existing_atom/1, which fails until a schema naming them is
      # loaded (reported beside this lane, not L2's to change).
      Code.ensure_loaded!(Portfolixir.Ledger.Transaction)
      {:ok, _} = Portfolios.delete_cash_account(Actor.owner_ui(), gone)

      assert {:ok, %{written: [], refused: []}} = FormerNamesBackfill.run(job())
    end
  end

  # --- helpers -------------------------------------------------------------

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

  # An account from before the name guard: created through the old writer,
  # journaled, with no check against the other accounts' names — so two live
  # accounts may share one.
  defp legacy_cash!(portfolio, name) do
    {:ok, %{account: cash}} =
      Multi.new()
      |> Multi.insert(
        :account,
        Ecto.Changeset.change(%CashAccount{},
          portfolio_id: portfolio.id,
          name: name,
          currency_code: "EUR"
        )
      )
      |> Journal.record(Actor.api_token_rw("synthetic-agent"),
        resource_type: "cash_account",
        operation: :create,
        source: :account
      )
      |> Repo.transaction()

    cash
  end

  # An account from before the journal was armed: the row exists, no journal
  # entry says when it was made. The table's actor guard is satisfied the way
  # a journaled write satisfies it, without writing an entry.
  defp unjournaled_cash!(portfolio, name) do
    {:ok, cash} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'system_job:legacy', true)")

        Repo.insert!(
          Ecto.Changeset.change(%CashAccount{},
            portfolio_id: portfolio.id,
            name: name,
            currency_code: "EUR"
          )
        )
      end)

    cash
  end

  # The writer before ADR-0050 §4: the name changes, the change is journaled,
  # and nothing is remembered.
  defp old_rename!(%schema{} = account, name) do
    resource_type =
      case schema do
        CashAccount -> "cash_account"
        SecuritiesAccount -> "securities_account"
      end

    {:ok, %{account: renamed}} =
      Multi.new()
      |> Multi.update(:account, Ecto.Changeset.change(account, name: name))
      |> Journal.record(Actor.api_token_rw("synthetic-agent"),
        resource_type: resource_type,
        operation: :update,
        source: :account,
        before: account
      )
      |> Repo.transaction()

    renamed
  end

  defp reload(%schema{id: id}), do: Repo.get!(schema, id)

  # The data migration's own `up/0`, which logs what it refused.
  defp run_migration do
    [{module, _bytecode}] = Code.require_file(@migration)
    module.up()
  end

  defp refused_in?(%{account_id: id, name: name}, log) do
    log =~ ~s(cash account ##{id}) and log =~ ~s("#{name}")
  end
end
