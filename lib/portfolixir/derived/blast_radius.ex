defmodule Portfolixir.Derived.BlastRadius do
  @moduledoc """
  Which portfolios' derived-value bases a write can affect (ADR-0032 §3,
  carried forward into ADR-0039's single mechanism).

  The owner chose targeted invalidation over one global counter, so this module
  exists to answer "which portfolios?" — and its whole design is about the
  *direction it fails in*.

  ## Two rules that make the narrow answer safe

  **0. Counter legs stay inside the portfolio.** Composite foreign keys pin a
  transfer's counter account to the transaction's own portfolio, so a transfer
  cannot cross a portfolio boundary and there is no second leg to invalidate.

  **1. Affected is historical, not current.** The series is a daily walk over
  the whole history, so a portfolio that held a security in 2019 and sold out in
  2020 is still affected by a 2019 quote for it. Every lookup here reads *ever
  transacted*, never *holds now*. Getting this wrong is the single most likely
  way to produce a stale series that looks current.

  **2. Anything unproven widens to `:all`.** The clauses below are an
  **allowlist of narrow cases**. Every resource type nobody wired up, and every
  listed type whose record does not carry the fields needed to resolve it,
  returns `:all`. So:

  - forgetting a new write kind costs **a recomputation** — exactly today's
    behaviour;
  - no path exists in which a write silently affects nothing.

  There is deliberately **no catch-all that returns a narrow answer**, and
  `test/invariants/blast_radius_widening_test.exs` asserts that by walking this
  module's AST. A narrowing default is the one mistake that would turn this
  optimisation into a correctness bug.
  """

  import Ecto.Query

  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Repo

  @type radius :: :all | [integer()]

  @doc """
  The portfolios a journaled write can affect, or `:all` when that cannot be
  proven narrower.
  """
  @spec for_write(String.t(), map()) :: radius()
  def for_write(resource_type, record)

  def for_write("transaction", %{__struct__: Transaction} = tx), do: transaction_radius(tx)
  def for_write("cash_account", %{portfolio_id: id}) when is_integer(id), do: [id]
  def for_write("securities_account", %{portfolio_id: id}) when is_integer(id), do: [id]

  def for_write("portfolio", %{__struct__: Portfolio, id: id}) when is_integer(id), do: [id]

  # Everything else — unlisted resource types, and listed ones whose record
  # cannot be resolved (a bulk write journals an aggregate with no id). Widening
  # is the only safe default; see the moduledoc.
  def for_write(_resource_type, _record), do: :all

  @doc """
  The portfolios a quote write for `security_id` can affect: every portfolio
  that has **ever** transacted it.
  """
  @spec for_quote(integer()) :: radius()
  def for_quote(security_id) when is_integer(security_id), do: portfolios_of_security(security_id)

  def for_quote(_security_id), do: :all

  @doc """
  The portfolios an exchange-rate write can affect: those with any
  foreign-currency touch — an account, or a security ever transacted, whose
  currency differs from the portfolio's base currency.

  A single-currency portfolio is never converted, so a rate cannot move it.
  """
  @spec for_exchange_rate() :: radius()
  def for_exchange_rate do
    (foreign_account_portfolios() ++ foreign_security_portfolios())
    |> Enum.uniq()
    |> Enum.sort()
  end

  # -- internals -------------------------------------------------------------

  # A split carries no cash legs and scales every holder of its security; the
  # additive kinds move their own portfolio, plus the counter-leg of a transfer.
  defp transaction_radius(%{type: "split", security_id: security_id})
       when is_integer(security_id) do
    portfolios_of_security(security_id)
  end

  # Both counter legs are pinned to the transaction's own portfolio by composite
  # foreign keys — `transactions_counter_cash_account_portfolio_fkey` and
  # `transactions_counter_securities_account_portfolio_fkey`, each referencing
  # `(id, portfolio_id)`. A transfer therefore cannot cross a portfolio
  # boundary, so there is no second leg to resolve. If that FK is ever relaxed,
  # this clause must gain the counter lookup; until then, resolving it would be
  # dead code pretending to be a safety measure.
  defp transaction_radius(%{portfolio_id: portfolio_id}) when is_integer(portfolio_id) do
    [portfolio_id]
  end

  defp transaction_radius(_tx), do: :all

  # "Ever transacted", not "currently held" — the walk is historical.
  defp portfolios_of_security(security_id) do
    Transaction
    |> where([t], t.security_id == ^security_id)
    |> select([t], t.portfolio_id)
    |> distinct(true)
    |> Repo.all()
    |> Enum.sort()
  end

  defp foreign_account_portfolios do
    CashAccount
    |> join(:inner, [a], p in Portfolio, on: p.id == a.portfolio_id)
    |> where([a, p], a.currency_code != p.base_currency_code)
    |> select([a], a.portfolio_id)
    |> distinct(true)
    |> Repo.all()
  end

  defp foreign_security_portfolios do
    Transaction
    |> join(:inner, [t], p in Portfolio, on: p.id == t.portfolio_id)
    |> join(:inner, [t, _p], s in Portfolixir.Catalog.Security, on: s.id == t.security_id)
    |> where([_t, p, s], s.currency_code != p.base_currency_code)
    |> select([t], t.portfolio_id)
    |> distinct(true)
    |> Repo.all()
  end
end
