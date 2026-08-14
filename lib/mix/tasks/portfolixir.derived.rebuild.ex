defmodule Mix.Tasks.Portfolixir.Derived.Rebuild do
  @shortdoc "Drops and rebuilds every durable derived value, reporting its runtime"

  @moduledoc """
  The single operator command behind ADR-0039 §6:

      mix portfolixir.derived.rebuild

  Drops **every** stored derived value, compacts the version-event log, and
  recomputes the operative scopes through exactly the request path a page
  uses (the performance warm-up set: every portfolio's unscoped walk plus the
  default view's, and the cross-portfolio view walks). Because every derived
  value is a pure function of the ledger, the rebuilt store is provably
  identical to the dropped one for unchanged data — the I6 invariant test
  holds that against historical exchange rates.

  The command reports how many values it dropped and its own runtime, which
  is the ADR's acceptance criterion: an emergency procedure with an unknown
  runtime is not one. The first run's number on the operator's hardware is
  recorded in ADR-0039 as a §6 amendment.

  Safe to run at any time: readers recompute on the next request at worst,
  and no financial data is touched — the ledger is never written by this
  task (I7 keeps the whole derived layer read-only toward it).
  """

  use Mix.Task

  alias Portfolixir.Derived
  alias Portfolixir.Portfolios.Performance.Warmup

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    {:ok, %{dropped: dropped, runtime_ms: runtime_ms}} = Derived.rebuild(&Warmup.warm/0)

    Mix.shell().info(
      "Derived rebuild complete: dropped #{dropped} stored value(s), " <>
        "recomputed the operative scopes in #{runtime_ms} ms."
    )
  end
end
