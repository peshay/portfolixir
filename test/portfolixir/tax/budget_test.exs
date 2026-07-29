defmodule Portfolixir.Tax.BudgetTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Tax
  alias Portfolixir.Tax.Budget

  # User story (2026-07-25, ADR-0031 §5, stories 19.4/19.5):
  # As a local portfolio maintainer,
  # I want the tax-free trim budget stated with its as-of date and its coverage,
  # so that I size a trim on a number whose age and completeness I can see.
  #
  # Acceptance criteria:
  # - allowance_remaining = granted - used; trim budget = equity loss pot +
  #   allowance_remaining.
  # - The figure is marked stale once a later day exists in which investment
  #   income can have landed.
  # - The roll-up states which institutions it covers and marks itself
  #   incomplete when a configured allowance order has no snapshot.
  # - Findings are computed at read time and never block a write.

  defp record(institution, overrides) do
    attrs =
      Map.merge(
        %{
          institution: institution,
          holder: "Owner",
          tax_year: 2025,
          as_of: ~D[2025-12-31],
          taxable_income: Decimal.new("0"),
          allowance_granted: Decimal.new("0"),
          allowance_used: Decimal.new("0"),
          loss_pot_equities: Decimal.new("0")
        },
        overrides
      )

    {:ok, snapshot} = Tax.create_snapshot(Actor.owner_ui(), attrs, today: ~D[2026-01-15])
    snapshot
  end

  test "the trim budget is the equity loss pot plus the remaining allowance" do
    snapshot =
      record("Example Bank", %{
        allowance_granted: Decimal.new("1000.00"),
        allowance_used: Decimal.new("400.00"),
        loss_pot_equities: Decimal.new("2500.00")
      })

    assert Decimal.equal?(Budget.allowance_remaining(snapshot), Decimal.new("600.00"))
    assert Decimal.equal?(Budget.tax_free_trim_budget(snapshot), Decimal.new("3100.00"))
  end

  # The allowance is consumed chronologically by dividends and interest, so it
  # decays with no action by the maintainer.
  test "the figure is stale as soon as a later day exists" do
    snapshot = record("Example Bank", %{})

    refute Budget.stale?(snapshot, ~D[2025-12-31])
    assert Budget.stale?(snapshot, ~D[2026-01-01])
  end

  test "the roll-up sums the latest statement per institution and names its coverage" do
    record("Bank A", %{
      as_of: ~D[2025-06-30],
      allowance_granted: Decimal.new("500.00"),
      loss_pot_equities: Decimal.new("100.00")
    })

    record("Bank A", %{
      as_of: ~D[2025-12-31],
      allowance_granted: Decimal.new("500.00"),
      allowance_used: Decimal.new("200.00"),
      loss_pot_equities: Decimal.new("1000.00")
    })

    record("Bank B", %{
      as_of: ~D[2025-11-30],
      allowance_granted: Decimal.new("500.00"),
      allowance_used: Decimal.new("500.00"),
      loss_pot_equities: Decimal.new("250.00")
    })

    summary = Tax.holder_summary("Owner", 2025)

    assert summary.institutions == ["Bank A", "Bank B"]
    # Only the latest per institution: Bank A's June row does not double-count.
    assert Decimal.equal?(summary.loss_pot_equities, Decimal.new("1250.00"))
    assert Decimal.equal?(summary.allowance_remaining, Decimal.new("300.00"))
    assert Decimal.equal?(summary.tax_free_trim_budget, Decimal.new("1550.00"))
    assert Decimal.equal?(summary.allowance_ceiling, Decimal.new("1000.00"))

    # As current as its OLDEST component, not its newest.
    assert summary.as_of == ~D[2025-11-30]
    assert summary.complete?
    assert summary.missing_institutions == []
  end

  test "a configured order without a snapshot marks the roll-up incomplete" do
    record("Bank A", %{loss_pot_equities: Decimal.new("1000.00")})

    {:ok, _order} =
      Tax.put_allowance_order(Actor.owner_ui(), %{
        holder: "Owner",
        institution: "Bank B",
        tax_year: 2025,
        amount_granted: Decimal.new("500.00")
      })

    summary = Tax.holder_summary("Owner", 2025)

    refute summary.complete?
    assert summary.missing_institutions == ["Bank B"]
  end

  test "an empty year rolls up to zero rather than to nothing" do
    summary = Tax.holder_summary("Owner", 2025)

    assert summary.institutions == []
    assert summary.as_of == nil
    assert Decimal.equal?(summary.tax_free_trim_budget, Decimal.new("0"))
    assert summary.complete?
  end

  test "findings are computed at read time and never block the write" do
    snapshot =
      record("Example Bank", %{
        taxable_income: Decimal.new("12000.00"),
        allowance_granted: Decimal.new("1000.00"),
        allowance_used: Decimal.new("1000.00"),
        capital_gains_tax_withheld: Decimal.new("5250.00"),
        solidarity_surcharge_withheld: Decimal.new("288.75")
      })

    # The write succeeded despite the mis-transcribed withholding.
    assert snapshot.id

    assert [finding] = Tax.findings_for(snapshot)
    assert finding.code == :c3
    assert finding.severity == :advisory
    assert Decimal.equal?(finding.expected, Decimal.new("2750.00"))
  end

  test "the instruction advisory compares against the configured order" do
    {:ok, _order} =
      Tax.put_allowance_order(Actor.owner_ui(), %{
        holder: "Owner",
        institution: "example bank",
        tax_year: 2025,
        amount_granted: Decimal.new("801.00")
      })

    snapshot = record("Example Bank", %{allowance_granted: Decimal.new("1000.00")})

    codes = snapshot |> Tax.findings_for() |> Enum.map(& &1.code)
    assert :c7 in codes
  end
end
