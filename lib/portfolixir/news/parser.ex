defmodule Portfolixir.News.Parser do
  @moduledoc """
  The news feed parser (ADR-0056 A1). Not implemented yet: its attack cases
  come first (Sprint 26 carry-forward 6).
  """

  @max_bytes 8 * 1024 * 1024
  @max_depth 64
  @max_items 5_000

  @refusal_reasons [
    :too_large,
    :dtd,
    :too_deep,
    :too_many_items,
    :malformed,
    :unsupported_encoding,
    :not_a_feed,
    :timeout,
    :failed
  ]

  @doc "The byte cap of a feed's body."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @doc "The deepest nesting a feed may have."
  @spec max_depth() :: pos_integer()
  def max_depth, do: @max_depth

  @doc "The most items one feed answer may carry."
  @spec max_items() :: pos_integer()
  def max_items, do: @max_items

  @doc "Every reason a refusal can carry."
  @spec refusal_reasons() :: [atom()]
  def refusal_reasons, do: @refusal_reasons

  @doc false
  def parse(_body, _opts \\ []), do: {:error, :not_implemented}

  @doc false
  def scan(_body), do: {:error, :not_implemented}
end
