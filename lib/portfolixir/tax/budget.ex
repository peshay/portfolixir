defmodule Portfolixir.Tax.Budget do
  @moduledoc """
  The two figures derived from a recorded statement, and their roll-up across
  institutions (ADR-0031 §5). Pure — no Repo, no clock (the caller injects
  `today`), no config.

      allowance_remaining  = allowance_granted − allowance_used
      tax_free_trim_budget = loss_pot_equities + allowance_remaining

  `tax_free_trim_budget` is the number this feature exists for: the volume of
  realised **equity** gain still free of Kapitalertragsteuer at that
  institution. Two honesty rules bind its presentation, and both are encoded
  here rather than left to the caller:

  - it is always stated **with its `as_of` date**, and `stale?/2` marks it once
    a later day exists in which investment income can have landed — the
    allowance is consumed chronologically by dividends and interest, so the
    remaining allowance decays with no action by the maintainer;
  - it is a **decision input, never an instruction**. The ADR-0023 boundary
    holds unchanged: nothing here creates, stores or transmits an order.

  The roll-up is only correct when a snapshot exists for every institution, so
  it always reports which institutions it covers and is marked incomplete when
  a configured allowance order has no matching snapshot for the year.
  """

  alias Portfolixir.Tax.Parameters
  alias Portfolixir.Tax.StatementSnapshot

  @type roll_up :: %{
          holder: String.t(),
          tax_year: integer(),
          institutions: [String.t()],
          as_of: Date.t() | nil,
          loss_pot_equities: Decimal.t(),
          loss_pot_other: Decimal.t(),
          allowance_remaining: Decimal.t(),
          tax_free_trim_budget: Decimal.t(),
          allowance_ceiling: Decimal.t() | nil,
          complete?: boolean(),
          missing_institutions: [String.t()]
        }

  @doc "Allowance granted minus allowance used, for one recorded statement."
  @spec allowance_remaining(StatementSnapshot.t()) :: Decimal.t()
  def allowance_remaining(%StatementSnapshot{} = snapshot) do
    Decimal.sub(snapshot.allowance_granted, snapshot.allowance_used)
  end

  @doc """
  Unused equity-loss volume plus the remaining allowance: the realised equity
  gain still free of Kapitalertragsteuer at that institution, as of the
  statement's date.
  """
  @spec tax_free_trim_budget(StatementSnapshot.t()) :: Decimal.t()
  def tax_free_trim_budget(%StatementSnapshot{} = snapshot) do
    Decimal.add(snapshot.loss_pot_equities, allowance_remaining(snapshot))
  end

  @doc """
  Whether the budget derived from `snapshot` may already be out of date on
  `today` — true as soon as a later day exists, because dividends and interest
  consume the allowance chronologically without any action by the maintainer.
  """
  @spec stale?(StatementSnapshot.t(), Date.t()) :: boolean()
  def stale?(%StatementSnapshot{as_of: as_of}, %Date{} = today) do
    Date.compare(today, as_of) == :gt
  end

  @doc """
  Rolls the latest snapshot per institution up to one `(holder, tax_year)`
  view.

  `snapshots` may contain several as-ofs per institution; only the latest per
  institution is counted. `expected_institutions` are the institutions the
  holder has a configured allowance order for — an institution present there
  and missing from `snapshots` makes the roll-up incomplete, and it says so
  rather than quietly summing a partial picture.
  """
  @spec roll_up([StatementSnapshot.t()], [String.t()], Parameters.t() | nil, String.t()) ::
          roll_up()
  def roll_up(snapshots, expected_institutions, parameters, assessment_type) do
    latest = latest_per_institution(snapshots)
    covered = Enum.map(latest, & &1.institution)
    missing = missing_institutions(expected_institutions, covered)

    %{
      holder: holder_of(latest),
      tax_year: tax_year_of(latest),
      institutions: Enum.sort(covered),
      as_of: oldest_as_of(latest),
      loss_pot_equities: sum_field(latest, :loss_pot_equities),
      loss_pot_other: sum_field(latest, :loss_pot_other),
      allowance_remaining: sum_by(latest, &allowance_remaining/1),
      tax_free_trim_budget: sum_by(latest, &tax_free_trim_budget/1),
      allowance_ceiling: ceiling_for(parameters, assessment_type),
      complete?: missing == [],
      missing_institutions: missing
    }
  end

  defp latest_per_institution(snapshots) do
    snapshots
    |> Enum.group_by(&String.downcase(&1.institution))
    |> Enum.map(fn {_key, group} -> Enum.max_by(group, & &1.as_of, Date) end)
  end

  defp missing_institutions(expected, covered) do
    folded = MapSet.new(covered, &String.downcase/1)

    expected
    |> Enum.reject(&MapSet.member?(folded, String.downcase(&1)))
    |> Enum.sort()
  end

  # The roll-up is only as current as its oldest component: quoting the newest
  # as-of would overstate how fresh the summed number is.
  defp oldest_as_of([]), do: nil
  defp oldest_as_of(snapshots), do: snapshots |> Enum.map(& &1.as_of) |> Enum.min(Date)

  defp holder_of([]), do: nil
  defp holder_of([snapshot | _rest]), do: snapshot.holder

  defp tax_year_of([]), do: nil
  defp tax_year_of([snapshot | _rest]), do: snapshot.tax_year

  defp sum_field(snapshots, field), do: sum_by(snapshots, &Map.fetch!(&1, field))

  defp sum_by(snapshots, fun) do
    Enum.reduce(snapshots, Decimal.new(0), fn snapshot, acc ->
      Decimal.add(acc, fun.(snapshot))
    end)
  end

  defp ceiling_for(nil, _assessment_type), do: nil
  defp ceiling_for(%Parameters{} = parameters, "joint"), do: parameters.saver_allowance_joint
  defp ceiling_for(%Parameters{} = parameters, _single), do: parameters.saver_allowance_single
end
