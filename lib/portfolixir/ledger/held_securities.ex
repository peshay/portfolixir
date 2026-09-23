defmodule Portfolixir.Ledger.HeldSecurities do
  @moduledoc """
  The one answer to "is this security held?" (#839).

  A security is held when its quantity summed across every depot of every
  portfolio is non-zero. That sum moves with exactly the kinds
  `Portfolixir.Ledger.Projection.security_quantity_sign/1` reads off the
  canonical projection — `buy` and `inbound_delivery` add, `sell` and
  `outbound_delivery` subtract — so a depot transferred in (the normal shape of
  a Portfolio Performance import) is held the moment it arrives. A
  `security_transfer` between own depots nets to zero at this level and a
  `split` only scales, so neither enters the sum.

  Three surfaces used to carry their own copy of this predicate — the
  catalog's `holding_status` filter, the research log's unreviewed-positions
  read and the events' `held_only` — and two of them counted only buys and
  sells, reporting a delivered-in position as not held. They now all read
  this module, so the predicate cannot drift between them again.

  It is a query rather than a fold over `Portfolixir.Ledger.Positions` so a
  catalog-sized filter stays one SQL statement; the kind sets it filters by
  come from the projection, which is what keeps the two in agreement.
  """

  import Ecto.Query

  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  @doc """
  `%{security_id, quantity}` per security with any quantity-moving booking:
  the net quantity across all depots.
  """
  @spec totals_query() :: Ecto.Query.t()
  def totals_query do
    %{increases: increases, decreases: decreases} = quantity_kinds()

    from(t in Transaction,
      where: t.type in ^(increases ++ decreases) and not is_nil(t.security_id),
      group_by: t.security_id,
      select: %{
        security_id: t.security_id,
        quantity:
          fragment(
            "sum(CASE WHEN ? = ANY(?) THEN ? ELSE -? END)",
            t.type,
            ^increases,
            t.quantity,
            t.quantity
          )
      }
    )
  end

  @doc "The ids of the held securities, as a query to compose into another."
  @spec held_ids_query() :: Ecto.Query.t()
  def held_ids_query do
    from(h in subquery(totals_query()),
      where: fragment("? <> 0", h.quantity),
      select: h.security_id
    )
  end

  @doc "The ids of the held securities."
  @spec held_ids() :: [integer()]
  def held_ids, do: Repo.all(held_ids_query())

  @doc """
  The booking kinds that move a security's total quantity, split by
  direction, as `Projection.security_quantity_sign/1` reads them.
  """
  @spec quantity_kinds() :: %{increases: [String.t()], decreases: [String.t()]}
  def quantity_kinds do
    signs = Map.new(Transaction.kinds(), &{&1, Projection.security_quantity_sign(&1)})

    %{
      increases: for({kind, 1} <- signs, do: kind) |> Enum.sort(),
      decreases: for({kind, -1} <- signs, do: kind) |> Enum.sort()
    }
  end
end
