defmodule Portfolixir.Knowledge.Events do
  @moduledoc """
  Security events (ADR-0048, FR-44): dated calendar facts about a security
  that book nothing — an earnings report, an ex-dividend or payment date, a
  lockup expiry, an index review, a shareholder meeting, a regulatory
  decision, a guidance update.

  The second knowledge family beside the research log, and deliberately unlike
  it in one respect (§4): an event is **one mutable row per fact**, and its
  change history lives in the append-only audit journal rather than in a chain
  of superseding entries. Every write here goes through
  `Portfolixir.Journal.record/3`; the table is guard-armed in the migration
  that created it, so an unjournaled write is refused by the database.

  ## The boundary that is the whole point

  Events key on `security_id` and **nothing else** — no portfolio, no depot,
  no view — and every read covers **the whole catalog by default** (§2).
  `held_only: true` narrows it and is never the default. This is stated as a
  decision rather than left to a query, because the default *is* the
  requirement: a calendar derived from the position list cannot hold a date
  for a security not yet owned, which is precisely how a purchase candidate's
  reporting date became invisible.

  ## The four reads are the acceptance criteria (§5)

    1. `list_for_security/2` — one security's events, past and future.
    2. `upcoming/1` — due within N days across the catalog. A `window` or
       `month` event is due when **any** day it could fall on is inside the
       horizon, the conservative direction, because the failure this object
       exists to prevent is a missed date.
    3. `unconfirmed_past/1` — the "did it actually happen?" queue.
    4. `stale/1` — events nobody has re-read in N days, which is a different
       risk from a date that has passed.

  Nothing here fetches a calendar: entry is manual or through the agent's own
  write, and automatic population is gate B3.3, untouched (§8).
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge.SecurityEvent
  alias Portfolixir.Ledger.HeldSecurities
  alias Portfolixir.Repo

  @default_upcoming_days 30
  @default_stale_days 90

  # The widest span a `month` event can reach back from its stored date, used
  # only to bound the candidate rows the horizon query materialises; the exact
  # span is then resolved in Elixir through `SecurityEvent.span/1`.
  @max_span_days 31

  @doc "The default horizon of `upcoming/1`, in days."
  @spec default_upcoming_days() :: pos_integer()
  def default_upcoming_days, do: @default_upcoming_days

  @doc "The default staleness threshold of `stale/1`, in days."
  @spec default_stale_days() :: pos_integer()
  def default_stale_days, do: @default_stale_days

  @doc """
  Records one event, journaled under `actor`.

  `attrs` carries the ADR-0048 §6 fields (`security_id`, `kind`, `date`,
  `date_end`, `timing`, `confirmed`, `source_url`, `source_quality`,
  `checked_at`, `note`).
  """
  @spec create_event(Actor.t(), map()) ::
          {:ok, SecurityEvent.t()} | {:error, Ecto.Changeset.t() | :stale | {atom(), term()}}
  def create_event(%Actor{} = actor, attrs) when is_map(attrs) do
    Multi.new()
    |> Multi.insert(:event, SecurityEvent.changeset(%SecurityEvent{}, attrs))
    |> Journal.record(actor, resource_type: "security_event", operation: :create, source: :event)
    |> commit()
  end

  @doc """
  Updates one event, journaled under `actor` with the previous row recorded as
  the `before` snapshot.

  A rescheduled date replaces the old one (§4): two rows for one reporting
  date is a calendar an operator cannot read, and "which of these three is
  current?" is exactly the question the object exists to answer.
  """
  @spec update_event(Actor.t(), SecurityEvent.t(), map()) ::
          {:ok, SecurityEvent.t()} | {:error, Ecto.Changeset.t() | :stale | {atom(), term()}}
  def update_event(%Actor{} = actor, %SecurityEvent{} = event, attrs) when is_map(attrs) do
    Multi.new()
    |> Multi.update(:event, SecurityEvent.changeset(event, attrs))
    |> Journal.record(actor,
      resource_type: "security_event",
      operation: :update,
      source: :event,
      before: event
    )
    |> commit()
  end

  @doc """
  Deletes one event, journaled under `actor` with the row recorded as the
  `before` snapshot — so removing a duplicate loses nothing (§4).
  """
  @spec delete_event(Actor.t(), SecurityEvent.t()) ::
          {:ok, SecurityEvent.t()} | {:error, Ecto.Changeset.t() | :stale | {atom(), term()}}
  def delete_event(%Actor{} = actor, %SecurityEvent{} = event) do
    Multi.new()
    |> Multi.delete(:event, event)
    |> Journal.record(actor,
      resource_type: "security_event",
      operation: :delete,
      source: :event,
      before: event
    )
    |> commit()
  end

  # `Multi.update`/`Multi.delete` RAISE on a row that vanished rather than
  # returning a changeset, and §4 makes these rows mutable precisely so two
  # writers can both touch them — so the race is part of the design and
  # `{:error, :stale}` is part of the contract. The last clause keeps a
  # journal-step failure a value rather than a `CaseClauseError`.
  defp commit(multi) do
    case Repo.transaction(multi) do
      {:ok, %{event: event}} -> {:ok, event}
      {:error, _step, %Ecto.Changeset{} = invalid, _changes} -> {:error, invalid}
      {:error, step, reason, _changes} -> {:error, {step, reason}}
    end
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
  end

  @doc "One event by id, or `nil`."
  @spec get_event(integer()) :: SecurityEvent.t() | nil
  def get_event(id) when is_integer(id), do: Repo.get(SecurityEvent, id)

  @doc "Number of events (all securities)."
  def count_events, do: Repo.aggregate(SecurityEvent, :count, :id)

  @doc """
  §5.1 — all of one security's events, past and future, soonest first.

  Option `:limit` keeps the earliest rows. Option `:updated_since` (a
  naive-UTC cut, FR-38 / #830) keeps the rows created or updated strictly
  after it — the delta read.
  """
  @spec list_for_security(integer(), keyword()) :: [SecurityEvent.t()]
  def list_for_security(security_id, opts \\ []) when is_integer(security_id) do
    SecurityEvent
    |> where([e], e.security_id == ^security_id)
    |> maybe_updated_since(Keyword.get(opts, :updated_since))
    |> order_by([e], asc: e.date, asc: e.id)
    |> maybe_limit(Keyword.get(opts, :limit))
    |> Repo.all()
  end

  @doc """
  §5.2 — events due within `:days` (default #{@default_upcoming_days}) across
  the **whole catalog**, soonest first.

  A `window` or `month` event is due when **any** day it could fall on falls
  inside `[today, today + days]`: the span is resolved through
  `SecurityEvent.span/1` after a bounded candidate query, so a month whose
  stored day sits outside the horizon is still reported when the month reaches
  into it.

  Options: `:days`, `:today`, `:kind` (narrows to one kind), `:held_only`
  (`true` restricts to securities with a non-zero ledger quantity — an opt-in,
  never the default), `:limit`.
  """
  @spec upcoming(keyword()) :: [SecurityEvent.t()]
  def upcoming(opts \\ []) do
    days = Keyword.get(opts, :days, @default_upcoming_days)
    today = Keyword.get(opts, :today, Clock.today())
    horizon = Date.add(today, days)
    floor_date = Date.add(today, -@max_span_days)

    SecurityEvent
    # A COARSE bound on the candidate rows, deliberately wider than the
    # horizon on both sides: a `month` event's span opens at the first of its
    # month, so its stored date may sit after the horizon while the month
    # still reaches into it, and a `window` may have opened long before today.
    # The exact span is resolved below through `SecurityEvent.span/1`.
    |> where([e], e.date <= ^Date.add(horizon, @max_span_days))
    |> where([e], e.date >= ^floor_date or e.date_end >= ^today)
    |> maybe_kind(Keyword.get(opts, :kind))
    |> maybe_held_only(Keyword.get(opts, :held_only, false))
    |> order_by([e], asc: e.date, asc: e.id)
    |> Repo.all()
    |> Enum.filter(&due?(&1, today, horizon))
    |> take(Keyword.get(opts, :limit))
  end

  @doc """
  §5.3 — unconfirmed events whose whole span is in the past, oldest first:
  the "did it actually happen?" queue, which is what keeps the calendar from
  quietly rotting.

  Options: `:today`, `:security_id`, `:kind`, `:held_only`, `:limit`.
  """
  @spec unconfirmed_past(keyword()) :: [SecurityEvent.t()]
  def unconfirmed_past(opts \\ []) do
    today = Keyword.get(opts, :today, Clock.today())

    SecurityEvent
    |> where([e], e.confirmed == false)
    |> where([e], e.date < ^today)
    |> maybe_security(Keyword.get(opts, :security_id))
    |> maybe_kind(Keyword.get(opts, :kind))
    |> maybe_held_only(Keyword.get(opts, :held_only, false))
    |> order_by([e], asc: e.date, asc: e.id)
    |> Repo.all()
    |> Enum.filter(fn event ->
      {_from, to} = SecurityEvent.span(event)
      Date.compare(to, today) == :lt
    end)
    |> take(Keyword.get(opts, :limit))
  end

  @doc """
  §5.4 — events whose `checked_at` is older than `:days`
  (default #{@default_stale_days}), or that were never checked at all, oldest
  first. The staleness of the **calendar** itself, distinct from a date that
  has passed.

  A never-checked event is listed with `days_since_checked: nil` — it is at
  least as unre-read as one checked long ago, and hiding it would make the
  read answer a narrower question than it claims.

  Options: `:days`, `:today`, `:security_id`, `:kind`, `:held_only`, `:limit`.
  """
  @spec stale(keyword()) :: [SecurityEvent.t()]
  def stale(opts \\ []) do
    days = Keyword.get(opts, :days, @default_stale_days)
    today = Keyword.get(opts, :today, Clock.today())
    cutoff = Date.add(today, -days)

    SecurityEvent
    |> where([e], is_nil(e.checked_at) or e.checked_at < ^cutoff)
    |> maybe_security(Keyword.get(opts, :security_id))
    |> maybe_kind(Keyword.get(opts, :kind))
    |> maybe_held_only(Keyword.get(opts, :held_only, false))
    |> order_by([e], asc_nulls_first: e.checked_at, asc: e.date, asc: e.id)
    |> maybe_limit(Keyword.get(opts, :limit))
    |> Repo.all()
    |> Enum.map(fn event ->
      %{event | days_since_checked: event.checked_at && Date.diff(today, event.checked_at)}
    end)
  end

  # §3, resolved conservatively: due when ANY day the event could fall on is
  # inside the horizon.
  defp due?(event, today, horizon) do
    {from, to} = SecurityEvent.span(event)
    Date.compare(to, today) != :lt and Date.compare(from, horizon) != :gt
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, n) when is_integer(n) and n > 0, do: limit(query, ^n)

  defp maybe_updated_since(query, nil), do: query

  defp maybe_updated_since(query, %NaiveDateTime{} = cut),
    do: where(query, [e], e.updated_at > ^cut)

  defp take(rows, nil), do: rows
  defp take(rows, n) when is_integer(n) and n > 0, do: Enum.take(rows, n)

  defp maybe_security(query, nil), do: query
  defp maybe_security(query, id) when is_integer(id), do: where(query, [e], e.security_id == ^id)

  defp maybe_kind(query, nil), do: query

  defp maybe_kind(query, kind) when is_binary(kind) do
    case kind in SecurityEvent.kinds() do
      true -> where(query, [e], e.kind == ^String.to_existing_atom(kind))
      # An unknown kind narrows to nothing rather than widening to everything;
      # the API layer refuses it with a 422 before reaching here.
      false -> where(query, [e], false)
    end
  end

  defp maybe_kind(query, kind) when is_atom(kind), do: where(query, [e], e.kind == ^kind)

  @doc """
  The security ids with a non-zero net ledger quantity — the same predicate
  `held_only: true` narrows by, and the one every held surface reads
  (`Portfolixir.Ledger.HeldSecurities`, #839). Exposed so a surface can MARK an unheld
  security rather than filter it away (ADR-0048 §2, design pick D3-A).
  """
  @spec held_security_ids() :: [integer()]
  def held_security_ids, do: HeldSecurities.held_ids()

  defp maybe_held_only(query, false), do: query

  defp maybe_held_only(query, true),
    do: where(query, [e], e.security_id in subquery(HeldSecurities.held_ids_query()))
end
