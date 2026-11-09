defmodule Portfolixir.Status do
  @moduledoc """
  A lifecycle is **named once** (ADR-0059). Every record or process whose
  state the product shows has one status module in its own context that

    * names the closed set of **statuses** the record passes through
      (`c:statuses/0`) and the **actions** — the writes — it may accept
      (`c:actions/0`);
    * **derives** the status from the record's evidence and the clock
      (`c:status/2`), never from a stored column: a stored status can be
      wrong, a derived one reproduces from the ledger (ADR-0004, ADR-0039);
    * says which actions the record **permits** now (`c:permits/2`) and why
      one is refused (`c:refusal/3`), so the write guards, the API payload
      and the screen's buttons consult the same function;
    * states its **basis** in one sentence (`c:basis/0`), carried once per
      payload as `status_basis`, as a metric carries its computation basis
      (ADR-0047).

  The first argument of the three per-record callbacks is the record's
  evidence as the context holds it (a policy rule's versions, a security's
  references), so it is typed per module, not here. The clock is the
  instance's calendar day (`Portfolixir.Clock.today/0`), passed in so a
  test reads another day.

  The registry of status modules, and the coupling of each to its label
  module, its MCP tool text and its API reads, is
  `test/invariants/status_named_once_test.exs`: a lifecycle is added there
  when its module lands, and the build then checks all four surfaces.
  """

  @doc "The closed set of statuses, in the order the product lists them."
  @callback statuses() :: [atom(), ...]

  @doc "Every action a record of this lifecycle may accept, named as the API's verb."
  @callback actions() :: [atom(), ...]

  @doc "One sentence: how the status and the permits derive, and that nothing is stored."
  @callback basis() :: String.t()

  @doc "The status of a record on `date`, derived from its evidence."
  @callback status(evidence :: term(), date :: Date.t()) :: atom()

  @doc "The actions the record accepts on `date`, in the order of `c:actions/0`."
  @callback permits(evidence :: term(), date :: Date.t()) :: [atom()]

  @doc "Why `action` is refused on `date`, or `nil` when it is permitted."
  @callback refusal(evidence :: term(), date :: Date.t(), action :: atom()) :: atom() | nil
end
