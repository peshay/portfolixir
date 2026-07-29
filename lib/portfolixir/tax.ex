defmodule Portfolixir.Tax do
  @moduledoc """
  Recorded tax-statement data and the configuration it is checked against
  (ADR-0031, FR-36).

  This story (19.2) ships the configuration layer only: year-scoped statutory
  `tax_parameters`, effective-dated `tax_profiles`, and configured
  `allowance_orders`. It ships **before** the snapshot table because checking a
  transcribed statement requires the law of its year — the Sparer-Pauschbetrag
  changed in 2023, so a hardcoded ceiling would flag every correct
  transcription of a pre-2023 statement as inconsistent.

  Two rules hold across the whole context:

  - **Writes are actor-first and journaled** (ADR-0017, FR-28). All three
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
  alias Portfolixir.Tax.Identity
  alias Portfolixir.Tax.Parameters
  alias Portfolixir.Tax.Profile

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

  defp fetch_one(schema, id) when is_integer(id) do
    case Repo.get(schema, id) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  defp normalize({:ok, changes}, step), do: {:ok, Map.fetch!(changes, step)}
  defp normalize({:error, step, changeset, _changes}, step), do: {:error, changeset}
end
