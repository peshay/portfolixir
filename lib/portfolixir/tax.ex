defmodule Portfolixir.Tax do
  @moduledoc """
  Recorded tax-statement data and the configuration it is checked against
  (ADR-0031, FR-36).

  Four tables: the recorded `tax_statement_snapshots` themselves, plus the
  configuration they are checked against — year-scoped statutory
  `tax_parameters`, effective-dated `tax_profiles`, and configured
  `allowance_orders`. The configuration exists because checking a transcribed
  statement requires the law of its year: the Sparer-Pauschbetrag changed in
  2023, so a hardcoded ceiling would flag every correct transcription of a
  pre-2023 statement as inconsistent.

  Two rules hold across the whole context:

  - **Writes are actor-first and journaled** (ADR-0017, FR-28). All four
    tables are guard-armed, `tax_parameters` deliberately: a statutory-rate
    edit silently changes every consistency finding for that year.
  - **Nothing here is derived.** ADR-0031 rejects computing the German tax pots
    from the ledger (average cost vs. mandated FIFO), so these rows are
    recorded inputs, never calculated ones.

  `fetch_parameters/2` never falls back to a neighbouring year or to a default.
  An unseeded year is an error the caller handles — a silently wrong ceiling is
  exactly what this context exists to prevent.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Repo
  alias Portfolixir.Tax.AllowanceOrder
  alias Portfolixir.Tax.Budget
  alias Portfolixir.Tax.Consistency
  alias Portfolixir.Tax.Identity
  alias Portfolixir.Tax.Parameters
  alias Portfolixir.Tax.Profile
  alias Portfolixir.Tax.StatementSnapshot

  @default_jurisdiction "DE"

  # German history, seeded by `20260725140000_seed_tax_parameters`. Starts at
  # the introduction of the Abgeltungsteuer and stops at the current year:
  # inventing a ceiling for a year whose law is not written is the same class of
  # fabrication this epic exists to avoid — `fetch_parameters/2` makes the gap
  # explicit instead.
  @seed_first_year 2009
  @seed_last_year 2026
  @seed_allowance_change_year 2023

  # The 2021 partial Soli abolition did not touch the Abgeltungsteuer, so these
  # hold for every seeded year. String literals: `Decimal.new/1` raises on a
  # float, and `Decimal.from_float/1` belongs at display boundaries only.
  @seed_capital_gains_tax_rate "0.25"
  @seed_solidarity_surcharge_rate "0.055"
  @seed_church_tax_rates ["0.08", "0.09"]

  # -- parameters ------------------------------------------------------------

  @doc """
  Fetches the statutory parameters for `jurisdiction` and `tax_year`.

  Returns `{:error, :not_found}` for a year with no row — never the nearest
  year, never a default (AC-8).
  """
  @spec fetch_parameters(String.t(), integer()) :: {:ok, Parameters.t()} | {:error, :not_found}
  def fetch_parameters(jurisdiction, tax_year) when is_binary(jurisdiction) do
    case Repo.get_by(Parameters, jurisdiction: jurisdiction, tax_year: tax_year) do
      nil -> {:error, :not_found}
      parameters -> {:ok, parameters}
    end
  end

  @doc "Lists parameters oldest year first. Pass `jurisdiction:` to filter."
  @spec list_parameters(keyword()) :: [Parameters.t()]
  def list_parameters(opts \\ []) do
    Parameters
    |> filter_eq(:jurisdiction, opts[:jurisdiction])
    |> order_by([p], asc: p.jurisdiction, asc: p.tax_year)
    |> Repo.all()
  end

  @doc """
  Inserts or replaces the parameters for a `(jurisdiction, tax_year)` on behalf
  of `actor`. The `built_in` marker is never changed by an operator edit, so a
  corrected seed row stays recognisable to the rollback.
  """
  @spec upsert_parameters(Actor.t(), map()) ::
          {:ok, Parameters.t()} | {:error, Ecto.Changeset.t()}
  def upsert_parameters(%Actor{} = actor, attrs) when is_map(attrs) do
    fresh = Parameters.changeset(%Parameters{}, attrs)
    jurisdiction = Ecto.Changeset.get_field(fresh, :jurisdiction)
    tax_year = Ecto.Changeset.get_field(fresh, :tax_year)

    case fetch_parameters(jurisdiction || @default_jurisdiction, tax_year) do
      {:error, :not_found} -> insert_parameters(actor, fresh)
      {:ok, existing} -> update_parameters(actor, existing, attrs)
    end
  end

  defp insert_parameters(actor, changeset) do
    Multi.new()
    |> Multi.insert(:parameters, changeset)
    |> Journal.record(actor,
      resource_type: "tax_parameters",
      operation: :create,
      source: :parameters
    )
    |> Repo.transaction()
    |> normalize(:parameters)
  end

  defp update_parameters(actor, existing, attrs) do
    Multi.new()
    |> Multi.update(:parameters, Parameters.changeset(existing, attrs))
    |> Journal.record(actor,
      resource_type: "tax_parameters",
      operation: :update,
      source: :parameters,
      before: existing
    )
    |> Repo.transaction()
    |> normalize(:parameters)
  end

  @doc """
  Seeds the built-in German statutory history, idempotently.

  An existing `(jurisdiction, tax_year)` row is skipped entirely, so a re-run
  inserts nothing, writes no journal entries, and never overwrites a value the
  operator has edited (the classifications precedent: backfill, never
  overwrite). Returns `{:ok, %{inserted: n, skipped: n}}`.

  Referenced from the immutable migration `20260725140000_seed_tax_parameters`
  — keep this signature stable.
  """
  @spec seed_builtin_parameters(Actor.t()) :: {:ok, %{inserted: integer(), skipped: integer()}}
  def seed_builtin_parameters(%Actor{} = actor) do
    summary =
      Enum.reduce(@seed_first_year..@seed_last_year, %{inserted: 0, skipped: 0}, fn year, acc ->
        seed_year(actor, year, acc)
      end)

    {:ok, summary}
  end

  defp seed_year(actor, year, acc) do
    case fetch_parameters(@default_jurisdiction, year) do
      {:ok, _existing} ->
        Map.update!(acc, :skipped, &(&1 + 1))

      {:error, :not_found} ->
        {:ok, _seeded} = insert_builtin_parameters(actor, year)
        Map.update!(acc, :inserted, &(&1 + 1))
    end
  end

  defp insert_builtin_parameters(actor, year) do
    changeset = Parameters.builtin_changeset(%Parameters{}, builtin_attrs(year))

    Multi.new()
    |> Multi.insert(:parameters, changeset,
      on_conflict: :nothing,
      conflict_target: [:jurisdiction, :tax_year]
    )
    |> Journal.record(actor,
      resource_type: "tax_parameters",
      operation: :create,
      source: :parameters
    )
    |> Repo.transaction()
    |> normalize(:parameters)
  end

  defp builtin_attrs(year) do
    {single, joint} = builtin_allowances(year)

    %{
      jurisdiction: @default_jurisdiction,
      tax_year: year,
      capital_gains_tax_rate: Decimal.new(@seed_capital_gains_tax_rate),
      solidarity_surcharge_rate: Decimal.new(@seed_solidarity_surcharge_rate),
      saver_allowance_single: single,
      saver_allowance_joint: joint,
      church_tax_rates: Enum.map(@seed_church_tax_rates, &Decimal.new/1)
    }
  end

  defp builtin_allowances(year) when year >= @seed_allowance_change_year,
    do: {Decimal.new("1000.00"), Decimal.new("2000.00")}

  defp builtin_allowances(_year), do: {Decimal.new("801.00"), Decimal.new("1602.00")}

  @doc """
  Removes the seeded rows, and only those: a parameter row the operator added
  survives the rollback.

  Referenced from the immutable migration `20260725140000_seed_tax_parameters`
  — keep this signature stable.
  """
  @spec rollback_builtin_parameters(Actor.t()) :: :ok
  def rollback_builtin_parameters(%Actor{} = actor) do
    Parameters
    |> where([p], p.built_in)
    |> Repo.all()
    |> Enum.each(fn parameters -> {:ok, _} = delete_parameters(actor, parameters) end)
  end

  defp delete_parameters(actor, %Parameters{} = parameters) do
    Multi.new()
    |> Multi.delete(:parameters, parameters)
    |> Journal.record(actor,
      resource_type: "tax_parameters",
      operation: :delete,
      source: :parameters,
      before: parameters
    )
    |> Repo.transaction()
    |> normalize(:parameters)
  end

  # -- profiles --------------------------------------------------------------

  @doc """
  The profile in force for `holder` on `on_date`: the row with the greatest
  `valid_from <= on_date`, or `nil` when none exists.

  Nearest-earlier-or-equal, **never an exact match** — a profile written on
  2020-03-01 governs 2024 until a newer row exists. This is the repo's
  `at_or_before` idiom (`Portfolixir.Fx`, `Portfolixir.Catalog.Quotes`), and it
  makes resolution a pure function of `(holder, on_date)`: adding a newer row
  cannot change what an earlier date resolves to.
  """
  @spec profile_in_force(String.t(), Date.t()) :: Profile.t() | nil
  def profile_in_force(holder, %Date{} = on_date) when is_binary(holder) do
    Profile
    |> for_holder(holder)
    |> where([p], p.valid_from <= ^on_date)
    |> order_by([p], desc: p.valid_from, desc: p.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc "Lists a holder's profiles, newest `valid_from` first."
  @spec list_profiles(String.t()) :: [Profile.t()]
  def list_profiles(holder) when is_binary(holder) do
    Profile
    |> for_holder(holder)
    |> order_by([p], desc: p.valid_from, desc: p.id)
    |> Repo.all()
  end

  @doc "Creates a taxpayer profile on behalf of `actor`."
  @spec create_profile(Actor.t(), map()) :: {:ok, Profile.t()} | {:error, Ecto.Changeset.t()}
  def create_profile(%Actor{} = actor, attrs) when is_map(attrs) do
    Multi.new()
    |> Multi.insert(:profile, Profile.changeset(%Profile{}, attrs))
    |> Journal.record(actor, resource_type: "tax_profile", operation: :create, source: :profile)
    |> Repo.transaction()
    |> normalize(:profile)
  end

  @doc "Updates a taxpayer profile on behalf of `actor`."
  @spec update_profile(Actor.t(), Profile.t(), map()) ::
          {:ok, Profile.t()} | {:error, Ecto.Changeset.t()}
  def update_profile(%Actor{} = actor, %Profile{} = profile, attrs) when is_map(attrs) do
    Multi.new()
    |> Multi.update(:profile, Profile.changeset(profile, attrs))
    |> Journal.record(actor,
      resource_type: "tax_profile",
      operation: :update,
      source: :profile,
      before: profile
    )
    |> Repo.transaction()
    |> normalize(:profile)
  end

  @doc "Deletes a taxpayer profile on behalf of `actor`."
  @spec delete_profile(Actor.t(), Profile.t() | integer()) ::
          {:ok, Profile.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def delete_profile(%Actor{} = actor, profile_or_id) do
    with {:ok, profile} <- fetch_one(Profile, profile_or_id) do
      Multi.new()
      |> Multi.delete(:profile, profile)
      |> Journal.record(actor,
        resource_type: "tax_profile",
        operation: :delete,
        source: :profile,
        before: profile
      )
      |> Repo.transaction()
      |> normalize(:profile)
    end
  end

  # -- allowance orders ------------------------------------------------------

  @doc """
  Lists allowance orders, newest tax year first. Filters (all optional and
  case-folded for the free-text ones): `:holder`, `:institution`, `:tax_year`.
  """
  @spec list_allowance_orders(keyword()) :: [AllowanceOrder.t()]
  def list_allowance_orders(opts \\ []) do
    AllowanceOrder
    |> filter_folded(:holder, opts[:holder])
    |> filter_folded(:institution, opts[:institution])
    |> filter_eq(:tax_year, opts[:tax_year])
    |> order_by([o], desc: o.tax_year, asc: o.id)
    |> Repo.all()
  end

  @doc """
  Records the instructed Freistellungsauftrag for a
  `(holder, institution, tax_year)` on behalf of `actor`, replacing the
  existing instruction for that triple.

  Identity is case-folded (§5a): re-recording `"Comdirect"` over `"comdirect"`
  updates the same order instead of creating a second one that story 19.4 would
  then cross-check against itself.
  """
  @spec put_allowance_order(Actor.t(), map()) ::
          {:ok, AllowanceOrder.t()} | {:error, Ecto.Changeset.t()}
  def put_allowance_order(%Actor{} = actor, attrs) when is_map(attrs) do
    fresh = AllowanceOrder.changeset(%AllowanceOrder{}, attrs)

    case existing_order(fresh) do
      nil -> insert_allowance_order(actor, fresh)
      existing -> update_allowance_order(actor, existing, attrs)
    end
  end

  defp existing_order(changeset) do
    holder = Ecto.Changeset.get_field(changeset, :holder)
    institution = Ecto.Changeset.get_field(changeset, :institution)
    tax_year = Ecto.Changeset.get_field(changeset, :tax_year)

    if is_binary(holder) and is_binary(institution) and is_integer(tax_year) do
      AllowanceOrder
      |> filter_folded(:holder, holder)
      |> filter_folded(:institution, institution)
      |> where([o], o.tax_year == ^tax_year)
      |> Repo.one()
    end
  end

  defp insert_allowance_order(actor, changeset) do
    Multi.new()
    |> Multi.insert(:order, changeset)
    |> Journal.record(actor,
      resource_type: "allowance_order",
      operation: :create,
      source: :order
    )
    |> Repo.transaction()
    |> normalize(:order)
  end

  defp update_allowance_order(actor, existing, attrs) do
    Multi.new()
    |> Multi.update(:order, AllowanceOrder.changeset(existing, attrs))
    |> Journal.record(actor,
      resource_type: "allowance_order",
      operation: :update,
      source: :order,
      before: existing
    )
    |> Repo.transaction()
    |> normalize(:order)
  end

  @doc "Deletes an allowance order on behalf of `actor`."
  @spec delete_allowance_order(Actor.t(), AllowanceOrder.t() | integer()) ::
          {:ok, AllowanceOrder.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def delete_allowance_order(%Actor{} = actor, order_or_id) do
    with {:ok, order} <- fetch_one(AllowanceOrder, order_or_id) do
      Multi.new()
      |> Multi.delete(:order, order)
      |> Journal.record(actor,
        resource_type: "allowance_order",
        operation: :delete,
        source: :order,
        before: order
      )
      |> Repo.transaction()
      |> normalize(:order)
    end
  end

  # -- statement snapshots ---------------------------------------------------

  @doc """
  Lists recorded statement snapshots, newest `as_of` first. Filters (all
  optional, case-folded for the free-text ones): `:holder`, `:institution`,
  `:tax_year`.
  """
  @spec list_snapshots(keyword()) :: [StatementSnapshot.t()]
  def list_snapshots(opts \\ []) do
    StatementSnapshot
    |> filter_folded(:holder, opts[:holder])
    |> filter_folded(:institution, opts[:institution])
    |> filter_eq(:tax_year, opts[:tax_year])
    |> order_by([s], desc: s.as_of, desc: s.id)
    |> Repo.all()
  end

  @doc "Fetches one snapshot, or `{:error, :not_found}`."
  @spec fetch_snapshot(StatementSnapshot.t() | integer()) ::
          {:ok, StatementSnapshot.t()} | {:error, :not_found}
  def fetch_snapshot(snapshot_or_id), do: fetch_one(StatementSnapshot, snapshot_or_id)

  @doc """
  The most recent statement recorded for an institution, holder and tax year,
  or `nil`. This is the row a trim budget is read off — story 19.6 states its
  `as_of` next to the number rather than presenting a bare balance.
  """
  @spec latest_snapshot(String.t(), String.t(), integer()) :: StatementSnapshot.t() | nil
  def latest_snapshot(institution, holder, tax_year) do
    StatementSnapshot
    |> filter_folded(:institution, institution)
    |> filter_folded(:holder, holder)
    |> where([s], s.tax_year == ^tax_year)
    |> order_by([s], desc: s.as_of, desc: s.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Records a statement snapshot on behalf of `actor`.

  `opts[:today]` injects the clock (AR-2) and defaults to `Date.utc_today/0`;
  an `as_of` after it is rejected. When the caller supplies no
  `church_tax_rate`, the holder's profile in force at `as_of` supplies it and
  the resolved value is then **frozen on the row** — a later profile edit
  changes future prefills, never a recorded transcription.
  """
  @spec create_snapshot(Actor.t(), map(), keyword()) ::
          {:ok, StatementSnapshot.t()} | {:error, Ecto.Changeset.t()}
  def create_snapshot(%Actor{} = actor, attrs, opts \\ []) when is_map(attrs) do
    today = Keyword.get(opts, :today, Date.utc_today())

    Multi.new()
    |> Multi.insert(:snapshot, snapshot_changeset(attrs, today))
    |> Journal.record(actor,
      resource_type: "tax_statement_snapshot",
      operation: :create,
      source: :snapshot
    )
    |> Repo.transaction()
    |> normalize(:snapshot)
  end

  @doc """
  Updates a recorded snapshot on behalf of `actor` — a corrected re-issue for
  the same statement date. The frozen `church_tax_rate` is not re-resolved.
  """
  @spec update_snapshot(Actor.t(), StatementSnapshot.t(), map(), keyword()) ::
          {:ok, StatementSnapshot.t()} | {:error, Ecto.Changeset.t()}
  def update_snapshot(%Actor{} = actor, %StatementSnapshot{} = snapshot, attrs, opts \\ [])
      when is_map(attrs) do
    today = Keyword.get(opts, :today, Date.utc_today())

    Multi.new()
    |> Multi.update(:snapshot, StatementSnapshot.changeset(snapshot, attrs, today))
    |> Journal.record(actor,
      resource_type: "tax_statement_snapshot",
      operation: :update,
      source: :snapshot,
      before: snapshot
    )
    |> Repo.transaction()
    |> normalize(:snapshot)
  end

  @doc "Deletes a recorded snapshot on behalf of `actor`."
  @spec delete_snapshot(Actor.t(), StatementSnapshot.t() | integer()) ::
          {:ok, StatementSnapshot.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def delete_snapshot(%Actor{} = actor, snapshot_or_id) do
    with {:ok, snapshot} <- fetch_one(StatementSnapshot, snapshot_or_id) do
      Multi.new()
      |> Multi.delete(:snapshot, snapshot)
      |> Journal.record(actor,
        resource_type: "tax_statement_snapshot",
        operation: :delete,
        source: :snapshot,
        before: snapshot
      )
      |> Repo.transaction()
      |> normalize(:snapshot)
    end
  end

  @doc """
  The advisory consistency findings for a recorded snapshot (ADR-0031 §4).

  This is the impure shell around the pure `Portfolixir.Tax.Consistency`
  engine: it gathers the year's statutory parameters, the earlier statements
  for the same identity, the configured allowance orders and the holder's
  assessment type, then hands them over. Findings are computed at read time and
  never stored, and they never block a write.
  """
  @spec findings_for(StatementSnapshot.t()) :: [Consistency.Finding.t()]
  def findings_for(%StatementSnapshot{} = snapshot) do
    Consistency.evaluate(snapshot, consistency_context(snapshot))
  end

  defp consistency_context(%StatementSnapshot{} = snapshot) do
    holder_orders = list_allowance_orders(holder: snapshot.holder, tax_year: snapshot.tax_year)

    %{
      parameters: parameters_for(snapshot),
      earlier_snapshots: earlier_snapshots(snapshot),
      allowance_order: Enum.find(holder_orders, &same_institution?(&1, snapshot)),
      holder_orders: holder_orders,
      assessment_type: assessment_type_for(snapshot)
    }
  end

  defp parameters_for(%StatementSnapshot{} = snapshot) do
    case fetch_parameters(@default_jurisdiction, snapshot.tax_year) do
      {:ok, parameters} -> parameters
      {:error, :not_found} -> nil
    end
  end

  defp earlier_snapshots(%StatementSnapshot{} = snapshot) do
    StatementSnapshot
    |> filter_folded(:institution, snapshot.institution)
    |> filter_folded(:holder, snapshot.holder)
    |> where([s], s.tax_year == ^snapshot.tax_year and s.as_of < ^snapshot.as_of)
    |> Repo.all()
  end

  defp same_institution?(order, snapshot) do
    Identity.fold(order.institution) == Identity.fold(snapshot.institution)
  end

  defp assessment_type_for(%StatementSnapshot{} = snapshot) do
    case profile_in_force(snapshot.holder, snapshot.as_of) do
      nil -> "single"
      profile -> profile.assessment_type
    end
  end

  @doc """
  Rolls every institution's latest statement up to one `(holder, tax_year)`
  view (ADR-0031 §5).

  The roll-up is only correct when a snapshot exists for every institution, so
  it reports which institutions it covers and marks itself incomplete when a
  configured allowance order has no matching snapshot for the year.
  """
  @spec holder_summary(String.t(), integer()) :: Budget.roll_up()
  def holder_summary(holder, tax_year) when is_binary(holder) do
    snapshots = list_snapshots(holder: holder, tax_year: tax_year)
    expected = list_allowance_orders(holder: holder, tax_year: tax_year)

    Budget.roll_up(
      snapshots,
      Enum.map(expected, & &1.institution),
      parameters_for_year(tax_year),
      assessment_type_at(holder, snapshots)
    )
  end

  defp parameters_for_year(tax_year) do
    case fetch_parameters(@default_jurisdiction, tax_year) do
      {:ok, parameters} -> parameters
      {:error, :not_found} -> nil
    end
  end

  defp assessment_type_at(_holder, []), do: "single"

  defp assessment_type_at(holder, [snapshot | _rest]) do
    case profile_in_force(holder, snapshot.as_of) do
      nil -> "single"
      profile -> profile.assessment_type
    end
  end

  # Two passes only when the caller supplied no rate: the first reads holder and
  # as_of back out of the cast, the second is built with the profile-resolved
  # rate injected, so the hard C2 rule validates against the rate the row will
  # actually carry. Re-casting rather than `put_change` keeps atom- and
  # string-keyed attrs both working.
  defp snapshot_changeset(attrs, today) do
    probe = StatementSnapshot.changeset(%StatementSnapshot{}, attrs, today)
    holder = Ecto.Changeset.get_field(probe, :holder)
    as_of = Ecto.Changeset.get_field(probe, :as_of)

    with nil <- Ecto.Changeset.get_change(probe, :church_tax_rate),
         true <- is_binary(holder) and match?(%Date{}, as_of),
         %Profile{} = profile <- profile_in_force(holder, as_of) do
      StatementSnapshot.changeset(%StatementSnapshot{}, attrs, today,
        default_church_tax_rate: profile.church_tax_rate
      )
    else
      _otherwise -> probe
    end
  end

  # -- internals -------------------------------------------------------------

  defp for_holder(query, holder) do
    where(query, [r], fragment("lower(?)", r.holder) == ^Identity.fold(holder))
  end

  defp filter_folded(query, _field, nil), do: query

  defp filter_folded(query, :holder, value),
    do: where(query, [r], fragment("lower(?)", r.holder) == ^Identity.fold(value))

  defp filter_folded(query, :institution, value),
    do: where(query, [r], fragment("lower(?)", r.institution) == ^Identity.fold(value))

  defp filter_eq(query, _field, nil), do: query
  defp filter_eq(query, field, value), do: where(query, [r], field(r, ^field) == ^value)

  defp fetch_one(_schema, %Profile{} = profile), do: {:ok, profile}
  defp fetch_one(_schema, %AllowanceOrder{} = order), do: {:ok, order}
  defp fetch_one(_schema, %StatementSnapshot{} = snapshot), do: {:ok, snapshot}

  defp fetch_one(schema, id) when is_integer(id) do
    case Repo.get(schema, id) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  defp normalize({:ok, changes}, step), do: {:ok, Map.fetch!(changes, step)}
  defp normalize({:error, step, changeset, _changes}, step), do: {:error, changeset}
end
