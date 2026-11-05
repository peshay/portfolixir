defmodule PortfolixirWeb.ApiV1SecurityDossierTest do
  # FR-49 (idea I7; Sprint 24 plan, Lane D, D1; D-2's field list): one read
  # per security that carries the parts an agent otherwise assembles from
  # seven reads. Each part is compared with what its own read answers on the
  # same synthetic world, so the dossier cannot compute a figure of its own
  # (D-1, criterion 1). Every name, identifier and figure here is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures,
    only: [
      add_depot: 2,
      base_world: 1,
      create_security!: 1,
      buy!: 3,
      deposit!: 3,
      put_quotes!: 2
    ]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Clock
  alias Portfolixir.Knowledge.SecurityEvent
  alias Portfolixir.Lifecycle

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  # A security held in two portfolios, with closes for its metrics, seven
  # research-log entries, two upcoming and six past events, a category two
  # levels deep in one classification and none in another, and a position
  # target in the first portfolio.
  defp seeded_world(conn) do
    first = base_world(name: "Synthetic Alpha", depot_name: "Alpha Depot")
    second = base_world(name: "Synthetic Beta", depot_name: "Beta Depot")

    security =
      create_security!(
        name: "Synthetic Dossier Equity",
        ticker: "SDEQ",
        asset_class: "equity"
      )

    other = create_security!(name: "Synthetic Other Equity", ticker: "SOEQ")

    today = Clock.today()

    deposit!(first, "5000", Date.add(today, -400))
    deposit!(second, "5000", Date.add(today, -400))
    buy!(first, security, quantity: "12", price: "80", date: Date.add(today, -380))
    buy!(second, security, quantity: "3", price: "90", date: Date.add(today, -300))
    buy!(first, other, quantity: "5", price: "40", date: Date.add(today, -380))

    put_quotes!(
      security,
      for(offset <- 0..60, do: {Date.add(today, -offset), Decimal.add(100, offset)})
    )

    for n <- 1..7 do
      post!(conn, "/api/v1/securities/#{security.id}/notes", %{
        "note" => %{
          "kind" => "evidence",
          "body" => "Synthetic finding #{n}",
          "source_quality" => "primary",
          "as_of" => Date.to_iso8601(Date.add(today, -10 * n))
        }
      })
    end

    for {offset, kind} <- [{5, "earnings"}, {40, "ex_dividend"}] ++ past_events() do
      post!(conn, "/api/v1/securities/#{security.id}/events", %{
        "event" => %{
          "kind" => kind,
          "date" => Date.to_iso8601(Date.add(today, offset)),
          "timing" => "exact",
          "source_quality" => "primary"
        }
      })
    end

    {:ok, strategy} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Synthetic Strategy"})

    {:ok, growth} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: strategy.id,
        name: "Growth"
      })

    {:ok, compounders} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: strategy.id,
        parent_id: growth.id,
        name: "Compounders"
      })

    {:ok, _regions} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Synthetic Regions"})

    {:ok, _} =
      Classifications.assign_security(Actor.owner_ui(), security.id, strategy.id, compounders.id)

    put!(conn, "/api/v1/portfolios/#{first.portfolio.id}/targets", %{
      "classification_id" => strategy.id,
      "targets" => [
        %{"category_id" => compounders.id, "security_id" => security.id, "target_weight" => "0.4"}
      ]
    })

    %{
      security: security,
      portfolios: [first.portfolio, second.portfolio],
      strategy: strategy,
      path: [growth, compounders]
    }
  end

  defp past_events do
    Enum.map(-1..-6//-1, &{&1 * 20, "guidance_update"})
  end

  # User story:
  # As the agent preparing a decision about one position,
  # I want one read that carries the security's record, its holdings per
  # depot and in total, its derived metrics, the newest research-log
  # entries, its upcoming and recent events, its categories and its position
  # targets,
  # so that I start from one call, and every figure in it is the one its own
  # read would have given me.
  #
  # Acceptance criteria:
  # - GET /api/v1/securities/:id/dossier answers 200 with security_id,
  #   as_of, a parts note naming the read each part mirrors, and the seven
  #   parts of D-2.
  # - security equals GET /api/v1/securities/:id.
  # - holdings carries one row per depot holding the security (here one
  #   depot in each of two portfolios), equal to each portfolio's
  #   GET /api/v1/portfolios/:id/holdings?security_id= rows,
  #   with the read's currency_basis, currency_basis_note and
  #   computation_basis; total equals the security's row of
  #   GET /api/v1/holdings/by_security, with that read's currency and note.
  # - metrics equals GET /api/v1/securities/:id/metrics, computation_basis
  #   included.
  # - research carries the newest 5 entries of GET .../notes?limit=5 and its
  #   has_more, and names the read that pages the rest.
  # - events carries every event of GET .../events whose span has not ended
  #   before today, soonest first, the newest 5 past ones, newest first, and
  #   has_more, and names the read that pages the rest.
  # - categories carries every classification of GET /api/v1/classifications
  #   with the security's category and its path from the root, null where it
  #   is not filed.
  # - targets carries every position target row naming the security, equal to
  #   each portfolio's GET .../position_targets rows, and names the read that
  #   states the drift.
  test "each part of the dossier equals what its own read answers", %{conn: conn} do
    world = seeded_world(conn)
    id = world.security.id

    dossier = get!(conn, "/api/v1/securities/#{id}/dossier")["data"]

    assert dossier["security_id"] == id
    assert dossier["as_of"] == Date.to_iso8601(Clock.today())

    assert Map.keys(dossier["parts"]) ==
             ~w(categories events holdings metrics research security targets)

    for {part, note} <- dossier["parts"] do
      assert is_binary(note) and note =~ "/api/v1/", part
    end

    # security
    assert dossier["security"] == get!(conn, "/api/v1/securities/#{id}")["data"]

    # holdings, per depot and in total
    holdings_reads =
      Enum.map(world.portfolios, fn portfolio ->
        get!(conn, "/api/v1/portfolios/#{portfolio.id}/holdings?security_id=#{id}")
      end)

    holdings = dossier["holdings"]
    assert holdings["rows"] == Enum.flat_map(holdings_reads, & &1["data"])
    assert length(holdings["rows"]) == 2

    for key <- ~w(currency_basis currency_basis_note computation_basis) do
      assert holdings[key] == hd(holdings_reads)[key], key
    end

    by_security = get!(conn, "/api/v1/holdings/by_security")["data"]
    assert holdings["total"] == Enum.find(by_security["holdings"], &(&1["security_id"] == id))
    assert holdings["total"]["quantity"] == "15"
    assert holdings["total_basis"] == Map.take(by_security, ~w(currency note))

    # metrics
    assert dossier["metrics"] == get!(conn, "/api/v1/securities/#{id}/metrics")["data"]
    assert is_map(dossier["metrics"]["computation_basis"])

    # research
    notes = get!(conn, "/api/v1/securities/#{id}/notes?limit=5")["data"]
    research = dossier["research"]
    assert research["entries"] == notes["entries"]
    assert length(research["entries"]) == 5
    assert research["has_more"] == notes["truncated"]
    assert research["has_more"] == true
    assert research["log_note"] == notes["log_note"]
    assert research["rest"] =~ "/api/v1/securities/#{id}/notes"

    # events
    all_events = get!(conn, "/api/v1/securities/#{id}/events")["data"]
    {upcoming, past} = Enum.split_with(all_events["events"], &not_ended?/1)

    events = dossier["events"]
    assert events["upcoming"] == upcoming
    assert length(events["upcoming"]) == 2
    assert events["past"] == past |> Enum.reverse() |> Enum.take(5)
    assert events["has_more"] == true
    assert events["events_note"] == all_events["events_note"]
    assert events["rest"] =~ "/api/v1/securities/#{id}/events"

    # categories
    trees = get!(conn, "/api/v1/classifications")["data"]
    assert length(dossier["categories"]) == length(trees)

    for {row, tree} <- Enum.zip(dossier["categories"], trees) do
      assert row["classification_id"] == tree["id"]
      assert row["classification_name"] == tree["name"]
      assert row["category"] == expected_category(tree, id)
    end

    strategy = Enum.find(dossier["categories"], &(&1["classification_id"] == world.strategy.id))

    assert Enum.map(strategy["category"]["path"], & &1["name"]) == ["Growth", "Compounders"]
    assert strategy["category"]["id"] == List.last(world.path).id

    assert %{"category" => nil} =
             Enum.find(dossier["categories"], &(&1["classification_name"] == "Synthetic Regions"))

    # targets
    target_rows =
      Enum.flat_map(world.portfolios, fn portfolio ->
        get!(conn, "/api/v1/portfolios/#{portfolio.id}/position_targets")["data"][
          "position_targets"
        ]
        |> Enum.filter(&(&1["security_id"] == id))
      end)

    targets = dossier["targets"]
    assert targets["rows"] == target_rows
    assert [%{"target_weight" => "0.4", "stale" => false}] = targets["rows"]
    assert targets["drift"] =~ "min_drift"
  end

  # User story:
  # As the agent opening the dossier of a security nobody has worked on yet,
  # I want each part answered empty,
  # so that an empty part reads as "nothing recorded", never as an error.
  #
  # Acceptance criteria:
  # - A security with no holding, entry, event, category or target answers
  #   200: holdings rows [] and total null, research and events empty with
  #   has_more false, a null category in every custom classification, no
  #   target rows, and the metrics read's own refusal markers.
  test "a security nothing was recorded for answers empty parts", %{conn: conn} do
    _portfolio = base_world(name: "Synthetic Gamma")
    security = create_security!(name: "Synthetic Blank Equity", ticker: "SBEQ")

    {:ok, _regions} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Synthetic Regions"})

    dossier = get!(conn, "/api/v1/securities/#{security.id}/dossier")["data"]

    assert dossier["holdings"]["rows"] == []
    assert dossier["holdings"]["total"] == nil
    assert %{"entries" => [], "has_more" => false} = dossier["research"]
    assert %{"upcoming" => [], "past" => [], "has_more" => false} = dossier["events"]
    assert dossier["targets"]["rows"] == []

    assert %{"category" => nil} =
             Enum.find(dossier["categories"], &(&1["classification_name"] == "Synthetic Regions"))

    assert dossier["metrics"] == get!(conn, "/api/v1/securities/#{security.id}/metrics")["data"]
    assert dossier["metrics"]["metrics"]["sma_50"]["insufficient_data"] == true
  end

  # User story (Sprint 24 closing act, D1; the agent's lens):
  # As the agent counting the dossier's holdings rows,
  # I want each row to be one depot (securities account) holding the
  # security, and the parts note to say so,
  # so that I do not read two rows as two portfolios.
  #
  # Acceptance criteria:
  # - A portfolio with two depots each holding the security answers two
  #   holdings rows, one per depot, equal to that portfolio's holdings read.
  # - parts.holdings says one row per depot (securities account), across
  #   portfolios.
  test "holdings rows are one per depot, across portfolios", %{conn: conn} do
    world = base_world(name: "Synthetic Epsilon", depot_name: "Epsilon Depot")

    second =
      add_depot(world.portfolio, depot_name: "Epsilon Depot B", cash_name: "Epsilon Cash B")

    second_world = Map.merge(world, second)
    security = create_security!(name: "Synthetic Depot Equity", ticker: "SDPE")
    day = Date.add(Clock.today(), -30)

    deposit!(world, "1000", day)
    deposit!(second_world, "1000", day)
    buy!(world, security, quantity: "4", price: "50", date: day)
    buy!(second_world, security, quantity: "6", price: "50", date: day)

    dossier = get!(conn, "/api/v1/securities/#{security.id}/dossier")["data"]

    read =
      get!(conn, "/api/v1/portfolios/#{world.portfolio.id}/holdings?security_id=#{security.id}")

    rows = dossier["holdings"]["rows"]
    assert rows == read["data"]

    assert rows |> Enum.map(& &1["securities_account_id"]) |> Enum.sort() ==
             Enum.sort([world.depot.id, second.depot.id])

    assert dossier["parts"]["holdings"] =~
             "one per depot (securities account) holding it, across portfolios"

    assert dossier["holdings"]["total"]["quantity"] == "10"
  end

  # User story (Sprint 24 closing act, D1; the agent's lens):
  # As the agent reading the dossier's targets part,
  # I want the parts note to say which plan the rows come from,
  # so that I never conclude "no target" when the only SOLL row sits in a
  # view's active plan.
  #
  # Acceptance criteria:
  # - parts.targets names the scope: each portfolio's active plan of the
  #   unscoped view.
  # - It names the read that answers a view's plan: position_targets with
  #   view=.
  test "the parts note names the plan the targets part reads", %{conn: conn} do
    _portfolio = base_world(name: "Synthetic Delta")
    security = create_security!(name: "Synthetic Scope Equity", ticker: "SSEQ")

    note = get!(conn, "/api/v1/securities/#{security.id}/dossier")["data"]["parts"]["targets"]

    assert note =~ "active plan of the unscoped view"
    assert note =~ "/api/v1/portfolios/:portfolio_id/position_targets?view=:view_id"
  end

  # User story:
  # As the agent holding the id of a security the operator merged away,
  # I want the dossier to name the survivor, as securities.get does,
  # so that I follow it instead of concluding the history is gone.
  #
  # Acceptance criteria:
  # - The dossier of a merged-away id answers 404 with errors.merged_into
  #   {"kind": "security", "id": <survivor>}, the body GET
  #   /api/v1/securities/:id answers.
  # - An id no security ever had, and an id that is no id, answer the plain
  #   404.
  test "a merged-away security answers 404 with merged_into", %{conn: conn} do
    target = create_security!(name: "Synthetic Harbour Fund", ticker: nil)
    source = create_security!(name: "Synthetic Harbour Fund", ticker: nil)

    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    {:ok, _record, :applied} =
      Lifecycle.merge_security(Actor.owner_ui(), source.id, target.id, %{
        plan_digest: preview.plan_digest
      })

    refute Catalog.get_security(source.id)

    dossier = conn |> get("/api/v1/securities/#{source.id}/dossier") |> json_response(404)

    assert dossier["errors"]["merged_into"] == %{"kind" => "security", "id" => target.id}
    assert dossier == conn |> get("/api/v1/securities/#{source.id}") |> json_response(404)

    for id <- ["999999999", "not-an-id"] do
      assert conn |> get("/api/v1/securities/#{id}/dossier") |> json_response(404) ==
               %{"errors" => %{"detail" => "not found"}}
    end
  end

  defp not_ended?(event) do
    {_from, to} =
      SecurityEvent.span(%SecurityEvent{
        timing: String.to_existing_atom(event["timing"]),
        date: Date.from_iso8601!(event["date"]),
        date_end: event["date_end"] && Date.from_iso8601!(event["date_end"])
      })

    Date.compare(to, Clock.today()) != :lt
  end

  defp expected_category(tree, security_id) do
    case Enum.find(tree["assignments"], &(&1["security_id"] == security_id)) do
      nil ->
        nil

      %{"category_id" => category_id} ->
        by_id = Map.new(tree["categories"], &{&1["id"], &1})
        path = category_path(by_id, category_id, [])
        leaf = List.last(path)
        %{"id" => leaf["id"], "name" => leaf["name"], "key" => leaf["key"], "path" => path}
    end
  end

  defp category_path(_by_id, nil, acc), do: acc

  defp category_path(by_id, id, acc) do
    category = Map.fetch!(by_id, id)
    category_path(by_id, category["parent_id"], [Map.take(category, ~w(id name key)) | acc])
  end

  defp get!(conn, path), do: conn |> get(path) |> json_response(200)

  defp post!(conn, path, body), do: conn |> post(path, body) |> json_response(201)

  defp put!(conn, path, body), do: conn |> put(path, body) |> json_response(200)
end
