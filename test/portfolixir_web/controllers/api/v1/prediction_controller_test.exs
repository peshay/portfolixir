defmodule PortfolixirWeb.Api.V1.PredictionControllerTest do
  # Sprint 25 Lane F, F4 (ADR-0055 §5): the predictions over the JSON API.
  # The write path's bounds and the resolution's figures are the context's
  # (pinned in test/portfolixir/predictions_test.exs and
  # test/portfolixir/predictions/); this test pins the wire: the author and
  # the clock come from the server, every refusal is a 422 naming its field,
  # each read carries the derived status, the closes used and the basis, and
  # every Decimal is a string. Every name and figure here is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [create_security!: 1, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Clock
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge
  alias Portfolixir.Predictions

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  defp security!(name), do: create_security!(name: name, ticker: nil, currency: "EUR")

  defp benchmark!(name) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        currency_code: "EUR",
        asset_class: "etf",
        is_benchmark: true
      })

    security
  end

  defp thesis!(security) do
    {:ok, note} =
      Knowledge.append_note(Actor.api_token_rw(nil), %{
        security_id: security.id,
        author: "agent",
        kind: "thesis",
        body: "Synthetic thesis: margins widen as the new plant ramps up.",
        source_quality: "primary",
        as_of: Clock.today()
      })

    note
  end

  defp body(security, extra \\ %{}) do
    Map.merge(
      %{
        "security_id" => security.id,
        "direction" => "outperform",
        "probability" => "0.70",
        "benchmark" => "rate:0",
        "resolves_on" => Date.to_iso8601(Date.add(Clock.today(), 30)),
        "model" => "example-model-1"
      },
      extra
    )
  end

  # A call made `made_days_ago` days ago (through the context's clock seam,
  # never the API) that resolved `resolved_days_ago` days ago.
  defp past_prediction!(security, extra \\ %{}, made_days_ago \\ 100, resolved_days_ago \\ 10) do
    made_on = Date.add(Clock.today(), -made_days_ago)
    {:ok, made_at} = DateTime.new(made_on, ~T[12:00:00.000000], "Etc/UTC")

    attrs =
      Map.merge(
        %{
          "security_id" => security.id,
          "direction" => "outperform",
          "probability" => "0.70",
          "benchmark" => "rate:0",
          "resolves_on" => Date.to_iso8601(Date.add(Clock.today(), -resolved_days_ago)),
          "model" => "example-model-1"
        },
        extra
      )

    {:ok, prediction} =
      Predictions.create_prediction(Actor.api_token_rw("research-agent"), attrs, now: made_at)

    prediction
  end

  defp post_prediction(conn, attrs),
    do: post(conn, "/api/v1/predictions", %{"prediction" => attrs})

  describe "POST /api/v1/predictions" do
    # User story (F4, ADR-0055 §§1, 5):
    # As the operator's agent with a view on a position,
    # I want to record one call in one request,
    # so that it is scored later against stored closes, under my model's
    # name, dated by the server.
    #
    # Acceptance criteria:
    # - A call from an API token answers 201 with the prediction: author
    #   agent, the model it named, made_at the server's clock, probability
    #   and the benchmark as strings, and its resolution: open, with the
    #   dates its closes will stand for and nothing measured yet.
    # - The read carries the permanence note and the resolution rule's
    #   computation_basis.
    # - The write is journaled as prediction / create under the token.
    test "an agent's call is recorded, open, under the server's clock", %{conn: conn} do
      security = security!("Synthetic Plant Co.")
      benchmark = benchmark!("Synthetic World Index")
      note = thesis!(security)

      before = DateTime.utc_now()

      data =
        conn
        |> post_prediction(
          body(security, %{
            "benchmark" => "security:#{benchmark.id}",
            "note_id" => note.id,
            "rationale" => "The thesis entry's ramp-up, priced in by spring."
          })
        )
        |> json_response(201)
        |> Map.fetch!("data")

      assert is_integer(data["id"])
      assert data["security_id"] == security.id
      assert data["direction"] == "outperform"
      assert data["probability"] == "0.70"
      assert data["benchmark"] == "security:#{benchmark.id}"
      assert data["resolves_on"] == Date.to_iso8601(Date.add(Clock.today(), 30))
      assert data["author"] == "agent"
      assert data["actor"] == nil
      assert data["model"] == "example-model-1"
      assert data["note_id"] == note.id
      assert data["rationale"] =~ "ramp-up"

      {:ok, made_at, 0} = DateTime.from_iso8601(data["made_at"])
      assert DateTime.compare(made_at, before) in [:gt, :eq]
      made_on = made_at |> DateTime.to_date() |> Date.to_iso8601()
      assert data["made_on"] == made_on

      assert data["resolution"] == %{
               "status" => "open",
               "outcome" => nil,
               "reason" => nil,
               "start_on" => made_at |> DateTime.to_date() |> Date.add(-1) |> Date.to_iso8601(),
               "end_on" => data["resolves_on"],
               "security" => nil,
               "benchmark" => nil,
               "excess" => nil
             }

      assert data["permanence_note"] =~ "cannot be edited, withdrawn or deleted"
      assert data["permanence_note"] =~ "a correction is a new prediction"
      assert data["computation_basis"]["start_close"] =~ "strictly before"
      assert data["computation_basis"]["staleness_days"] == 7
      assert data["computation_basis"]["outcome"] =~ "excess = 0 is a miss"

      assert [entry] = Journal.list_entries(resource_type: "prediction")
      assert entry.operation == :create
      assert entry.actor_type == :api_token_rw
      assert entry.resource_id == to_string(data["id"])
    end

    # User story (F4; ADR-0055 §1 and the plan's D-8.1, attacked over the
    # wire): a call outside the bounds is refused with a field error, and a
    # field the server states is refused by name rather than dropped.
    #
    # Acceptance criteria:
    # - 0.49 answers 422 on probability naming the other direction; 1.00
    #   answers 422 on probability.
    # - An agent's call without a model answers 422 on model.
    # - A made_at, author or actor in the body answers 422 on that field.
    # - A JSON number for probability answers 422 on probability.
    # - Nothing is stored or journaled by any refusal.
    test "a refused call answers 422 with its field errors and stores nothing", %{conn: conn} do
      security = security!("Synthetic Refused Co.")

      errors = fn attrs ->
        conn
        |> post_prediction(attrs)
        |> json_response(422)
        |> Map.fetch!("errors")
      end

      below = errors.(body(security, %{"probability" => "0.49"}))
      assert [message] = below["probability"]
      assert message =~ "record it as underperform with probability 0.51"

      assert [certain] = errors.(body(security, %{"probability" => "1.00"}))["probability"]
      assert certain =~ "at most 0.99"

      assert [model] = errors.(Map.delete(body(security), "model"))["model"]
      assert model =~ "name the model you run on"

      made_at = errors.(body(security, %{"made_at" => "2020-01-01T00:00:00Z"}))
      assert [dated] = made_at["made_at"]
      assert dated =~ "never dated in the past"

      assert [_] = errors.(body(security, %{"author" => "operator"}))["author"]
      assert [_] = errors.(body(security, %{"actor" => "someone-else"}))["actor"]

      assert [number] = errors.(body(security, %{"probability" => 0.7}))["probability"]
      assert number =~ "decimal string"
      assert [_] = errors.(body(security, %{"probability" => 1}))["probability"]

      assert Predictions.list_predictions() == []
      assert Journal.list_entries(resource_type: "prediction") == []
    end

    # User story (F4; #853's input-shape rule): a wrapper that is not an
    # object answers 422 naming it, and an absent wrapper answers the
    # required fields.
    test "the prediction wrapper must be an object", %{conn: conn} do
      assert %{"errors" => %{"prediction" => ["must be an object"]}} =
               conn
               |> post("/api/v1/predictions", %{"prediction" => "outperform"})
               |> json_response(422)

      errors =
        conn
        |> post("/api/v1/predictions", %{})
        |> json_response(422)
        |> Map.fetch!("errors")

      for field <- ~w(security_id direction probability benchmark resolves_on model) do
        assert Map.has_key?(errors, field), field
      end
    end
  end

  describe "GET /api/v1/predictions/:id" do
    # User story (F4, ADR-0055 §§3, 5):
    # As the operator's agent coming back to a call,
    # I want one read naming its status, its outcome and the closes used,
    # so that I can check the figure rather than trust it.
    #
    # Acceptance criteria:
    # - A resolved call carries status resolved and its outcome, both
    #   sides' start and end (stands_for, date, close, stored_close,
    #   source, fx_rate, eur_value), both returns and the excess, every
    #   Decimal a string.
    # - A rate benchmark names its rate, the dates it compounds between and
    #   the days.
    # - An unresolved call names its reason; an unknown or malformed id is
    #   404.
    test "a resolved call names its outcome and the closes it used", %{conn: conn} do
      security = security!("Synthetic Rising Co.")
      benchmark = benchmark!("Synthetic Flat Index")
      prediction = past_prediction!(security, %{"benchmark" => "security:#{benchmark.id}"})

      start_on = prediction |> Predictions.Prediction.made_on() |> Date.add(-1)
      end_on = prediction.resolves_on

      put_quotes!(security, [{start_on, "100"}, {end_on, "110"}])
      put_quotes!(benchmark, [{start_on, "200"}, {end_on, "210"}])

      data =
        conn
        |> get("/api/v1/predictions/#{prediction.id}")
        |> json_response(200)
        |> Map.fetch!("data")

      assert data["id"] == prediction.id
      assert data["actor"] == "research-agent"

      resolution = data["resolution"]
      assert resolution["status"] == "resolved"
      assert resolution["outcome"] == "hit"
      assert resolution["reason"] == nil
      assert resolution["start_on"] == Date.to_iso8601(start_on)
      assert resolution["end_on"] == Date.to_iso8601(end_on)

      assert resolution["security"] == %{
               "security_id" => security.id,
               "currency_code" => "EUR",
               "start" => %{
                 "stands_for" => Date.to_iso8601(start_on),
                 "date" => Date.to_iso8601(start_on),
                 "close" => "100",
                 "stored_close" => "100",
                 "source" => "manual",
                 "fx_rate" => "1",
                 "eur_value" => "100"
               },
               "end" => %{
                 "stands_for" => Date.to_iso8601(end_on),
                 "date" => Date.to_iso8601(end_on),
                 "close" => "110",
                 "stored_close" => "110",
                 "source" => "manual",
                 "fx_rate" => "1",
                 "eur_value" => "110"
               },
               "return" => "0.1"
             }

      # 210 / 200 - 1 = 0.05; excess 0.1 - 0.05 = 0.05, an outperform hit.
      assert resolution["benchmark"]["kind"] == "security"
      assert resolution["benchmark"]["security_id"] == benchmark.id
      assert resolution["benchmark"]["start"]["close"] == "200"
      assert resolution["benchmark"]["end"]["eur_value"] == "210"
      assert resolution["benchmark"]["return"] == "0.05"
      assert resolution["excess"] == "0.05"

      assert data["computation_basis"]["benchmark"] =~ "rate:<r>"
      assert data["permanence_note"] =~ "A mistaken one stays and counts"
    end

    test "a rate benchmark names its compounding, an unresolved call its reason", %{conn: conn} do
      security = security!("Synthetic Absolute Co.")
      absolute = past_prediction!(security, %{"direction" => "underperform"})
      start_on = absolute |> Predictions.Prediction.made_on() |> Date.add(-1)
      put_quotes!(security, [{start_on, "50"}, {absolute.resolves_on, "40"}])

      resolution =
        conn
        |> get("/api/v1/predictions/#{absolute.id}")
        |> json_response(200)
        |> get_in(["data", "resolution"])

      # 40 / 50 - 1 = -0.2 against rate:0's exact 0: an underperform hit.
      assert resolution["outcome"] == "hit"
      assert resolution["security"]["return"] == "-0.2"

      assert resolution["benchmark"] == %{
               "kind" => "rate",
               "rate" => "0",
               "from" => Date.to_iso8601(start_on),
               "to" => Date.to_iso8601(absolute.resolves_on),
               "days" => Date.diff(absolute.resolves_on, start_on),
               "return" => "0"
             }

      assert resolution["excess"] == "-0.2"

      no_quotes = past_prediction!(security!("Synthetic Unquoted Co."))

      unresolved =
        conn
        |> get("/api/v1/predictions/#{no_quotes.id}")
        |> json_response(200)
        |> get_in(["data", "resolution"])

      assert unresolved["status"] == "unresolved"
      assert unresolved["reason"] == "no_start_close"
      assert unresolved["outcome"] == nil
      assert unresolved["excess"] == nil

      assert %{"errors" => %{"detail" => "not found"}} =
               conn |> get("/api/v1/predictions/999999") |> json_response(404)

      assert conn |> get("/api/v1/predictions/abc") |> json_response(404)
    end
  end
end
