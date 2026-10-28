defmodule Portfolixir.PreCommitHooksTest do
  # The pre-commit hooks and what they run on: .pre-commit-config.yaml, the
  # hashed requirements file and CI's install of it. Reads repository files
  # only.
  use ExUnit.Case, async: true

  # Languages for which pre-commit builds no environment: the hook runs what
  # is already on PATH or in the repository. (pre-commit 4.3 renamed system
  # and script to unsupported and unsupported_script; both spellings count.)
  @installs_nothing ~w(system unsupported script unsupported_script pygrep fail)

  # What a pre-commit-hooks hook runs on: the package itself, and ruamel.yaml
  # (its setup.cfg install_requires `ruamel.yaml>=0.15`; check-yaml parses
  # with it).
  @hook_package_runtime ~w(pre-commit-hooks ruamel.yaml)

  defp config, do: File.read!(".pre-commit-config.yaml")

  defp ci_workflow, do: File.read!(".github/workflows/ci.yml")

  defp repos(config) do
    ~r/^\s*- repo: (\S+)/m |> Regex.scan(config, capture: :all_but_first) |> List.flatten()
  end

  defp requirements do
    ".github/pre-commit/requirements.txt"
    |> File.read!()
    |> String.replace("\\\n", " ")
    |> String.split("\n")
    |> Enum.map(&(&1 |> String.split() |> Enum.join(" ")))
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
  end

  # PEP 503: ruamel.yaml, ruamel_yaml and ruamel-yaml name one distribution.
  defp canonical(name), do: name |> String.downcase() |> String.replace(~r/[-_.]+/, "-")

  defp hash_pinned?(requirements, distribution) do
    Enum.any?(requirements, fn line ->
      case Regex.run(~r/^([A-Za-z0-9._-]+)==\S+(?: --hash=sha256:[0-9a-f]{64})+$/, line) do
        [_, name] -> canonical(name) == canonical(distribution)
        nil -> false
      end
    end)
  end

  describe "the part of F60 this builds on" do
    test "pre-commit and its own dependencies install by version and sha256, wheels only" do
      requirements = requirements()

      for distribution <- ~w(pre-commit virtualenv pyyaml identify cfgv nodeenv) do
        assert hash_pinned?(requirements, distribution), "#{distribution} is not hash-pinned"
      end

      assert ci_workflow() =~
               "python3 -m pip install --require-hashes --only-binary :all: -r .github/pre-commit/requirements.txt"
    end

    test "every remote hook repository is frozen to a commit" do
      config = config()
      remote = config |> repos() |> Enum.reject(&(&1 in ["local", "meta"]))
      revs = Regex.scan(~r/^\s+rev: (.*)$/m, config, capture: :all_but_first)

      assert length(revs) == length(remote)

      for [rev] <- revs do
        assert rev =~ ~r/^[0-9a-f]{40}\s+# frozen: v\d+(\.\d+)*$/
      end
    end

    test "CI restores no pre-commit hook environment from a cache" do
      # The only cache in ci.yml is dialyzer's PLT; pre-commit's own cache
      # (~/.cache/pre-commit, where hook environments live) is not restored,
      # so nothing a cache holds runs as a hook.
      ci = ci_workflow()

      cache_paths =
        ci
        |> String.split(~r/\n\s*- (?=name:|uses:|run:)/)
        |> Enum.filter(&(&1 =~ "uses: actions/cache@"))
        |> Enum.flat_map(&Regex.scan(~r/^\s+path: (\S+)$/m, &1, capture: :all_but_first))
        |> List.flatten()

      assert cache_paths == ["priv/plts"]

      [pre_commit_job] = Regex.run(~r/^  pre-commit:\n(?:(?:    .*| *)\n)*/m, ci)
      refute pre_commit_job =~ "cache"
      refute ci =~ ".cache/pre-commit"
      refute ci =~ "PRE_COMMIT_HOME"
    end
  end

  describe "no package is resolved at hook-install time" do
    # User story (security review 2026-10-12, H65):
    # As the maintainer, and an agent, whose machines and CI run the pre-commit
    # hooks,
    # I want every hook to run code this repository pins by version and sha256,
    # with no hook environment built from the package index,
    # so that a new upload to the index cannot change what a hook runs without
    # a commit here.
    #
    # Acceptance criteria:
    # - Every hook is local, with a language that installs nothing (system,
    #   script, pygrep, fail); no remote hook repository and no
    #   additional_dependencies remain.
    # - The packages the hygiene hooks run on (pre-commit-hooks, ruamel.yaml)
    #   are pinned by version and sha256 in the requirements file CI installs
    #   with --require-hashes.
    test "no hook builds its environment from the package index" do
      config = config()
      remote = config |> repos() |> Enum.reject(&(&1 in ["local", "meta"]))

      assert remote == [],
             "remote hook repositories take their language from their own manifest " <>
               "(pre-commit-hooks: language: python), so pre-commit runs `pip install .` " <>
               "for them in a fresh virtualenv, resolving setuptools and ruamel.yaml from " <>
               "the package index unpinned and unhashed: #{inspect(remote)}"

      languages =
        ~r/^\s+language: (\S+)/m |> Regex.scan(config, capture: :all_but_first) |> List.flatten()

      for language <- languages do
        assert language in @installs_nothing,
               "a local hook with language #{language} builds an environment from a package registry"
      end

      refute config =~ ~r/^\s+additional_dependencies:/m,
             "additional_dependencies are installed from the package index without hashes"
    end

    test "every package a pre-commit-hooks hook runs on is hash-pinned in the file CI installs" do
      config = config()

      uses_hook_package? =
        config =~ "pre-commit/pre-commit-hooks" or
          config =~
            ~r/^\s+entry: .*(pre_commit_hooks|trailing-whitespace-fixer|end-of-file-fixer|check-yaml|mixed-line-ending)/m

      missing =
        if uses_hook_package?,
          do: Enum.reject(@hook_package_runtime, &hash_pinned?(requirements(), &1)),
          else: []

      assert missing == [],
             "hooks from pre-commit-hooks run on packages that .github/pre-commit/requirements.txt " <>
               "does not pin by version and sha256: #{inspect(missing)}"
    end
  end
end
