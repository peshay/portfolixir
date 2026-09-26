defmodule PortfolixirWeb.ApiV1BoundedDatesTest do
  # E25 S4, F70 (#889): a cast date field accepted any year the cast could
  # build, and a year the database cannot hold faithfully reached storage
  # changed — which let a policy-rule version start before the day the
  # context allows. Every writer now meets one bounded date
  # (`Portfolixir.Input.BoundedDate`).
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Input.BoundedDate
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.PolicyRule
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Portfolios.Snapshot
  alias Portfolixir.Repo
  alias Portfolixir.Tax.StatementSnapshot

  # A date given as parts, with a year no calendar column holds faithfully.
  @far_parts %{"year" => 6_000_000, "month" => 1, "day" => 1}

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    world = base_world(name: "Bounded dates")
    security = create_security!(name: "Helios Solar Systems SE", ticker: "HSS")
    %{conn: conn, world: world, security: security}
  end

  defp version(security, overrides \\ %{}) do
    Map.merge(
      %{
        "subject_type" => "security",
        "security_id" => security.id,
        "measure" => "weight",
        "kind" => "cap",
        "threshold" => "10",
        "severity" => "hard"
      },
      overrides
    )
  end

  defp deposit(world, date) do
    %{
      "portfolio_id" => world.portfolio.id,
      "cash_account_id" => world.cash.id,
      "type" => "deposit",
      "date" => date,
      "gross_amount" => "100",
      "currency_code" => "EUR"
    }
  end

  defp out_of_range do
    [
      @far_parts,
      Date.to_iso8601(Date.add(BoundedDate.latest(), 1)),
      Date.to_iso8601(Date.add(BoundedDate.earliest(), -1)),
      "2026-01-01T00:00:00Z"
    ]
  end

  # User story:
  # As the operator's agent writing a dated record over the API,
  # I want a date outside the accepted range refused as a field error,
  # so that the date I sent is the one stored — and a policy rule can never
  # start on a day the rule's own check refuses.
  #
  # Acceptance criteria:
  # - A policy-rule create and a new version with an out-of-range valid_from
  #   answer 422 naming valid_from, and store no rule, no version and no
  #   journal entry.
  # - A transaction create and update with an out-of-range date answer 422
  #   naming date, and store nothing.
  # - A depot snapshot and a tax statement snapshot with an out-of-range
  #   as_of answer 422 naming as_of, and store nothing.
  test "an out-of-range date answers 422 on policy-rule, transaction and snapshot writes and stores nothing",
       %{conn: conn, world: world, security: security} do
    for date <- out_of_range() do
      body =
        conn
        |> post("/api/v1/portfolios/#{world.portfolio.id}/policy_rules", %{
          "rule" => %{
            "name" => "Cap",
            "version" => version(security, %{"valid_from" => date})
          }
        })
        |> json_response(422)

      assert inspect(body["errors"]) =~ "valid_from", "#{inspect(date)}: #{inspect(body)}"

      body =
        conn
        |> post("/api/v1/transactions", %{"transaction" => deposit(world, date)})
        |> json_response(422)

      assert Map.has_key?(body["errors"], "date"), "#{inspect(date)}: #{inspect(body)}"

      body =
        conn
        |> post("/api/v1/snapshots", %{"name" => "Year end", "as_of" => date})
        |> json_response(422)

      assert Map.has_key?(body["errors"], "as_of"), "#{inspect(date)}: #{inspect(body)}"

      body =
        conn
        |> post("/api/v1/tax/statement_snapshots", %{
          "statement_snapshot" => %{
            "institution" => "Example Bank",
            "holder" => "Owner",
            "tax_year" => 2025,
            "as_of" => date
          }
        })
        |> json_response(422)

      assert Map.has_key?(body["errors"], "as_of"), "#{inspect(date)}: #{inspect(body)}"
    end

    assert Repo.aggregate(PolicyRule, :count) == 0
    assert Repo.aggregate(Transaction, :count) == 0
    assert Repo.aggregate(Snapshot, :count) == 0
    assert Repo.aggregate(StatementSnapshot, :count) == 0
    assert Journal.list_entries(resource_type: "policy_rule") == []
    assert Journal.list_entries(resource_type: "transaction") == []
  end

  test "a new rule version and a transaction update refuse an out-of-range date too",
       %{conn: conn, world: world, security: security} do
    {:ok, rule} =
      PolicyRules.create_rule(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "Cap",
        version: version(security)
      })

    {:ok, booked} = Ledger.create_transaction(Actor.owner_ui(), deposit(world, "2026-01-02"))

    for date <- out_of_range() do
      conn
      |> post("/api/v1/policy_rules/#{rule.id}/versions", %{
        "version" => version(security, %{"valid_from" => date})
      })
      |> json_response(422)

      body =
        conn
        |> patch("/api/v1/transactions/#{booked.id}", %{"transaction" => %{"date" => date}})
        |> json_response(422)

      assert Map.has_key?(body["errors"], "date")
    end

    assert [_only_version] = PolicyRules.get_rule(rule.id).versions
    assert Repo.reload(booked).date == ~D[2026-01-02]
  end

  # Acceptance criteria:
  # - Every other writer of a date — research-log entries, security events,
  #   tax profiles, ISIN changes, quotes, splits and a rule's retirement —
  #   answers an out-of-range date with a 422, never a server error.
  test "every other dated writer answers an out-of-range date with a 422",
       %{conn: conn, world: world, security: security} do
    {:ok, isin_security} =
      Portfolixir.Catalog.create_security(Actor.owner_ui(), %{
        name: "Kestrel Industrial Group NV",
        currency_code: "EUR",
        isin: "NL0000000016"
      })

    {:ok, rule} =
      PolicyRules.create_rule(
        Actor.owner_ui(),
        %{
          portfolio_id: world.portfolio.id,
          name: "Cap",
          version: version(security, %{"valid_from" => Date.add(Portfolixir.Clock.today(), -3)})
        },
        today: Date.add(Portfolixir.Clock.today(), -3)
      )

    # A split needs a position held before its effective date.
    buy!(world, security, date: ~D[2026-01-01])

    writes = fn date, retire_date ->
      [
        {:post, "/api/v1/securities/#{security.id}/notes",
         %{
           "note" => %{
             "kind" => "evidence",
             "body" => "Order book grew.",
             "source_quality" => "primary",
             "source_url" => "https://example.com/report",
             "as_of" => date
           }
         }},
        {:post, "/api/v1/securities/#{security.id}/notes",
         %{
           "note" => %{
             "kind" => "evidence",
             "body" => "Order book grew.",
             "source_quality" => "primary",
             "source_url" => "https://example.com/report",
             "as_of" => "2026-01-02",
             "valid_until" => date
           }
         }},
        {:post, "/api/v1/securities/#{security.id}/events",
         %{
           "event" => %{
             "kind" => "earnings",
             "date" => date,
             "timing" => "exact",
             "source_quality" => "primary"
           }
         }},
        {:post, "/api/v1/securities/#{security.id}/events",
         %{
           "event" => %{
             "kind" => "earnings",
             "date" => "2026-01-02",
             "timing" => "exact",
             "source_quality" => "primary",
             "checked_at" => date
           }
         }},
        {:post, "/api/v1/tax/profiles",
         %{
           "profile" => %{
             "holder" => "Owner",
             "valid_from" => date,
             "assessment_type" => "single"
           }
         }},
        {:post, "/api/v1/securities/#{isin_security.id}/isin-change",
         %{"isin_change" => %{"new_isin" => "NL0000000024", "changed_on" => date}}},
        {:put, "/api/v1/securities/#{security.id}/quotes",
         %{"quotes" => [%{"date" => date, "close" => "10", "source" => "manual"}]}},
        {:post, "/api/v1/splits",
         %{
           "security_id" => security.id,
           "date" => date,
           "ratio_numerator" => 2,
           "ratio_denominator" => 1
         }},
        {:post, "/api/v1/policy_rules/#{rule.id}/retire", %{"valid_until" => retire_date}}
      ]
    end

    for date <- out_of_range(), {verb, path, body} <- writes.(date, date) do
      conn = Phoenix.ConnTest.dispatch(conn, @endpoint, verb, path, body)
      assert conn.status == 422, "#{verb} #{path} with #{inspect(date)}: #{conn.status}"
    end

    # The control: the same writes with a date inside the range succeed, so
    # the refusals above are the date's and nothing else's.
    for {verb, path, body} <- writes.("2026-01-02", Date.to_iso8601(Portfolixir.Clock.today())) do
      conn = Phoenix.ConnTest.dispatch(conn, @endpoint, verb, path, body)
      assert conn.status in 200..299, "#{verb} #{path}: #{conn.status} #{conn.resp_body}"
    end
  end

  # Acceptance criteria:
  # - A date on the range's edge is stored, answered and journaled as the
  #   same date.
  test "the stored row, the answer and the journal carry the same date", %{
    conn: conn,
    world: world
  } do
    edge = Date.to_iso8601(BoundedDate.earliest())

    %{"data" => created} =
      conn
      |> post("/api/v1/transactions", %{"transaction" => deposit(world, edge)})
      |> json_response(201)

    stored = Repo.get!(Transaction, created["id"])
    [entry] = Journal.list_entries(resource_type: "transaction")

    assert Date.to_iso8601(stored.date) == edge
    assert created["date"] == edge
    assert entry.after["date"] == edge
  end
end
