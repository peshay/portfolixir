defmodule Portfolixir.Ledger.HeldSecurities do
  @moduledoc """
  The one answer to "is this security held?" (#839).

  A security is held when its quantity summed across every depot of every
  portfolio is non-zero. That sum moves with exactly the kinds
  `Portfolixir.Ledger.Projection.security_quantity_sign/1` reads off the
  canonical projection — `buy` and `inbound_delivery` add, `sell` and
  `outbound_delivery` subtract — so a depot transferred in (the normal shape of
  a Portfolio Performance import) is held the moment it arrives. A
  `security_transfer` between own depots nets to zero at this level.

  **A split is the one kind a sum cannot answer.** It scales the quantity
  held before it, and every booking after it is in post-split units
  (ADR-0028 §3): bought 10, split 2:1, sold 20 is a raw sum of -10 and a
  position of 0. So a security that has ever split is answered by the
  canonical fold itself — `Portfolixir.Ledger.Positions` over that
  security's bookings — and only the securities that never split take the
  one-statement sum, where it is exact (closing-act finding, Sprint 14).

  Three surfaces used to carry their own copy of this predicate — the
  catalog's `holding_status` filter, the research log's unreviewed-positions
  read and the events' `held_only` — and two of them counted only buys and
  sells, reporting a delivered-in position as not held. They now all read
  this module, so the predicate cannot drift between them again.

  It stays a query for the never-split majority so a catalog-sized filter is
  one SQL statement; the kind sets it filters by come from the projection,
  which is what keeps the two in agreement. `held_ids_query/0` therefore reads
  the split securities' bookings when it is BUILT, and composes their answer
  in as a parameter.
  """

  import Ecto.Query

  alias Portfolixir.Ledger.Positions
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

  @doc """
  The ids of the held securities, as a query to compose into another.

  A security that never split is held when its raw sum is non-zero; one that
  has split is held when the canonical fold leaves it a non-zero total. Every
  held security has a quantity-moving booking, so every one of them has a row
  in `totals_query/0` to be selected from.
  """
  @spec held_ids_query() :: Ecto.Query.t()
  def held_ids_query do
    split_ids = split_security_ids()
    split_held = held_by_fold(split_ids)

    from(h in subquery(totals_query()),
      where:
        (fragment("? <> 0", h.quantity) and h.security_id not in ^split_ids) or
          h.security_id in ^split_held,
      select: h.security_id
    )
  end

  defp split_security_ids do
    Repo.all(
      from(t in Transaction,
        where: t.type == "split" and not is_nil(t.security_id),
        distinct: true,
        select: t.security_id
      )
    )
  end

  # The canonical fold over every booking of the securities that split, in
  # replay order; the split's scale leg reaches only its own portfolio's
  # positions, which is what the fold's account-to-portfolio map is for.
  defp held_by_fold([]), do: []

  defp held_by_fold(security_ids) do
    from(t in Transaction, where: t.security_id in ^security_ids)
    |> Repo.all()
    |> Positions.calculate()
    |> Enum.reduce(%{}, fn {{_account, security_id}, quantity}, acc ->
      Map.update(acc, security_id, quantity, &Decimal.add(&1, quantity))
    end)
    |> Enum.reject(fn {_security_id, total} -> Decimal.equal?(total, 0) end)
    |> Enum.map(&elem(&1, 0))
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
