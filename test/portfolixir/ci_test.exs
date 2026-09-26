defmodule Portfolixir.CITest do
  use ExUnit.Case, async: true

  @migration_gate "Reject any change to an existing migration"

  # A scratch repository's git reads neither the user's nor the system's
  # configuration (no rename default, hook or signing setting of the machine
  # running the suite), and commits under a synthetic identity.
  @git_env [
    {"GIT_CONFIG_GLOBAL", "/dev/null"},
    {"GIT_CONFIG_NOSYSTEM", "1"},
    {"GIT_AUTHOR_NAME", "Synthetic Author"},
    {"GIT_AUTHOR_EMAIL", "author@example.invalid"},
    {"GIT_COMMITTER_NAME", "Synthetic Author"},
    {"GIT_COMMITTER_EMAIL", "author@example.invalid"}
  ]

  # Long enough that an edit keeps it above git's 50% rename-similarity
  # threshold, so a renamed-and-edited copy is reported as a rename.
  @migration """
  defmodule Portfolixir.Repo.Migrations.CreateWidgets do
    use Ecto.Migration

    def change do
      create table(:widgets) do
        add :name, :string, null: false
        add :size, :integer
        add :colour, :string
        timestamps()
      end

      create index(:widgets, [:name])
    end
  end
  """

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

    # E25 S7, F23: with PHX_FORCE_SSL on, the companion's plain-HTTP calls
    # under the Compose name are left unredirected; runtime.exs reads the
    # variable through force_ssl_opts/0, which takes it as its second input.
    assert compose =~ ~s(PORTFOLIXIR_FORCE_SSL_EXCLUDED_HOSTS: app)
    assert compose =~ "PORTFOLIXIR_API_BASE_URL: http://app:4000"
    assert runtime =~ "Portfolixir.RuntimeConfig.force_ssl_opts()"

    assert File.read!("lib/portfolixir/runtime_config.ex") =~
             ~s[System.get_env("PORTFOLIXIR_FORCE_SSL_EXCLUDED_HOSTS")]

    # E25 S7, G26: the app knows the companion's token as the named entry
    # "mcp", so the journal names the companion; the operator's further
    # entries follow it. The token itself reaches the app only there, once.
    assert compose =~
             "PORTFOLIXIR_API_TOKENS: mcp=${PORTFOLIXIR_API_TOKEN:?set PORTFOLIXIR_API_TOKEN " <>
               "in .env},${PORTFOLIXIR_API_TOKENS:-}"

    [app_service] = Regex.run(~r/^  app:\n(?:    .*\n|\n)*/m, compose)
    refute app_service =~ ~r/^      PORTFOLIXIR_API_TOKEN:/m

    for variable <-
          ~w(PORTFOLIXIR_TRUSTED_PROXIES PORTFOLIXIR_MCP_ALLOWED_HOSTS POSTGRES_PASSWORD) do
      assert env_example =~ variable <> "="
    end

    assert env_example =~ "rand-hex-32"
  end

  # User story (E25 S2, F08):
  # As an operator who starts the development stack on a machine in a network,
  # I want both Compose files to publish every port on loopback only,
  # so that the development app and its database, which run on public
  # development secrets, are never reachable from the rest of the network.
  #
  # Acceptance criteria:
  # - Every `ports:` entry in docker-compose.yml and docker-compose.dev.yml is
  #   prefixed with 127.0.0.1.
  # - SECURITY.md names the development stack's public secrets.
  # - The deployment guide (EN, DE) moves an instance off the development
  #   stack, the documented deployment before #760, by a backup and a restore.
  test "every published port in both Compose files is on loopback" do
    for path <- ["docker-compose.yml", "docker-compose.dev.yml"] do
      entries =
        ~r/^\s+ports:\n((?:\s+- .*\n)+)/m
        |> Regex.scan(File.read!(path), capture: :all_but_first)
        |> Enum.flat_map(fn [block] -> String.split(block, "\n", trim: true) end)
        |> Enum.map(&String.trim/1)

      assert entries != [], "#{path} publishes no port at all"

      for entry <- entries do
        assert entry =~ ~r/^- "127\.0\.0\.1:\d+:\d+"$/,
               "#{path} publishes a port beyond loopback: #{entry}"
      end
    end

    security = "SECURITY.md" |> File.read!() |> String.replace(~r/\s+/, " ")
    assert security =~ "`docker-compose.dev.yml`"
    assert security =~ "public development secrets"

    for {path, heading} <- [
          {"docs/home-deployment.md", "### Moving off the development stack"},
          {"docs/de/home-deployment.md", "### Umzug vom Entwicklungs-Stack"}
        ] do
      guide = File.read!(path)
      assert guide =~ heading, path
      assert guide =~ "pg_dump -U postgres -d portfolixir_dev --format=custom", path
      assert guide =~ "docker compose -f docker-compose.dev.yml down -v", path
    end
  end

  # User story (E25 S2, F62):
  # As an operator running the release image beside a database and a
  # companion container,
  # I want the release to start without Erlang distribution,
  # so that no distribution listener is open to the sibling containers.
  #
  # Acceptance criteria:
  # - The runtime stage of Dockerfile.release sets RELEASE_DISTRIBUTION=none.
  test "the release starts without Erlang distribution" do
    # The header comment, the build stage, the runtime stage.
    assert [_header, _build_stage, runtime_stage] =
             "Dockerfile.release" |> File.read!() |> String.split(~r/^FROM /m)

    assert runtime_stage =~ ~r/^(?:ENV)?\s+RELEASE_DISTRIBUTION=none\b/m,
           "the runtime stage does not switch Erlang distribution off"
  end

  # User story (E25 S2, F59):
  # As an operator running the release image,
  # I want the release tree owned by root and not writable by the user it runs
  # as, with the stored logos on a named volume of their own,
  # so that the running application cannot change its own code, and the logos
  # survive a rebuild and are part of the backup.
  #
  # Acceptance criteria:
  # - No COPY in the runtime stage carries --chown.
  # - The runtime stage creates the logo directory for the runtime user, names
  #   it in PORTFOLIXIR_LOGO_DIR, and keeps the release's temporary files
  #   outside the release tree (RELEASE_TMP).
  # - docker-compose.yml mounts a named volume at that directory and declares it.
  # - The deployment guide's backup section (EN, DE) covers the volume.
  test "the release tree is read-only for its user and the logos live on a volume" do
    assert [_header, _build_stage, runtime_stage] =
             "Dockerfile.release" |> File.read!() |> String.split(~r/^FROM /m)

    copies = Regex.scan(~r/^COPY .*$/m, runtime_stage) |> List.flatten()
    assert copies != []

    for copy <- copies do
      refute copy =~ "--chown", "the runtime user would own what this copies: #{copy}"
    end

    logo_dir = "/var/lib/portfolixir/logos"
    assert runtime_stage =~ "install -d -o portfolixir -g portfolixir -m 0750 #{logo_dir}"
    assert runtime_stage =~ ~r/^(?:ENV)?\s+PORTFOLIXIR_LOGO_DIR=#{Regex.escape(logo_dir)}\b/m
    assert [_, release_tmp] = Regex.run(~r/^(?:ENV)?\s+RELEASE_TMP=(\S+)/m, runtime_stage)
    refute String.starts_with?(release_tmp, "/opt/app")

    compose = File.read!("docker-compose.yml")
    assert compose =~ "- portfolixir-logos:#{logo_dir}"
    assert compose =~ ~r/^volumes:\n(?:  .*\n)*  portfolixir-logos:$/m

    for path <- ["docs/home-deployment.md", "docs/de/home-deployment.md"] do
      guide = File.read!(path)
      assert guide =~ "portfolixir-logos", path
      assert guide =~ "tar -C #{logo_dir} -cf -", path
    end
  end

  # User story (E25 S2, F25; ADR-0045 §2 "digest-pinned images"):
  # As an operator building and running the documented images,
  # I want every base image and every Compose image pinned by tag and digest,
  # and each kept current by Dependabot,
  # so that what I run is exactly what the repository names, and an OS or
  # database fix arrives as a reviewed digest move rather than never.
  #
  # Acceptance criteria:
  # - Every FROM line of the three Dockerfiles carries @sha256 and 64 hex digits.
  # - Every image line of both Compose files does too.
  # - Dependabot watches the Compose files (the docker-compose ecosystem) as
  #   well as the Dockerfiles, and never proposes a PostgreSQL major, which
  #   needs a dump and restore rather than a bump.
  test "every base image and Compose image is pinned by digest" do
    digest = ~r/@sha256:[0-9a-f]{64}(\s+AS\s+\w+)?$/

    for path <- ["Dockerfile", "Dockerfile.release", "mcp-server/Dockerfile"],
        line <- Regex.scan(~r/^FROM .*$/m, File.read!(path)) |> List.flatten() do
      assert line =~ digest, "#{path}: not pinned by digest: #{line}"
    end

    for path <- ["docker-compose.yml", "docker-compose.dev.yml"] do
      images = Regex.scan(~r/^\s+image: .*$/m, File.read!(path)) |> List.flatten()
      assert images != [], "#{path} names no image"

      for line <- images do
        assert String.trim(line) =~ ~r/^image: [\w.\/-]+:[\w.-]+@sha256:[0-9a-f]{64}$/,
               "#{path}: not pinned by tag and digest: #{String.trim(line)}"
      end
    end

    dependabot = File.read!(".github/dependabot.yml")
    assert dependabot =~ ~s(package-ecosystem: "docker-compose")

    [_, compose_entry] = String.split(dependabot, ~s(package-ecosystem: "docker-compose"))
    compose_entry = compose_entry |> String.split("- package-ecosystem:") |> hd()
    assert compose_entry =~ ~s(dependency-name: "postgres")
    assert compose_entry =~ ~s(update-types: ["version-update:semver-major"])
  end

  # User story (E25 S2, F65):
  # As an operator building the images from my own checkout,
  # I want the build context to leave out everything git leaves out,
  # so that my agent memory, local settings, secrets, stored logos and
  # generated files never end up inside an image.
  #
  # Acceptance criteria:
  # - Every pattern in .gitignore appears in .dockerignore.
  # - A pattern git matches at any depth (no slash but a trailing one) appears
  #   in its any-depth form, `**/<pattern>`, because .dockerignore anchors
  #   every pattern at the context root; a negation keeps its `!`.
  test "the build context leaves out everything git leaves out" do
    patterns = fn path ->
      path
      |> File.read!()
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    end

    dockerignore = MapSet.new(patterns.(".dockerignore"))

    missing =
      for pattern <- patterns.(".gitignore"),
          expected = dockerignore_form(pattern),
          not MapSet.member?(dockerignore, expected),
          do: "#{pattern} (as #{expected})"

    assert missing == [], ".dockerignore lacks .gitignore entries:\n" <> Enum.join(missing, "\n")
  end

  defp dockerignore_form("!" <> pattern), do: "!" <> dockerignore_form(pattern)

  defp dockerignore_form(pattern) do
    anchored? = pattern |> String.trim_trailing("/") |> String.contains?("/")
    if anchored?, do: pattern, else: "**/" <> pattern
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

  # User story (E25 S8, F61 -- #893):
  # As a maintainer whose workflows run on pull requests from anyone,
  # I want every run script to read refs and SHAs from its environment, and
  # every checkout that never pushes to drop the job token once it is done,
  # so that a crafted ref name reaches a script as data rather than as shell
  # text, and no later step -- a dependency's install script, a hook -- finds
  # the token in .git/config.
  #
  # Acceptance criteria:
  # - No `run:` script in any workflow contains a `${{ }}` context expression;
  #   the values reach the script through the step's `env:`.
  # - Every actions/checkout step sets `persist-credentials: false`: no
  #   workflow here pushes.
  # - The migration gate diffs against the pull request's immutable base SHA,
  #   passed through env, instead of a branch name fetched at run time.
  test "run scripts read no context expressions and checkouts keep no token" do
    checked =
      for {path, workflow} <- workflows() do
        scripts = run_scripts(workflow)

        for script <- scripts do
          refute script =~ "${{",
                 "#{path}: a run script interpolates a context expression:\n#{script}"
        end

        checkouts = for step <- steps(workflow), step =~ "uses: actions/checkout@", do: step

        for checkout <- checkouts do
          assert checkout =~ ~r/^\s+persist-credentials: false$/m,
                 "#{path}: a checkout leaves the job token in .git/config:\n#{checkout}"
        end

        {length(scripts), length(checkouts)}
      end

    # The parser found what it polices, so a passing run is not a vacuous one.
    assert Enum.sum(for {scripts, _} <- checked, do: scripts) > 0
    assert Enum.sum(for {_, checkouts} <- checked, do: checkouts) > 0

    gate = step!(ci_workflow(), @migration_gate)
    assert gate =~ ~r/^\s+BASE_SHA: \$\{\{ github\.event\.pull_request\.base\.sha \}\}$/m
    assert gate =~ ~s("$BASE_SHA"...HEAD)
  end

  # User story (E25 S8, F55 -- #893):
  # As a maintainer relying on applied migrations being immutable,
  # I want the migration gate to see every way an existing migration file can
  # change, not only the two statuses it used to list,
  # so that renaming a migration while editing it -- which git reports as a
  # rename, neither a modification nor a deletion -- cannot carry an edited
  # migration past the gate.
  #
  # Acceptance criteria:
  # - The gate diffs with rename detection off (`--no-renames`), so a moved
  #   file is a deletion plus an addition.
  # - It lists every status except an addition (`--diff-filter=a`): the only
  #   change it lets through under priv/repo/migrations/ is a new file.
  # - Run against a scratch repository, the gate's own script passes a new
  #   migration and fails an edit, a deletion, a rename, a rename with an
  #   edit, a mode change and a type change.
  test "the migration gate turns rename detection off and permits only additions" do
    [script] = ci_workflow() |> step!(@migration_gate) |> run_scripts()

    assert {"No existing migration was changed.\n", 0} = run_migration_gate(script, :add)

    for change <- [:edit, :delete, :rename, :rename_and_edit, :mode, :type] do
      {output, status} = run_migration_gate(script, change)
      assert status != 0, "the gate let an existing migration's #{change} through:\n#{output}"
      # Refused by the gate itself, naming the file, not by a script error.
      assert output =~ "Applied migrations are immutable"
      assert output =~ "20260101000000_create_widgets.exs"
    end

    # The flags that make it so, pinned where the behaviour above would only
    # show a symptom.
    assert [diff] = Regex.run(~r/git diff [^\n]* -- priv\/repo\/migrations\//, script)
    assert diff =~ " --no-renames "
    assert diff =~ " --diff-filter=a "
    refute script =~ "--diff-filter=MD"
  end

  # User story (E25 S8, F58 -- #893):
  # As an operator building the MCP companion's image, or installing the
  # companion on its own,
  # I want the dependency install to run no dependency lifecycle script, as
  # CI's install already runs none,
  # so that a compromised package in the tree cannot execute code in the image
  # build or on my machine merely by being installed.
  #
  # Acceptance criteria:
  # - Every npm install in mcp-server/Dockerfile is `npm ci --ignore-scripts`.
  # - The image is built in two stages, and the runtime stage copies only the
  #   package manifest, the production modules and dist/ from the build: no
  #   source, no compiler, no dev dependency, no install of its own.
  # - mcp-server/.npmrc sets ignore-scripts=true, so an ad-hoc `npm install`
  #   in the companion's folder runs none either.
  # - The documented standalone install (README, CONTRIBUTING, the home
  #   deployment guide in English and German) is
  #   `npm ci --ignore-scripts --prefix mcp-server`.
  test "the MCP image and the documented install run no dependency lifecycle scripts" do
    dockerfile = File.read!("mcp-server/Dockerfile")

    installs = Regex.scan(~r/\bnpm (?:ci|install|i|add)\b[^\n]*/, dockerfile)
    assert installs != []

    for [install] <- installs do
      assert install =~ ~r/^npm ci --ignore-scripts\b/, "mcp-server/Dockerfile: #{install}"
    end

    assert [build, runtime] = String.split(dockerfile, ~r/^FROM /m) |> tl()
    assert build =~ ~r/ AS build\n/
    assert build =~ "npm run build"

    copied = Regex.scan(~r/^COPY (.*)$/m, runtime, capture: :all_but_first)

    assert copied == [
             ["--from=build /app/package.json ./"],
             ["--from=build /app/node_modules ./node_modules"],
             ["--from=build /app/dist ./dist"]
           ]

    refute runtime =~ ~r/^RUN /m, "the runtime stage installs or builds on its own"

    assert File.read!("mcp-server/.npmrc") =~ ~r/^ignore-scripts=true$/m

    for doc <- ~w(README.md CONTRIBUTING.md docs/home-deployment.md docs/de/home-deployment.md) do
      text = File.read!(doc)

      assert text =~ "npm ci --ignore-scripts --prefix mcp-server",
             "#{doc}: no script-free install"

      refute text =~ "npm install --prefix mcp-server", "#{doc}: still runs install scripts"
    end
  end

  # User story (E25 S8, F60 -- #893):
  # As a maintainer whose pre-commit gate runs third-party code on every CI run,
  # I want pre-commit installed from a hash-pinned requirements file and every
  # hook repository frozen to a commit,
  # so that neither a new upload to the package index nor a moved tag in a
  # hook repository changes what the gate runs without a commit here.
  #
  # Acceptance criteria:
  # - Every remote hook repository's `rev:` is a 40-hex commit SHA, with the
  #   tag it was resolved from in a `# frozen: vX.Y.Z` comment.
  # - CI installs pre-commit with `--require-hashes`, wheels only, from
  #   .github/pre-commit/requirements.txt; `pip install --upgrade
  #   pre-commit` is gone.
  # - Every requirement in that file, pre-commit's own dependencies included,
  #   is pinned with `==` and carries at least one sha256 hash.
  test "pre-commit is hash-pinned and its hook repositories are frozen to commits" do
    config = File.read!(".pre-commit-config.yaml")
    remote_repos = Regex.scan(~r/^\s*- repo: https:\/\//m, config)
    revs = Regex.scan(~r/^\s+rev: (.*)$/m, config, capture: :all_but_first)

    assert remote_repos != []
    assert length(revs) == length(remote_repos), "a remote hook repository has no rev"

    for [rev] <- revs do
      assert rev =~ ~r/^[0-9a-f]{40}\s+# frozen: v\d+(\.\d+)*$/,
             ".pre-commit-config.yaml: rev is not frozen to a commit: #{rev}"
    end

    [install] = ci_workflow() |> step!("Install pre-commit") |> run_scripts()
    assert install =~ "python3 -m pip install --require-hashes --only-binary :all:"
    assert install =~ "-r .github/pre-commit/requirements.txt"
    refute install =~ "--upgrade"

    requirements =
      ".github/pre-commit/requirements.txt"
      |> File.read!()
      |> String.replace("\\\n", " ")
      |> String.split("\n")
      |> Enum.map(&(&1 |> String.split() |> Enum.join(" ")))
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))

    assert Enum.any?(requirements, &String.starts_with?(&1, "pre-commit=="))

    for requirement <- requirements do
      assert requirement =~ ~r/^[A-Za-z0-9._-]+==\S+( --hash=sha256:[0-9a-f]{64})+$/,
             "not pinned by version and hash: #{requirement}"
    end
  end

  # User story (E25 S8 review round, F60 -- #893):
  # As a contributor whose system Python is externally managed (PEP 668, as
  # on current Debian, Ubuntu and Homebrew),
  # I want the documented local pre-commit install to go into a virtual
  # environment,
  # so that the hash-pinned install CI runs works on my machine as well
  # instead of being refused.
  #
  # Acceptance criteria:
  # - CONTRIBUTING creates a virtual environment outside the checkout, so
  #   neither git nor the image build context ever sees it.
  # - The hash-pinned requirements file is installed with that environment's
  #   pip, and no documented command installs into the global interpreter
  #   with `python3 -m pip install`.
  test "the documented local pre-commit install goes into a virtual environment" do
    contributing = File.read!("CONTRIBUTING.md")

    assert [[venv]] =
             Regex.scan(~r/^python3 -m venv (\S+)$/m, contributing, capture: :all_but_first)

    assert venv =~ ~r/^(~|\$HOME)\//, "the virtual environment lies in the checkout: #{venv}"

    assert contributing =~
             """
             python3 -m venv #{venv}
             . #{venv}/bin/activate
             python -m pip install --require-hashes --only-binary :all: -r .github/pre-commit/requirements.txt
             pre-commit install --install-hooks
             """

    refute contributing =~ "python3 -m pip install", "installs into the global interpreter"
  end

  # User story (E25 S8, F60 -- #893):
  # As a maintainer, and an agent whose toolchain the install script fetches,
  # I want CI's database service and the companion's base image pinned by
  # digest, and every toolchain archive the install script downloads checked
  # against a SHA-256 written in this repository,
  # so that a re-pushed tag or a tampered download cannot change what the
  # gates and the agent run on without a commit here.
  #
  # Acceptance criteria:
  # - Every CI service container names an exact PostgreSQL tag and a sha256
  #   digest, the same in every job.
  # - Both stages of the MCP image name one Node tag with a sha256 digest.
  # - The agent install script hard-codes a SHA-256 for the OTP and the
  #   Elixir archive; a version override without its own checksum is refused.
  # - Its one download helper removes and refuses an archive whose SHA-256
  #   differs, and every download goes through it, before the installed
  #   toolchain is removed.
  test "service and base images are pinned by digest and toolchain downloads by SHA-256" do
    images = Regex.scan(~r/^\s+image: (.*)$/m, ci_workflow(), capture: :all_but_first)
    assert images != []
    assert [[image]] = Enum.uniq(images), "CI jobs disagree on the database image"
    assert image =~ ~r/^postgres:\d+\.\d+@sha256:[0-9a-f]{64}$/

    froms = Regex.scan(~r/^FROM (\S+)/m, File.read!("mcp-server/Dockerfile"))
    assert [[_, build], [_, runtime]] = froms
    assert build == runtime, "the MCP image's two stages differ in base"
    assert build =~ ~r/^node:[\w.-]+@sha256:[0-9a-f]{64}$/

    script = File.read!(".claude/scripts/install-elixir-toolchain.sh")
    assert script =~ ~r/^OTP_SHA256="\$\{OTP_SHA256:-[0-9a-f]{64}\}"$/m
    assert script =~ ~r/^ELIXIR_SHA256="\$\{ELIXIR_SHA256:-[0-9a-f]{64}\}"$/m

    # Every download goes through the helper, and each archive is fetched and
    # verified before the toolchain it replaces is removed.
    assert [_] = Regex.scan(~r/^\s*curl /m, script)

    for {download, dir} <- [
          {~s(fetch_verified "https://builds.hex.pm/builds/otp/), ~s(rm -rf "${OTP_DIR}")},
          {~s(fetch_verified "https://github.com/elixir-lang/elixir/), ~s(rm -rf "${ELIXIR_DIR}")}
        ] do
      assert {fetched, _} = :binary.match(script, download)
      assert {removed, _} = :binary.match(script, dir)
      assert fetched < removed, "#{dir} runs before its archive is verified"
    end

    assert [helper] = Regex.run(~r/^fetch_verified\(\) \{\n.*?^\}$/ms, script)
    assert {"", 0} = run_fetch_verified(helper, :match)
    assert {output, status} = run_fetch_verified(helper, :mismatch)
    assert status != 0
    assert output =~ "refusing"
  end

  defp ci_workflow, do: File.read!(".github/workflows/ci.yml")

  defp workflows do
    for path <- Path.wildcard(".github/workflows/*.yml"), do: {path, File.read!(path)}
  end

  # The script under every `run:` key: the inline scalar, or a block scalar's
  # lines -- every following line indented deeper than the key, blank lines
  # included, which is where YAML ends a block scalar -- with the block's
  # indentation removed, as the runner hands it to bash.
  defp run_scripts(yaml) do
    lines = String.split(yaml, "\n")

    for {line, index} <- Enum.with_index(lines),
        [_, indent, dash, value] <- [Regex.run(~r/^(\s*)(- )?run:(.*)$/, line)] do
      key_column = String.length(indent) + String.length(dash)
      body = block_after(lines, index, key_column)

      if String.trim(value) =~ ~r/^[|>][-+]?$/ do
        dedent(body)
      else
        Enum.join([String.trim(value) | body], "\n")
      end
    end
  end

  defp dedent(lines) do
    column =
      lines |> Enum.reject(&(String.trim(&1) == "")) |> Enum.map(&indentation/1) |> Enum.min()

    Enum.map_join(lines, "\n", &String.slice(&1, column..-1//1))
  end

  # Every step of every job: its `- ` line plus every following line indented
  # deeper than the dash, which is where YAML ends a block sequence item.
  defp steps(yaml) do
    lines = String.split(yaml, "\n")

    for {line, index} <- Enum.with_index(lines),
        [_, indent] <- [Regex.run(~r/^(\s*)- (?:name|uses|run):/, line)] do
      Enum.join([line | block_after(lines, index, String.length(indent))], "\n")
    end
  end

  defp step!(yaml, name) do
    [step] = for step <- steps(yaml), step =~ ~r/^\s*- name: #{Regex.escape(name)}$/m, do: step
    step
  end

  defp block_after(lines, index, column) do
    lines
    |> Enum.drop(index + 1)
    |> Enum.take_while(&(String.trim(&1) == "" or indentation(&1) > column))
  end

  defp indentation(line), do: String.length(line) - String.length(String.trim_leading(line, " "))

  # Runs the gate's script in a scratch repository whose base commit holds one
  # migration and whose HEAD applies `change` to it, as the pull_request event
  # would: BASE_SHA in the environment, the change checked out, `bash -e` as
  # the runner invokes a `run:` script.
  defp run_migration_gate(script, change) do
    dir = Path.join(System.tmp_dir!(), "migration-gate-#{System.unique_integer([:positive])}")
    migrations = Path.join(dir, "priv/repo/migrations")
    File.mkdir_p!(migrations)

    try do
      git!(dir, ["init", "--quiet"])
      File.write!(Path.join(migrations, "20260101000000_create_widgets.exs"), @migration)
      git!(dir, ["add", "--all"])
      git!(dir, ["commit", "--quiet", "--message", "base"])
      base = dir |> git!(["rev-parse", "HEAD"]) |> String.trim()

      change_migration(change, Path.join(migrations, "20260101000000_create_widgets.exs"))
      git!(dir, ["add", "--all"])
      git!(dir, ["commit", "--quiet", "--message", "#{change}"])

      System.cmd("bash", ["-e", "-c", script],
        cd: dir,
        env: [{"BASE_SHA", base} | @git_env],
        stderr_to_stdout: true
      )
    after
      File.rm_rf!(dir)
    end
  end

  defp change_migration(:add, path) do
    File.write!(Path.join(Path.dirname(path), "20260102000000_create_gadgets.exs"), @migration)
  end

  defp change_migration(:edit, path),
    do: File.write!(path, String.replace(@migration, ":integer", ":bigint"))

  defp change_migration(:delete, path), do: File.rm!(path)

  defp change_migration(:rename, path),
    do: File.rename!(path, String.replace(path, "create_widgets", "make_widgets"))

  defp change_migration(:rename_and_edit, path) do
    change_migration(:rename, path)

    File.write!(
      String.replace(path, "create_widgets", "make_widgets"),
      String.replace(@migration, ":integer", ":bigint")
    )
  end

  defp change_migration(:mode, path), do: File.chmod!(path, 0o755)

  defp change_migration(:type, path) do
    File.rm!(path)
    File.ln_s!("20260102000000_elsewhere.exs", path)
  end

  # Runs the install script's download helper on a local file:// archive --
  # no network -- once with its real SHA-256 and once with another, and
  # checks that a refused download leaves no file behind.
  defp run_fetch_verified(helper, outcome) do
    dir = Path.join(System.tmp_dir!(), "fetch-verified-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    source = Path.join(dir, "toolchain.tar.gz")
    dest = Path.join(dir, "downloaded.tar.gz")
    File.write!(source, "synthetic toolchain archive\n")

    sha256 =
      case outcome do
        :match -> :crypto.hash(:sha256, File.read!(source)) |> Base.encode16(case: :lower)
        :mismatch -> String.duplicate("0", 64)
      end

    try do
      result =
        System.cmd(
          "bash",
          ["-c", "set -euo pipefail\n#{helper}\nfetch_verified \"$1\" \"$2\" \"$3\"", "_"] ++
            ["file://#{source}", dest, sha256],
          stderr_to_stdout: true
        )

      assert File.exists?(dest) == (outcome == :match)
      result
    after
      File.rm_rf!(dir)
    end
  end

  defp git!(dir, args) do
    {output, 0} = System.cmd("git", args, cd: dir, env: @git_env, stderr_to_stdout: true)
    output
  end
end
