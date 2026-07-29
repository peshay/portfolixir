defmodule Portfolixir.Portfolios.Performance.Invalidation do
  @moduledoc """
  The seam every write calls to drop the performance memo it invalidates
  (ADR-0032 §3.4).

  It exists as its own module so the write paths depend on **one narrow
  function**, not on the cache internals or on the resolver. `Portfolixir.Journal`
  in particular is a low-level module that has no business knowing how a
  portfolio's series is memoised; it knows only that a committed write must
  announce itself here.

  The call is **synchronous and inside the writing transaction's `Ecto.Multi`**,
  not a broadcast. That is deliberate: an asynchronous notification would open
  a window in which a read immediately after a write is served the pre-write
  series, which is exactly the staleness ADR-0032 §4 rules out. A rolled-back
  transaction may therefore have invalidated a memo that did not need it —
  harmless, and the correct direction to err in.
  """

  alias Portfolixir.Portfolios.Performance.BlastRadius
  alias Portfolixir.Portfolios.Performance.Cache

  @doc """
  Invalidates the memo of every portfolio a journaled write can affect.

  `resource_type` and `record` come straight from `Journal.record/3`, so a new
  journaled resource type needs no change here — it simply resolves to `:all`
  until someone teaches `BlastRadius` a narrower answer.
  """
  @spec after_write(String.t(), map()) :: :ok
  def after_write(resource_type, record) when is_binary(resource_type) do
    Cache.invalidate(BlastRadius.for_write(resource_type, record))
  end

  def after_write(_resource_type, _record), do: Cache.invalidate(:all)

  @doc """
  Invalidates after a quote write. Quotes are allowlisted out of the audit
  journal (market data, ADR-0017), so they cannot ride the journal seam and
  announce themselves here directly.
  """
  @spec after_quote_write(integer()) :: :ok
  def after_quote_write(security_id), do: Cache.invalidate(BlastRadius.for_quote(security_id))

  @doc """
  Invalidates after an exchange-rate write. Allowlisted out of the journal for
  the same reason as quotes.
  """
  @spec after_exchange_rate_write() :: :ok
  def after_exchange_rate_write, do: Cache.invalidate(BlastRadius.for_exchange_rate())
end
