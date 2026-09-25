defmodule Portfolixir.Portfolios.PositionTargetUniqueTest do
  # E25 S6 (#891), G13: a plan carries one position row per security, and
  # the rule was checked with a read that nothing held, so two writes filing
  # one security under two categories could both pass the check and both
  # insert. A partial unique index on (plan, security) where the security is
  # set now holds the rule in the database; the writer maps its violation to
  # the duplicate-position refusal the check already answers. The migration
  # stops, naming each pair, when an instance already holds such a pair.
  #
  # The race is driven in one connection: the second writer's row is
  # inserted right after the first writer's check has read, which is the
  # interleaving two connections produce.
  #
  # async: false — the migration test drops and re-creates an index on
  # portfolio_targets, which every concurrent targets test would wait on.
  use PortfolixirWeb.ConnCase, async: false

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Target
  alias Portfolixir.Portfolios.TargetPlan
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Repo

  @migration "priv/repo/migrations/20260925210000_unique_position_target_per_plan.exs"
  @migration_module Portfolixir.Repo.Migrations.UniquePositionTargetPerPlan
  @index "portfolio_targets_plan_security_index"

  defp owner, do: Actor.owner_ui()

  defp world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(owner(), %{name: "Unique World", base_currency_code: "EUR"})

    {:ok, classification} = Classifications.create_classification(owner(), %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(owner(), %{
        classification_id: classification.id,
        name: "Core"
      })

    {:ok, tech} =
      Classifications.create_category(owner(), %{
        classification_id: classification.id,
        name: "Tech",
        parent_id: core.id
      })

    {:ok, security} =
      Catalog.create_security(owner(), %{
        name: "Unique Alpha",
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, _} = Classifications.assign_security(owner(), security.id, classification.id, tech.id)

    # The plan exists before the race, as it does once a plan has been saved.
    {:ok, _} =
      Targets.set_targets(owner(), portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.5"}
      ])

    %{
      portfolio: portfolio,
      classification: classification,
      core: core,
      tech: tech,
      security: security
    }
  end

  # User story:
  # As the operator and the agent steering one plan at the same time,
  # I want a security filed under one category by one of us and under
  # another by the other to end with one position row,
  # so that a security never steers two categories of one plan.
  #
  # Acceptance criteria:
  # - When another writer's row for the security lands after this write's
  #   check, this write answers the duplicate-position refusal and stores
  #   nothing and journals nothing: the other writer's row is the one row.
  test "a write that loses the race to file one security answers duplicate position" do
    w = world()
    plan = Repo.get_by!(TargetPlan, portfolio_id: w.portfolio.id)

    result =
      with_row_landing_after_check(plan, w.core, w.security, fn ->
        Targets.set_targets(owner(), w.portfolio.id, w.classification.id, [
          %{"category_id" => w.tech.id, "security_id" => w.security.id, "target_weight" => "0.3"}
        ])
      end)

    assert result == {:error, {:duplicate_position, w.security.id}}

    # Driven in one connection, the other writer's row shares this write's
    # transaction and rolls back with it; across two connections it was
    # committed first and stays. Either way this write left no row.
    assert Targets.list_position_targets(w.portfolio.id) == []
    assert Journal.list_entries(resource_type: "target", operation: :upsert) |> length() == 1
  end

  # User story:
  # As the agent losing that race over the API,
  # I want the answer to be the documented 422, not a 500,
  # so that I can re-read the plan and decide.
  #
  # Acceptance criteria:
  # - PUT /api/v1/portfolios/:id/targets answers 422 naming the one-position
  #   rule, and stores no row of its own.
  test "the losing API write answers 422", %{conn: conn} do
    w = world()
    plan = Repo.get_by!(TargetPlan, portfolio_id: w.portfolio.id)

    conn =
      with_row_landing_after_check(plan, w.core, w.security, fn ->
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer test-api-token")
        |> put("/api/v1/portfolios/#{w.portfolio.id}/targets", %{
          "classification_id" => w.classification.id,
          "targets" => [
            %{
              "category_id" => w.tech.id,
              "security_id" => w.security.id,
              "target_weight" => "0.3"
            }
          ]
        })
      end)

    assert %{"errors" => %{"detail" => detail}} = json_response(conn, 422)
    assert detail =~ "one position row per security"
    assert Targets.list_position_targets(w.portfolio.id) == []
  end

  # User story:
  # As the maintainer of the plan tables,
  # I want the database itself to refuse a second position row for one
  # security in a plan,
  # so that no writer, present or future, can store one.
  #
  # Acceptance criteria:
  # - A raw insert of a second position row for the security under another
  #   category of the same plan is refused by the unique index.
  test "the database refuses a second position row for one security in a plan" do
    w = world()
    plan = Repo.get_by!(TargetPlan, portfolio_id: w.portfolio.id)
    insert_position_row!(plan, w.core, w.security, "0.2")

    error =
      assert_raise Postgrex.Error, fn ->
        insert_position_row!(plan, w.tech, w.security, "0.3")
      end

    assert error.postgres.code == :unique_violation
    assert error.postgres.constraint == @index
  end

  # User story:
  # As the operator upgrading an instance that already holds a security
  # filed twice in one plan,
  # I want the upgrade to stop and name each such pair,
  # so that I choose which row stays rather than the upgrade choosing for me.
  #
  # Acceptance criteria:
  # - With such a pair the migration step raises, naming the plan, the
  #   security and each row id, and the index is not created.
  # - The message names a remedy that works while this release cannot start
  #   (E25 S6 review round, D1): the pre-upgrade backup and the previous
  #   release, where the plan editor and the API remove the rows journaled.
  # - Without one, the index is created.
  test "the migration names an existing duplicate instead of choosing a row" do
    w = world()
    plan = Repo.get_by!(TargetPlan, portfolio_id: w.portfolio.id)
    Repo.query!("DROP INDEX #{@index}")

    insert_position_row!(plan, w.core, w.security, "0.2")
    insert_position_row!(plan, w.tech, w.security, "0.3")

    row_ids =
      Repo.all(from(t in Target, where: t.security_id == ^w.security.id, select: t.id))

    error = assert_raise RuntimeError, fn -> migration().create_index(Repo) end
    assert error.message =~ "plan #{plan.id}"
    assert error.message =~ "security #{w.security.id}"
    for id <- row_ids, do: assert(error.message =~ "#{id}")
    assert error.message =~ "previous release"
    assert error.message =~ "backup"
    refute index_exists?()

    Repo.delete_all(from(t in Target, where: t.category_id == ^w.tech.id))

    assert :ok = migration().create_index(Repo)
    assert index_exists?()
  end

  # --- helpers ---------------------------------------------------------------

  # Runs `fun` with a one-shot hook: right after the one-position check has
  # read the plan's position rows, another writer's row for `security` under
  # `category` lands, in the same transaction, as a concurrent commit would
  # land between the check and the insert.
  defp with_row_landing_after_check(plan, category, security, fun) do
    test_pid = self()
    handler = "position-target-race-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:portfolixir, :repo, :query],
        fn _event, _measurements, %{query: query}, _config ->
          if self() == test_pid and check_query?(query) and
               Process.get(:landed) == nil do
            Process.put(:landed, true)
            insert_position_row!(plan, category, security, "0.2")
          end
        end,
        nil
      )

    try do
      fun.()
    after
      :telemetry.detach(handler)
      Process.delete(:landed)
    end
  end

  defp check_query?(query) do
    query =~
      ~r/^SELECT .* FROM "portfolio_targets" .*"plan_id" = \$1\) AND .*"security_id" = ANY/s
  end

  # A raw row, as another writer's committed row: portfolio_targets is
  # journal-armed, so the write names an actor the way the journal seam does.
  defp insert_position_row!(plan, category, security, weight) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    Repo.query!("SELECT set_config('portfolixir.journal_actor', 'owner_ui', true)")

    Repo.insert_all(Target, [
      %{
        plan_id: plan.id,
        portfolio_id: plan.portfolio_id,
        classification_id: plan.classification_id,
        category_id: category.id,
        security_id: security.id,
        target_weight: Decimal.new(weight),
        inserted_at: now,
        updated_at: now
      }
    ])
  end

  defp index_exists? do
    %{rows: [[count]]} =
      Repo.query!("SELECT count(*) FROM pg_indexes WHERE indexname = $1", [@index])

    count == 1
  end

  defp migration do
    case Code.ensure_loaded(@migration_module) do
      {:module, module} ->
        module

      {:error, _not_loaded} ->
        [{module, _bytecode}] = Code.require_file(@migration)
        module
    end
  end
end
