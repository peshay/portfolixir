defmodule PortfolixirWeb.ApiV1ListTruncationTest do
  # Issue #1254 (Sprint 22, A1): every capped list read under /api/v1 says
  # whether its cap cut rows. K17 gave the five delta reads `limit` and
  # `truncated`; the other capped reads answered a cut list with no flag, and
  # several did not echo the limit they applied, so an agent could not tell a
  # complete answer from a capped one. The sweep below covers every read that
  # applies a default or maximum row cap, the five delta reads included, so a
  # read added to the family without the fields fails here. Every name and
  # amount is synthetic.
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, buy!: 3, create_security!: 1, deposit!: 3, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Clock
  alias Portfolixir.Fx
  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Ledger
  alias Portfolixir.Lifecycle
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Portfolios.Snapshots

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    Map.put(seed!(), :conn, conn)
  end

  # User story:
  # As the operator whose agent reads lists over the API,
  # I want every capped list read to echo the limit it applied and say
  # whether that limit cut rows,
  # so that my agent never takes a capped answer for the whole one.
  #
  # Acceptance criteria:
  # - Every list read under /api/v1 that applies a default or maximum row cap
  #   carries `limit` (the cap it applied) and `truncated` (true when more
  #   rows matched than the answer holds), where the five delta reads carry
  #   them: at the top level beside `data` when `data` is the list, inside
  #   `data` when `data` is an object.
  # - A read whose cap cut rows answers truncated: true; one whose answer is
  #   whole answers truncated: false.
  # - A roll-up's cap is on the years of its annual matrix, and its
  #   `truncated` says whether years were left out.
  test "every capped list read echoes its limit and says when the cap cut rows", ctx do
    failures =
      for {path, place} <- ctx.reads,
          failure <- [
            check(ctx.conn, path, place, %{"limit" => "1"}, 1, true),
            check(ctx.conn, path, place, %{"limit" => "1000"}, 1000, false)
          ],
          failure != :ok,
          do: failure

    assert failures == []
  end

  test "a capped read without a limit echoes its default and says the answer is whole", ctx do
    failures =
      for {path, place} <- ctx.reads,
          failure = check(ctx.conn, path, place, %{}, :default, false),
          failure != :ok,
          do: failure

    assert failures == []
  end

  # The quote read's limit keeps the newest rows, ascending: the row a cut
  # leaves out is the oldest, never the newest.
  test "a cut quote read keeps the newest rows and leaves out the oldest", ctx do
    body =
      ctx.conn
      |> get("/api/v1/securities/#{ctx.held.id}/quotes", %{"limit" => "1"})
      |> json_response(200)

    assert %{"limit" => 1, "truncated" => true, "data" => [row]} = body
    assert row["date"] == "2026-01-06"
  end

  defp check(conn, path, place, params, expected_limit, expected_truncated) do
    body = conn |> get(path, params) |> json_response(200)
    holder = if place == :top, do: body, else: body["data"]
    limit = holder["limit"]
    truncated = Map.get(holder, "truncated", :missing)

    limit_ok =
      if expected_limit == :default, do: is_integer(limit), else: limit == expected_limit

    if limit_ok and truncated == expected_truncated do
      :ok
    else
      {path, params, place, %{"limit" => limit, "truncated" => truncated}}
    end
  end

  # At least two rows behind every capped read and far fewer than 1000, so
  # limit=1 cuts one and limit=1000 cuts none. Returns each read's path and
  # where its fields sit, and the security whose quotes are stored.
  defp seed! do
    world = base_world()
    today = Clock.today()
    traded = create_security!(name: "Traded Co", ticker: "TRD")
    held = create_security!(name: "Held Co", ticker: "HLD")
    noted = create_security!(name: "Noted Co", ticker: "NTD")

    # Two years of deposits, fees, closed trades: the three roll-ups.
    for year <- [2025, 2026] do
      deposit!(world, "1000", Date.new!(year, 1, 10))
      buy!(world, traded, quantity: "1", price: "100", fees: "1.50", date: Date.new!(year, 2, 1))
      sell!(world, traded, quantity: "1", price: "110", date: Date.new!(year, 3, 1))
    end

    # Two held positions with no research-log entry: the unreviewed queue.
    buy!(world, held, quantity: "1", price: "50", date: ~D[2026-04-01])
    buy!(world, traded, quantity: "1", price: "100", date: ~D[2026-04-01])

    # Two non-primary entries on an unheld security, each a dated block about
    # to lapse: a security's log, the uncorroborated and the expiring queues.
    for days <- [5, 12] do
      {:ok, _} =
        Knowledge.append_note(Actor.owner_ui(), %{
          security_id: noted.id,
          author: "agent",
          kind: "decision",
          body: "block for #{days} days",
          source_quality: "awareness",
          as_of: today,
          valid_until: Date.add(today, days)
        })
    end

    # Two past, unconfirmed, never-checked events and two due ones: a
    # security's events, the unconfirmed, stale and upcoming queues.
    for date <- [
          Date.add(today, -20),
          Date.add(today, -10),
          Date.add(today, 3),
          Date.add(today, 6)
        ] do
      {:ok, _} =
        Events.create_event(Actor.owner_ui(), %{
          security_id: held.id,
          kind: "earnings",
          date: date,
          timing: "estimated",
          source_quality: "awareness"
        })
    end

    # Two manual stretches split by a provider row, and three quotes.
    {:ok, 3} =
      Quotes.upsert_many(held.id, [
        %{date: ~D[2026-01-02], close: "10", source: "manual"},
        %{date: ~D[2026-01-05], close: "11", source: "portfolio_performance"},
        %{date: ~D[2026-01-06], close: "12", source: "manual"}
      ])

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-02-10],
          rate: "1.25",
          source: "manual"
        },
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-02-11],
          rate: "1.26",
          source: "manual"
        }
      ])

    for {name, date} <- [{"first", ~D[2026-01-05]}, {"second", ~D[2026-02-01]}] do
      {:ok, _} =
        Snapshots.create_snapshot(Actor.owner_ui(), %{name: name, as_of: date, view_id: nil})
    end

    for n <- 1..2 do
      {:ok, _} =
        PolicyRules.create_rule(
          Actor.owner_ui(),
          %{
            portfolio_id: world.portfolio.id,
            name: "Truncation cap #{n}",
            version: %{
              subject_type: "security",
              security_id: held.id,
              measure: "weight",
              kind: "cap",
              threshold: "50",
              severity: "hard"
            }
          },
          today: today
        )
    end

    two_merges!()

    reads = [
      {"/api/v1/transactions", :top},
      {"/api/v1/securities", :top},
      {"/api/v1/securities/#{noted.id}/notes", :data},
      {"/api/v1/securities/#{held.id}/events", :data},
      {"/api/v1/portfolios/#{world.portfolio.id}/policy_rules", :data},
      {"/api/v1/journal", :top},
      {"/api/v1/merges", :top},
      {"/api/v1/exchange_rates", :top},
      {"/api/v1/securities/#{held.id}/quotes", :top},
      {"/api/v1/securities/#{held.id}/quotes/manual", :data},
      {"/api/v1/snapshots", :data},
      {"/api/v1/realized_gains", :data},
      {"/api/v1/external_flows", :data},
      {"/api/v1/costs", :data},
      {"/api/v1/notes/unreviewed", :data},
      {"/api/v1/notes/uncorroborated", :data},
      {"/api/v1/notes/expiring", :data},
      {"/api/v1/events/upcoming", :data},
      {"/api/v1/events/unconfirmed", :data},
      {"/api/v1/events/stale", :data}
    ]

    %{reads: reads, held: held}
  end

  defp two_merges! do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Merged", base_currency_code: "EUR"})

    # Distinct bookings, so no merge meets a duplicate to choose about.
    [savings, old, older] =
      for {name, day} <- [{"Savings", 2}, {"Savings (old)", 3}, {"Savings (older)", 4}] do
        {:ok, cash} =
          Portfolios.create_cash_account(Actor.owner_ui(), %{
            portfolio_id: portfolio.id,
            name: name,
            currency_code: "EUR"
          })

        {:ok, _} =
          Ledger.create_transaction(Actor.owner_ui(), %{
            portfolio_id: portfolio.id,
            cash_account_id: cash.id,
            type: "deposit",
            date: Date.new!(2025, 1, day),
            gross_amount: "#{day}0.00",
            currency_code: "EUR"
          })

        cash
      end

    for {source, target} <- [{older, old}, {old, savings}] do
      {:ok, preview} = Lifecycle.preview_cash_merge(source.id, target.id)

      {:ok, _record, :applied} =
        Lifecycle.merge_cash_account(Actor.owner_ui(), source.id, target.id, %{
          plan_digest: preview.plan_digest
        })
    end
  end
end
