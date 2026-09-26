defmodule PortfolixirWeb.PerformanceOutOfRangeTest do
  # E25 S4, G12 (#889): a security's splits, stored before their product was
  # bounded, could scale a position past what the IRR solver's one float step
  # carries, and the conversion raised on every later performance read — on
  # Wealth that took the page down. The IRR is now absent with its reason,
  # and the page falls back to its failed-performance state instead of
  # matching on a summary it did not get.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  # Splits stored before the bound, the way such history looks: past the
  # booking flow, under the journal's actor.
  defp store_splits!(world, security, dates) do
    {type, _label} = Actor.to_columns(Actor.owner_ui())
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    rows =
      for date <- dates do
        %{
          type: "split",
          portfolio_id: world.portfolio.id,
          security_id: security.id,
          date: date,
          currency_code: security.currency_code,
          split_ratio_numerator: 2_147_483_647,
          split_ratio_denominator: 1,
          inserted_at: now,
          updated_at: now
        }
      end

    {:ok, _} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', $1, true)", [type])
        Repo.insert_all(Transaction, rows)
      end)
  end

  # User story:
  # As the operator whose stored history scales a position beyond what the
  # money-weighted return can be computed over,
  # I want Wealth to open with that figure absent,
  # so that one stored oddity does not take the page and every other figure
  # with it.
  #
  # Acceptance criteria:
  # - The page renders its performance figures after the walk lands.
  # - The money-weighted figure reads as absent ("—"), never a number.
  test "Wealth renders with the money-weighted figure absent over an out-of-range walk", %{
    conn: conn
  } do
    Classifications.ensure_builtins()
    world = base_world(name: "Range World")
    security = create_security!(name: "Range Holdings AG", ticker: "RHA")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2025-01-02])
    store_splits!(world, security, Enum.map(1..40, &Date.add(~D[2025-02-01], &1)))
    put_quote!(security, ~D[2025-04-01], "100")

    {:ok, view, _html} = live(conn, "/portfolio?period=max")
    html = render_async(view, 10_000)

    assert html =~ ~s(id="kpi-irr")
    assert has_element?(view, "#kpi-irr strong.stat-empty", "—")
    assert has_element?(view, ~s([data-role="period-badge"]))
  end
end
