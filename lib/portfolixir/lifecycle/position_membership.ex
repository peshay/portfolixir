defmodule Portfolixir.Lifecycle.PositionMembership do
  @moduledoc """
  The membership rule of a merge that moves a position's bookings onto
  another position (ADR-0050 §7's depot guards; §9 applies it per depot to a
  security merge). View membership is retroactive (ADR-0024 point 4), so every
  position keeps its **effective** bucket set.

  A *source position* is where the bookings come from and a *target
  position* where they land: in a depot merge `(source depot, security)` and
  `(target depot, security)`; in a security merge `(depot, source security)`
  and `(depot, target security)`. For each source position that holds
  bookings or carries an override, `action/2` answers the write that keeps
  its effective set:

    * the source holds no rows: its override has no history to keep —
      `:drop_unheld` (or `:none` when it inherits);
    * both hold rows: the effective sets must already agree — the source's
      override, then redundant, is dropped (`:drop_redundant`); any
      difference is `:refuse`, because moving an override onto a position the
      target holds would re-view the target's own history;
    * only the source holds rows: its effective set is carried onto the
      target position — its override moves (`:carry`), or, where the source
      inherits, a dead override of the target is cleared (`:clear_target`).

  An override to carry that holds more than one scope-dimension bucket
  (stored before ADR-0024's one-scope rule held for overrides) is
  `:refuse_carry`: the target position cannot take it.

  `write/4` performs an action through the journaled `Portfolixir.Buckets`
  writers — one aggregate entry per position.
  """

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.Bucket
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Engines.BucketResolution
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Repo

  @type override :: :inherit | :explicit_empty | {:explicit, [integer()]}

  @type action ::
          :none
          | :drop_unheld
          | :drop_redundant
          | :clear_target
          | :carry
          | :refuse
          | :refuse_carry

  @typedoc "One side of a position pair: whether it holds rows, its override, its effective set."
  @type side :: %{holds: boolean(), override: override(), effective: [integer()]}

  @typedoc "A position: its depot and its security."
  @type position :: {%SecuritiesAccount{}, %Security{}}

  @doc "The effective bucket set of a position with `override` in a depot defaulting to `defaults`."
  @spec effective(override(), [integer()]) :: [integer()]
  def effective(override, defaults),
    do: override |> BucketResolution.effective_position_buckets(defaults) |> Enum.sort()

  @doc "The write that keeps the source position's effective set (see the moduledoc)."
  @spec action(side(), side()) :: action()
  def action(source, target) do
    {source.holds, target.holds}
    |> base_action({source.override, target.override}, source.effective, target.effective)
    |> carriable(source.override)
  end

  # S holds no rows of it: its override has no history to keep.
  defp base_action({false, _target_holds}, {:inherit, _t}, _s_eff, _t_eff), do: :none
  defp base_action({false, _target_holds}, _overrides, _s_eff, _t_eff), do: :drop_unheld

  # Both hold it: the sets must already agree.
  defp base_action({true, true}, _overrides, s_eff, t_eff) when s_eff != t_eff, do: :refuse
  defp base_action({true, true}, {:inherit, _t}, _s_eff, _t_eff), do: :none
  defp base_action({true, true}, _overrides, _s_eff, _t_eff), do: :drop_redundant

  # Only S holds it: S's effective set is carried onto T.
  defp base_action({true, false}, {:inherit, _t}, same, same), do: :none
  defp base_action({true, false}, {:inherit, _t}, _s_eff, _t_eff), do: :clear_target
  defp base_action({true, false}, {same, same}, _s_eff, _t_eff), do: :drop_redundant
  defp base_action({true, false}, _overrides, _s_eff, _t_eff), do: :carry

  # A carried override is written through `Buckets.set_position_override/4`,
  # which refuses more than one scope-dimension bucket (ADR-0024). An
  # override stored before that rule is refused here, by name, rather than
  # failing the merge half-way.
  defp carriable(:carry, {:explicit, bucket_ids}) do
    scope_buckets =
      Repo.aggregate(
        from(b in Bucket, where: b.id in ^bucket_ids and b.dimension == "scope"),
        :count
      )

    if scope_buckets > 1, do: :refuse_carry, else: :carry
  end

  defp carriable(action, _override), do: action

  @doc """
  Performs `action` for the pair `source` → `target` through the journaled
  Buckets writers, with the source and target overrides the plan read:
  `:none`, `{:ok, :carried | :dropped | :cleared, facts}` (the bucket ids
  carried or cleared, or the reason a source override was dropped), or the
  writer's `{:error, reason}`.
  """
  @spec write(Actor.t(), action(), {position(), override()}, {position(), override()}) ::
          :none | {:ok, :carried | :dropped | :cleared, map()} | {:error, term()}
  def write(actor, :carry, {{s_depot, s_security}, s_override}, {{t_depot, t_security}, _t}) do
    bucket_ids = override_ids(s_override)

    with :ok <- Buckets.set_position_override(actor, t_depot, t_security, bucket_ids),
         :ok <- Buckets.clear_position_override(actor, s_depot, s_security),
         do: {:ok, :carried, %{bucket_ids: bucket_ids}}
  end

  def write(actor, action, {{s_depot, s_security}, _s_override}, _target)
      when action in [:drop_redundant, :drop_unheld] do
    reason = if action == :drop_redundant, do: :redundant, else: :no_rows

    with :ok <- Buckets.clear_position_override(actor, s_depot, s_security),
         do: {:ok, :dropped, %{reason: reason}}
  end

  def write(actor, :clear_target, _source, {{t_depot, t_security}, t_override}) do
    with :ok <- Buckets.clear_position_override(actor, t_depot, t_security),
         do: {:ok, :cleared, %{bucket_ids: override_ids(t_override)}}
  end

  def write(_actor, :none, _source, _target), do: :none

  @doc """
  An override as the bucket ids it assigns — `[]` for a deliberately empty
  one — or `nil` for a position that inherits its depot's default set.
  """
  @spec override_ids(override()) :: [integer()] | nil
  def override_ids(:inherit), do: nil
  def override_ids(:explicit_empty), do: []
  def override_ids({:explicit, ids}), do: ids
end
