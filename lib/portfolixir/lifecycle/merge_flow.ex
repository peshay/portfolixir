defmodule Portfolixir.Lifecycle.MergeFlow do
  @moduledoc """
  The parts of a lifecycle merge every merge kind shares (ADR-0050 §8, §10,
  §12): reading the operator's consent, answering a retry of a completed
  merge, the guard results a preview and a refusal carry, and the JSON form
  of the record a merge writes.

  Shared by the cash-account merge (`Portfolixir.Lifecycle.CashMerge`), the
  depot merge (`Portfolixir.Lifecycle.DepotMerge`) and the security merge
  (`Portfolixir.Lifecycle.SecurityMerge`), so the consent rules cannot drift
  apart between them:

    * `plan_digest` is required — the digest of the preview the operator
      approved (§10);
    * `collapse_key_equal` is a boolean or absent, and **required** once the
      recomputed plan lists key-equal pairs (§8) — never assumed;
    * a completed merge of the same pair answers its record; a source merged
      into another target answers `already_merged` (§10).
  """

  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.MergeRecord
  alias Portfolixir.Repo

  @typedoc "One guard's result: its refusal code, what it checks, and the outcome in words."
  @type guard :: %{code: atom(), check: String.t(), passed: boolean(), detail: String.t()}

  @doc """
  The operator's consent from the apply's `params`: `{:ok, plan_digest,
  collapse_key_equal}` (the choice `nil` when absent), or `{:error,
  {:invalid, field, message}}` for a missing digest or a choice that is not a
  boolean.
  """
  @spec consent(map()) ::
          {:ok, String.t(), boolean() | nil}
          | {:error, {:invalid, :plan_digest | :collapse_key_equal, String.t()}}
  def consent(params) when is_map(params) do
    with {:ok, digest} <- digest_param(params),
         {:ok, collapse} <- collapse_param(params),
         do: {:ok, digest, collapse}
  end

  defp digest_param(params) do
    case Map.get(params, :plan_digest) do
      digest when is_binary(digest) and digest != "" -> {:ok, digest}
      _missing -> {:error, {:invalid, :plan_digest, "can't be blank"}}
    end
  end

  defp collapse_param(params) do
    case Map.get(params, :collapse_key_equal) do
      value when is_boolean(value) or is_nil(value) -> {:ok, value}
      _other -> {:error, {:invalid, :collapse_key_equal, "must be true or false"}}
    end
  end

  @doc """
  The merge that already took `source_id` away under `kind`: `:none`,
  `{:ok, record}` when it went into `target_id` (a retry of a completed
  merge), or `{:error, {:already_merged, record}}` when it went elsewhere.
  """
  @spec prior_merge(atom(), integer(), integer()) ::
          :none | {:ok, MergeRecord.t()} | {:error, {:already_merged, MergeRecord.t()}}
  def prior_merge(kind, source_id, target_id) do
    case Lifecycle.merge_of(kind, source_id) do
      nil -> :none
      %MergeRecord{target_id: ^target_id} = record -> {:ok, record}
      %MergeRecord{} = record -> {:error, {:already_merged, record}}
    end
  end

  @doc """
  §8: with key-equal pairs in the recomputed plan, the operator's choice is
  required; without, an absent choice means nothing to collapse.
  """
  @spec choose([term()], boolean() | nil) ::
          {:ok, boolean()} | {:error, {:choice_required, :collapse_key_equal, pos_integer()}}
  def choose([_ | _] = pairs, nil),
    do: {:error, {:choice_required, :collapse_key_equal, length(pairs)}}

  def choose(_pairs, collapse), do: {:ok, collapse == true}

  @doc "A guard's result."
  @spec guard(atom(), String.t(), boolean(), String.t()) :: guard()
  def guard(code, check, passed?, detail),
    do: %{code: code, check: check, passed: passed?, detail: detail}

  @doc "A guard's result, with the detail for either outcome."
  @spec guard(atom(), String.t(), boolean(), String.t(), String.t()) :: guard()
  def guard(code, check, true, passed, _refused), do: guard(code, check, true, passed)
  def guard(code, check, false, _passed, refused), do: guard(code, check, false, refused)

  @doc "Whether every guard passed."
  @spec passed?([guard()]) :: boolean()
  def passed?(guards), do: Enum.all?(guards, & &1.passed)

  @doc """
  `Repo.transaction/1` for a merge (§10: every race ends in a clean 409,
  never a 500). A merge takes its locks in a fixed order that every
  concurrent writer shares, but a writer outside that order (a quote sync, a
  hardened delete) can still close a lock cycle, which PostgreSQL breaks by
  aborting one side with `deadlock_detected` — or a lock wait can hit the
  session's `lock_timeout`. The merge side answers `{:error, :raced}`, which
  each merge turns into `plan_changed` with a fresh preview; nothing was
  written. Any other database error is re-raised.
  """
  @spec transaction((-> term())) :: {:ok, term()} | {:error, term()}
  def transaction(fun) when is_function(fun, 0) do
    Repo.transaction(fun)
  rescue
    error in Postgrex.Error ->
      if raced?(error), do: {:error, :raced}, else: reraise(error, __STACKTRACE__)
  end

  defp raced?(%Postgrex.Error{postgres: %{code: code}})
       when code in [:deadlock_detected, :lock_not_available],
       do: true

  defp raced?(_error), do: false

  @doc """
  Runs `fun` over `items` in order until one answers an error, which is
  returned; `:ok` when every one answered `:ok`.
  """
  @spec each(Enumerable.t(), (term() -> :ok | {:error, term()})) :: :ok | {:error, term()}
  def each(items, fun) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case fun.(item) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @doc """
  `term` as the plain JSON a merge record stores (§12): string keys, a
  `Decimal` as its normalized string, a date or timestamp as ISO 8601, an
  atom as its name.
  """
  @spec jsonable(term()) :: term()
  def jsonable(%Decimal{} = value), do: Decimal.to_string(Decimal.normalize(value), :normal)
  def jsonable(%Date{} = value), do: Date.to_iso8601(value)
  def jsonable(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  def jsonable(%DateTime{} = value), do: DateTime.to_iso8601(value)

  def jsonable(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), jsonable(value)} end)

  def jsonable(list) when is_list(list), do: Enum.map(list, &jsonable/1)
  def jsonable(value) when is_boolean(value) or is_nil(value), do: value
  def jsonable(value) when is_atom(value), do: Atom.to_string(value)
  def jsonable(value), do: value
end
