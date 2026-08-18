defmodule Portfolixir.WorkflowDocsTest do
  use ExUnit.Case, async: true

  @workflow_docs [
    "README.md",
    "CONTRIBUTING.md",
    "AGENTS.md",
    "docs/development/story-workflow.md"
  ]

  # User story:
  # As a contributor preparing Portfolixir stories,
  # I want the story, test, implementation, API, MCP, and documentation workflow documented,
  # so that visible changes stay small, reviewed, and test-first.
  #
  # Acceptance criteria:
  # - Public docs state the required story -> test -> failure -> code -> API/MCP -> docs -> security -> gates order.
  # - The user story template includes problem, behavior, surface, severity, acceptance, non-goals,
  #   required evidence, and done condition fields.
  # - The pull request template requires story-comment, test-first, API/MCP, docs-review, coverage, and gate evidence.
  # - Public docs state that new functionality updates user documentation, API/MCP coverage, and coverage gates.
  test "public workflow docs require story comments, failing tests, gates, and docs review" do
    workflow_text =
      @workflow_docs
      |> Enum.map(&File.read!/1)
      |> Enum.join("\n")

    for step <- [
          "1. User Story documented.",
          "2. Functional test written directly below the User Story comment.",
          "3. Test failure confirmed for the expected reason.",
          "4. Smallest implementation code written.",
          "5. API coverage reviewed and updated, or explicitly marked not applicable.",
          "6. MCP coverage reviewed and updated, or explicitly marked not applicable.",
          "7. User documentation reviewed and updated when visible behavior changed.",
          "8. Security audit performed.",
          "9. Required gates run."
        ] do
      assert workflow_text =~ step
    end

    assert workflow_text =~ "Every user-visible change updates user documentation"

    assert workflow_text =~
             "Every new user-visible function must include JSON API and MCP companion coverage"

    assert workflow_text =~ "mix coveralls"
    assert workflow_text =~ "npm test --prefix mcp-server"

    story_template = File.read!(".github/ISSUE_TEMPLATE/user_story.md")

    for field <- [
          "## User-visible problem",
          "## Expected behavior",
          "## Affected screen/route/surface",
          "## Severity",
          "## Acceptance criteria",
          "## Non-goals",
          "## Required evidence",
          "## Done condition"
        ] do
      assert story_template =~ field
    end

    pr_template = File.read!(".github/pull_request_template.md")

    for evidence <- [
          "Story text and acceptance criteria",
          "User story test evidence",
          "Security audit evidence",
          "API and MCP evidence",
          "Tests and Gates",
          "## Documentation",
          "mix coveralls",
          "npm test --prefix mcp-server",
          "Agent branch"
        ] do
      assert pr_template =~ evidence
    end

    public_text = workflow_text <> story_template <> pr_template

    for private_marker <- ["/Users/", "private board", "raw logs", "secret token"] do
      refute public_text =~ private_marker
    end
  end

  # User story:
  # As the maintainer of a repository whose backlog is kept by agents,
  # I want the batch close-out and the pull-request body to carry the maintenance
  # lane and the issue-closing duty in writing,
  # so that a dependency review is never skipped for lack of an owner and a
  # merged pull request closes the issues it finished without me asking.
  #
  # Acceptance criteria:
  # - AGENTS.md binds the maintenance lane to the epic-batch close-out, including
  #   the duty to report what was deliberately not updated (issue #675).
  # - AGENTS.md requires every PR body to name the issues its diff closes using a
  #   GitHub closing keyword, or to say why none applies.
  # - AGENTS.md keeps the carve-out for an issue a diff invalidates rather than
  #   implements: it is closed with a written reason, not by a keyword.
  # - The pull-request template offers a working closing-keyword line — one that
  #   references a GitHub issue number, not the non-resolving `PFX-...` form it
  #   carried until 2026-08-12.
  test "docs bind the maintenance lane and make a merged PR close its issues" do
    agents = File.read!("AGENTS.md")

    for maintenance_lane <- [
          "Maintenance lane",
          "reviews available updates for Hex, npm, Elixir/OTP",
          "reports what it deliberately did not update"
        ] do
      assert agents =~ maintenance_lane
    end

    for issue_closing <- [
          "closing keyword",
          "Closes #",
          "invalidates rather than implements",
          "say so in one clause and why"
        ] do
      assert agents =~ issue_closing
    end

    pr_template = File.read!(".github/pull_request_template.md")

    # `Closes #` and not `Closes`: the template read `- Closes PFX-...` until
    # 2026-08-12, which contains "Closes" and could never close anything. An
    # assertion that survives the defect it was written for guards nothing.
    assert pr_template =~ "Closes #"
    refute pr_template =~ "Closes PFX"
  end

  # User story:
  # As the maintainer of a repository whose design reviews are run by agents,
  # I want the design-critic and UAT walkthroughs bound to the conditions the
  # defects they exist to catch are actually visible under,
  # so that a review cannot pass a phone-clipping tab row or an untranslated
  # header simply because it ran at desktop width in English.
  #
  # Acceptance criteria:
  # - The agent-runnable review rubric records the three binding walkthrough
  #   conditions from issue #706: DE locale, a pass at 390 px or narrower, and
  #   seed data that triggers the finding surfaces on the touched screens.
  # - The rubric names the finding surfaces concretely (unclassified security,
  #   stale quote, a plan that does not sum to 100 %), so "triggering data" is
  #   checkable rather than aspirational.
  # - The conditions are binding on the walkthroughs, not advisory: a
  #   user-visible batch whose review skipped one of them is a finding.
  test "the review rubric binds the design-critic and UAT walkthrough conditions" do
    rubric = File.read!("docs/development/pr-review-checklist.md")

    for condition <- [
          "DE locale",
          "390 px",
          "unclassified security",
          "stale quote",
          "does not sum to 100"
        ] do
      assert rubric =~ condition
    end

    # Binding, not advisory. The triage that produced #706 diagnosed the Sprint 6
    # misses as review *conditions* rather than a missing gate, so the rubric has
    # to state the consequence of skipping one or it reads as a suggestion.
    assert rubric =~ "Walkthrough conditions"
    assert rubric =~ "skipped condition is itself a finding"
  end

  # User story:
  # As the maintainer of a project that carried two competing planning structures
  # since June,
  # I want the requirement registry and the work ledger to stop overlapping,
  # so that a reconciliation is one act of reading rather than a translation
  # between two documents that drift apart between sprints.
  #
  # Acceptance criteria (ADR-0042, Accepted 2026-08-17):
  # - `epics.md` keeps the Requirements Inventory and the FR Coverage Map, which
  #   are the sections every review actually reads.
  # - `epics.md` loses the Epic Detail sections and every `##### Story` row, and
  #   gains a tracker index carrying each epic's name, tracker and intent.
  # - `sprint-status.yaml` loses only the story rows; the `epic-N` and
  #   `epic-N-retrospective` keys stay, because `development_status` is required,
  #   the status view fails without it, and it is the retrospective ledger
  #   ADR-0026 step 5 depends on.
  # - #321's working agreement survives in `AGENTS.md`, the destination this
  #   decision leaves standing once the epic sections go.
  test "the planning structure is the requirement registry, not a work breakdown" do
    epics = File.read!("_bmad-output/planning-artifacts/epics.md")

    # Kept -- the parts ADR-0042 found demonstrably useful.
    assert epics =~ "## Requirements Inventory"
    assert epics =~ "### FR Coverage Map"

    # Removed -- the work breakdown that competed with the tracker set. Matched
    # as headings rather than as substrings: the migration note in this same
    # document has to be able to *name* what it removed.
    epic_headings =
      epics
      |> String.split("\n")
      |> Enum.filter(
        &(String.starts_with?(&1, "## Epic Detail") or String.starts_with?(&1, "##### Story"))
      )

    assert epic_headings == [],
           "epics.md still carries a work breakdown: #{inspect(epic_headings)}"

    # Replaced by one line per epic: name, tracker where one exists, intent.
    assert epics =~ "## Tracker Index"

    for epic <- 1..19 do
      assert epics =~ "**E#{epic} —", "tracker index is missing epic E#{epic}"
    end

    status = File.read!("_bmad-output/implementation-artifacts/sprint-status.yaml")

    [_preamble, development_status] = String.split(status, "\ndevelopment_status:", parts: 2)

    story_keys =
      development_status
      |> String.split("\n")
      |> Enum.map(&Regex.run(~r/^  (\S+):/, &1, capture: :all_but_first))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&hd/1)
      |> Enum.reject(&String.starts_with?(&1, "epic-"))

    assert story_keys == [],
           "development_status still carries story rows: #{inspect(story_keys)}"

    # ...and the two key shapes ADR-0042 §4 keeps are still there.
    assert development_status =~ "epic-19: "
    assert development_status =~ "epic-19-retrospective: "

    # #321's working agreement, preserved before the issue is closed by hand.
    agents = File.read!("AGENTS.md")
    assert agents =~ "One topic = one issue"
    assert agents =~ "file a new issue immediately"
  end
end
