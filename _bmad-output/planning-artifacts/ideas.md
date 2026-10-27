# Ideas

Every idea that is not yet worked out enough to build. This is the stage
before the registry ([ADR-0042, amendment of
2026-10-27](../../docs/decisions/0042-one-planning-structure.md)); the rule
that runs it is the sprint workflow's
["Ideas"](../../docs/development/sprint-workflow.md#ideas).

**How to add one:** say "Idee: …" (or "Idea: …") in any session. The session
writes it here as said and touches no code.

**This file is public.** It carries no instance facts, figures or names. An
idea that came with them is stated generically.

## Statuses

| Status | Meaning |
|---|---|
| `captured` | recorded as said; nobody has looked yet |
| `triaged` | an agent has searched where it is already described, checked it against the ADRs, the scope ladder and the non-goals, and named its kind and its open questions |
| `discussing` | the owner and an agent are working it through; the open question is in its row |
| `worked-out` | ready to plan; it moves to `epics.md` or an issue, and its row becomes a pointer |
| `planned` | named in a sprint plan |
| `built` | its sprint built it; the close-out sets this |
| `dropped` | not pursued, with the reason and what would reopen it |
| `gated` | behind a decision gate that names it; only that gate's decision reopens it |

A **`no-brainer`** mark on a `triaged` idea says it needs no conversation: one
obvious answer, inside scope, no money semantics. A plan may take it
straight away and says so.

**Kinds:** feature, UI, docs, app page, process, data.

**Per session, one idea goes deep.** A planning session proposes the next
one; the order below is the recommended one.

## The list

<!-- IDEAS-TABLE -->
