defmodule Portfolixir.BuildVersionTest do
  # FR-55 (#1429), Sprint 28 V1 (plan D-7, D-1 criterion 9): the version the
  # running instance was built from, read once at compile time. Each kind is
  # pinned here with its source faked: the build arguments as a map, the
  # checkout as the facts `Source.git/1` answers. One test runs the real
  # `git` on a repository it makes, to show the reader reads what git says.
  use ExUnit.Case, async: true

  alias Portfolixir.BuildVersion

  @commit "3cba116e0f4a5b6c7d8e9f00112233445566778a"
  @short "3cba116"
  @repository "https://github.com/peshay/portfolixir"

  defp env(version, commit \\ nil, date \\ nil) do
    %{
      "PORTFOLIXIR_VERSION" => version,
      "PORTFOLIXIR_COMMIT" => commit,
      "PORTFOLIXIR_BUILD_DATE" => date
    }
  end

  defp git(fields) do
    Map.merge(%{commit: @short, branch: "main", tag: nil, committed_on: ~D[2026-11-08]}, fields)
  end

  @no_env %{}

  # User story:
  # As the operator, and the agent I run,
  # I want the instance to state the version it was built from — the
  # calendar release tag when the build is exactly at one, else the branch,
  # short hash and commit date, else "unknown" —
  # so that I know which release is installed, and the instance never
  # guesses one.
  #
  # Acceptance criteria:
  # - Build arguments (PORTFOLIXIR_VERSION, PORTFOLIXIR_COMMIT,
  #   PORTFOLIXIR_BUILD_DATE) decide when any is set: a calendar tag reads
  #   release, linked to its release notes; a branch with a commit and a
  #   date reads build, linked to the commit.
  # - Without them, the checkout decides: a calendar tag at its commit reads
  #   release, else its branch, short hash and commit date read build.
  # - Anything else reads unknown, with no link: no source, an empty or
  #   partial set of build arguments, a value of the wrong shape.
  describe "resolve/2, a release" do
    test "from a build argument naming a calendar tag" do
      version = BuildVersion.resolve(env("2026.11.12", @commit, "2026-11-08"), git(%{}))

      assert version.kind == :release
      assert version.value == "2026.11.12"
      assert version.tag == "2026.11.12"
      assert version.commit == @commit
      assert version.source == :build_arguments
      assert version.url == "#{@repository}/releases/tag/2026.11.12"
    end

    test "from a build argument alone, without the commit" do
      version = BuildVersion.resolve(env("2026.1.3"), nil)

      assert {version.kind, version.value, version.commit} == {:release, "2026.1.3", nil}
      assert version.url == "#{@repository}/releases/tag/2026.1.3"
    end

    test "from a checkout exactly at a calendar tag" do
      version = BuildVersion.resolve(@no_env, git(%{tag: "2026.11.12"}))

      assert version.kind == :release
      assert version.value == "2026.11.12"
      assert version.branch == "main"
      assert version.source == :git
      assert version.url == "#{@repository}/releases/tag/2026.11.12"
    end
  end

  describe "resolve/2, a build" do
    test "from build arguments naming a branch, a commit and a date" do
      version = BuildVersion.resolve(env("main", @commit, "2026-11-08"), nil)

      assert version.kind == :build
      assert version.value == "main · 3cba116 · 2026-11-08"
      assert version.branch == "main"
      assert version.commit == @commit
      assert version.date == ~D[2026-11-08]
      assert version.source == :build_arguments
      assert version.url == "#{@repository}/commit/#{@commit}"
    end

    test "from build arguments of a detached checkout (HEAD), no branch" do
      version = BuildVersion.resolve(env("HEAD", @commit, "2026-11-08"), nil)

      assert {version.kind, version.branch} == {:build, nil}
      assert version.value == "3cba116 · 2026-11-08"
    end

    test "from a checkout not at a calendar tag" do
      version = BuildVersion.resolve(@no_env, git(%{}))

      assert version.kind == :build
      assert version.value == "main · 3cba116 · 2026-11-08"
      assert version.source == :git
      assert version.url == "#{@repository}/commit/#{@short}"
    end

    test "from a detached checkout, which git names HEAD" do
      version = BuildVersion.resolve(@no_env, git(%{branch: "HEAD"}))

      assert {version.kind, version.branch, version.value} ==
               {:build, nil, "3cba116 · 2026-11-08"}
    end

    test "a tag of another shape at the checkout is no release" do
      version = BuildVersion.resolve(@no_env, git(%{tag: "2026.13.1"}))

      assert {version.kind, version.tag} == {:build, nil}
    end
  end

  describe "resolve/2, unknown, never a guess" do
    test "no source at all" do
      version = BuildVersion.resolve(@no_env, nil)

      assert version.kind == :unknown
      assert version.value == "unknown"
      assert version.url == nil
      assert version.source == :none
      assert {version.tag, version.branch, version.commit, version.date} == {nil, nil, nil, nil}
    end

    test "build arguments passed empty, as Compose passes an unset one, read as unset" do
      assert BuildVersion.resolve(env("", "", ""), nil).kind == :unknown
      assert BuildVersion.resolve(env("", "", ""), git(%{})).kind == :build
    end

    test "build arguments that do not make a version, whatever the checkout says" do
      for arguments <- [
            env("main"),
            env("main", @commit),
            env("main", nil, "2026-11-08"),
            env("main", "not-a-hash", "2026-11-08"),
            env("main", "3cba11", "2026-11-08"),
            env("main", @commit, "08.11.2026"),
            env("main", @commit, "2026-02-30"),
            env("a branch with spaces", @commit, "2026-11-08"),
            env("../../etc", @commit, "2026-11-08"),
            env("2026.13.1"),
            env("v2026.11.12"),
            env(String.duplicate("b", 101), @commit, "2026-11-08")
          ] do
        version = BuildVersion.resolve(arguments, git(%{tag: "2026.11.12"}))
        assert version.kind == :unknown, inspect(arguments)
        assert version.url == nil
        assert version.source == :build_arguments
      end
    end

    test "a checkout whose commit date could not be read" do
      assert BuildVersion.resolve(@no_env, git(%{committed_on: nil})).kind == :unknown
    end

    test "an answer of git's of the wrong shape, a warning say" do
      for fields <- [
            %{commit: "warning: unable to access"},
            %{branch: "warning: refname is ambiguous"},
            %{commit: "zzzzzzz"}
          ] do
        version = BuildVersion.resolve(@no_env, git(Map.put(fields, :tag, "2026.11.12")))
        assert {version.kind, version.source} == {:unknown, :git}, inspect(fields)
      end
    end
  end

  # User story:
  # As the agent reading GET /api/v1/version,
  # I want the version as JSON with its kind, value and link,
  # so that I can tell which release I am talking to.
  #
  # Acceptance criteria:
  # - The payload names kind, value, url, tag, branch, commit, date (ISO) and
  #   source, and a note saying how it was read and that the app requests
  #   nothing.
  describe "json/1" do
    test "each kind" do
      release = BuildVersion.json(BuildVersion.resolve(env("2026.11.12"), nil))
      assert release.kind == "release"
      assert release.value == "2026.11.12"
      assert release.url == "#{@repository}/releases/tag/2026.11.12"
      assert release.source == "build_arguments"

      build = BuildVersion.json(BuildVersion.resolve(@no_env, git(%{})))
      assert build.kind == "build"
      assert build.date == "2026-11-08"
      assert build.commit == @short
      assert build.url == "#{@repository}/commit/#{@short}"

      unknown = BuildVersion.json(BuildVersion.resolve(@no_env, nil))

      assert Map.take(unknown, [:kind, :value, :url, :tag, :branch, :commit, :date, :source]) ==
               %{
                 kind: "unknown",
                 value: "unknown",
                 url: nil,
                 tag: nil,
                 branch: nil,
                 commit: nil,
                 date: nil,
                 source: "none"
               }

      assert unknown.version_note =~ "never a guess"
      assert unknown.version_note =~ "requests nothing"
    end
  end

  # User story:
  # As the operator,
  # I want the running instance to carry the version it was compiled with,
  # and a change of the build arguments or of the checkout to recompile it,
  # so that the version on the screen is never older than the code.
  #
  # Acceptance criteria:
  # - current/0 is resolve/2 over the inputs read when the module compiled.
  # - __mix_recompile__?/0 is false while the inputs read now are those.
  test "current/0 is the compiled read, and recompiles only when the inputs change" do
    assert %BuildVersion{} = BuildVersion.current()

    assert BuildVersion.current() ==
             BuildVersion.resolve(BuildVersion.Source.env(), BuildVersion.Source.git())

    refute BuildVersion.__mix_recompile__?()
  end

  # User story (FR-55; the orchestrator's review of V1: git, not a reader of
  # our own, answers what the checkout is):
  # As the operator running from a source checkout,
  # I want the version read by `git` itself,
  # so that a checkout at a calendar tag reads that release, and one past it
  # its branch, short hash and commit date.
  #
  # Acceptance criteria:
  # - In a repository this test makes, at an annotated calendar tag,
  #   Source.git/1 answers the tag, the branch, the short hash and the
  #   commit's date, and resolve/2 reads release.
  # - One commit later, with a lightweight tag of another shape on it, it
  #   reads build.
  # - A directory with no repository answers nil, and resolve/2 unknown.
  # No skip: git is on every machine the suite runs on, CI included.
  test "the real git reader, in a repository made here" do
    dir = Path.join(System.tmp_dir!(), "build-version-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    git!(dir, ["init", "--quiet", "--initial-branch=main"])

    git!(
      dir,
      ["commit", "--quiet", "--allow-empty", "--message=first"],
      "2026-11-08T10:00:00+01:00"
    )

    git!(dir, ["tag", "--annotate", "2026.11.12", "--message=Portfolixir 2026.11.12"])

    {short, 0} = System.cmd("git", ["rev-parse", "--short", "HEAD"], cd: dir)

    facts = BuildVersion.Source.git(dir)

    assert facts == %{
             tag: "2026.11.12",
             branch: "main",
             commit: String.trim(short),
             committed_on: ~D[2026-11-08]
           }

    assert %{kind: :release, value: "2026.11.12", source: :git} =
             BuildVersion.resolve(%{}, facts)

    git!(
      dir,
      ["commit", "--quiet", "--allow-empty", "--message=second"],
      "2026-11-09T23:30:00-02:00"
    )

    git!(dir, ["tag", "0.14.0"])

    assert %{kind: :build, branch: "main", date: ~D[2026-11-09], tag: nil} =
             BuildVersion.resolve(%{}, BuildVersion.Source.git(dir))

    empty = Path.join(dir, "not-a-repository")
    File.mkdir_p!(empty)
    File.write!(Path.join(empty, ".git"), "gitdir: nowhere\n")
    assert BuildVersion.Source.git(empty) == nil
    assert BuildVersion.resolve(%{}, nil).kind == :unknown
  end

  defp git!(dir, args, date \\ "2026-11-08T10:00:00+01:00") do
    env = [
      {"GIT_AUTHOR_DATE", date},
      {"GIT_COMMITTER_DATE", date},
      {"GIT_CONFIG_NOSYSTEM", "1"},
      {"GIT_CONFIG_GLOBAL", "/dev/null"}
    ]

    identity = ["-c", "user.name=Synthetic", "-c", "user.email=synthetic@example.com"]
    signing = ["-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false"]

    {output, status} =
      System.cmd("git", identity ++ signing ++ args, cd: dir, env: env, stderr_to_stdout: true)

    assert status == 0, output
  end
end
