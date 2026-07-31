defmodule Portfolixir.Tax.ConsistencyTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Tax.Consistency
  alias Portfolixir.Tax.Parameters
  alias Portfolixir.Tax.StatementSnapshot

  # User story (2026-07-25, ADR-0031, story 19.4):
  # As a local portfolio maintainer,
  # I want a transposed digit or a stale statement to surface when I record it,
  # so that a wrong number does not sit in the app looking correct.
  #
  # Acceptance criteria:
  # - The withheld KESt, Soli and KiSt are reconstructed via (e - 4q)/(4 + k),
  #   x 5.5 % and x k, with disagreement outside max(1.00, 0.05 %) reported.
  # - A later as-of reporting lower year-to-date withheld tax or allowance use
  #   raises the monotonicity advisory (C6).
  # - A recorded allowance_granted that disagrees with the configured
  #   allowance_orders row raises the instruction-vs-reality advisory (C7).
  # - Configured orders summing above the year's ceiling for the profile's
  #   assessment type raise the budget advisory (C8).
  # - No advisory blocks a save, and no advisory proposes a corrected value.
  # - The engine is pure: no Repo, no clock, no config (AR-2).

  defp parameters do
    %Parameters{
      jurisdiction: "DE",
      tax_year: 2025,
      capital_gains_tax_rate: Decimal.new("0.25"),
      solidarity_surcharge_rate: Decimal.new("0.055"),
      saver_allowance_single: Decimal.new("1000.00"),
      saver_allowance_joint: Decimal.new("2000.00")
    }
  end

  # The ADR's worked synthetic example: e = 11,000.00, q = 200.00, k = 0
  # → expected KESt = (11,000.00 − 800.00) / 4 = 2,550.00
  # → expected Soli = 2,550.00 × 5.5 %       =   140.25
  defp worked_snapshot(overrides \\ %{}) do
    struct(
      %StatementSnapshot{
        institution: "Example Bank",
        holder: "Owner",
        tax_year: 2025,
        as_of: ~D[2025-12-31],
        church_tax_rate: Decimal.new("0"),
        taxable_income: Decimal.new("12000.00"),
        allowance_granted: Decimal.new("1000.00"),
        allowance_used: Decimal.new("1000.00"),
        withholding_tax_credited: Decimal.new("200.00"),
        capital_gains_tax_withheld: Decimal.new("2550.00"),
        solidarity_surcharge_withheld: Decimal.new("140.25"),
        church_tax_withheld: Decimal.new("0"),
        loss_pot_equities: Decimal.new("0"),
        loss_pot_other: Decimal.new("0"),
        loss_carryforward_prior_years: Decimal.new("0"),
        withholding_tax_pot: Decimal.new("0")
      },
      overrides
    )
  end

  defp context(overrides \\ %{}) do
    Map.merge(
      %{
        parameters: parameters(),
        earlier_snapshots: [],
        allowance_order: nil,
        holder_orders: [],
        assessment_type: "single"
      },
      overrides
    )
  end

  test "a correctly transcribed statement produces no findings" do
    assert Consistency.evaluate(worked_snapshot(), context()) == []
  end

  test "the reconstruction follows the closed formula, church tax included" do
    # k = 0.09: e = 11,000.00, q = 200.00
    # expected KESt = (11,000.00 − 800.00) / 4.09 = 2,493.8875… → 2,493.89
    # expected KiSt = 2,493.89 × 0.09 = 224.45
    # expected Soli = 2,493.89 × 0.055 = 137.16
    snapshot =
      worked_snapshot(%{
        church_tax_rate: Decimal.new("0.09"),
        capital_gains_tax_withheld: Decimal.new("2493.89"),
        church_tax_withheld: Decimal.new("224.45"),
        solidarity_surcharge_withheld: Decimal.new("137.16")
      })

    assert Consistency.evaluate(snapshot, context()) == []
  end

  test "a transposed digit in the withheld tax is reported with both numbers and the gap" do
    snapshot = worked_snapshot(%{capital_gains_tax_withheld: Decimal.new("5250.00")})

    assert [finding] =
             snapshot |> Consistency.evaluate(context()) |> Enum.filter(&(&1.code == :c3))

    assert finding.severity == :advisory
    assert finding.field == :capital_gains_tax_withheld
    assert Decimal.equal?(finding.recorded, Decimal.new("5250.00"))
    assert Decimal.equal?(finding.expected, Decimal.new("2550.00"))
    assert Decimal.equal?(finding.gap, Decimal.new("2700.00"))
  end

  # Withholding is rounded to cents on every settlement, so a year of them
  # accumulates legitimate drift. The band absorbs that and still catches a
  # transposed digit.
  test "drift inside the tolerance band is not a finding, just outside it is" do
    inside = worked_snapshot(%{capital_gains_tax_withheld: Decimal.new("2550.99")})
    assert Consistency.evaluate(inside, context()) == []

    outside = worked_snapshot(%{capital_gains_tax_withheld: Decimal.new("2551.50")})
    assert [%{code: :c3}] = Consistency.evaluate(outside, context())
  end

  test "the band is the greater of 1.00 and 0.05 percent of the expected value" do
    # e = 103,000.00 − 1,000.00 = 102,000.00; q = 200.00
    # expected KESt = (102,000.00 − 800.00) / 4 = 25,300.00
    # 0.05 % of that is 12.65, which wins over the 1.00 floor.
    inside =
      worked_snapshot(%{
        taxable_income: Decimal.new("103000.00"),
        capital_gains_tax_withheld: Decimal.new("25310.00"),
        solidarity_surcharge_withheld: Decimal.new("1392.05")
      })

    assert Consistency.evaluate(inside, context()) == []

    outside = struct(inside, capital_gains_tax_withheld: Decimal.new("25315.00"))
    assert [%{code: :c3}] = Consistency.evaluate(outside, context())
  end

  test "a soli and a church-tax mismatch are reported separately" do
    snapshot =
      worked_snapshot(%{
        church_tax_rate: Decimal.new("0.09"),
        capital_gains_tax_withheld: Decimal.new("2493.89"),
        church_tax_withheld: Decimal.new("500.00"),
        solidarity_surcharge_withheld: Decimal.new("500.00")
      })

    codes = snapshot |> Consistency.evaluate(context()) |> Enum.map(& &1.code) |> Enum.sort()
    assert codes == [:c4, :c5]
  end

  # C6 — catches "recorded the wrong year's statement".
  test "a later as-of reporting lower year-to-date figures raises the monotonicity advisory" do
    earlier =
      worked_snapshot(%{
        as_of: ~D[2025-06-30],
        capital_gains_tax_withheld: Decimal.new("2550.00"),
        allowance_used: Decimal.new("1000.00")
      })

    later =
      worked_snapshot(%{
        as_of: ~D[2025-12-31],
        taxable_income: Decimal.new("6000.00"),
        allowance_used: Decimal.new("400.00"),
        withholding_tax_credited: Decimal.new("0"),
        capital_gains_tax_withheld: Decimal.new("1400.00"),
        solidarity_surcharge_withheld: Decimal.new("77.00")
      })

    findings = Consistency.evaluate(later, context(%{earlier_snapshots: [earlier]}))
    monotonicity = Enum.filter(findings, &(&1.code == :c6))

    assert Enum.map(monotonicity, & &1.field) |> Enum.sort() ==
             [:allowance_used, :capital_gains_tax_withheld]

    assert Enum.all?(monotonicity, &(&1.severity == :advisory))
  end

  test "an earlier as-of is not compared against a later one" do
    later = worked_snapshot(%{as_of: ~D[2025-12-31]})

    earlier =
      worked_snapshot(%{
        as_of: ~D[2025-06-30],
        taxable_income: Decimal.new("6000.00"),
        allowance_used: Decimal.new("1000.00"),
        withholding_tax_credited: Decimal.new("0"),
        capital_gains_tax_withheld: Decimal.new("1250.00"),
        solidarity_surcharge_withheld: Decimal.new("68.75")
      })

    assert Consistency.evaluate(earlier, context(%{earlier_snapshots: [later]})) == []
  end

  # C7 — the instruction never landed at the bank, or the configuration is stale.
  test "a recorded allowance that disagrees with the configured order is reported" do
    order = %{amount_granted: Decimal.new("801.00")}

    assert [finding] =
             worked_snapshot()
             |> Consistency.evaluate(context(%{allowance_order: order}))
             |> Enum.filter(&(&1.code == :c7))

    assert Decimal.equal?(finding.recorded, Decimal.new("1000.00"))
    assert Decimal.equal?(finding.expected, Decimal.new("801.00"))
    assert Decimal.equal?(finding.gap, Decimal.new("199.00"))
  end

  # Deliberate: no configured order is not a divergence. Orders are optional
  # configuration, and firing C7 on every snapshot recorded before the operator
  # configures them would train the advisory to be ignored.
  test "a snapshot with no configured order at all raises no instruction advisory" do
    findings = Consistency.evaluate(worked_snapshot(), context())
    assert Enum.filter(findings, &(&1.code == :c7)) == []
  end

  test "a matching configured order produces no finding" do
    order = %{amount_granted: Decimal.new("1000.00")}
    assert Consistency.evaluate(worked_snapshot(), context(%{allowance_order: order})) == []
  end

  # C8 — over-allocating across banks is the taxpayer's to correct with the
  # banks; the app states it, it does not fix it.
  test "configured orders above the year's ceiling raise the budget advisory" do
    orders = [
      %{amount_granted: Decimal.new("800.00")},
      %{amount_granted: Decimal.new("400.00")}
    ]

    findings =
      Consistency.evaluate(
        worked_snapshot(),
        context(%{
          allowance_order: %{amount_granted: Decimal.new("1000.00")},
          holder_orders: orders
        })
      )

    assert [finding] = Enum.filter(findings, &(&1.code == :c8))
    assert Decimal.equal?(finding.recorded, Decimal.new("1200.00"))
    assert Decimal.equal?(finding.expected, Decimal.new("1000.00"))
    assert Decimal.equal?(finding.gap, Decimal.new("200.00"))
  end

  test "the joint ceiling applies to a jointly assessed taxpayer" do
    orders = [
      %{amount_granted: Decimal.new("800.00")},
      %{amount_granted: Decimal.new("400.00")}
    ]

    findings =
      Consistency.evaluate(
        worked_snapshot(),
        context(%{
          allowance_order: %{amount_granted: Decimal.new("1000.00")},
          holder_orders: orders,
          assessment_type: "joint"
        })
      )

    assert Enum.filter(findings, &(&1.code == :c8)) == []
  end

  # AR-2: the engine takes the year's law as an argument and hardcodes nothing.
  test "without parameters the rate-dependent advisories are skipped, not guessed" do
    snapshot = worked_snapshot(%{solidarity_surcharge_withheld: Decimal.new("999.00")})

    # With the year's row present, the soli mismatch is a finding.
    assert [%{code: :c4}] = Consistency.evaluate(snapshot, context())

    # Without it, the soli check has no rate to work from and is skipped rather
    # than falling back to a hardcoded 5.5 % (AC-1 of story 19.2, AR-2).
    assert Consistency.evaluate(snapshot, context(%{parameters: nil})) == []
  end

  test "no finding proposes a corrected value" do
    snapshot = worked_snapshot(%{capital_gains_tax_withheld: Decimal.new("5250.00")})

    for finding <- Consistency.evaluate(snapshot, context()) do
      assert Map.keys(finding |> Map.from_struct()) |> Enum.sort() ==
               [:code, :expected, :field, :gap, :recorded, :severity]
    end
  end
end
