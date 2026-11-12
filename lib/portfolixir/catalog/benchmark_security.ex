defmodule Portfolixir.Catalog.BenchmarkSecurity do
  @moduledoc """
  The one rule for which security may be a benchmark (ADR-0046's amendment
  of 2026-11-07, #1416): **any security with at least one stored quote,
  flagged `is_benchmark` or not.** Every read that takes
  `benchmark=security:<id>` applies it — the portfolio and view comparisons,
  sale hindsight, the predictions' write — and so does the crash benchmark of
  ADR-0058 §1.

  `is_benchmark` keeps its meaning (the amendment's point 2): it marks a
  reference-only instrument, kept out of the booking forms and the
  data-quality sets. It no longer gates the benchmark parameter, so a fund
  the operator holds can be the reference and stay bookable and checked.

  `standing/1` names which kind a benchmark is, for the computation basis
  (point 4): `:flagged`, or a `:held` or `:unheld` catalog security, held
  read by the one held predicate (`Portfolixir.Ledger.HeldSecurities`, #839)
  across every depot today. A flagged security that is also held is
  `:flagged`: the flag is the operator's own statement that it is a
  reference.
  """

  import Ecto.Query

  alias Portfolixir.Catalog.Quote
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Ledger.HeldSecurities
  alias Portfolixir.Lifecycle
  alias Portfolixir.Repo

  @typedoc """
  Why an id is no benchmark: `:no_quote`, the security exists with no
  stored quote; `{:merged_into, id}`, a merge took it away and the live end
  of its chain is a security this rule accepts (#959); `:not_found`, no row
  under the id, or a merged-away one whose survivor this rule refuses or
  that was deleted since.
  """
  @type refusal :: :no_quote | :not_found | {:merged_into, pos_integer()}

  @type standing :: :flagged | :held | :unheld

  @doc """
  The security under `id` when it may be a benchmark, else the refusal.
  """
  @spec resolve(integer()) :: {:ok, Security.t()} | {:error, refusal()}
  def resolve(id) when is_integer(id) do
    case Repo.get(Security, id) do
      %Security{} = security -> quoted(security)
      nil -> merged_away(id)
    end
  end

  @doc """
  Which kind of security a benchmark is: `:flagged`, `:held` (held today in
  any depot) or `:unheld`.
  """
  @spec standing(Security.t()) :: standing()
  def standing(%Security{is_benchmark: true}), do: :flagged

  def standing(%Security{id: id}) do
    held? =
      Repo.exists?(
        from(s in Security,
          where: s.id == ^id and s.id in subquery(HeldSecurities.held_ids_query())
        )
      )

    if held?, do: :held, else: :unheld
  end

  defp quoted(%Security{id: id} = security) do
    if Repo.exists?(from(q in Quote, where: q.security_id == ^id)),
      do: {:ok, security},
      else: {:error, :no_quote}
  end

  # #959: the refusal names the survivor only when a retry with it would
  # compare; a survivor this rule refuses is named nowhere.
  defp merged_away(id) do
    with survivor when is_integer(survivor) <- Lifecycle.merged_into(:security, id),
         %Security{} = security <- Repo.get(Security, survivor),
         {:ok, _security} <- quoted(security) do
      {:error, {:merged_into, survivor}}
    else
      _no_benchmark_survivor -> {:error, :not_found}
    end
  end
end
