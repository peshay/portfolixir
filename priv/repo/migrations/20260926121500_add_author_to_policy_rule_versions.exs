defmodule Portfolixir.Repo.Migrations.AddAuthorToPolicyRuleVersions do
  @moduledoc """
  E25 S7 (#892), G30 and decision T-8 of the 2026-09-24 security triage:
  every policy-rule version stores its **author**, derived from the actor of
  the write — `operator` for the Risk page, `agent` for an API or MCP token
  (`Portfolixir.Portfolios.PolicyRuleVersion.author_for/1`) — so a line the
  agent drew is told apart from the operator's own without the journal.

    1. **The column** is nullable text with a CHECK mirroring the schema's
       closed set. New versions always carry it (the context sets it); a
       version stored before this migration has none until step 2 gives it
       one.
    2. **The backfill** (`Portfolixir.Portfolios.PolicyRuleAuthorBackfill`)
       reads each such version's journaled creation — both tables were
       journal-armed from their first migration — and stores the author its
       actor type names, each write journaled under a `system_job` actor.
       A version with no creation entry keeps no author and is named in the
       log. Idempotent: a re-run writes nothing.
    3. **The guard** (`portfolixir_policy_rule_version_identity_guard`,
       `20260925220000_guard_policy_rule_identity`) is replaced by the same
       function plus one clause: a recorded author never changes, to another
       value or to NULL. A version without one may be given one once, which
       is what step 2 and nothing else does. Replacing a function rewrites no
       row, so the journal is untouched.

  `PolicyRuleAuthorBackfill.run/1` is referenced from this immutable
  migration — keep its signature stable.
  """
  use Ecto.Migration

  require Logger

  alias Portfolixir.Actor
  alias Portfolixir.Portfolios.PolicyRuleAuthorBackfill

  def up do
    alter table(:policy_rule_versions) do
      add(:author, :string)
    end

    create(
      constraint(:policy_rule_versions, :policy_rule_versions_author_check,
        check: "author IS NULL OR author IN ('operator', 'agent')"
      )
    )

    # The backfill reads and writes through the schema, which needs the
    # column committed to the migration's own transaction first.
    flush()

    {:ok, report} = PolicyRuleAuthorBackfill.run(Actor.system_job("policy_author_backfill"))

    if report.untraced > 0 do
      Logger.warning(
        "policy-rule author backfill (E25 S7, G30): #{report.untraced} version(s) have no " <>
          "journaled creation and keep no author"
      )
    end

    execute("""
    CREATE OR REPLACE FUNCTION portfolixir_policy_rule_version_identity_guard()
    RETURNS trigger AS $$
    BEGIN
      IF (NEW.id, NEW.policy_rule_id, NEW.subject_type, NEW.security_id, NEW.classification_id,
          NEW.category_id, NEW.subject_view_id, NEW.measure, NEW.kind, NEW.threshold,
          NEW.lower, NEW.upper, NEW.metric_window, NEW.severity, NEW.note, NEW.valid_from)
         IS DISTINCT FROM
         (OLD.id, OLD.policy_rule_id, OLD.subject_type, OLD.security_id, OLD.classification_id,
          OLD.category_id, OLD.subject_view_id, OLD.measure, OLD.kind, OLD.threshold,
          OLD.lower, OLD.upper, OLD.metric_window, OLD.severity, OLD.note, OLD.valid_from) THEN
        RAISE EXCEPTION 'policy_rule_versions: a version''s identity, predicate and start never change (UPDATE of version %)', OLD.id
          USING ERRCODE = 'restrict_violation';
      END IF;

      IF OLD.author IS NOT NULL AND NEW.author IS DISTINCT FROM OLD.author THEN
        RAISE EXCEPTION 'policy_rule_versions: a version''s author never changes (UPDATE of version %)', OLD.id
          USING ERRCODE = 'restrict_violation';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)
  end

  def down do
    execute("""
    CREATE OR REPLACE FUNCTION portfolixir_policy_rule_version_identity_guard()
    RETURNS trigger AS $$
    BEGIN
      IF (NEW.id, NEW.policy_rule_id, NEW.subject_type, NEW.security_id, NEW.classification_id,
          NEW.category_id, NEW.subject_view_id, NEW.measure, NEW.kind, NEW.threshold,
          NEW.lower, NEW.upper, NEW.metric_window, NEW.severity, NEW.note, NEW.valid_from)
         IS DISTINCT FROM
         (OLD.id, OLD.policy_rule_id, OLD.subject_type, OLD.security_id, OLD.classification_id,
          OLD.category_id, OLD.subject_view_id, OLD.measure, OLD.kind, OLD.threshold,
          OLD.lower, OLD.upper, OLD.metric_window, OLD.severity, OLD.note, OLD.valid_from) THEN
        RAISE EXCEPTION 'policy_rule_versions: a version''s identity, predicate and start never change (UPDATE of version %)', OLD.id
          USING ERRCODE = 'restrict_violation';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    drop(constraint(:policy_rule_versions, :policy_rule_versions_author_check))

    # Dropping the column rewrites no row, so the journal needs no actor.
    alter table(:policy_rule_versions) do
      remove(:author)
    end
  end
end
