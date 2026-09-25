defmodule Portfolixir.Knowledge do
  @moduledoc """
  The security research log (ADR-0044): what the operator or the agent knows
  about a security, as **append-only** dated entries, and the thesis state as a
  projection over them.

  The log is the truth; the state is derived (`Portfolixir.Knowledge.ThesisState`).
  Entries are never updated and never deleted — a refuted finding is withdrawn
  by appending a `retraction` that supersedes it, and both stay readable (§3).
  There is deliberately no update and no delete function here; adding one is a
  change to the ADR, not an implementation detail.

  Every write goes through `Portfolixir.Journal.record/3` (§5): the table is
  guard-armed in the migration that created it, so an unjournaled insert is
  refused by the database.

  The four reads (§7) are the acceptance criteria: a security's log newest
  first, held positions with no entry for N days, entries that still need
  corroboration, and dated blocks expiring within N days.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Clock
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge.SecurityNote
  alias Portfolixir.Knowledge.ThesisState
  alias Portfolixir.Ledger.HeldSecurities
  alias Portfolixir.Repo

  @default_days 90

  @doc """
  Appends one entry to a security's research log, journaled under `actor`.

  `attrs` carries the ADR-0044 §2 fields (`security_id`, `author`, `kind`,
  `body`, `source_url`, `source_quality`, `as_of`, `supersedes_id`,
  `valid_until`, `machine_generated`, and the thesis fields `conviction`,
  `invalidation_condition`, `time_stop`). `supersedes_id` must name an entry
  of the same security; a `retraction` must supersede one.

  `opts[:today]` injects the clock (AR-2) and defaults to `Clock.today/0`;
  an `as_of` after it is refused (E25 S6, F44).

  Returns `{:ok, note}` or `{:error, changeset}`.
  """
  @spec append_note(Actor.t(), map(), keyword()) ::
          {:ok, SecurityNote.t()} | {:error, Ecto.Changeset.t()}
  def append_note(%Actor{} = actor, attrs, opts \\ []) when is_map(attrs) do
    today = Keyword.get(opts, :today, Clock.today())
    changeset = SecurityNote.changeset(%SecurityNote{}, attrs, today)

    multi =
      Multi.new()
      |> Multi.run(:supersedes_guard, fn repo, _ -> supersedes_guard(repo, changeset) end)
      |> Multi.insert(:note, changeset)
      |> Journal.record(actor, resource_type: "security_note", operation: :create, source: :note)

    case Repo.transaction(multi) do
      {:ok, %{note: note}} -> {:ok, note}
      {:error, _step, %Ecto.Changeset{} = invalid, _changes} -> {:error, invalid}
    end
  end

  # The superseded entry must belong to the same security — a cross-table
  # invariant the FK alone cannot express, checked inside the write transaction.
  # (An invalid changeset never reaches this step: `Repo.transaction/1` fails an
  # `Ecto.Multi` carrying one before running any step.)
  defp supersedes_guard(repo, %Ecto.Changeset{} = changeset) do
    case Ecto.Changeset.get_field(changeset, :supersedes_id) do
      nil ->
        {:ok, :none}

      supersedes_id ->
        security_id = Ecto.Changeset.get_field(changeset, :security_id)

        case repo.get(SecurityNote, supersedes_id) do
          %SecurityNote{security_id: ^security_id} ->
            {:ok, :same_security}

          _other ->
            {:error,
             Ecto.Changeset.add_error(
               changeset,
               :supersedes_id,
               "must reference an entry of the same security"
             )}
        end
    end
  end

  @doc """
  All entries of one security, **newest first** (by `as_of`, then write time,
  then id), each annotated with `superseded_by_ids` — the ids of the entries
  that supersede it, so a superseded entry is shown as superseded rather than
  hidden (§6).

  Option `:limit` keeps the newest `limit` entries (#776); the superseder
  annotation still looks beyond the page. The thesis projection never passes
  one — it reads the whole log.

  Option `:inserted_since` (a naive-UTC cut, FR-38 / #830) keeps the entries
  inserted strictly after it — the delta read. The log is append-only, so an
  entry's `inserted_at` is the last time it changed.
  """
  @spec list_notes(integer(), keyword()) :: [SecurityNote.t()]
  def list_notes(security_id, opts \\ []) when is_integer(security_id) do
    SecurityNote
    |> where([n], n.security_id == ^security_id)
    |> maybe_inserted_since(Keyword.get(opts, :inserted_since))
    |> order_by([n], desc: n.as_of, desc: n.inserted_at, desc: n.id)
    |> maybe_limit(Keyword.get(opts, :limit))
    |> Repo.all()
    |> annotate_superseded()
  end

  @doc "One entry by id, or `nil`."
  @spec get_note(integer()) :: SecurityNote.t() | nil
  def get_note(id) when is_integer(id), do: Repo.get(SecurityNote, id)

  @doc """
  The current thesis state of a security — a pure projection over its log
  (`Portfolixir.Knowledge.ThesisState.project/1`).
  """
  @spec thesis_state(integer()) :: ThesisState.t()
  def thesis_state(security_id) when is_integer(security_id) do
    security_id |> list_notes() |> ThesisState.project()
  end

  @doc """
  Attaches the thesis state to a security's virtual `thesis_state` field, for
  the detail read (#749: "the state is part of the security read").
  """
  @spec with_thesis_state(Security.t()) :: Security.t()
  def with_thesis_state(%Security{id: id} = security) when is_integer(id) do
    %{security | thesis_state: thesis_state(id)}
  end

  @doc """
  Held securities with **no entry for N days** (§7.2, review hygiene): every
  security whose ledger quantity is non-zero (`Ledger.HeldSecurities` — every
  quantity-moving kind, deliveries included) and whose newest `as_of` is older
  than `days` (default #{@default_days}) — or absent. Rows carry the security,
  `last_entry_as_of` (nil when none) and `days_since_last_entry`.

  Options: `:days`, `:today` (defaults to the host date), `:limit` — the most
  overdue rows first, so a limit keeps the most urgent ones (#776).
  """
  @spec unreviewed_positions(keyword()) :: [map()]
  def unreviewed_positions(opts \\ []) do
    days = Keyword.get(opts, :days, @default_days)
    today = Keyword.get(opts, :today, Clock.today())
    cutoff = Date.add(today, -days)

    # An entry counts as a review on its as_of, but no later than the day it
    # was written (one day of zone slack): an entry stored with a future
    # as_of cannot keep its position off this read (E25 S6, F44;
    # `SecurityNote.review_date/1` is the same rule for one loaded entry).
    latest =
      from(n in SecurityNote,
        group_by: n.security_id,
        select: %{
          security_id: n.security_id,
          last_as_of: max(fragment("LEAST(?, (?::date + 1))", n.as_of, n.inserted_at))
        }
      )

    from(s in Security,
      left_join: l in subquery(latest),
      on: l.security_id == s.id,
      where: s.id in subquery(HeldSecurities.held_ids_query()),
      where: is_nil(l.last_as_of) or l.last_as_of < ^cutoff,
      order_by: [asc_nulls_first: l.last_as_of, asc: s.name],
      select: {s, l.last_as_of}
    )
    |> maybe_limit(Keyword.get(opts, :limit))
    |> Repo.all()
    |> Enum.map(fn {security, last_as_of} ->
      %{
        security: security,
        last_entry_as_of: last_as_of,
        days_since_last_entry: last_as_of && Date.diff(today, last_as_of)
      }
    end)
  end

  @doc """
  Entries whose `source_quality` is not `primary` (§7.3 — what still needs
  corroboration), newest first, superseded entries skipped unless
  `include_superseded: true`. Option `:security_id` narrows to one security;
  `:limit` keeps the newest entries (#776).
  """
  @spec uncorroborated_notes(keyword()) :: [SecurityNote.t()]
  def uncorroborated_notes(opts \\ []) do
    SecurityNote
    |> where([n], n.source_quality != :primary)
    |> maybe_security(Keyword.get(opts, :security_id))
    |> maybe_exclude_superseded(Keyword.get(opts, :include_superseded, false))
    |> order_by([n], desc: n.as_of, desc: n.inserted_at, desc: n.id)
    |> maybe_limit(Keyword.get(opts, :limit))
    |> Repo.all()
    |> annotate_superseded()
  end

  @doc """
  Entries whose `valid_until` falls inside the next N days (§7.4 — expiring
  blocks): `today <= valid_until <= today + days`, soonest first, superseded
  entries skipped. Rows carry `days_until_expiry`.

  Options: `:days` (default 30), `:today`, `:security_id`, `:limit` — soonest
  first, so a limit keeps the entries closest to expiry (#776).
  """
  @spec expiring_notes(keyword()) :: [SecurityNote.t()]
  def expiring_notes(opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    today = Keyword.get(opts, :today, Clock.today())
    horizon = Date.add(today, days)

    SecurityNote
    |> where([n], not is_nil(n.valid_until))
    |> where([n], n.valid_until >= ^today and n.valid_until <= ^horizon)
    |> maybe_security(Keyword.get(opts, :security_id))
    |> maybe_exclude_superseded(false)
    |> order_by([n], asc: n.valid_until, desc: n.as_of, desc: n.id)
    |> maybe_limit(Keyword.get(opts, :limit))
    |> Repo.all()
    |> annotate_superseded()
    |> Enum.map(&Map.put(&1, :days_until_expiry, Date.diff(&1.valid_until, today)))
  end

  @doc "Number of entries in the log (all securities)."
  def count_notes, do: Repo.aggregate(SecurityNote, :count, :id)

  # #776: a bound on the rows one read materialises, in each read's own order.
  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, n) when is_integer(n) and n > 0, do: limit(query, ^n)

  defp maybe_inserted_since(query, nil), do: query

  defp maybe_inserted_since(query, %NaiveDateTime{} = cut),
    do: where(query, [n], n.inserted_at > ^cut)

  defp maybe_security(query, nil), do: query
  defp maybe_security(query, id) when is_integer(id), do: where(query, [n], n.security_id == ^id)

  defp maybe_exclude_superseded(query, true), do: query

  defp maybe_exclude_superseded(query, false) do
    where(
      query,
      [n],
      not exists(from(s in SecurityNote, where: s.supersedes_id == parent_as(:note).id))
    )
    |> from(as: :note)
  end

  defp annotate_superseded([]), do: []

  defp annotate_superseded(notes) do
    ids = Enum.map(notes, & &1.id)

    superseders =
      from(s in SecurityNote,
        where: s.supersedes_id in ^ids,
        order_by: [desc: s.as_of, desc: s.inserted_at, desc: s.id],
        select: {s.supersedes_id, s.id}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    Enum.map(notes, &%{&1 | superseded_by_ids: Map.get(superseders, &1.id, [])})
  end
end
