defmodule PortfolixirWeb.ApiV1DeltaReadsTest do
  # FR-38 / issue #666: `?since=` delta reads on the two recurring-sync
  # reads (transactions and securities), so an agent's recurring run fetches
  # what changed instead of pulling the full state and diffing it against a
  # local copy. The push half stays gated at B3.7 — that boundary is pinned
  # here as its own acceptance criterion.
  #
  # Issue #830 (Sprint 14, D-5) extends it to the rest of the row-collection
  # family a scheduled run polls — a security's research log and events, the
  # category and position target reads — and pins the time-derived queues
  # that deliberately do NOT honour it.
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures
  alias PortfolixirWeb.Api.V1.SinceParam

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp owner, do: Portfolixir.Actor.owner_ui()

  defp seed_world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(owner(), %{name: "Delta", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(owner(), %{
        portfolio_id: portfolio.id,
        name: "Delta Cash",
        currency_code: "EUR"
      })

    %{portfolio: portfolio, cash: cash}
  end

  defp create_deposit!(world, date) do
    {:ok, transaction} =
      Ledger.create_transaction(owner(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        type: "deposit",
        date: date,
        gross_amount: "100.00",
        currency_code: "EUR"
      })

    transaction
  end

  # Test-only clock control: backdate a row's updated_at so the delta cut
  # has something on both sides. The journal guard requires an actor for any
  # write, so the transaction-local actor is set first (sandbox-scoped).
  defp backdate!(table, id, naive)
       when table in [
              "transactions",
              "securities",
              "security_events",
              "portfolio_targets",
              "portfolio_target_plans"
            ] do
    Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test_backdate', true)")
    Repo.query!("UPDATE #{table} SET updated_at = $1 WHERE id = $2", [naive, id])
  end

  # User story (FR-38, issue #666):
  # As the operating LLM agent on a recurring run,
  # I want `?since=<ISO8601>` on the transactions read,
  # so that I fetch the rows created or updated since my last run instead of
  # pulling the whole ledger and diffing it locally.
  #
  # Acceptance criteria:
  # - Only rows with updated_at strictly after `since` (UTC) return.
  # - The response echoes `since`, carries `as_of` (the read instant, usable
  #   as the next `since`) and a `delta_note` stating the semantics —
  #   including that deletions are NOT represented (a caller that must
  #   detect deletions performs a full read).
  # - An invalid `since` is a 422; the plain read is unchanged.
  test "transactions ?since= returns only rows changed after the cut", %{conn: conn} do
    world = seed_world()
    old = create_deposit!(world, ~D[2026-01-02])
    new = create_deposit!(world, ~D[2026-01-03])
    backdate!("transactions", old.id, ~N[2026-01-02 08:00:00])

    response =
      conn
      |> api_conn()
      |> get("/api/v1/transactions?since=2026-06-01T00:00:00Z")
      |> json_response(200)

    assert Enum.map(response["data"], & &1["id"]) == [new.id]
    assert response["since"] == "2026-06-01T00:00:00Z"
    assert is_binary(response["as_of"])
    assert response["delta_note"] =~ "Deletions are not represented"

    # The plain read is unchanged: both rows, no delta envelope.
    plain = conn |> api_conn() |> get("/api/v1/transactions") |> json_response(200)
    assert length(plain["data"]) == 2
    refute Map.has_key?(plain, "delta_note")

    assert conn
           |> api_conn()
           |> get("/api/v1/transactions?since=yesterdayish")
           |> json_response(422)
  end

  test "transactions ?since= composes with fields= and accepts a plain date", %{conn: conn} do
    world = seed_world()
    old = create_deposit!(world, ~D[2026-01-02])
    _new = create_deposit!(world, ~D[2026-01-03])
    backdate!("transactions", old.id, ~N[2026-01-02 08:00:00])

    response =
      conn
      |> api_conn()
      |> get("/api/v1/transactions?since=2026-06-01&fields=id,type")
      |> json_response(200)

    assert [row] = response["data"]
    assert Map.keys(row) |> Enum.sort() == ["id", "type"]
  end

  # User story (FR-38, issue #666):
  # As the operating LLM agent keeping a catalog state file,
  # I want `?since=` on the securities read,
  # so that a recurring catalog sync transfers only what changed.
  #
  # Acceptance criteria:
  # - Only securities with updated_at strictly after `since` return.
  # - The delta envelope (since / as_of / delta_note) travels with it.
  # - An invalid `since` is a 422.
  test "securities ?since= returns only rows changed after the cut", %{conn: conn} do
    {:ok, old} =
      Catalog.create_security(owner(), %{name: "Old Equity", currency_code: "EUR"})

    {:ok, new} =
      Catalog.create_security(owner(), %{name: "New Equity", currency_code: "EUR"})

    backdate!("securities", old.id, ~N[2026-01-02 08:00:00])

    response =
      conn
      |> api_conn()
      |> get("/api/v1/securities?since=2026-06-01T00:00:00Z")
      |> json_response(200)

    assert Enum.map(response["data"], & &1["id"]) == [new.id]
    assert response["since"] == "2026-06-01T00:00:00Z"
    assert is_binary(response["as_of"])
    assert response["delta_note"] =~ "Deletions are not represented"

    assert conn
           |> api_conn()
           |> get("/api/v1/securities?since=not-a-time")
           |> json_response(422)
  end

  # -- #830 (Sprint 14, D-5): the rest of the row-collection family ----------

  # The research log is append-only (a trigger forbids UPDATE), so a note
  # cannot be backdated after the fact; a test-only raw INSERT writes it with
  # an explicit inserted_at instead, under the journal actor the guard needs.
  defp insert_old_note!(security, inserted_at) do
    Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test_backdate', true)")

    %{rows: [[id]]} =
      Repo.query!(
        "INSERT INTO security_notes (security_id, author, kind, body, source_quality, as_of, inserted_at) " <>
          "VALUES ($1, 'agent', 'evidence', 'old finding', 'primary', '2026-01-01', $2) RETURNING id",
        [security.id, inserted_at]
      )

    id
  end

  defp append_note!(security, attrs) do
    {:ok, note} =
      Knowledge.append_note(
        Actor.owner_ui(),
        Map.merge(
          %{
            security_id: security.id,
            author: "agent",
            kind: "evidence",
            body: "new finding",
            source_quality: "primary",
            as_of: ~D[2026-08-01]
          },
          attrs
        )
      )

    note
  end

  defp event!(security, attrs) do
    {:ok, event} =
      Events.create_event(
        Actor.owner_ui(),
        Enum.into(attrs, %{
          security_id: security.id,
          kind: "earnings",
          date: ~D[2026-11-04],
          timing: "exact",
          source_quality: "primary"
        })
      )

    event
  end

  defp target_world do
    world = WorldFixtures.base_world()

    {:ok, classification} =
      Classifications.create_classification(owner(), %{name: "Delta Strategy"})

    {:ok, core} =
      Classifications.create_category(owner(), %{
        classification_id: classification.id,
        name: "Core"
      })

    {:ok, satellite} =
      Classifications.create_category(owner(), %{
        classification_id: classification.id,
        name: "Satellite"
      })

    one = WorldFixtures.create_security!(name: "Delta One", ticker: "DONE")
    two = WorldFixtures.create_security!(name: "Delta Two", ticker: "DTWO")

    {:ok, _} = Classifications.assign_security(owner(), one.id, classification.id, core.id)
    {:ok, _} = Classifications.assign_security(owner(), two.id, classification.id, core.id)

    Map.merge(world, %{
      classification: classification,
      core: core,
      satellite: satellite,
      one: one,
      two: two
    })
  end

  defp active_plan!(portfolio_id) do
    portfolio_id |> Targets.list_plans() |> Enum.find(&(&1.status == "active"))
  end

  # User story (FR-38, issue #830, D-5):
  # As the operating LLM agent on a scheduled run,
  # I want `?since=` on the per-security research-log read,
  # so that my run fetches the entries appended since the last run instead of
  # re-reading a log that only ever grows.
  #
  # Acceptance criteria:
  # - Only entries inserted strictly after `since` return (the log is
  #   append-only, so inserted_at is when an entry last changed).
  # - The delta envelope (since / as_of / delta_note) travels at the top
  #   level, as on the transactions and securities reads.
  # - thesis_state still derives from the WHOLE log, not the delta.
  # - An invalid `since` is a 422; the plain read is unchanged.
  test "notes ?since= returns only entries appended after the cut", %{conn: conn} do
    security = WorldFixtures.create_security!(name: "Delta Notes", ticker: "DNOT")
    old_id = insert_old_note!(security, ~N[2026-01-02 08:00:00])
    thesis = append_note!(security, %{kind: "thesis", body: "holds", conviction: "high"})

    response =
      conn
      |> api_conn()
      |> get("/api/v1/securities/#{security.id}/notes?since=2026-06-01T00:00:00Z")
      |> json_response(200)

    assert Enum.map(response["data"]["entries"], & &1["id"]) == [thesis.id]
    assert response["since"] == "2026-06-01T00:00:00Z"
    assert is_binary(response["as_of"])
    assert response["delta_note"] =~ "inserted_at"
    assert response["delta_note"] =~ "append-only"
    assert response["data"]["thesis_state"]["derived_from_entry_id"] == thesis.id

    plain =
      conn
      |> api_conn()
      |> get("/api/v1/securities/#{security.id}/notes")
      |> json_response(200)

    assert plain["data"]["entries"] |> Enum.map(& &1["id"]) |> Enum.sort() ==
             Enum.sort([old_id, thesis.id])

    refute Map.has_key?(plain, "delta_note")

    assert conn
           |> api_conn()
           |> get("/api/v1/securities/#{security.id}/notes?since=soon")
           |> json_response(422)
  end

  # User story (FR-38, issue #830, D-5):
  # As the operating LLM agent keeping a calendar state file,
  # I want `?since=` on the per-security events read,
  # so that a rescheduled date reaches my run as one changed row.
  #
  # Acceptance criteria:
  # - Only events with updated_at strictly after `since` return — a PATCH on
  #   an old row brings it back into the delta.
  # - The delta envelope travels with it, deletions stated as not represented.
  # - An invalid `since` is a 422.
  test "events ?since= returns only rows created or updated after the cut", %{conn: conn} do
    security = WorldFixtures.create_security!(name: "Delta Cal", ticker: "DCAL")
    old = event!(security, date: ~D[2026-10-01])
    touched = event!(security, date: ~D[2026-10-02])
    new = event!(security, date: ~D[2026-10-03])
    backdate!("security_events", old.id, ~N[2026-01-02 08:00:00])
    backdate!("security_events", touched.id, ~N[2026-01-02 08:00:00])

    {:ok, _} =
      Events.update_event(owner(), Events.get_event(touched.id), %{date: ~D[2026-10-05]})

    response =
      conn
      |> api_conn()
      |> get("/api/v1/securities/#{security.id}/events?since=2026-06-01T00:00:00Z")
      |> json_response(200)

    assert response["data"]["events"] |> Enum.map(& &1["id"]) |> Enum.sort() ==
             Enum.sort([touched.id, new.id])

    assert response["since"] == "2026-06-01T00:00:00Z"
    assert is_binary(response["as_of"])
    assert response["delta_note"] =~ "Deletions are not represented"

    plain =
      conn |> api_conn() |> get("/api/v1/securities/#{security.id}/events") |> json_response(200)

    assert length(plain["data"]["events"]) == 3
    refute Map.has_key?(plain, "delta_note")

    assert conn
           |> api_conn()
           |> get("/api/v1/securities/#{security.id}/events?since=nope")
           |> json_response(422)
  end

  # User story (FR-38, issue #830, D-5):
  # As the operating LLM agent on a scheduled drift check,
  # I want `?since=` on the category and position target reads,
  # so that a run notices a changed target weight without diffing the plan.
  #
  # Acceptance criteria:
  # - Only target rows changed strictly after `since` return, on both reads.
  # - A row whose PLAN changed after the cut also returns: activating another
  #   plan version swaps the steering rows without touching any of them, and
  #   a row-only cut would hide exactly that change.
  # - The position read's effective roll-up still covers the whole plan.
  # - An invalid `since` is a 422 on both reads.
  test "targets ?since= returns only rows changed after the cut", %{conn: conn} do
    world = target_world()
    pid = world.portfolio.id

    {:ok, rows} =
      Targets.set_targets(owner(), pid, world.classification.id, [
        %{"category_id" => world.core.id, "target_weight" => "0.6"},
        %{"category_id" => world.satellite.id, "target_weight" => "0.4"},
        %{
          "category_id" => world.core.id,
          "security_id" => world.one.id,
          "target_weight" => "0.3"
        }
      ])

    backdate!("portfolio_target_plans", active_plan!(pid).id, ~N[2026-01-02 08:00:00])
    for row <- rows, do: backdate!("portfolio_targets", row.id, ~N[2026-01-02 08:00:00])

    {:ok, _} =
      Targets.set_targets(owner(), pid, world.classification.id, [
        %{"category_id" => world.core.id, "target_weight" => "0.7"},
        %{
          "category_id" => world.core.id,
          "security_id" => world.two.id,
          "target_weight" => "0.2"
        }
      ])

    targets =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{pid}/targets?since=2026-06-01T00:00:00Z")
      |> json_response(200)

    assert [%{"category_id" => core_id, "target_weight" => "0.7"}] =
             targets["data"]["targets"]

    assert core_id == world.core.id
    assert targets["since"] == "2026-06-01T00:00:00Z"
    assert targets["delta_note"] =~ "plan"

    positions =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{pid}/position_targets?since=2026-06-01T00:00:00Z")
      |> json_response(200)

    assert [%{"security_id" => two_id}] = positions["data"]["position_targets"]
    assert two_id == world.two.id
    assert is_binary(positions["as_of"])

    # The roll-up is derived from the whole plan, not from the delta.
    assert [%{"position_sum" => "0.5"}] = positions["data"]["effective_targets"]

    plain = conn |> api_conn() |> get("/api/v1/portfolios/#{pid}/targets") |> json_response(200)
    assert length(plain["data"]["targets"]) == 2
    refute Map.has_key?(plain, "delta_note")

    for path <- ["targets", "position_targets"] do
      assert conn
             |> api_conn()
             |> get("/api/v1/portfolios/#{pid}/#{path}?since=later")
             |> json_response(422)
    end
  end

  test "targets ?since= returns the rows a plan activation swapped in", %{conn: conn} do
    world = target_world()
    pid = world.portfolio.id

    {:ok, _rows} =
      Targets.set_targets(owner(), pid, world.classification.id, [
        %{"category_id" => world.core.id, "target_weight" => "0.6"}
      ])

    active = active_plan!(pid)
    {:ok, draft} = Targets.duplicate_plan(owner(), active, %{name: "Draft"})

    {:ok, _rows} =
      Targets.set_targets(
        owner(),
        pid,
        world.classification.id,
        [%{"category_id" => world.core.id, "target_weight" => "0.9"}],
        plan: draft.id
      )

    # Everything — both plans and all their rows — last changed long ago.
    for plan <- [active, draft] do
      backdate!("portfolio_target_plans", plan.id, ~N[2026-01-02 08:00:00])

      for row <- Targets.list_targets(pid, plan: plan.id),
          do: backdate!("portfolio_targets", row.id, ~N[2026-01-02 08:00:00])
    end

    # The activation touches the plans, never a target row.
    {:ok, _} = Targets.activate_plan(owner(), draft.id)

    response =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{pid}/targets?since=2026-06-01T00:00:00Z")
      |> json_response(200)

    assert [%{"category_id" => core_id, "target_weight" => "0.9"}] =
             response["data"]["targets"]

    assert core_id == world.core.id
  end

  # User story (FR-38, issue #830, D-5 — the shape that must NOT carry it):
  # As the operating LLM agent polling the review and calendar queues,
  # I want the time-derived queues to keep answering in full whatever
  # `since` I send,
  # so that a note that became unreviewed overnight, or a date that entered
  # the horizon, is never dropped because no row changed.
  #
  # Acceptance criteria:
  # - /notes/unreviewed, /notes/expiring, /notes/uncorroborated,
  #   /events/upcoming, /events/stale and /events/unconfirmed IGNORE `since`
  #   the way the API ignores every parameter a read does not define: the
  #   answer is the full queue, with no delta envelope, and a malformed
  #   `since` is not a 422 there.
  test "the time-derived queues do not honour since", %{conn: conn} do
    world = WorldFixtures.base_world()
    security = WorldFixtures.create_security!(name: "Queue Co", ticker: "QUEU")
    WorldFixtures.buy!(world, security, quantity: "1", price: "10")
    today = Portfolixir.Clock.today()

    append_note!(security, %{as_of: Date.add(today, -200), source_quality: "awareness"})

    append_note!(security, %{
      kind: "decision",
      body: "no adds",
      as_of: Date.add(today, -200),
      valid_until: Date.add(today, 4)
    })

    event!(security, date: Date.add(today, 5))
    event!(security, date: Date.add(today, -5))

    # A cut in the future: an honouring read would answer nothing at all.
    queues = [
      {"/api/v1/notes/unreviewed", "positions"},
      {"/api/v1/notes/expiring", "entries"},
      {"/api/v1/notes/uncorroborated", "entries"},
      {"/api/v1/events/upcoming", "events"},
      {"/api/v1/events/stale", "events"},
      {"/api/v1/events/unconfirmed", "events"}
    ]

    for {path, key} <- queues, since <- ["2099-01-01T00:00:00Z", "not-a-time"] do
      response = conn |> api_conn() |> get("#{path}?since=#{since}") |> json_response(200)

      assert response["data"][key] != [], "#{path} dropped its queue under since=#{since}"

      for envelope_key <- ["since", "delta_note"],
          do: refute(Map.has_key?(response, envelope_key), "#{path} carries #{envelope_key}")
    end
  end

  # User story (FR-38, issue #666, review findings):
  # As an agent polling with `?since=`,
  # I want `as_of` captured BEFORE the query runs and backdated one second,
  # so that a row committed between the query and the stamp — or inside the
  # stamp's own wall-clock second, where second-precision `updated_at`
  # equals `as_of` — falls into the next poll's window (overlap) instead of
  # being skipped forever by the strictly-after cut.
  #
  # Acceptance criteria:
  # - `SinceParam.parse/1` captures the read instant at parse time, strictly
  #   before the current second.
  # - `put_envelope/2` serializes exactly that pre-query stamp, never a
  #   fresh `DateTime.utc_now/0` taken at render time.
  test "as_of is the backdated parse-time stamp, not a render-time one" do
    {:ok, parsed} = SinceParam.parse(%{"since" => "2026-06-01"})

    assert %DateTime{} = parsed.as_of

    # Strictly before the current second: the clock only moves forward, so
    # this holds deterministically for a stamp backdated by one second.
    assert DateTime.compare(parsed.as_of, DateTime.truncate(DateTime.utc_now(), :second)) == :lt

    pinned = DateTime.new!(~D[2026-06-02], ~T[08:00:00], "Etc/UTC")
    envelope = SinceParam.put_envelope(%{data: []}, %{parsed | as_of: pinned})

    assert envelope.as_of == "2026-06-02T08:00:00Z"
  end

  # Issue #666's own boundary: the push half (webhooks to user-configured
  # endpoints) stays gated at B3.7 and is deliberately NOT part of this
  # surface. Pinned against the documentation so scoping it in later
  # requires changing this stated boundary consciously.
  test "the docs state that delta reads are pull-only and push delivery stays gated (B3.7)" do
    docs = File.read!(Path.join(File.cwd!(), "docs/integration/api-and-mcp.md"))

    assert docs =~ "pull-only"
    assert docs =~ "B3.7"
  end

  # Acceptance criteria (closing-act finding, error contract): a since the
  # database cannot encode — a year before 1 — is a 422 naming the field on
  # every delta read, never a 500.
  test "a since before year 1 is a 422 on every delta read", %{conn: conn} do
    world = seed_world()
    security = Portfolixir.WorldFixtures.create_security!(name: "Ancient Co", ticker: "ANC")

    for path <- [
          "/api/v1/transactions",
          "/api/v1/securities",
          "/api/v1/securities/#{security.id}/notes",
          "/api/v1/securities/#{security.id}/events",
          "/api/v1/portfolios/#{world.portfolio.id}/targets",
          "/api/v1/portfolios/#{world.portfolio.id}/position_targets"
        ] do
      body =
        conn
        |> api_conn()
        |> get(path, %{"since" => "-9999-01-01T00:00:00Z"})
        |> json_response(422)

      assert body["errors"]["since"] == ["is invalid"], path
    end
  end
end
