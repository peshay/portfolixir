defmodule Portfolixir.WorkflowDocsTest do
  use ExUnit.Case, async: true

  @workflow_docs [
    "README.md",
    "CONTRIBUTING.md",
    "AGENTS.md",
    "docs/development/story-workflow.md"
  ]

  # User story:
  # As a contributor preparing future Portfolixir Epics,
  # I want the story, test, implementation, and user documentation workflow documented,
  # so that visible changes stay small, reviewed, and test-first.
  #
  # Acceptance criteria:
  # - Public docs state the required story -> test -> failure -> code -> gates -> docs order.
  # - The user story template includes problem, behavior, surface, severity, acceptance, non-goals,
  #   required evidence, and done condition fields.
  # - The pull request template requires story-comment, test-first, docs-review, coverage, and gate evidence.
  # - Public docs state that new functionality updates user documentation and coverage gates.
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
          "5. Security audit performed.",
          "6. Required gates run.",
          "7. User documentation reviewed and updated when visible behavior changed."
        ] do
      assert workflow_text =~ step
    end

    assert workflow_text =~ "Every user-visible change updates user documentation"
    assert workflow_text =~ "mix coveralls"

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
          "Tests and Gates",
          "## Documentation",
          "mix coveralls",
          "Agent branch"
        ] do
      assert pr_template =~ evidence
    end

    public_text = workflow_text <> story_template <> pr_template

    for private_marker <- ["/Users/", "private board", "raw logs", "secret token"] do
      refute public_text =~ private_marker
    end
  end
end
