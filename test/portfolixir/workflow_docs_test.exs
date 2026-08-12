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
end
