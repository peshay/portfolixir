defmodule Portfolixir.Tax.StalenessTest do
  # Issue #667: staleness as a function of activity, not only of the
  # calendar. The E19 surface marked every snapshot stale the day after its
  # as_of — technically true, useless as a warning. The staleness assessment
  # warns when the snapshot is older than the age threshold OR when
  # tax-relevant transactions were booked since it was taken — the second
  # condition is the substantive one.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Tax

  defp owner, do: Actor.owner_ui()

  defp seed_world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(owner(), %{name: "Tax world", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(owner(), %{
        portfolio_id: portfolio.id,
        name: "Tax Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(owner(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Tax Depot"
      })

    {:ok, security} =
      Catalog.create_security(owner(), %{name: "Taxed Equity", currency_code: "EUR"})

    %{portfolio: portfolio, cash: cash, depot: depot, security: security}
  end

  defp book!(world, type, date, extra \\ %{}) do
    base = %{
      portfolio_id: world.portfolio.id,
      cash_account_id: world.cash.id,
      type: type,
      date: date,
      gross_amount: "50.00",
      currency_code: "EUR"
    }

    {:ok, transaction} = Ledger.create_transaction(owner(), Map.merge(base, extra))
    transaction
  end

  # User story (issue #667):
  # As the operating LLM agent (and the operator reading the tax page),
  # I want the staleness of a recorded tax statement judged by age AND by
  # tax-relevant activity booked since its as_of,
  # so that a fresh statement is not flagged as noise and a statement
  # invalidated by yesterday's dividend is flagged immediately.
  #
  # Acceptance criteria:
  # - A recent as_of with no tax-relevant bookings since: no warning.
  # - A tax-relevant booking (dividend/interest/sell/tax/tax_refund) dated
  #   after as_of triggers the activity warning; a buy does not.
  # - An as_of older than the age threshold triggers the age warning even
  #   with no activity.
  # - The assessment states its own computation basis: the counted kinds,
  #   the window, the threshold, and that bookings are not attributed to an
  #   institution or tax year.
  test "no warning for a recent statement without tax-relevant activity" do
    world = seed_world()
    today = ~D[2026-08-14]
    as_of = ~D[2026-08-10]

    # A buy after as_of is not tax-relevant and must not trigger the warning.
    book!(world, "buy", ~D[2026-08-12], %{
      securities_account_id: world.depot.id,
      security_id: world.security.id,
      quantity: "1",
      price: "50.00",
      gross_amount: nil
    })

    staleness = Tax.staleness(as_of, today)

    assert staleness.age_days == 4
    assert staleness.age_warning == false
    assert staleness.activity_since_count == 0
    assert staleness.activity_warning == false
    assert staleness.warning == false
  end

  test "a tax-relevant booking after as_of triggers the activity warning" do
    world = seed_world()
    today = ~D[2026-08-14]
    as_of = ~D[2026-08-10]

    book!(world, "dividend", ~D[2026-08-12], %{security_id: world.security.id})
    book!(world, "tax_refund", ~D[2026-08-13])
    # On or before as_of: does not count (window is strictly after as_of).
    book!(world, "interest", ~D[2026-08-10])

    staleness = Tax.staleness(as_of, today)

    assert staleness.activity_since_count == 2
    assert staleness.activity_warning == true
    assert staleness.warning == true
    assert staleness.age_warning == false
  end

  test "an old statement warns by age alone" do
    _world = seed_world()
    today = ~D[2026-08-14]
    as_of = ~D[2025-12-31]

    staleness = Tax.staleness(as_of, today)

    assert staleness.age_days == Date.diff(today, as_of)
    assert staleness.age_warning == true
    assert staleness.activity_since_count == 0
    assert staleness.warning == true
  end

  test "the assessment states its computation basis" do
    staleness = Tax.staleness(~D[2026-08-10], ~D[2026-08-14])

    assert staleness.as_of == ~D[2026-08-10]
    assert staleness.today == ~D[2026-08-14]
    assert staleness.age_threshold_days == 90
    assert staleness.activity_kinds == ["sell", "dividend", "interest", "tax", "tax_refund"]
    assert staleness.basis =~ "strictly after"
    assert staleness.basis =~ "not attributed"
  end

  test "a nil as_of has no staleness assessment" do
    assert Tax.staleness(nil, ~D[2026-08-14]) == nil
  end
end
