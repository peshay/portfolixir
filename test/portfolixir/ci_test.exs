defmodule Portfolixir.CITest do
  use ExUnit.Case, async: true

  # User story:
  # As a maintainer keeping CI focused,
  # I want CI to run code coverage without deployment workflows,
  # so that the base branch proves quality without carrying staging or
  # deploy machinery. (The notes-only Release workflow is sanctioned
  # separately — issue 659; it builds nothing and deploys nothing.)
  #
  # Acceptance criteria:
  # - CI runs mix coveralls.
  # - mix coveralls is configured to run in the test environment by default.
  # - The test dependencies include excoveralls.
  # - No image build or deploy workflow remains.
  # - Release-image and runtime-deploy files are absent.
  test "ci keeps coverage while deployment automation stays out" do
    ci_workflow = File.read!(".github/workflows/ci.yml")
    mix_file = File.read!("mix.exs")

    assert ci_workflow =~ "mix coveralls"
    assert mix_file =~ ":excoveralls"
    assert mix_file =~ "preferred_envs:"
    assert mix_file =~ ~s(coveralls: :test)

    refute File.exists?(".github/workflows/build-image.yml")
    refute File.exists?(".github/workflows/deploy.yml")
    refute File.exists?("Dockerfile.release")
    refute File.exists?("deploy")
    refute File.exists?("docs/deployment.md")
    refute File.exists?("lib/portfolixir/release.ex")
    refute File.exists?(".github/CODEOWNERS")
  end

  # User story:
  # As a maintainer guarding the dependency tree,
  # I want CI to fail on known Hex security advisories,
  # so that vulnerable dependencies cannot land on the base branch unnoticed.
  #
  # Acceptance criteria:
  # - The quality job runs `mix deps.audit`.
  # - The mix_audit dependency stays declared.
  # - The historical "intentionally NOT wired" placeholder is gone.
  test "ci audits hex dependencies for security advisories" do
    ci_workflow = File.read!(".github/workflows/ci.yml")
    mix_file = File.read!("mix.exs")

    assert ci_workflow =~ "mix deps.audit"
    assert mix_file =~ ":mix_audit"
    refute ci_workflow =~ "intentionally NOT wired"
  end

  # User story:
  # As a self-hosted operator upgrading between sprints,
  # I want every sprint merge to produce a version tag and a GitHub release
  # with generated notes,
  # so that a known-good rollback point and a communicable changelog exist
  # without any manual release work (issue 659, ADR-0026 step 5).
  #
  # Acceptance criteria:
  # - A Release workflow triggers on version-tag pushes — the bare-number
  #   scheme the owner's first release (0.5.0) established, with v* kept
  #   for compatibility — and creates the release with generated notes
  #   from a verified tag.
  # - It builds no installable artifacts and needs only contents: write.
  # - AGENTS.md step 5 carries the tag duty, so the close-out creates the
  #   tag that feeds this workflow.
  test "a tag push creates the GitHub release with generated notes" do
    release = File.read!(".github/workflows/release.yml")

    assert release =~ ~s(tags: ["v*", "[0-9]*.[0-9]*.[0-9]*"])
    assert release =~ "--generate-notes"
    assert release =~ "--verify-tag"
    assert release =~ "contents: write"
    refute release =~ "upload-artifact"

    assert File.read!("AGENTS.md") =~ "creates and pushes an annotated"
  end

  # User story:
  # As a maintainer diagnosing a red CI run,
  # I want the test job's full output preserved as an artifact,
  # so that failures that scroll out of the 5000-line log window stay
  # recoverable (issue 654 — run 31043767212 lost all twenty failure
  # blocks), and I want the warning flood that pushed them out fixed at the
  # source: a phx-change form without an id fails the build (issue 653).
  #
  # Acceptance criteria:
  # - The test step tees its output to a file with pipefail intact.
  # - The artifact uploads on every outcome (if: always()).
  # - config/test.exs raises on LiveView's missing-form-id warning.
  test "test failures survive the log window and form-id warnings are fatal" do
    ci_workflow = File.read!(".github/workflows/ci.yml")

    assert ci_workflow =~ "set -o pipefail"
    assert ci_workflow =~ "tee test-output.log"
    assert ci_workflow =~ "if: always()"
    assert ci_workflow =~ "actions/upload-artifact"

    assert File.read!("config/test.exs") =~ "missing_form_id: :raise"
  end

  # User story:
  # As a maintainer starting the local Docker app,
  # I want the container image to install the expected Hex version during build,
  # so that runtime startup does not print package-manager update warnings.
  #
  # Acceptance criteria:
  # - The Dockerfile pins Hex to the currently expected version.
  # - The pinned Hex version is installed before dependencies are fetched.
  test "docker image pins hex before fetching dependencies" do
    dockerfile = File.read!("Dockerfile")

    assert dockerfile =~ "HEX_VERSION=2.4.2"
    assert dockerfile =~ "mix local.hex ${HEX_VERSION} --force"

    assert String.split(dockerfile, "mix local.hex ${HEX_VERSION} --force")
           |> Enum.at(1)
           |> String.contains?("mix deps.get")
  end

  # User story (#728):
  # As a maintainer whose MCP gates decide whether an MCP change may land,
  # I want the Node version those gates run under pinned, and pinned in the
  # SAME place local runs, the container and the type definitions read,
  # so that the runtime cannot change under the project with no commit, no PR
  # and no failing check -- which is why `@types/node` had nothing to agree
  # with and stayed parked in Sprint 7.
  #
  # Acceptance criteria:
  # - The job running the MCP gates sets up Node explicitly.
  # - `mcp-server/package.json` declares the same major in `engines.node`.
  # - The MCP container image names the same major.
  # - `@types/node` follows that major rather than the registry's latest.
  test "the MCP gates, the container and the type definitions name one Node major" do
    ci_workflow = File.read!(".github/workflows/ci.yml")
    package_json = File.read!("mcp-server/package.json")
    dockerfile = File.read!("mcp-server/Dockerfile")

    assert ci_workflow =~ "actions/setup-node",
           "the MCP gates would otherwise run on whatever Node ubuntu-latest ships"

    assert [[_, ci_major]] = Regex.scan(~r/node-version: ['"](\d+)['"]/, ci_workflow)

    # The pinned line is an Active LTS major, not the newest release: type
    # definitions describe the runtime, and the runtime is the one the
    # container ships.
    assert package_json =~ ~s("node": ">=#{ci_major} <#{String.to_integer(ci_major) + 1}")
    assert dockerfile =~ "FROM node:#{ci_major}-"
    assert package_json =~ ~s("@types/node": "^#{ci_major}.)
  end

  # User story:
  # As a maintainer whose test suite is the mechanical guard behind money math,
  # I want async LiveView assertions to have a wall-clock budget that survives
  # coverage instrumentation,
  # so that a red CI run means a real defect instead of a timing coincidence,
  # and the next red run is not assumed to be the flake.
  #
  # Context (#682 follow-on): #682 shipped the instrumentation -- the persisted
  # test-output artifact and the recorded seed -- and said explicitly that
  # hunting the cause was only worth doing once a burst could be inspected. The
  # artifact caught one: `render_async/1` defaults its timeout to
  # `:ex_unit, :assert_receive_timeout`, which is 100 ms, and the async work
  # behind a LiveView mount regularly exceeds that under `mix coveralls`
  # instrumentation. 129 call sites relied on that default; 11 had already been
  # hand-patched with explicit timeouts, which is symptom-patching that left the
  # other 118 exposed.
  #
  # Acceptance criteria:
  # - The suite raises `assert_receive_timeout` centrally, so every
  #   `render_async/1` call site inherits the budget rather than 11 of them.
  # - The budget stays a *timeout*, not a delay: a passing assertion returns as
  #   soon as the async work completes, so the suite does not get slower.
  # - `refute_receive_timeout` is NOT raised -- negative assertions must stay
  #   fast, and raising both would trade the flake for a slow suite.
  test "async assertions have a coverage-proof wall-clock budget (#682 follow-on)" do
    assert Application.fetch_env!(:ex_unit, :assert_receive_timeout) >= 1_000,
           "render_async/1 inherits this value; under coverage instrumentation " <>
             "100ms is not enough and the suite goes intermittently red."

    # The negative-assertion budget is deliberately left alone.
    assert Application.fetch_env!(:ex_unit, :refute_receive_timeout) <= 200

    # Set centrally, so a new async test does not have to know about this.
    assert File.read!("test/test_helper.exs") =~ "assert_receive_timeout"
  end
end
