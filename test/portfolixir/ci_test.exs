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
  # - Runtime-deploy automation files are absent; the local release image
  #   exists per ADR-0045 §2.
  test "ci keeps coverage while deployment automation stays out" do
    ci_workflow = File.read!(".github/workflows/ci.yml")
    mix_file = File.read!("mix.exs")

    assert ci_workflow =~ "mix coveralls"
    assert mix_file =~ ":excoveralls"
    assert mix_file =~ "preferred_envs:"
    assert mix_file =~ ~s(coveralls: :test)

    refute File.exists?(".github/workflows/build-image.yml")
    refute File.exists?(".github/workflows/deploy.yml")
    refute File.exists?("deploy")
    refute File.exists?("docs/deployment.md")
    refute File.exists?(".github/CODEOWNERS")

    # ADR-0045 §2 (D-2, signed 2026-09-05): the documented home deployment is a
    # production configuration built from a release. The release image and the
    # migration entrypoint are the operator's local build, never a published
    # artifact; the deploy-automation refutes above are unchanged.
    assert File.exists?("Dockerfile.release")
    assert File.exists?("lib/portfolixir/release.ex")
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
  # - AGENTS.md step 5 carries the tag duty: the close-out prepares the
  #   annotated-tag command and the owner runs it (owner action since
  #   2026-09-07, PR #780 -- the agent credential cannot push tags), and that
  #   push is what feeds this workflow.
  test "a tag push creates the GitHub release with generated notes" do
    release = File.read!(".github/workflows/release.yml")

    assert release =~ ~s(tags: ["v*", "[0-9]*.[0-9]*.[0-9]*"])
    assert release =~ "--generate-notes"
    assert release =~ "--verify-tag"
    assert release =~ "contents: write"
    refute release =~ "upload-artifact"

    agents = File.read!("AGENTS.md")
    assert agents =~ "prepares the annotated `X.Y.Z` tag"
    assert agents =~ "The tag is an **owner action**"
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
    # An exact tag (24.x.y-alpine, #761) or the floating major both name the
    # same major; the invariant is the major, not the tag shape.
    assert dockerfile =~ ~r/FROM node:#{ci_major}[.-]/
    assert package_json =~ ~s("@types/node": "^#{ci_major}.)
  end

  # User story (the 2026-09-24 runtime hotfix, Sprint 16 plan D-2):
  # As an operator who runs the image the documented deployment builds,
  # I want that image to ship exactly the Elixir and Erlang/OTP patch CI tests,
  # pinned in the same places the agent's toolchain and the dialyzer cache read,
  # so that the runtime cannot fall behind the tested one without a commit --
  # which is how every instance came to run an OTP whose TLS client had
  # published certificate-verification bypasses while CI tested a patched one.
  #
  # Acceptance criteria:
  # - Every CI job names one exact Elixir version and one exact OTP patch.
  # - The dialyzer cache key names the same versions.
  # - The development image and the release build stage are the Hex team's
  #   image for exactly those versions, pinned by tag and digest.
  # - The release runtime stage is the Debian release the build stage was
  #   built on, pinned by tag and digest.
  # - The agent install script defaults to the same versions.
  test "CI, both images, the PLT key and the install script name one Elixir and one OTP" do
    ci_workflow = File.read!(".github/workflows/ci.yml")
    dev_dockerfile = File.read!("Dockerfile")
    release_dockerfile = File.read!("Dockerfile.release")
    install_script = File.read!(".claude/scripts/install-elixir-toolchain.sh")

    elixir_versions =
      Regex.scan(~r/elixir-version: ['"]?([^'"\s]+)['"]?/, ci_workflow, capture: :all_but_first)

    otp_versions =
      Regex.scan(~r/otp-version: ['"]?([^'"\s]+)['"]?/, ci_workflow, capture: :all_but_first)

    assert [[elixir] | _] = elixir_versions
    assert [[otp] | _] = otp_versions
    assert Enum.uniq(elixir_versions) == [[elixir]], "CI jobs disagree on the Elixir version"
    assert Enum.uniq(otp_versions) == [[otp]], "CI jobs disagree on the OTP version"

    # A bare major ("27") lets setup-beam float to whatever patch is newest;
    # the image cannot follow a float, so both sides name an exact version.
    assert elixir =~ ~r/^\d+\.\d+\.\d+$/, "CI's Elixir version is not exact: #{elixir}"
    assert otp =~ ~r/^\d+\.\d+(\.\d+)+$/, "CI's OTP version is not an exact patch: #{otp}"

    plt = "${{ runner.os }}-plt-otp#{otp}-elixir#{elixir}-"

    assert ci_workflow =~ "key: #{plt}${{ hashFiles",
           "the PLT cache key would reuse a PLT built on another toolchain"

    assert ci_workflow =~ ~r/restore-keys: \|\s+#{Regex.escape(plt)}$/m,
           "the PLT restore key would fall back to a PLT built on another toolchain"

    # One FROM per stage, so a stale extra stage cannot hide beside a match.
    assert length(Regex.scan(~r/^FROM /m, dev_dockerfile)) == 1
    assert length(Regex.scan(~r/^FROM /m, release_dockerfile)) == 2

    image = ~r/hexpm\/elixir:#{Regex.escape("#{elixir}-erlang-#{otp}")}-debian-([a-z]+-\d{8})/

    assert [_, dev_debian] =
             Regex.run(~r/^FROM #{image.source}@sha256:[0-9a-f]{64}$/m, dev_dockerfile)

    assert [_, build_debian] =
             Regex.run(
               ~r/^FROM #{image.source}-slim@sha256:[0-9a-f]{64} AS build$/m,
               release_dockerfile
             )

    assert dev_debian == build_debian, "the development and release images differ in Debian"

    # The release carries the build stage's ERTS, linked against that Debian
    # release's libraries, so the runtime stage is the same release.
    assert release_dockerfile =~
             ~r/^FROM debian:#{build_debian}-slim@sha256:[0-9a-f]{64}$/m

    assert install_script =~ ~s(ELIXIR_VERSION="${ELIXIR_VERSION:-#{elixir}}")
    assert install_script =~ ~s(OTP_VERSION="${OTP_VERSION:-#{otp}}")
  end

  # User story (the 2026-09-24 runtime hotfix):
  # As an operator upgrading my instance,
  # I want the documented upgrade to fetch the current base images,
  # so that a runtime fix shipped in a base image actually reaches me -- a
  # plain `docker compose up --build` reuses the base image already cached.
  #
  # Acceptance criteria:
  # - The deployment guide, in English and German, rebuilds with --pull.
  # - The version report prints the OTP inside the release's base image,
  #   because reading the tag is exactly what hid the frozen runtime.
  test "the upgrade pulls the base images and the version report reads the OTP inside them" do
    for guide <- ["docs/home-deployment.md", "docs/de/home-deployment.md"] do
      assert File.read!(guide) =~ "docker compose build --pull",
             "#{guide} does not rebuild with --pull"
    end

    report = File.read!("scripts/version-report.sh")
    assert report =~ ~s(awk '/^FROM .* AS build$/ {print $2; exit}' Dockerfile.release)
    assert report =~ ~s(docker run --rm --entrypoint sh "${build_image}")
    assert report =~ "/releases/*/OTP_VERSION"
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

  # User story (ADR-0045 §2, closing-act findings):
  # As an operator starting the documented Compose deployment,
  # I want the companion to reach the app under its Compose name, the socket
  # handshake to accept every allowed Host, the release to find its static
  # manifest, and the throttle's proxy list to be settable,
  # so that the first `docker compose up` works instead of answering 421.
  test "the Compose deployment agrees with the runtime perimeter" do
    compose = File.read!("docker-compose.yml")
    dev_compose = File.read!("docker-compose.dev.yml")
    runtime = File.read!("config/runtime.exs")
    env_example = File.read!(".env.example")

    assert compose =~ ~s(PORTFOLIXIR_ALLOWED_HOSTS: app,)
    assert dev_compose =~ ~s(PORTFOLIXIR_ALLOWED_HOSTS: app)
    assert compose =~ "PORTFOLIXIR_TRUSTED_PROXIES:"
    assert compose =~ "PORTFOLIXIR_MCP_ALLOWED_HOSTS:"
    assert compose =~ "openssl rand -hex 32"

    assert runtime =~ ~s(cache_static_manifest: "priv/static/cache_manifest.json")
    refute runtime =~ "/opt/app/priv"
    assert runtime =~ "check_origin: Enum.map(Portfolixir.RuntimeConfig.allowed_hosts()"
    assert runtime =~ "Portfolixir.RuntimeConfig.trusted_proxies()"

    for variable <-
          ~w(PORTFOLIXIR_TRUSTED_PROXIES PORTFOLIXIR_MCP_ALLOWED_HOSTS POSTGRES_PASSWORD) do
      assert env_example =~ variable <> "="
    end

    assert env_example =~ "rand-hex-32"
  end

  # User story (#772 — Sprint 11 Lane D; D-3 of the 2026-09-05 security triage):
  # As a maintainer whose dependency tree carried three cowlib advisories
  # with no fixed release,
  # I want the HTTP server to be Bandit, Phoenix 1.8's default,
  # so that cowlib leaves the tree and the advisory gates run on the current
  # Hex with no pin and no ignore list.
  #
  # Acceptance criteria:
  # - mix.exs declares bandit and no plug_cowboy; the endpoint's adapter is
  #   Bandit.PhoenixAdapter.
  # - mix.lock carries no cowboy, cowlib, plug_cowboy, cowboy_telemetry or
  #   ranch entry.
  # - ci.yml no longer pins Hex ahead of `mix hex.audit`, and `mix deps.audit`
  #   runs with no --ignore-advisory-ids.
  test "the HTTP server is Bandit and the advisory gates run unpinned" do
    mix_file = File.read!("mix.exs")
    lock = File.read!("mix.lock")
    ci_workflow = File.read!(".github/workflows/ci.yml")

    assert mix_file =~ "{:bandit,"
    refute mix_file =~ ":plug_cowboy"

    assert Application.get_env(:portfolixir, PortfolixirWeb.Endpoint)[:adapter] ==
             Bandit.PhoenixAdapter

    for package <- ~w(cowboy cowlib plug_cowboy cowboy_telemetry ranch) do
      refute lock =~ ~s("#{package}":), "#{package} is still in mix.lock"
    end

    refute ci_workflow =~ "mix local.hex"
    assert ci_workflow =~ "run: mix hex.audit"
    assert ci_workflow =~ "run: mix deps.audit"
    refute ci_workflow =~ "--ignore-advisory-ids"
  end

  # User story (#772 — the triage's L11, same lane):
  # As a maintainer whose CI runs third-party actions,
  # I want every action pinned to a commit SHA with its version tag in a
  # comment,
  # so that a moved or compromised tag cannot change what runs on the runner,
  # and Dependabot's github-actions ecosystem still sees the version to bump.
  #
  # Acceptance criteria:
  # - Every `uses:` line in every workflow names a 40-hex-digit commit and
  #   carries a `# vX.Y.Z` comment.
  test "every GitHub Actions step is pinned to a commit SHA" do
    uses_lines =
      for path <- Path.wildcard(".github/workflows/*.yml"),
          line <- String.split(File.read!(path), "\n"),
          String.contains?(line, "uses:"),
          do: {path, String.trim(line)}

    assert uses_lines != []

    for {path, line} <- uses_lines do
      assert Regex.match?(~r|^uses: [\w.-]+/[\w.-]+@[0-9a-f]{40} # v\d+(\.\d+)*$|, line),
             "#{path}: not pinned to a commit SHA with a version comment: #{line}"
    end
  end

  # User story (#382 — Sprint 11 Lane C; D-2 of the Sprint 11 plan):
  # As a maintainer whose security gate used to ignore two of its own findings,
  # I want Sobelow to run with no --ignore,
  # so that the CSP and the HTTPS posture are checked rather than waived.
  #
  # Acceptance criteria:
  # - The Sobelow step is `mix sobelow --skip --exit` with no --ignore.
  # - config/prod.exs states the HTTPS posture: the force_ssl key is present
  #   and off by default, the runtime opt-in PHX_FORCE_SSL switching it on.
  test "sobelow runs with no ignore and prod.exs states the HTTPS posture" do
    ci_workflow = File.read!(".github/workflows/ci.yml")
    prod_config = File.read!("config/prod.exs")

    assert ci_workflow =~ "run: mix sobelow --skip --exit\n"
    refute ci_workflow =~ "sobelow --skip --exit --ignore"
    assert prod_config =~ "force_ssl: false"
    assert prod_config =~ "PHX_FORCE_SSL"
  end

  # User story (E25 S2, F66):
  # As an operator reading my container's log,
  # I want the production release to log at info,
  # so that database query parameters, request and page-event parameters and
  # session contents -- my financial figures among them -- never reach the log.
  #
  # Acceptance criteria:
  # - Reading config/prod.exs yields the logger level :info.
  test "the production release logs at info, not debug" do
    prod = Config.Reader.read!("config/prod.exs", env: :prod)

    assert get_in(prod, [:logger, :level]) == :info
  end

  # User story (Sprint 15 plan D-7):
  # As the maintainer relying on the npm audit gate,
  # I want it to run on the pinned Node toolchain,
  # so that it goes red for an advisory, not because the runner image's npm
  # called an audit endpoint the registry is retiring.
  #
  # Acceptance criteria:
  # - In the quality job the npm audit step runs after the Setup Node step
  #   (Node 24, the pinned line) — CI 1558 ran it before, on the image's npm,
  #   and failed on the retiring quick-audit endpoint's 400.
  # - The gate is unchanged: `--audit-level=high`, no `|| true`, no
  #   `continue-on-error`.
  test "the npm audit runs on the pinned Node and keeps its level" do
    ci = File.read!(".github/workflows/ci.yml")
    [_before, quality] = String.split(ci, ~r/^  quality:$/m, parts: 2)
    quality = quality |> String.split(~r/^  [a-z-]+:$/m) |> hd()

    {setup_node, _} = :binary.match(quality, "uses: actions/setup-node@")

    {audit, _} =
      :binary.match(quality, "run: npm audit --audit-level=high --prefix mcp-server")

    assert setup_node < audit, "the npm audit runs before the pinned Node is set up"
    assert quality =~ ~s(node-version: "24")

    audit_step = binary_part(quality, audit, byte_size(quality) - audit)
    audit_step = audit_step |> String.split("\n      - name:") |> hd()
    refute audit_step =~ "|| true"
    refute audit_step =~ "continue-on-error"
  end
end
