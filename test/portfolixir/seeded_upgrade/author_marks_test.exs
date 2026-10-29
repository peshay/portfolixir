defmodule Portfolixir.SeededUpgrade.AuthorMarksTest do
  # Security review 2026-10-12, H14 and K12 (decision T-16): the migrations
  # that store who named a rule and who recorded or corrected a tax
  # statement or an allowance order each add a CHECK and run a backfill from
  # the journal, so each gets a seeded case (docs/development/guide.md,
  # "Upgrade migrations over legacy rows"). The backfills call application
  # code; these cases pin it (#1015): a later change that makes it, or the
  # journal write it calls, touch a column the migration's version lacks
  # turns its case red.
  #
  # async: false -- see Portfolixir.SeededUpgrade, "Where the cases run".
  use ExUnit.Case, async: false

  alias Portfolixir.SeededUpgrade

  @moduletag :seeded_upgrade

  # The migration before the name-author column.
  @before_name_author 20_261_006_120_000

  # User story (security review 2026-10-12, H14):
  # As the operator upgrading an instance whose agent already renamed my
  # rules,
  # I want the upgrade to give every stored rule the author of its last
  # journaled rename, or of the version written with its name,
  # so that the release boots and the agent's labels are marked from the
  # first day.
  #
  # Acceptance criteria:
  # - Seeded with a rule the operator created and a token renamed last, a
  #   rule the agent created and never renamed, and a rule with neither a
  #   rename nor a version, the database migrates to head.
  # - The first two read agent, the third keeps no name author, and the
  #   upgrade's log counts it.
  # - Each backfilled rule is journaled under the backfill's system job.
  @tag seeded_upgrade: 20_261_029_121_200
  test "the name-author backfill does not stop the upgrade over renamed rules",
       %{seeded_upgrade: migration} do
    upgrade = SeededUpgrade.upgrade!(from: @before_name_author, seed: &seed_named_rules/1)
    rules = upgrade.seeded

    assert migration in upgrade.migrated
    assert List.last(upgrade.migrated) == SeededUpgrade.head()

    assert %{rows: rows} =
             SeededUpgrade.query!(upgrade, "SELECT id, name_author FROM policy_rules ORDER BY id")

    assert rows == [
             [rules.renamed_by_agent, "agent"],
             [rules.created_by_agent, "agent"],
             [rules.untraced, nil]
           ]

    assert upgrade.log =~ "1 rule(s) have neither a journaled rename nor an authored version"

    assert %{rows: backfilled} =
             SeededUpgrade.query!(
               upgrade,
               """
               SELECT resource_id FROM audit_journal
                WHERE resource_type = 'policy_rule' AND operation = 'update'
                  AND actor_type = 'system_job' AND actor_label = 'policy_name_author_backfill'
                ORDER BY resource_id::bigint
               """
             )

    assert backfilled == [
             [Integer.to_string(rules.renamed_by_agent)],
             [Integer.to_string(rules.created_by_agent)]
           ]
  end

  defp seed_named_rules(db) do
    portfolio =
      insert!(db, "INSERT INTO portfolios #{row(~w(name base_currency_code))}", [
        "Upgrade Portfolio",
        "EUR"
      ])

    security =
      insert!(db, "INSERT INTO securities #{row(~w(name currency_code))}", [
        "Synthetic Basin Minerals",
        "EUR"
      ])

    renamed_by_agent = insert_rule!(db, portfolio, "Renamed by a token")
    insert_version!(db, renamed_by_agent, security, "operator")
    journal!(db, "policy_rule", renamed_by_agent, "update", "owner_ui")
    journal!(db, "policy_rule", renamed_by_agent, "update", "api_token_rw")

    created_by_agent = insert_rule!(db, portfolio, "Written by a token")
    insert_version!(db, created_by_agent, security, "agent")

    untraced = insert_rule!(db, portfolio, "No trace")

    %{renamed_by_agent: renamed_by_agent, created_by_agent: created_by_agent, untraced: untraced}
  end

  defp insert_rule!(db, portfolio, name) do
    insert!(db, "INSERT INTO policy_rules #{row(~w(portfolio_id name))}", [portfolio, name])
  end

  defp insert_version!(db, rule, security, author) do
    SeededUpgrade.query!(
      db,
      """
      INSERT INTO policy_rule_versions
        (policy_rule_id, subject_type, security_id, measure, kind, threshold, severity,
         valid_from, author, inserted_at, updated_at)
      VALUES ($1, 'security', $2, 'weight', 'cap', 10, 'hard', CURRENT_DATE + 5, $3,
              LOCALTIMESTAMP(0), LOCALTIMESTAMP(0))
      """,
      [rule, security, author]
    )
  end

  defp journal!(db, resource_type, id, operation, actor_type) do
    SeededUpgrade.query!(
      db,
      """
      INSERT INTO audit_journal
        (actor_type, actor_label, operation, resource_type, resource_id, "after", inserted_at)
      VALUES ($1, 'synthetic-actor', $2, $3, $4::text, jsonb_build_object('id', $5::bigint),
              now())
      """,
      [actor_type, operation, resource_type, Integer.to_string(id), id]
    )
  end

  # `(columns..., inserted_at, updated_at) VALUES ($1, ..., now, now)
  # RETURNING id` for an insert of one row.
  defp row(columns) do
    placeholders = Enum.map_join(1..length(columns), ", ", &"$#{&1}")

    "(#{Enum.join(columns, ", ")}, inserted_at, updated_at) " <>
      "VALUES (#{placeholders}, LOCALTIMESTAMP(0), LOCALTIMESTAMP(0)) RETURNING id"
  end

  defp insert!(db, sql, params) do
    %{rows: [[id]]} = SeededUpgrade.query!(db, sql, params)
    id
  end
end
