defmodule Portfolixir.BuildVersion.Source do
  @moduledoc """
  The two inputs of the version (FR-55, #1429), read where they are:

    * `env/0`, the three build arguments `Dockerfile.release` sets as
      environment variables for its compile step (plan D-7), each read by
      its literal name so B2's environment registry can name it;
    * `git/1`, what `git` says of the source checkout the code is compiled
      in: the calendar tag it is exactly at, its branch, its short commit
      hash and the commit's own date; `nil` where there is no checkout or no
      `git`, as in the release image, whose build context leaves `.git` out.

  **Why a `git` process.** `git` is the one reader that answers what the
  checkout is for every repository format; a reader of our own could answer
  wrong where `git` would not, and a wrong version is what FR-55 forbids.
  B2 (`test/invariants/scope_b2_outbound_chokepoint_test.exs`) registers
  this module, the executable `git` and these four literal argument lists
  and no other subprocess: they read the local checkout and open no
  connection. Each runs in the given directory with the system
  configuration and any terminal prompt switched off. stderr is merged into
  the output so a refusal ("no tag exactly matches") does not print on
  every compile; nothing is read from a call that did not exit 0, and what
  one that did prints is checked for its shape (`Portfolixir.BuildVersion`),
  so a stray warning reads "unknown", never as a version.

  `Portfolixir.BuildVersion` calls both once, when it compiles, and again
  from `__mix_recompile__?/0` to see whether they moved. Nothing here runs
  in a running instance.
  """

  # The project root: this file is lib/portfolixir/build_version/source.ex.
  @root Path.expand("../../..", __DIR__)

  @calendar_tag ~r/\A\d{4}\.(?:[1-9]|1[0-2])\.[1-9]\d*\z/

  @typedoc "What `git` says of a checkout; each part `nil` where it said nothing."
  @type facts :: %{
          tag: String.t() | nil,
          branch: String.t() | nil,
          commit: String.t(),
          committed_on: Date.t() | nil
        }

  @doc "The calendar version's shape, `YYYY.M.N`, as the Release workflow makes it."
  @spec calendar_tag() :: Regex.t()
  def calendar_tag, do: @calendar_tag

  @doc "The build arguments, `nil` where unset."
  @spec env() :: %{String.t() => String.t() | nil}
  def env do
    %{
      "PORTFOLIXIR_VERSION" => System.get_env("PORTFOLIXIR_VERSION"),
      "PORTFOLIXIR_COMMIT" => System.get_env("PORTFOLIXIR_COMMIT"),
      "PORTFOLIXIR_BUILD_DATE" => System.get_env("PORTFOLIXIR_BUILD_DATE")
    }
  end

  @doc """
  What `git` says of the checkout at `root` (the project root by default),
  or `nil` when there is no `git` or no commit to read.
  """
  @spec git(Path.t()) :: facts() | nil
  def git(root \\ @root) do
    opts = [
      cd: root,
      stderr_to_stdout: true,
      env: [{"GIT_TERMINAL_PROMPT", "0"}, {"GIT_CONFIG_NOSYSTEM", "1"}]
    ]

    case output(fn -> System.cmd("git", ["rev-parse", "--short", "HEAD"], opts) end) do
      nil ->
        nil

      commit ->
        %{
          commit: commit,
          tag:
            output(fn ->
              System.cmd(
                "git",
                ["describe", "--tags", "--exact-match", "--match", "[0-9][0-9][0-9][0-9].*"],
                opts
              )
            end),
          branch:
            output(fn -> System.cmd("git", ["rev-parse", "--abbrev-ref", "HEAD"], opts) end),
          committed_on:
            output(fn -> System.cmd("git", ["log", "-1", "--format=%cs"], opts) end) |> date()
        }
    end
  end

  # No `git` on the path raises ErlangError (`:enoent`); a directory that is
  # not there exits non-zero. Either way this source says nothing.
  defp output(command) do
    case command.() do
      {out, 0} -> out |> String.trim() |> nonempty()
      {_out, _status} -> nil
    end
  rescue
    _ in ErlangError -> nil
  end

  defp nonempty(""), do: nil
  defp nonempty(value), do: value

  defp date(nil), do: nil

  defp date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
