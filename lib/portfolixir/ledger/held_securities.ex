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

  alias Portfolixir.Buckets
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Positions
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios
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
  The ids of the securities the view `view_id` holds today, ascending: a
  position of any portfolio in a depot the view covers
  (`Portfolixir.Buckets.load_global_scope/1`, its overrides included) whose
  quantity summed over those positions is not zero. The one rule for "what a
  view holds": the news digest's securities (`Portfolixir.News.Reads`) and a
  crash window's `view:<id>` universe (`Portfolixir.Crashes.Rankings`) both
  read it. `{:error, :view_not_found}` for a view that does not exist.
  """
  @spec in_view(pos_integer()) :: {:ok, [pos_integer()]} | {:error, :view_not_found}
  def in_view(view_id) when is_integer(view_id) do
    case Buckets.load_global_scope(view_id) do
      {:error, :view_not_found} -> {:error, :view_not_found}
      scope -> {:ok, held_in_scope(scope)}
    end
  end

  defp held_in_scope(scope) do
    Portfolios.list_portfolios()
    |> Enum.flat_map(fn portfolio ->
      portfolio.id
      |> Ledger.positions_for_portfolio()
      |> Enum.filter(fn {{account_id, security_id}, _quantity} ->
        Buckets.position_in_scope?(scope, account_id, security_id)
      end)
    end)
    |> Enum.reduce(%{}, fn {{_account_id, security_id}, quantity}, acc ->
      Map.update(acc, security_id, quantity, &Decimal.add(&1, quantity))
    end)
    |> Enum.reject(fn {_security_id, quantity} -> Decimal.eq?(quantity, 0) end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

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
