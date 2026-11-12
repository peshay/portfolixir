defmodule Portfolixir.Repo.Migrations.AddHalvingKindToSecurityEvents do
  @moduledoc """
  ADR-0048's amendment of 2026-11-12, items 1 and 2 (Sprint 29 H1, FR-58):
  a new event kind `halving` and a nullable `chain_height`.

  - The kind check gains `halving`.
  - `chain_height` is a positive block height, present on a `halving` event
    and absent on every other kind, checked here as well as in the
    changeset. Whether it is a multiple of the security's chain interval is
    checked by the context, which reads the binding (ADR-0059 §2, §4).
  - A unique index on `(security_id, chain_height)`: per security and height
    there is exactly one row (ADR-0059 §13 item 6), so the chain reader's
    upsert by height and a security merge can never produce a second one.
    Every other kind carries a null height, which the index never compares.

  Additive: no stored event is a halving, so the new checks hold over every
  row an instance holds (every existing kind with a null height).
  """
  use Ecto.Migration

  @kinds_before "kind IN ('earnings', 'ex_dividend', 'dividend_payment', 'lockup_expiry', " <>
                  "'index_review', 'shareholder_meeting', 'regulatory_decision', 'guidance_update')"

  @kinds_after "kind IN ('earnings', 'ex_dividend', 'dividend_payment', 'lockup_expiry', " <>
                 "'index_review', 'shareholder_meeting', 'regulatory_decision', " <>
                 "'guidance_update', 'halving')"

  def up do
    alter table(:security_events) do
      add(:chain_height, :bigint)
    end

    drop(constraint(:security_events, :security_events_kind_check))
    create(constraint(:security_events, :security_events_kind_check, check: @kinds_after))

    create(
      constraint(:security_events, :security_events_chain_height_check,
        check:
          "(kind = 'halving' AND chain_height IS NOT NULL AND chain_height > 0) " <>
            "OR (kind <> 'halving' AND chain_height IS NULL)"
      )
    )

    create(
      unique_index(:security_events, [:security_id, :chain_height],
        name: :security_events_security_id_chain_height_index
      )
    )
  end

  def down do
    drop(
      index(:security_events, [:security_id, :chain_height],
        name: :security_events_security_id_chain_height_index
      )
    )

    drop(constraint(:security_events, :security_events_chain_height_check))
    drop(constraint(:security_events, :security_events_kind_check))
    create(constraint(:security_events, :security_events_kind_check, check: @kinds_before))

    alter table(:security_events) do
      remove(:chain_height)
    end
  end
end
