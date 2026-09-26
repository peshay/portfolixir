defmodule Portfolixir.Repo.Migrations.ScopePolicyRuleBackdatedEndGuard do
  @moduledoc """
  The in-force guard of `20260923120000_create_policy_rules` (ADR-0049 §4)
  refuses a **backdated end**: a `valid_until` set more than two days before
  today. Its clause read the new row alone, so it fired on every UPDATE of a
  version whose end already lay that far back — an edit's closed predecessor
  or a retired rule's last line, two days after the write that closed it —
  whether the write moved the end or not.

  The next migration, `20260926121500_add_author_to_policy_rule_versions`
  (E25 S7), writes each stored version's author and `updated_at` and moves
  no end. On any instance holding such a version, the old clause refused that
  write and the upgrade stopped at boot (closing-act finding CR-1).

  The clause now fires only when the write changes `valid_until`, which is
  what "backdating an end" means. Nothing else changes: the predicate stays
  immutable once in force, and a closed period stays closed (the clause
  before it refuses any change to an end already more than a day past).
  Replacing a function rewrites no row, so the journal is untouched.

  Numbered to run before the author migration on an upgrade; on a database
  that already ran that migration, `ecto.migrate` runs this one as pending.
  """
  use Ecto.Migration

  def up do
    execute(guard(scoped?: true))
  end

  def down do
    execute(guard(scoped?: false))
  end

  defp guard(scoped?: scoped?) do
    backdated =
      if scoped?,
        do:
          "NEW.valid_until IS NOT NULL AND NEW.valid_until < CURRENT_DATE - 2\n" <>
            "           AND NEW.valid_until IS DISTINCT FROM OLD.valid_until",
        else: "NEW.valid_until IS NOT NULL AND NEW.valid_until < CURRENT_DATE - 2"

    """
    CREATE OR REPLACE FUNCTION portfolixir_policy_rule_version_in_force_guard()
    RETURNS trigger AS $$
    BEGIN
      IF TG_OP = 'DELETE' THEN
        IF OLD.valid_from < CURRENT_DATE THEN
          RAISE EXCEPTION 'policy_rule_versions: a version in force is immutable (DELETE of version %)', OLD.id
            USING ERRCODE = 'restrict_violation';
        END IF;
        RETURN OLD;
      END IF;

      IF OLD.valid_from < CURRENT_DATE THEN
        IF (NEW.policy_rule_id, NEW.subject_type, NEW.security_id, NEW.classification_id,
            NEW.category_id, NEW.subject_view_id, NEW.measure, NEW.kind, NEW.threshold,
            NEW.lower, NEW.upper, NEW.metric_window, NEW.severity, NEW.note, NEW.valid_from)
           IS DISTINCT FROM
           (OLD.policy_rule_id, OLD.subject_type, OLD.security_id, OLD.classification_id,
            OLD.category_id, OLD.subject_view_id, OLD.measure, OLD.kind, OLD.threshold,
            OLD.lower, OLD.upper, OLD.metric_window, OLD.severity, OLD.note, OLD.valid_from) THEN
          RAISE EXCEPTION 'policy_rule_versions: a version in force is immutable (UPDATE of version %)', OLD.id
            USING ERRCODE = 'restrict_violation';
        END IF;

        IF OLD.valid_until IS NOT NULL AND OLD.valid_until < CURRENT_DATE - 1
           AND NEW.valid_until IS DISTINCT FROM OLD.valid_until THEN
          RAISE EXCEPTION 'policy_rule_versions: a version in force is immutable (closed period of version %)', OLD.id
            USING ERRCODE = 'restrict_violation';
        END IF;

        IF #{backdated} THEN
          RAISE EXCEPTION 'policy_rule_versions: a version in force is immutable (backdated end of version %)', OLD.id
            USING ERRCODE = 'restrict_violation';
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """
  end
end
