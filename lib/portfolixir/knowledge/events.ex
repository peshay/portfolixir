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

  Nothing here fetches a calendar, except ADR-0059's chain reader, for
  `halving` events only (§8 as ADR-0048's amendment of 2026-11-12 narrows
  it): entry of every other kind is manual or through the agent's own
  write, and automatic population of those stays behind gate B3.3.

  ## Halvings (ADR-0048's amendment of 2026-11-12, ADR-0059)

  A `halving` event needs a security bound to a registered chain
  (`halving_chain`), else `{:error, :no_halving_chain}`, and a
  `chain_height` that is *k* × that chain's interval. On a chain with a
  source (Bitcoin) only the chain reader writes them, through
  `put_chain_halving/6`; a create, update or delete through this module's
  ordinary writers answers `{:error, {:halving_from_chain, chain}}`. Every
  event write reads the binding under a share lock on the security, so a
  rebinding, which deletes the security's halvings in its own write
  (`delete_halvings/2`), and an event write never interleave.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Chains.Registry
  alias Portfolixir.Clock
  alias Portfolixir.DeltaCursor
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

  `opts[:today]` injects the clock (AR-2) and defaults to `Clock.today/0`; a
  `checked_at` later than the day after it is refused (E25 S6, G09).
  """
  @spec create_event(Actor.t(), map(), keyword()) ::
          {:ok, SecurityEvent.t()}
          | {:error,
             Ecto.Changeset.t() | :stale | :no_halving_chain | :binding_changed | {atom(), term()}}
  def create_event(%Actor{} = actor, attrs, opts \\ []) when is_map(attrs) do
    today = Keyword.get(opts, :today, Clock.today())
    insert_event(actor, SecurityEvent.changeset(%SecurityEvent{}, attrs, today), :caller)
  end

  defp insert_event(actor, changeset, mode) do
    Multi.new()
    |> Multi.run(:halving, fn _repo, %{binding: binding} ->
      halving_guard(binding, changeset, nil, mode)
    end)
    |> Multi.insert(:event, & &1.halving)
    |> Journal.record(actor, resource_type: "security_event", operation: :create, source: :event)
    |> Multi.prepend(binding_lock(Ecto.Changeset.get_field(changeset, :security_id)))
    |> commit()
  end

  @doc """
  Updates one event, journaled under `actor` with the previous row recorded as
  the `before` snapshot.

  `opts[:today]` injects the clock as in `create_event/3`.

  A rescheduled date replaces the old one (§4): two rows for one reporting
  date is a calendar an operator cannot read, and "which of these three is
  current?" is exactly the question the object exists to answer.
  """
  @spec update_event(Actor.t(), SecurityEvent.t(), map(), keyword()) ::
          {:ok, SecurityEvent.t()}
          | {:error,
             Ecto.Changeset.t() | :stale | :no_halving_chain | :binding_changed | {atom(), term()}}
  def update_event(%Actor{} = actor, %SecurityEvent{} = event, attrs, opts \\ [])
      when is_map(attrs) do
    today = Keyword.get(opts, :today, Clock.today())
    change_event(actor, event, attrs, today, :caller)
  end

  defp change_event(actor, event, attrs, today, mode) do
    Multi.new()
    |> Multi.run(:halving, fn _repo, %{binding: binding} = changes ->
      locked = Journal.locked_row(changes)
      halving_guard(binding, SecurityEvent.changeset(locked, attrs, today), locked, mode)
    end)
    |> Multi.update(:event, & &1.halving)
    |> Journal.record(actor,
      resource_type: "security_event",
      operation: :update,
      source: :event,
      before: event
    )
    |> Multi.prepend(binding_lock(event.security_id))
    |> commit()
  end

  @doc """
  Moves one event onto the security `security_id`, journaled under `actor`
  as one `security_event` update with the row as stored under its lock as
  the `before` snapshot (ADR-0050 §9: a security merge moves the source's
  events onto the target; a same-kind, same-day pair it lists and leaves for
  the operator). Only `security_id` changes; the event's facts are not
  re-validated.
  """
  @spec reassign_event(Actor.t(), SecurityEvent.t(), integer()) ::
          {:ok, SecurityEvent.t()}
          | {:error,
             Ecto.Changeset.t() | :stale | :no_halving_chain | :binding_changed | {atom(), term()}}
  def reassign_event(%Actor{} = actor, %SecurityEvent{} = event, security_id)
      when is_integer(security_id) do
    Multi.new()
    |> Multi.update(
      :event,
      &SecurityEvent.reassign_changeset(Journal.locked_row(&1), security_id)
    )
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
          {:ok, SecurityEvent.t()}
          | {:error,
             Ecto.Changeset.t() | :stale | :no_halving_chain | :binding_changed | {atom(), term()}}
  def delete_event(%Actor{} = actor, %SecurityEvent{} = event) do
    Multi.new()
    |> Multi.run(:halving, fn _repo, %{binding: binding} = changes ->
      changes |> Journal.locked_row() |> delete_guard(binding)
    end)
    |> Multi.delete(:event, event)
    |> Journal.record(actor,
      resource_type: "security_event",
      operation: :delete,
      source: :event,
      before: event
    )
    |> Multi.prepend(binding_lock(event.security_id))
    |> commit()
  end

  @doc """
  Deletes one event without the halving guard, journaled under `actor` with
  the row as the `before` snapshot: the writer of the two system decisions
  that remove a halving whoever its writer was, a security merge dropping a
  halving the target holds or whose chain differs (ADR-0048's amendment,
  item 8) and `delete_halvings/2`. Never a caller's request.
  """
  @spec discard_event(Actor.t(), SecurityEvent.t()) ::
          {:ok, SecurityEvent.t()}
          | {:error,
             Ecto.Changeset.t() | :stale | :no_halving_chain | :binding_changed | {atom(), term()}}
  def discard_event(%Actor{} = actor, %SecurityEvent{} = event) do
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

  @doc """
  Deletes every `halving` event of `security_id`, one journaled delete per
  row under `actor` (ADR-0059 §4; ADR-0048's amendment, item 7): what
  unbinding or rebinding a security does in the same write, because a
  halving is a fact about the security *as bound to that chain*. The rows
  are re-read under their lock first. Answers `{:ok, count}`.
  """
  @spec delete_halvings(Actor.t(), integer()) :: {:ok, non_neg_integer()} | {:error, term()}
  def delete_halvings(%Actor{} = actor, security_id) when is_integer(security_id) do
    Repo.transaction(fn ->
      halvings =
        Repo.all(
          from(e in SecurityEvent,
            where: e.security_id == ^security_id and e.kind == ^:halving,
            order_by: e.id,
            lock: "FOR UPDATE"
          )
        )

      Enum.each(halvings, fn event ->
        case discard_event(actor, event) do
          {:ok, _deleted} -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

      length(halvings)
    end)
  end

  @doc """
  The number of `halving` events of `security_id`: what a rebinding would
  delete, for a screen that asks first (ADR-0059 §4).
  """
  @spec count_halvings(integer()) :: non_neg_integer()
  def count_halvings(security_id) when is_integer(security_id) do
    SecurityEvent
    |> where([e], e.security_id == ^security_id and e.kind == ^:halving)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  The chain reader's write of one halving (ADR-0059 §5, §6; ADR-0048's
  amendment, item 4): the event of `security_id` at `height` is created, or
  the one row stored at that height is updated, idempotent by security and
  height. A call that changes nothing writes no row and no journal entry.

  `attrs` carries the event's other fields (`date`, `date_end`, `timing`,
  `confirmed`, `source_url`, `source_quality`, `checked_at`, `note`); `kind`,
  `security_id` and `chain_height` are this function's. The security must
  still be bound to `chain` under its share lock, else
  `{:error, :binding_changed}` and nothing is written (a rebinding during a
  run), and `height` must be a halving of it, else a changeset error on
  `chain_height`. `opts[:today]` injects the clock as in `create_event/3`.
  """
  @spec put_chain_halving(Actor.t(), integer(), Registry.chain(), integer(), map(), keyword()) ::
          {:ok, SecurityEvent.t()}
          | {:error, Ecto.Changeset.t() | :binding_changed | :stale | {atom(), term()}}
  def put_chain_halving(%Actor{} = actor, security_id, chain, height, attrs, opts \\ [])
      when is_integer(security_id) and is_map(attrs) do
    today = Keyword.get(opts, :today, Clock.today())

    attrs =
      attrs
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.merge(%{
        "security_id" => security_id,
        "kind" => "halving",
        "chain_height" => height
      })

    put_halving(actor, attrs, {:chain_reader, chain}, today, 2)
  end

  # Insert when no row holds the height, update the one that does. A
  # concurrent writer that inserted first (a unique violation) or deleted the
  # row first (`:stale`) is met by one more attempt the other way.
  defp put_halving(actor, attrs, mode, today, attempts) do
    stored =
      Repo.one(
        from(e in SecurityEvent,
          where:
            e.security_id == ^attrs["security_id"] and e.chain_height == ^attrs["chain_height"]
        )
      )

    result =
      case stored do
        nil -> insert_event(actor, SecurityEvent.changeset(%SecurityEvent{}, attrs, today), mode)
        %SecurityEvent{} -> change_event(actor, stored, attrs, today, mode)
      end

    if attempts > 1 and retry?(result),
      do: put_halving(actor, attrs, mode, today, attempts - 1),
      else: result
  end

  defp retry?({:error, :stale}), do: true

  defp retry?({:error, %Ecto.Changeset{errors: errors}}) do
    case errors[:chain_height] do
      {_message, opts} -> opts[:constraint] == :unique
      nil -> false
    end
  end

  defp retry?(_result), do: false

  # The security's binding, read under a share lock ahead of any event row
  # lock (the order a rebinding takes too: the security, then its events).
  defp binding_lock(security_id) do
    Multi.run(Multi.new(), :binding, fn repo, _changes ->
      if is_integer(security_id) do
        case repo.one(
               from(s in Security,
                 where: s.id == ^security_id,
                 select: s.halving_chain,
                 lock: "FOR SHARE"
               )
             ) do
          nil -> {:ok, binding_or_missing(repo, security_id)}
          chain -> {:ok, {:bound, chain}}
        end
      else
        {:ok, :missing}
      end
    end)
  end

  # `select: s.halving_chain` reads nil both for an unbound security and for
  # none at all; the second is the foreign key's error, not this guard's.
  defp binding_or_missing(repo, security_id) do
    if repo.exists?(from(s in Security, where: s.id == ^security_id)),
      do: {:bound, nil},
      else: :missing
  end

  # ADR-0048's amendment, items 2 to 4: decides a write that involves a
  # halving (the row before it, or the row it makes). `mode` is `:caller`
  # (the API, the screen, an agent) or `{:chain_reader, chain}`.
  defp halving_guard(binding, changeset, before, mode) do
    kind = Ecto.Changeset.get_field(changeset, :kind)
    involved? = kind == :halving or match?(%SecurityEvent{kind: :halving}, before)

    case {involved?, binding, mode} do
      {false, _binding, _mode} ->
        {:ok, changeset}

      {true, :missing, _mode} ->
        {:ok, changeset}

      {true, {:bound, chain}, {:chain_reader, expected}} when chain != expected ->
        {:error, :binding_changed}

      {true, {:bound, chain}, :caller} when not is_nil(chain) ->
        if Registry.has_source?(chain),
          do: {:error, {:halving_from_chain, chain}},
          else: {:ok, halving_height(changeset, kind, chain)}

      {true, {:bound, nil}, _mode} when kind == :halving ->
        {:error, :no_halving_chain}

      {true, {:bound, chain}, _mode} ->
        {:ok, halving_height(changeset, kind, chain)}
    end
  end

  # ADR-0048's amendment, item 2: k × the chain's interval, k ≥ 1.
  defp halving_height(changeset, :halving, chain) when not is_nil(chain) do
    Ecto.Changeset.validate_change(changeset, :chain_height, fn :chain_height, height ->
      if Registry.halving_height?(chain, height),
        do: [],
        else: [
          chain_height:
            {"is not a halving of %{chain} (a multiple of %{interval} blocks)",
             chain: Atom.to_string(chain),
             interval: Registry.halving_interval(chain),
             validation: :halving_height}
        ]
    end)
  end

  defp halving_height(changeset, _kind, _chain), do: changeset

  # ADR-0048's amendment, item 4: on a chain with a source the reader alone
  # removes a halving; any other row, and a halving of a chain without one
  # (or of none), is deleted as before.
  defp delete_guard(%SecurityEvent{kind: :halving}, {:bound, chain}) when not is_nil(chain) do
    if Registry.has_source?(chain),
      do: {:error, {:halving_from_chain, chain}},
      else: {:ok, :allowed}
  end

  defp delete_guard(_event, _binding), do: {:ok, :allowed}

  # `Multi.update`/`Multi.delete` RAISE on a row that vanished rather than
  # returning a changeset, and §4 makes these rows mutable precisely so two
  # writers can both touch them — so the race is part of the design and
  # `{:error, :stale}` is part of the contract. The last clause keeps a
  # journal-step failure a value rather than a `CaseClauseError`.
  defp commit(multi) do
    case Repo.transaction(multi) do
      {:ok, %{event: event}} -> {:ok, event}
      {:error, _step, %Ecto.Changeset{} = invalid, _changes} -> {:error, invalid}
      # ADR-0048's amendment, items 3 and 4, and a rebinding during a run.
      {:error, :halving, reason, _changes} -> {:error, reason}
      # The row was deleted before the write took its lock (E25 S6, F49).
      {:error, {:journal_lock, _}, :not_found, _changes} -> {:error, :stale}
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
  after it — the delta read. Option `:delta` (a `Portfolixir.DeltaCursor`
  cursor, K17) is the API's paged delta read: the rows changed after the
  cursor, oldest change first, so a capped page continues where the last
  one ended.
  """
  @spec list_for_security(integer(), keyword()) :: [SecurityEvent.t()]
  def list_for_security(security_id, opts \\ []) when is_integer(security_id) do
    SecurityEvent
    |> where([e], e.security_id == ^security_id)
    |> maybe_updated_since(Keyword.get(opts, :updated_since))
    |> order_events(Keyword.get(opts, :delta))
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
  read answer a narrower question than it claims. An event whose stored
  `checked_at` is later than tomorrow (written before E25 S6, G09 refused
  one) is listed too, with a negative `days_since_checked`.

  Options: `:days`, `:today`, `:security_id`, `:kind`, `:held_only`, `:limit`.
  """
  @spec stale(keyword()) :: [SecurityEvent.t()]
  def stale(opts \\ []) do
    days = Keyword.get(opts, :days, @default_stale_days)
    today = Keyword.get(opts, :today, Clock.today())
    cutoff = Date.add(today, -days)

    # A checked_at later than tomorrow was stored before the refusal existed
    # (E25 S6, G09); it is no re-read, so the event is listed as stale.
    latest = Date.add(today, 1)

    SecurityEvent
    |> where([e], is_nil(e.checked_at) or e.checked_at < ^cutoff or e.checked_at > ^latest)
    # ADR-0048's amendment, item 6: a confirmed halving's block is buried and
    # there is nothing to re-read; the unconfirmed next one stays in.
    |> where([e], not (e.kind == ^:halving and e.confirmed == true))
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

  defp order_events(query, nil), do: order_by(query, [e], asc: e.date, asc: e.id)

  defp order_events(query, cursor),
    do: DeltaCursor.page(query, dynamic([e], e.updated_at), cursor)

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
