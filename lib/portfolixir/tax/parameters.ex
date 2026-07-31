defmodule Portfolixir.Tax.Parameters do
  @moduledoc """
  Year-scoped statutory tax parameters (ADR-0031 §3): the rates and
  Sparer-Pauschbetrag ceilings in force for one `(jurisdiction, tax_year)`.

  These are data, not constants, because the law is not constant — the
  Sparer-Pauschbetrag rose from 801/1602 € to 1000/2000 € in 2023. The
  consistency engine (story 19.4) takes the row for the statement's year as an
  argument and hardcodes nothing, so a correctly transcribed pre-2023 statement
  validates against the ceiling that actually applied to it.

  Rates are stored as fractions in `[0, 1)` — `0.25`, never `25`.

  `built_in` marks a row written by the seed migration. It is not castable from
  user input: an operator correcting a seeded year keeps the marker, so the
  rollback still recognises the row as one the seed put there.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @jurisdictions ~w(DE)
  @min_tax_year 1990
  @max_tax_year 2200

  schema "tax_parameters" do
    field(:jurisdiction, :string, default: "DE")
    field(:tax_year, :integer)
    field(:capital_gains_tax_rate, :decimal)
    field(:solidarity_surcharge_rate, :decimal)
    field(:saver_allowance_single, :decimal)
    field(:saver_allowance_joint, :decimal)
    field(:church_tax_rates, {:array, :decimal}, default: [])
    field(:built_in, :boolean, default: false)

    timestamps()
  end

  @doc """
  Builds a parameters changeset for an operator write. `built_in` stays out of
  the cast list on purpose — only the seed sets it.
  """
  def changeset(parameters, attrs) do
    parameters
    |> cast(attrs, [
      :jurisdiction,
      :tax_year,
      :capital_gains_tax_rate,
      :solidarity_surcharge_rate,
      :saver_allowance_single,
      :saver_allowance_joint,
      :church_tax_rates
    ])
    |> validate_common()
  end

  @doc """
  Builds a changeset for the seed migration, which is the only writer allowed
  to set the `built_in` marker.
  """
  def builtin_changeset(parameters, attrs) do
    parameters
    |> changeset(attrs)
    |> put_change(:built_in, true)
  end

  defp validate_common(changeset) do
    changeset
    |> validate_required([
      :jurisdiction,
      :tax_year,
      :capital_gains_tax_rate,
      :solidarity_surcharge_rate,
      :saver_allowance_single,
      :saver_allowance_joint
    ])
    |> validate_inclusion(:jurisdiction, @jurisdictions)
    |> validate_number(:tax_year,
      greater_than_or_equal_to: @min_tax_year,
      less_than_or_equal_to: @max_tax_year
    )
    |> validate_rate(:capital_gains_tax_rate)
    |> validate_rate(:solidarity_surcharge_rate)
    |> validate_non_negative(:saver_allowance_single)
    |> validate_non_negative(:saver_allowance_joint)
    |> validate_rate_list(:church_tax_rates)
    |> unique_constraint([:jurisdiction, :tax_year],
      name: :tax_parameters_jurisdiction_tax_year_index
    )
    |> check_constraint(:capital_gains_tax_rate, name: :tax_parameters_rates_check)
    |> check_constraint(:saver_allowance_single, name: :tax_parameters_allowances_check)
    |> check_constraint(:tax_year, name: :tax_parameters_tax_year_check)
    |> check_constraint(:jurisdiction, name: :tax_parameters_jurisdiction_check)
  end

  defp validate_rate(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if rate?(value),
        do: [],
        else: [{field, "must be a fraction between 0 and 1 (0.25, not 25)"}]
    end)
  end

  defp validate_rate_list(changeset, field) do
    validate_change(changeset, field, fn ^field, values ->
      if Enum.all?(values, &rate?/1),
        do: [],
        else: [{field, "must all be fractions between 0 and 1 (0.09, not 9)"}]
    end)
  end

  defp validate_non_negative(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if Decimal.compare(value, 0) == :lt, do: [{field, "must not be negative"}], else: []
    end)
  end

  defp rate?(%Decimal{} = value) do
    Decimal.compare(value, 0) != :lt and Decimal.compare(value, 1) == :lt
  end
end
