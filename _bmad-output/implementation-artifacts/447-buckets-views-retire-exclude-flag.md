# Story: Buckets & views — retire `excluded_from_allocation_targets` (GitHub #447)

Status: in progress

> **Tracking:** GitHub issue [#447](https://github.com/peshay/portfolixir/issues/447),
> final story of epic [#448](https://github.com/peshay/portfolixir/issues/448)
> "Buckets & views: tag-based wealth scoping (ADR-0018)".
> Epic chain: **#443 (data model) → #444 (engine scoping) → #445 (API/MCP) →
> #446 (UI) → #447 (this, retire `excluded_from_allocation_targets`, supersede
> ADR-0013)**.

## Story

As a **local portfolio maintainer**,
I want **the per-security `excluded_from_allocation_targets` flag removed now that
views can scope the steering basis**,
so that **there is one mechanism (buckets + views) for carving holdings out of the
steering basis, and no redundant, conflicting flag to maintain**.

## Acceptance Criteria

Copied from issue #447, renumbered for task traceability:

1. The `excluded_from_allocation_targets` schema field, its changeset
   cast/validation, and the security-field registry entry are removed.
2. `Catalog.excluded_from_allocation_target_ids/0` is removed.
3. The allocation engine no longer carves out flagged positions: the steering
   basis is the (possibly view-scoped) valued positions plus deployable cash.
   The separate `excluded` block is removed from the allocation result (it is
   **not** re-derived — the behaviour is reproduced by excluding a bucket from a
   view, ADR-0018 §4).
4. The risk engine no longer references the flag; its steerable basis is the
   valued positions (scoped by the active view).
5. The JSON API security serializer drops `excluded_from_allocation_targets`; the
   allocation serializer drops the `excluded` block; the risk note no longer
   mentions the flag.
6. A reversible migration drops the column (`up` drops, `down` re-adds with the
   original default). The original add migration is left intact (append-only
   history).
7. The MCP companion drops the flag from its security and allocation schemas.
8. The security form dialog drops the toggle; the portfolio LiveView drops the
   "outside the steering basis" block.
9. ADR-0013 is marked **Superseded by ADR-0018**; product and integration docs
   replace the flag/"outside the steering basis" descriptions with the new
   bucket-excluded-from-view workflow (EN source baseline, faithful DE).

### Out of scope (do NOT build here)

- Re-deriving an "excluded block" from buckets — the behaviour is reproduced by
  the manual re-setup (tag the security with a bucket, exclude that bucket from
  the Strategie view), not by a new surfaced block.
- Any new bucket/view feature beyond what #443–#446 already shipped.

## Reproduction path (replaces the flag)

To keep a holding out of the steering basis while it still counts toward total
wealth: assign the affected securities to a bucket and exclude that bucket from
the Strategie view, then view allocation/risk under that view — those securities
are simply out of scope.

## Notes

- API/MCP coverage: in scope (security serializer, allocation `excluded` block,
  MCP schemas) — all updated here.
- User docs: updated (product documentation EN/DE, API & MCP integration EN/DE,
  ADR-0013 status, ADR index).
