defmodule Portfolixir.Repo.Migrations.GuardPolicyRuleIdentity do
  @moduledoc """
  E25 S6 (#891), F51, decision T-3: the database's own guard on the policy
  tables is extended to what ADR-0049 §4 states.

  `20260923120000_create_policy_rules` refuses a change to a version once it
  is in force, and two overlapping versions. It left three writes that bypass
  `Portfolixir.Portfolios.PolicyRules` unrefused:

    1. **A version's identity, predicate and start date**, while the version
       is only scheduled: a raw write could move its start into the past,
       move it onto another rule, or change what it states. The context never
       updates any of them — a scheduled version is edited by replacing it,
       and a version is closed by setting `valid_until` — so the new guard
       refuses the change on every version. `valid_until` and the timestamps
       stay writable, and the in-force guard keeps judging `valid_until`.
    2. **A rule's identity and context** (`id`, `portfolio_id`, `view_id`):
       a raw write could move a rule, with its whole history, into another
       portfolio or view. The context never changes them; the name, the
       operator's label, stays writable (the rename).
    3. **TRUNCATE** of either table, a statement no row-level guard sees.

  Each raises `restrict_violation`, as the existing guards do. **No insert
  trigger** (T-3): the shared bounded date on every writer and the context's
  refusal to start a version before today are the two layers on the insert
  side. Adding a trigger rewrites no row, so the journal is untouched.
  """
  use Ecto.Migration

  def up do
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

    # Named to sort after policy_rule_versions_in_force_guard, so a version
    # in force keeps that guard's message.
    execute("""
    CREATE TRIGGER policy_rule_versions_version_identity_guard
      BEFORE UPDATE ON policy_rule_versions
      FOR EACH ROW EXECUTE FUNCTION portfolixir_policy_rule_version_identity_guard();
    """)

    execute("""
    CREATE OR REPLACE FUNCTION portfolixir_policy_rule_identity_guard()
    RETURNS trigger AS $$
    BEGIN
      IF (NEW.id, NEW.portfolio_id, NEW.view_id)
         IS DISTINCT FROM (OLD.id, OLD.portfolio_id, OLD.view_id) THEN
        RAISE EXCEPTION 'policy_rules: a rule''s identity and context never change (UPDATE of rule %)', OLD.id
          USING ERRCODE = 'restrict_violation';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER policy_rules_rule_identity_guard
      BEFORE UPDATE ON policy_rules
      FOR EACH ROW EXECUTE FUNCTION portfolixir_policy_rule_identity_guard();
    """)

    execute("""
    CREATE OR REPLACE FUNCTION portfolixir_policy_rules_no_truncate()
    RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION '%: TRUNCATE is not permitted; a rule is retired or deleted through its writes', TG_TABLE_NAME
        USING ERRCODE = 'restrict_violation';
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER policy_rules_no_truncate
      BEFORE TRUNCATE ON policy_rules
      FOR EACH STATEMENT EXECUTE FUNCTION portfolixir_policy_rules_no_truncate();
    """)

    execute("""
    CREATE TRIGGER policy_rule_versions_no_truncate
      BEFORE TRUNCATE ON policy_rule_versions
      FOR EACH STATEMENT EXECUTE FUNCTION portfolixir_policy_rules_no_truncate();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS policy_rule_versions_no_truncate ON policy_rule_versions;")
    execute("DROP TRIGGER IF EXISTS policy_rules_no_truncate ON policy_rules;")
    execute("DROP FUNCTION IF EXISTS portfolixir_policy_rules_no_truncate();")
    execute("DROP TRIGGER IF EXISTS policy_rules_rule_identity_guard ON policy_rules;")
    execute("DROP FUNCTION IF EXISTS portfolixir_policy_rule_identity_guard();")

    execute(
      "DROP TRIGGER IF EXISTS policy_rule_versions_version_identity_guard ON policy_rule_versions;"
    )

    execute("DROP FUNCTION IF EXISTS portfolixir_policy_rule_version_identity_guard();")
  end
end
