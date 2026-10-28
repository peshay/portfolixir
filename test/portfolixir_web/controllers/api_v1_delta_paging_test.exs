defmodule PortfolixirWeb.ApiV1DeltaPagingTest do
  use PortfolixirWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  @max_polls 6

  defp api_conn do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp owner, do: Actor.owner_ui()

  # Every row a test writes is stamped with this one instant: time has
  # passed since the writes, and rows sharing a stamp are the shape an
  # import leaves. The journal guard needs a transaction-local actor.
  defp stamp!(table, column \\ "updated_at")
       when table in [
              "transactions",
              "securities",
              "security_events",
              "policy_rules",
              "policy_rule_versions"
            ] do
    Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test_backdate', true)")
    Repo.query!("UPDATE #{table} SET #{column} = $1", [ten_minutes_ago()])
  end

  defp ten_minutes_ago do
    NaiveDateTime.utc_now() |> NaiveDateTime.add(-600, :second) |> NaiveDateTime.truncate(:second)
  end

  # The agent's cursor from its previous poll: an hour ago, before every write.
  defp previous_cursor do
    DateTime.utc_now()
    |> DateTime.add(-3600, :second)
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp poll(path, since, extra) do
    query = URI.encode_query(Map.merge(%{"since" => since}, extra))
    conn = get(api_conn(), path <> "?" <> query)
    {conn.status, Jason.decode!(conn.resp_body)}
  end

  # The documented protocol: use each response's `as_of` as the next `since`
  # and keep polling while a poll still returns rows (bounded).
  defp follow(path, rows_of, extra) do
    Enum.reduce_while(1..@max_polls, {previous_cursor(), [], []}, fn _poll, {since, ids, pages} ->
      assert {200, body} = poll(path, since, extra)
      rows = rows_of.(body)
      pages = pages ++ [body]
      ids = ids ++ Enum.map(rows, & &1["id"])

      if rows == [],
        do: {:halt, {ids, pages}},
        else: {:cont, {body["as_of"], ids, pages}}
    end)
  end

  defp assert_paged_exactly_once({_since, _ids, _pages}, _changed_ids, _limit),
    do: flunk("following as_of did not reach an empty page in #{@max_polls} polls")

  defp assert_paged_exactly_once({ids, [first | _] = pages}, changed_ids, limit) do
    assert MapSet.new(ids) == MapSet.new(changed_ids)
    assert length(ids) == length(Enum.uniq(ids)), "a row was delivered twice"

    assert first["has_more"] == true
    assert echo(first, "truncated") == true
    assert echo(first, "limit") == limit

    assert List.last(pages)["has_more"] == false
  end

  # The list reads echo `limit` and `truncated` beside their rows: at the top
  # level when `data` is the row list, inside `data` when it is an object.
  defp echo(%{"data" => data}, key) when is_map(data), do: data[key]
  defp echo(body, key), do: body[key]

  # User story (security review 2026-10-12, K17):
  # As the agent keeping its copy of the ledger by delta reads,
  # I want a delta read whose change set exceeds the read's limit to come
  # back as a page that says more rows are waiting and whose `as_of`
  # continues where the page ended,
  # so that following `as_of` delivers every changed row exactly once and a
  # large import never leaves bookings my copy will never see.
  #
  # Acceptance criteria:
  # - A full page carries `has_more: true`, `truncated: true` and the
  #   applied `limit`; the last page carries `has_more: false`.
  # - Following `as_of` from page to page delivers every row changed after
  #   the first cursor, each exactly once, also when the rows share one stamp.
  test "a delta read with an explicit limit below the change set pages through every row" do
    world = WorldFixtures.base_world(name: "Paging Small")
    old = WorldFixtures.deposit!(world, "1.00", ~D[2020-01-02])
    mid = WorldFixtures.deposit!(world, "2.00", ~D[2025-01-02])
    new = WorldFixtures.deposit!(world, "3.00", ~D[2026-01-02])
    stamp!("transactions")

    "/api/v1/transactions"
    |> follow(& &1["data"], %{"limit" => "2", "fields" => "id,date"})
    |> assert_paged_exactly_once([old.id, mid.id, new.id], 2)
  end

  @tag timeout: 240_000
  test "a delta read past the default limit (no limit sent) pages through every row" do
    world = WorldFixtures.base_world(name: "Paging Import")
    oldest = WorldFixtures.deposit!(world, "1.00", ~D[2020-01-02])
    template = WorldFixtures.deposit!(world, "100.00", ~D[2026-01-02])

    # 10_000 synthetic copies of the template, the shape a large import leaves.
    Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test_backdate', true)")

    %{rows: rows} =
      Repo.query!("""
      SELECT column_name FROM information_schema.columns
      WHERE table_schema = current_schema() AND table_name = 'transactions'
        AND column_name <> 'id'
      ORDER BY ordinal_position
      """)

    cols = Enum.map_join(rows, ", ", fn [name] -> ~s("#{name}") end)

    Repo.query!(
      "INSERT INTO transactions (#{cols}) SELECT #{cols} " <>
        "FROM transactions, generate_series(1, 10000) WHERE id = $1",
      [template.id]
    )

    stamp!("transactions")

    changed =
      Repo.all(from(t in Transaction, where: t.portfolio_id == ^world.portfolio.id, select: t.id))

    assert length(changed) == 10_002
    assert oldest.id in changed

    "/api/v1/transactions"
    |> follow(& &1["data"], %{"fields" => "id,date"})
    |> assert_paged_exactly_once(changed, 10_000)
  end

  test "the securities delta read pages through rows sharing one stamp" do
    ids =
      for name <- ["Paging Alpha", "Paging Beta", "Paging Gamma"] do
        WorldFixtures.create_security!(name: name).id
      end

    stamp!("securities")

    "/api/v1/securities"
    |> follow(& &1["data"], %{"limit" => "2"})
    |> assert_paged_exactly_once(ids, 2)
  end

  test "the research log delta read pages through entries sharing one stamp" do
    security = WorldFixtures.create_security!(name: "Paging Log")
    Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test_backdate', true)")

    ids =
      for body <- ["one", "two", "three"] do
        %{rows: [[id]]} =
          Repo.query!(
            "INSERT INTO security_notes (security_id, author, kind, body, source_quality, as_of, inserted_at) " <>
              "VALUES ($1, 'agent', 'evidence', $2, 'primary', '2026-01-01', $3) RETURNING id",
            [security.id, body, ten_minutes_ago()]
          )

        id
      end

    "/api/v1/securities/#{security.id}/notes"
    |> follow(& &1["data"]["entries"], %{"limit" => "2"})
    |> assert_paged_exactly_once(ids, 2)
  end

  test "the events delta read pages through rows sharing one stamp" do
    security = WorldFixtures.create_security!(name: "Paging Calendar")

    ids =
      for date <- [~D[2026-11-04], ~D[2026-11-05], ~D[2026-11-06]] do
        {:ok, event} =
          Events.create_event(owner(), %{
            security_id: security.id,
            kind: "earnings",
            date: date,
            timing: "exact",
            source_quality: "primary"
          })

        event.id
      end

    stamp!("security_events")

    "/api/v1/securities/#{security.id}/events"
    |> follow(& &1["data"]["events"], %{"limit" => "2"})
    |> assert_paged_exactly_once(ids, 2)
  end

  test "the policy rules delta read pages through rules sharing one stamp" do
    world = WorldFixtures.base_world(name: "Paging Rules")
    security = WorldFixtures.create_security!(name: "Paging Ruled")

    ids =
      for n <- 1..3 do
        {:ok, rule} =
          PolicyRules.create_rule(
            owner(),
            %{
              portfolio_id: world.portfolio.id,
              name: "Paging cap #{n}",
              version: %{
                subject_type: "security",
                security_id: security.id,
                measure: "weight",
                kind: "cap",
                threshold: "50",
                severity: "hard"
              }
            },
            today: Portfolixir.Clock.today()
          )

        rule.id
      end

    stamp!("policy_rules")
    stamp!("policy_rule_versions")

    "/api/v1/portfolios/#{world.portfolio.id}/policy_rules"
    |> follow(& &1["data"]["rules"], %{"limit" => "2"})
    |> assert_paged_exactly_once(ids, 2)
  end

  # User story (security review 2026-10-12, K17):
  # As the agent reading a capped list,
  # I want every read of the delta-capable lists to echo the limit it applied
  # and whether rows were left out,
  # so that a full page is never mistaken for the whole answer.
  #
  # Acceptance criteria:
  # - A full read echoes `limit` and `truncated`: true when more rows matched
  #   than the page holds, false otherwise.
  test "a full read echoes the applied limit and whether rows were left out" do
    world = WorldFixtures.base_world(name: "Echo")

    for amount <- ["1.00", "2.00", "3.00"],
        do: WorldFixtures.deposit!(world, amount, ~D[2026-01-02])

    cut = Jason.decode!(get(api_conn(), "/api/v1/transactions?limit=2").resp_body)
    assert cut["limit"] == 2
    assert cut["truncated"] == true
    assert length(cut["data"]) == 2

    whole = Jason.decode!(get(api_conn(), "/api/v1/transactions?limit=3").resp_body)
    assert whole["limit"] == 3
    assert whole["truncated"] == false
    refute Map.has_key?(whole, "has_more")

    security = WorldFixtures.create_security!(name: "Echo Calendar")
    WorldFixtures.create_security!(name: "Echo Second")

    securities = Jason.decode!(get(api_conn(), "/api/v1/securities?limit=1").resp_body)
    assert securities["limit"] == 1
    assert securities["truncated"] == true

    events =
      Jason.decode!(get(api_conn(), "/api/v1/securities/#{security.id}/events").resp_body)

    assert events["data"]["limit"] == 1_000
    assert events["data"]["truncated"] == false

    notes = Jason.decode!(get(api_conn(), "/api/v1/securities/#{security.id}/notes").resp_body)
    assert notes["data"]["truncated"] == false

    rules =
      Jason.decode!(
        get(api_conn(), "/api/v1/portfolios/#{world.portfolio.id}/policy_rules").resp_body
      )

    assert rules["data"]["truncated"] == false
  end

  test "a malformed page cursor is refused as an invalid since" do
    for since <- ["~5", "2026-01-01T00:00:00Z~0", "2026-01-01T00:00:00Z~x", "soon~5", "a~b~c"] do
      conn = get(api_conn(), "/api/v1/transactions?" <> URI.encode_query(%{"since" => since}))
      assert %{"errors" => %{"since" => _}} = json_response(conn, 422), since
    end
  end
end
