defmodule Portfolixir.Tax.Consistency do
  @moduledoc """
  Read-time consistency checks for a recorded tax statement (ADR-0031 §4).

  The statement block is internally reconstructable, because withholding
  follows the closed formula of **§ 32d Abs. 1 EStG**:

      e = taxable_income − allowance_used     (assessment base after allowance)
      q = withholding_tax_credited            (creditable foreign withholding)
      k = church_tax_rate                     (0 when not liable — the default)
      s = solidarity_surcharge_rate           (from tax_parameters for the year)

      expected KESt = (e − 4q) / (4 + k)
      expected Soli = capital_gains_tax_withheld × s
      expected KiSt = capital_gains_tax_withheld × k

  `k` and `s` are **resolved, never hardcoded**: `k` from the snapshot's own
  frozen rate, `s` and the allowance ceilings from the `tax_parameters` row for
  the year. Without that row the rate-dependent checks are **skipped**, not
  guessed. The `4` is the statute's own algebra for the 25 % rate — a future
  change of the capital-gains rate means a new formula clause keyed to the
  year, decided by the ADR that changes it, not an edited constant.

  This module is a **pure engine** (AR-2): no Repo, no clock, no application
  config. Everything it needs arrives in the context map, and findings are
  computed at read time and never stored (the ADR-0012 precedent).

  **Advisories never block a save.** Teilfreistellung applied at source, a
  mid-year allowance change and broker-side corrections can all break the
  simple identity while the recorded numbers are perfectly correct. A finding
  states which two numbers disagree and by how much; it never proposes a
  "corrected" value, and it carries no prose — the display layer renders it, so
  the engine stays free of locale concerns.
  """

  alias Portfolixir.Tax.Consistency.Finding
  alias Portfolixir.Tax.Parameters
  alias Portfolixir.Tax.StatementSnapshot

  # Withholding is rounded to cents on every individual settlement, so a year's
  # worth legitimately accumulates a few cents of drift against a single
  # closed-form reconstruction. The band absorbs that and still catches a
  # transposed digit.
  @absolute_band Decimal.new("1.00")
  @relative_band Decimal.new("0.0005")

  @typedoc """
  Everything the engine needs, gathered by the caller:

    * `:parameters` — the `tax_parameters` row for the snapshot's year, or
      `nil` (rate-dependent checks are then skipped);
    * `:earlier_snapshots` — same institution/holder/year, any as-of;
    * `:allowance_order` — the configured order for the same triple, or `nil`;
    * `:holder_orders` — every configured order for `(holder, tax_year)`;
    * `:assessment_type` — `"single"` or `"joint"`, from the profile in force.
  """
  @type context :: %{
          required(:parameters) => Parameters.t() | nil,
          required(:earlier_snapshots) => [StatementSnapshot.t()],
          required(:allowance_order) => %{amount_granted: Decimal.t()} | nil,
          required(:holder_orders) => [%{amount_granted: Decimal.t()}],
          required(:assessment_type) => String.t()
        }

  @doc """
  Evaluates one snapshot against its context and returns the advisory findings,
  in rule order. An empty list means every check that could run, agreed.

  The hard rules C1 (`allowance_used <= allowance_granted`) and C2 (church tax
  withheld at a zero rate) are **not** here: they are changeset errors on
  `Portfolixir.Tax.StatementSnapshot`, because a save must not persist them at
  all.
  """
  @spec evaluate(StatementSnapshot.t(), context()) :: [Finding.t()]
  def evaluate(%StatementSnapshot{} = snapshot, context) do
    Enum.concat([
      withholding_findings(snapshot, context[:parameters]),
      monotonicity_findings(snapshot, context[:earlier_snapshots] || []),
      instruction_findings(snapshot, context[:allowance_order]),
      budget_findings(context)
    ])
  end

  @doc """
  The expected Kapitalertragsteuer for a snapshot, rounded to cents.

  Exposed because story 19.5 reports the reconstruction alongside the recorded
  figure, and story 19.6 shows both in the entry surface.
  """
  @spec expected_capital_gains_tax(StatementSnapshot.t()) :: Decimal.t()
  def expected_capital_gains_tax(%StatementSnapshot{} = snapshot) do
    base = Decimal.sub(snapshot.taxable_income, snapshot.allowance_used)
    credited = Decimal.mult(snapshot.withholding_tax_credited, 4)
    divisor = Decimal.add(4, snapshot.church_tax_rate)

    base
    |> Decimal.sub(credited)
    |> Decimal.div(divisor)
    |> at_least_zero()
    |> cents()
  end

  # -- C3/C4/C5 — the § 32d reconstruction -----------------------------------

  defp withholding_findings(snapshot, parameters) do
    expected_kest = expected_capital_gains_tax(snapshot)

    [
      compare(
        :c3,
        :capital_gains_tax_withheld,
        snapshot.capital_gains_tax_withheld,
        expected_kest
      ),
      soli_finding(snapshot, parameters),
      church_tax_finding(snapshot)
    ]
    |> Enum.reject(&is_nil/1)
  end

  # Skipped without the year's row: the rate is data, and falling back to a
  # hardcoded 5.5 % is exactly what story 19.2 exists to prevent.
  defp soli_finding(_snapshot, nil), do: nil

  defp soli_finding(snapshot, %Parameters{} = parameters) do
    expected =
      cents(
        Decimal.mult(snapshot.capital_gains_tax_withheld, parameters.solidarity_surcharge_rate)
      )

    compare(:c4, :solidarity_surcharge_withheld, snapshot.solidarity_surcharge_withheld, expected)
  end

  defp church_tax_finding(snapshot) do
    expected = cents(Decimal.mult(snapshot.capital_gains_tax_withheld, snapshot.church_tax_rate))

    compare(:c5, :church_tax_withheld, snapshot.church_tax_withheld, expected)
  end

  # -- C6 — year-to-date monotonicity ----------------------------------------

  defp monotonicity_findings(snapshot, earlier_snapshots) do
    earlier = Enum.filter(earlier_snapshots, &(Date.compare(&1.as_of, snapshot.as_of) == :lt))

    Enum.flat_map([:capital_gains_tax_withheld, :allowance_used], fn field ->
      case highest(earlier, field) do
        nil -> []
        peak -> monotonicity_finding(field, Map.fetch!(snapshot, field), peak)
      end
    end)
  end

  defp monotonicity_finding(field, recorded, peak) do
    if Decimal.compare(recorded, peak) == :lt do
      [Finding.new(:c6, field, recorded, peak)]
    else
      []
    end
  end

  defp highest([], _field), do: nil

  defp highest(snapshots, field) do
    snapshots |> Enum.map(&Map.fetch!(&1, field)) |> Enum.max(Decimal)
  end

  # -- C7 — instruction vs. reality ------------------------------------------

  # No configured order is not a divergence: orders are optional configuration,
  # and firing on every snapshot recorded before they exist would train the
  # advisory to be ignored.
  defp instruction_findings(_snapshot, nil), do: []

  defp instruction_findings(snapshot, %{amount_granted: granted}) do
    if Decimal.equal?(snapshot.allowance_granted, granted) do
      []
    else
      [Finding.new(:c7, :allowance_granted, snapshot.allowance_granted, granted)]
    end
  end

  # -- C8 — allowance budget across institutions -----------------------------

  defp budget_findings(%{parameters: %Parameters{} = parameters} = context) do
    orders = context[:holder_orders] || []
    instructed = orders |> Enum.map(& &1.amount_granted) |> sum()
    ceiling = ceiling_for(parameters, context[:assessment_type])

    if Decimal.compare(instructed, ceiling) == :gt do
      [Finding.new(:c8, :allowance_granted, instructed, ceiling)]
    else
      []
    end
  end

  defp budget_findings(_context), do: []

  defp ceiling_for(%Parameters{} = parameters, "joint"), do: parameters.saver_allowance_joint
  defp ceiling_for(%Parameters{} = parameters, _single), do: parameters.saver_allowance_single

  # -- shared ----------------------------------------------------------------

  defp compare(code, field, recorded, expected) do
    if within_band?(recorded, expected) do
      nil
    else
      Finding.new(code, field, recorded, expected)
    end
  end

  defp within_band?(recorded, expected) do
    gap = recorded |> Decimal.sub(expected) |> Decimal.abs()

    Decimal.compare(gap, band(expected)) != :gt
  end

  defp band(expected) do
    relative = expected |> Decimal.abs() |> Decimal.mult(@relative_band)

    Enum.max([@absolute_band, relative], Decimal)
  end

  defp sum(values), do: Enum.reduce(values, Decimal.new(0), &Decimal.add/2)

  defp cents(value), do: Decimal.round(value, 2)

  defp at_least_zero(value) do
    # A credited foreign withholding larger than the assessment base leaves
    # nothing to withhold. Reporting a negative expectation would produce a
    # finding about an impossible number rather than about the transcription.
    if Decimal.compare(value, 0) == :lt, do: Decimal.new(0), else: value
  end
end
