defmodule Portfolixir.BuildVersion do
  @moduledoc """
  The version the running instance was built from (FR-55, #1429; Sprint 28
  plan D-7), read **once, at compile time**, and never a guess:

    1. **The build arguments**, when any of `PORTFOLIXIR_VERSION`,
       `PORTFOLIXIR_COMMIT` and `PORTFOLIXIR_BUILD_DATE` is set (not empty):
       the way the release image learns it, because its build context leaves
       `.git` out (`.dockerignore`). A calendar tag in `PORTFOLIXIR_VERSION`
       is a **release**; a branch there (or `HEAD`, a detached checkout) with
       a commit hash and a date is a **build**; anything else is
       **unknown**, whatever the checkout says, because the build arguments
       were meant to decide.
    2. **The checkout**, when no build argument is set, as `git` reads it
       (`Portfolixir.BuildVersion.Source`): the calendar tag it is exactly at
       is a release, else its branch (none when detached), short hash and
       commit date are a build. An answer of the wrong shape is unknown.
    3. Otherwise **unknown**: no checkout, no `git`, or neither readable.

  A release links its release notes on GitHub, a build its commit, unknown
  nothing. The link is one the operator follows; nothing here requests it.

  **Recompiling.** The inputs are an environment and a directory, not files
  Mix knows, so `@external_resource` cannot name them: a new tag adds a file
  nobody listed. `__mix_recompile__?/0` reads them again on every
  `mix compile` (one `git` call each, four in all) and answers true when
  they moved, so a source tree that pulls, checks out a tag or changes a
  build argument compiles the version it now is.
  """

  alias Portfolixir.BuildVersion.Source

  @repository "https://github.com/peshay/portfolixir"
  @commit ~r/\A[0-9a-f]{7,40}\z/
  @branch ~r/\A[A-Za-z0-9][A-Za-z0-9._\/-]{0,99}\z/

  @enforce_keys [:kind, :value, :source]
  defstruct [:kind, :value, :source, tag: nil, branch: nil, commit: nil, date: nil, url: nil]

  @type kind :: :release | :build | :unknown
  @type t :: %__MODULE__{
          kind: kind(),
          value: String.t(),
          source: :build_arguments | :git | :none,
          tag: String.t() | nil,
          branch: String.t() | nil,
          commit: String.t() | nil,
          date: Date.t() | nil,
          url: String.t() | nil
        }

  # The one read: the module attribute is evaluated when this module
  # compiles, and the running instance carries its result.
  @inputs {Source.env(), Source.git()}

  @doc "The version this code was compiled as."
  @spec current() :: t()
  def current do
    {env, git} = @inputs
    resolve(env, git)
  end

  @doc false
  # Mix asks before every compile: the inputs read now against those this
  # module was compiled with.
  def __mix_recompile__?, do: {Source.env(), Source.git()} != @inputs

  @doc """
  The version from the build arguments (`env`, unset as `nil` or `""`) and
  the checkout's facts (`git`, `nil` without one).
  """
  @spec resolve(%{optional(String.t()) => String.t() | nil}, Source.facts() | nil) :: t()
  def resolve(env, git) do
    arguments =
      for name <- ~w(PORTFOLIXIR_VERSION PORTFOLIXIR_COMMIT PORTFOLIXIR_BUILD_DATE),
          into: %{} do
        {name, present(Map.get(env, name))}
      end

    if Enum.any?(arguments, fn {_name, value} -> value != nil end) do
      from_arguments(arguments)
    else
      from_git(git)
    end
  end

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_value), do: nil

  defp from_arguments(%{"PORTFOLIXIR_VERSION" => version} = arguments) do
    commit = arguments["PORTFOLIXIR_COMMIT"]
    date = arguments["PORTFOLIXIR_BUILD_DATE"]

    cond do
      calendar?(version) ->
        release(version, if(commit?(commit), do: commit), :build_arguments)

      (version == nil or branch?(version)) and commit?(commit) and match?({:ok, _}, iso(date)) ->
        {:ok, day} = iso(date)
        build(if(version != "HEAD", do: version), commit, day, :build_arguments)

      true ->
        unknown(:build_arguments)
    end
  end

  defp from_git(%{commit: commit, branch: branch, tag: tag, committed_on: day}) do
    branch = if branch == "HEAD", do: nil, else: branch

    cond do
      not commit?(commit) or not (branch == nil or branch?(branch)) ->
        unknown(:git)

      calendar?(tag) ->
        %{release(tag, commit, :git) | branch: branch, date: day}

      is_struct(day, Date) ->
        build(branch, commit, day, :git)

      true ->
        unknown(:git)
    end
  end

  defp from_git(_none), do: unknown(:none)

  defp release(tag, commit, source) do
    %__MODULE__{
      kind: :release,
      value: tag,
      tag: tag,
      commit: commit,
      source: source,
      url: "#{@repository}/releases/tag/#{tag}"
    }
  end

  defp build(branch, commit, day, source) do
    %__MODULE__{
      kind: :build,
      value:
        Enum.join(Enum.reject([branch, short(commit), Date.to_iso8601(day)], &is_nil/1), " · "),
      branch: branch,
      commit: commit,
      date: day,
      source: source,
      url: "#{@repository}/commit/#{commit}"
    }
  end

  defp unknown(source), do: %__MODULE__{kind: :unknown, value: "unknown", source: source}

  @doc "The commit's short form, as the screen shows it."
  @spec short(String.t()) :: String.t()
  def short(commit), do: String.slice(commit, 0, 7)

  defp calendar?(value), do: is_binary(value) and Regex.match?(Source.calendar_tag(), value)

  defp commit?(value), do: is_binary(value) and Regex.match?(@commit, value)

  # A branch name `git` would accept and a URL would carry as it is: no
  # space, no `..`, no leading dot or dash.
  defp branch?(value),
    do: Regex.match?(@branch, value) and not String.contains?(value, "..")

  defp iso(value) when is_binary(value) do
    if Regex.match?(~r/\A\d{4}-\d{2}-\d{2}\z/, value), do: Date.from_iso8601(value), else: :error
  end

  defp iso(_value), do: :error

  @doc """
  The API's and the companion's form of a version (`GET /api/v1/version`,
  `portfolixir.version`): the kind, the value, the link and the parts it is
  made of, with a note saying how it was read.
  """
  @spec json(t()) :: map()
  def json(%__MODULE__{} = version) do
    %{
      kind: Atom.to_string(version.kind),
      value: version.value,
      url: version.url,
      tag: version.tag,
      branch: version.branch,
      commit: version.commit,
      date: version.date && Date.to_iso8601(version.date),
      source: Atom.to_string(version.source),
      version_note:
        "Read once when this instance's code was compiled: the build arguments " <>
          "PORTFOLIXIR_VERSION, PORTFOLIXIR_COMMIT and PORTFOLIXIR_BUILD_DATE when set, else " <>
          "the source checkout. release: the calendar tag the build is exactly at, url its " <>
          "release notes; build: branch, short commit hash and commit date, url the commit; " <>
          "unknown: neither could be read, never a guess. The url is for the operator to " <>
          "follow; the app requests nothing."
    }
  end
end
