defmodule Portfolixir.Repo.Migrations.CreatePolicyRules do
  @moduledoc """
  ADR-0049 §1, §4, §8: **policy rules** — a stored predicate (cap, floor or
  band) over one named measure an existing read already produces, versioned and
  effective-dated so "what was the standard on date D" is a read rather than
  journal forensics.

  Two tables, because a rule has a stable identity and a history:

    * `policy_rules` — the identity: the context the rule is evaluated in
      (`portfolio_id`, and `view_id` where NULL is the portfolio-wide scope,
      the ADR-0020 convention) and the operator's name for it;
    * `policy_rule_versions` — the predicate (subject, measure, kind,
      thresholds, window, severity, the operator's note) and the period it is
      in force, `[valid_from, valid_until]` inclusive, `valid_until` NULL while
      open-ended.

  Enforced here, at the database, and not only in the context:

  1. **Versions of one rule never overlap** (§4). An exclusion constraint over
     `(policy_rule_id, daterange(valid_from, valid_until, '[]'))`; the integer
     equality half needs `btree_gist`, a trusted contrib extension.
  2. **A version that has been in force is immutable** (§4). A trigger refuses
     any change to the predicate or to `valid_from`, and any DELETE, once
     `valid_from` lies before the database's current date. `valid_until` stays
     writable on such a row — that is how an edit or a retirement closes it —
     but a period that already closed in the past is never reopened or
     shortened. The context holds the exact rule against the host's calendar
     day (`Portfolixir.Clock`); the trigger is the backstop against a write
     that bypasses it, and keeps a day of slack for the difference between the
     host's day and the database session's.
  3. **Closed sets and the §2 measure matrix** as CHECK constraints mirroring
     `Portfolixir.Portfolios.PolicyRuleVersion` exactly.
  4. **Referenced objects are protected** (§8): every reference is
     `ON DELETE RESTRICT`, so a security, category, classification or view a
     rule reads cannot vanish underneath it; the context answers the delete
     with a 409 naming the rules before the constraint is ever reached.
  5. **Journaled from the first migration** (ADR-0017; ADR-0049 §4): an agent
     writes these rows, so both tables carry the journal-actor guard trigger
     from the migration that creates them.

  The window column is `metric_window` because `window` is an SQL keyword;
  the schema field and the API keep the ADR's word.

  Thresholds are `numeric` without a scale: they cross the boundary as Decimal
  strings (ADR-0016) and are compared, never rounded.
  """
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS btree_gist;")

    create table(:policy_rules) do
      add(:portfolio_id, references(:portfolios, on_delete: :restrict), null: false)
      add(:view_id, references(:views, on_delete: :restrict))
      add(:name, :string, null: false)

      timestamps()
    end

    create(index(:policy_rules, [:portfolio_id, :view_id]))
    create(index(:policy_rules, [:view_id]))

    create table(:policy_rule_versions) do
      add(:policy_rule_id, references(:policy_rules, on_delete: :restrict), null: false)
      add(:subject_type, :string, null: false)
      add(:security_id, references(:securities, on_delete: :restrict))
      add(:classification_id, references(:classifications, on_delete: :restrict))
      add(:category_id, references(:classification_categories, on_delete: :restrict))
      add(:subject_view_id, references(:views, on_delete: :restrict))
      add(:measure, :string, null: false)
      add(:kind, :string, null: false)
      add(:threshold, :numeric)
      add(:lower, :numeric)
      add(:upper, :numeric)
      add(:metric_window, :string)
      add(:severity, :string, null: false)
      add(:note, :text)
      add(:valid_from, :date, null: false)
      add(:valid_until, :date)

      timestamps()
    end

    create(index(:policy_rule_versions, [:policy_rule_id, :valid_from]))
    create(index(:policy_rule_versions, [:security_id]))
    create(index(:policy_rule_versions, [:category_id]))
    create(index(:policy_rule_versions, [:classification_id]))
    create(index(:policy_rule_versions, [:subject_view_id]))

    # Mirrors the closed sets in Portfolixir.Portfolios.PolicyRuleVersion.
    create(
      constraint(:policy_rule_versions, :policy_rule_versions_subject_type_check,
        check: "subject_type IN ('basis', 'security', 'category', 'view', 'cash')"
      )
    )

    create(
      constraint(:policy_rule_versions, :policy_rule_versions_measure_check,
        check: "measure IN ('weight', 'drift', 'hhi', 'volatility', 'max_drawdown')"
      )
    )

    create(
      constraint(:policy_rule_versions, :policy_rule_versions_kind_check,
        check: "kind IN ('cap', 'floor', 'band')"
      )
    )

    create(
      constraint(:policy_rule_versions, :policy_rule_versions_severity_check,
        check: "severity IN ('warn', 'hard')"
      )
    )

    # §2: the window is the ADR-0047 window a metric rule reads, present
    # exactly for the metric measures.
    create(
      constraint(:policy_rule_versions, :policy_rule_versions_window_check,
        check:
          "(measure IN ('volatility', 'max_drawdown') AND metric_window IN ('30d', '90d', '365d')) " <>
            "OR (measure NOT IN ('volatility', 'max_drawdown') AND metric_window IS NULL)"
      )
    )

    # §2: the measure matrix — which subjects each measure is read for.
    create(
      constraint(:policy_rule_versions, :policy_rule_versions_matrix_check,
        check:
          "(measure = 'weight' AND subject_type IN ('security', 'category', 'cash', 'view')) " <>
            "OR (measure = 'drift' AND subject_type IN ('category', 'security')) " <>
            "OR (measure IN ('hhi', 'volatility', 'max_drawdown') AND subject_type = 'basis')"
      )
    )

    # §1: each subject carries exactly its own reference. A security subject
    # read for drift also names the classification whose plan carries its
    # position target.
    create(
      constraint(:policy_rule_versions, :policy_rule_versions_subject_check,
        check: """
        (subject_type IN ('basis', 'cash')
          AND security_id IS NULL AND classification_id IS NULL
          AND category_id IS NULL AND subject_view_id IS NULL)
        OR (subject_type = 'security'
          AND security_id IS NOT NULL AND category_id IS NULL AND subject_view_id IS NULL
          AND ((measure = 'drift') = (classification_id IS NOT NULL)))
        OR (subject_type = 'category'
          AND classification_id IS NOT NULL AND category_id IS NOT NULL
          AND security_id IS NULL AND subject_view_id IS NULL)
        OR (subject_type = 'view'
          AND subject_view_id IS NOT NULL AND security_id IS NULL
          AND classification_id IS NULL AND category_id IS NULL)
        """
      )
    )

    # §1: a cap or floor carries one threshold; a band carries lower <= upper.
    create(
      constraint(:policy_rule_versions, :policy_rule_versions_thresholds_check,
        check:
          "(kind IN ('cap', 'floor') AND threshold IS NOT NULL AND lower IS NULL AND upper IS NULL) " <>
            "OR (kind = 'band' AND threshold IS NULL AND lower IS NOT NULL AND upper IS NOT NULL " <>
            "AND lower <= upper)"
      )
    )

    create(
      constraint(:policy_rule_versions, :policy_rule_versions_period_check,
        check: "valid_until IS NULL OR valid_until >= valid_from"
      )
    )

    # §4: versions of one rule never overlap — a constraint, not a check in code.
    execute("""
    ALTER TABLE policy_rule_versions
      ADD CONSTRAINT policy_rule_versions_no_overlap
      EXCLUDE USING gist (
        policy_rule_id WITH =,
        daterange(valid_from, valid_until, '[]') WITH &&
      );
    """)

    # §4: a version that has been in force is immutable.
    execute("""
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

        IF NEW.valid_until IS NOT NULL AND NEW.valid_until < CURRENT_DATE - 2 THEN
          RAISE EXCEPTION 'policy_rule_versions: a version in force is immutable (backdated end of version %)', OLD.id
            USING ERRCODE = 'restrict_violation';
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER policy_rule_versions_in_force_guard
      BEFORE UPDATE OR DELETE ON policy_rule_versions
      FOR EACH ROW EXECUTE FUNCTION portfolixir_policy_rule_version_in_force_guard();
    """)

    # ADR-0017 / §4: journal-armed at creation.
    execute("""
    CREATE TRIGGER policy_rules_require_journal_actor
      BEFORE INSERT OR UPDATE OR DELETE ON policy_rules
      FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
    """)

    execute("""
    CREATE TRIGGER policy_rule_versions_require_journal_actor
      BEFORE INSERT OR UPDATE OR DELETE ON policy_rule_versions
      FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
    """)
  end

  def down do
    execute(
      "DROP TRIGGER IF EXISTS policy_rule_versions_require_journal_actor ON policy_rule_versions;"
    )

    execute("DROP TRIGGER IF EXISTS policy_rules_require_journal_actor ON policy_rules;")
    execute("DROP TRIGGER IF EXISTS policy_rule_versions_in_force_guard ON policy_rule_versions;")
    execute("DROP FUNCTION IF EXISTS portfolixir_policy_rule_version_in_force_guard() CASCADE;")
    drop(table(:policy_rule_versions))
    drop(table(:policy_rules))
    # btree_gist is left installed: other objects may come to depend on it,
    # and an unused extension is inert.
  end
end
