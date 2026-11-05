defmodule Portfolixir.PredictionsTest do
  # ADR-0055 §§1-2 (Sprint 25 plan, Lane F, F1; risk tier: a record that
  # must never change). The write path of the predictions table, its bounds
  # and the attacks of D-8.1, each refused. The database half of the
  # permanence (a raw UPDATE, DELETE and TRUNCATE) is pinned unboxed in
  # test/portfolixir/journal/append_only_test.exs.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Derived.BlastRadius
  alias Portfolixir.Derived.DataVersion
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge
  alias Portfolixir.Portfolios
  alias Portfolixir.Predictions
  alias Portfolixir.Predictions.Prediction
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  # 2026-11-05 14:30 UTC: the made day is 2026-11-05.
  @now ~U[2026-11-05 14:30:00.123456Z]

  defp agent, do: Actor.api_token_rw("research-agent")
  defp operator, do: Actor.owner_ui()

  defp security!(name \\ "Forecast Co.") do
    WorldFixtures.create_security!(name: name, ticker: nil, asset_class: "equity")
  end

  defp benchmark!(name \\ "World Index") do
    {:ok, security} =
      Catalog.create_security(operator(), %{
        name: name,
        currency_code: "EUR",
        asset_class: "etf",
        is_benchmark: true
      })

    security
  end

  defp note!(security) do
    {:ok, note} =
      Knowledge.append_note(operator(), %{
        security_id: security.id,
        author: "agent",
        kind: "thesis",
        body: "Margins widen as the new plant ramps up.",
        source_quality: "primary",
        as_of: ~D[2026-11-01]
      })

    note
  end

  defp attrs(security, extra \\ %{}) do
    Map.merge(
      %{
        "security_id" => security.id,
        "direction" => "outperform",
        "probability" => "0.70",
        "benchmark" => "rate:0",
        "resolves_on" => "2027-05-05",
        "model" => "example-model-1"
      },
      extra
    )
  end

  defp create(actor, attrs), do: Predictions.create_prediction(actor, attrs, now: @now)

  defp count, do: Repo.aggregate(Prediction, :count, :id)

  # User story (ADR-0055 §1):
  # As the operator's agent stating a view on a security,
  # I want to record one call — a direction against a benchmark by a date,
  # with my probability and the model I run on —
  # so that the call can be scored later against what the prices did.
  #
  # Acceptance criteria:
  # - The prediction stores the security, direction, probability as a
  #   Decimal of two places, the benchmark as its kind and its security or
  #   rate, resolves_on, the model, the linked note and the rationale.
  # - made_at is the server's clock; author and actor come from the
  #   credential: agent and the token's name for a token, operator and none
  #   for the pages.
  # - The write is journaled as `prediction` / create under the token.
  describe "create_prediction/3" do
    test "stores an agent's call against a benchmark security and journals it under the token" do
      security = security!()
      benchmark = benchmark!()
      note = note!(security)

      assert {:ok, %Prediction{} = prediction} =
               create(
                 agent(),
                 attrs(security, %{
                   "probability" => "0.7",
                   "benchmark" => "security:#{benchmark.id}",
                   "note_id" => note.id,
                   "rationale" => "The thesis entry's plant ramp-up, priced in by spring."
                 })
               )

      assert prediction.security_id == security.id
      assert prediction.direction == :outperform
      assert prediction.probability == Decimal.new("0.70")
      assert prediction.benchmark_kind == :security
      assert prediction.benchmark_security_id == benchmark.id
      assert prediction.benchmark_rate == nil
      assert Prediction.benchmark(prediction) == "security:#{benchmark.id}"
      assert prediction.resolves_on == ~D[2027-05-05]
      assert prediction.made_at == @now
      assert prediction.author == :agent
      assert prediction.actor == "research-agent"
      assert prediction.model == "example-model-1"
      assert prediction.note_id == note.id
      assert prediction.rationale =~ "plant ramp-up"

      stored = Predictions.get_prediction(prediction.id)
      assert stored.probability == Decimal.new("0.70")
      assert stored.made_at == @now

      assert [entry] = Journal.list_entries(resource_type: "prediction")
      assert entry.operation == :create
      assert entry.actor_type == :api_token_rw
      assert entry.actor_label == "research-agent"
      assert entry.resource_id == to_string(prediction.id)
      assert entry.after["probability"] == "0.70"
      assert entry.after["author"] == "agent"
    end

    test "an operator's call carries no model and a rate benchmark keeps its rate" do
      security = security!()

      assert {:ok, prediction} =
               create(
                 operator(),
                 attrs(security, %{
                   "direction" => "underperform",
                   "probability" => "0.55",
                   "benchmark" => "rate:0.02"
                 })
                 |> Map.delete("model")
               )

      assert prediction.author == :operator
      assert prediction.actor == nil
      assert prediction.model == nil
      assert prediction.direction == :underperform
      assert prediction.benchmark_kind == :rate
      assert prediction.benchmark_rate == Decimal.new("0.02")
      assert prediction.benchmark_security_id == nil
      assert Prediction.benchmark(prediction) == "rate:0.02"

      assert [entry] = Journal.list_entries(resource_type: "prediction")
      assert entry.actor_type == :owner_ui
    end

    test "without a clock given, made_at is the server's time now" do
      security = security!()
      before = DateTime.utc_now()

      assert {:ok, prediction} =
               Predictions.create_prediction(
                 agent(),
                 attrs(security, %{
                   "resolves_on" => Date.to_iso8601(Date.add(Date.utc_today(), 30))
                 })
               )

      assert DateTime.compare(prediction.made_at, before) != :lt
      assert DateTime.compare(prediction.made_at, DateTime.utc_now()) != :gt
    end

    test "the bounds themselves are accepted: 0.50, 0.99, 7 and 1,830 days" do
      security = security!()

      for {probability, resolves_on} <- [{"0.50", "2026-11-12"}, {"0.99", "2031-11-09"}] do
        assert {:ok, prediction} =
                 create(
                   agent(),
                   attrs(security, %{"probability" => probability, "resolves_on" => resolves_on})
                 )

        assert prediction.probability == Decimal.new(probability)
      end
    end
  end

  # User story (ADR-0055 §§1-2; Sprint 25 plan, D-8.1):
  # As the operator who reads the calibration report,
  # I want every way of bending a prediction refused at the write,
  # so that the report scores only calls stated plainly, ahead of their
  # outcome, by an author who cannot hide which model made them.
  #
  # Acceptance criteria (each refused, nothing stored):
  # - a caller-supplied made_at, author or actor;
  # - a probability of 0.49 (the message names the other direction), 1.00,
  #   0.555, or a float;
  # - an agent's write without a model, an operator's write with one;
  # - resolves_on 6 days and 1,831 days after the UTC day made;
  # - a note_id of another security;
  # - a benchmark security not flagged is_benchmark, the security itself as
  #   its benchmark, and a malformed benchmark.
  describe "create_prediction/3 refuses" do
    setup do
      %{security: security!()}
    end

    test "a caller-supplied made_at, author or actor", %{security: security} do
      for {key, value} <- [
            {"made_at", "2020-01-01T00:00:00Z"},
            {"author", "operator"},
            {"actor", "someone-else"}
          ] do
        assert {:error, changeset} = create(agent(), Map.put(attrs(security), key, value))
        field = if is_atom(key), do: key, else: String.to_existing_atom(key)
        assert [message] = errors_on(changeset)[field]
        assert message =~ "cannot be given"
      end

      assert count() == 0
    end

    test "a probability of 0.49, naming the other direction", %{security: security} do
      assert {:error, changeset} = create(agent(), attrs(security, %{"probability" => "0.49"}))

      assert errors_on(changeset).probability == [
               "must be at least 0.50: a call below 50 % is the opposite call, so record it " <>
                 "as underperform with probability 0.51"
             ]

      assert {:error, changeset} =
               create(
                 agent(),
                 attrs(security, %{"probability" => "0.49", "direction" => "underperform"})
               )

      assert [message] = errors_on(changeset).probability
      assert message =~ "as outperform with probability 0.51"
      assert count() == 0
    end

    test "a probability of 1.00, of 0.555 and a float", %{security: security} do
      assert {:error, changeset} = create(agent(), attrs(security, %{"probability" => "1.00"}))
      assert [message] = errors_on(changeset).probability
      assert message =~ "must be at most 0.99"

      assert {:error, changeset} = create(agent(), attrs(security, %{"probability" => "0.555"}))
      assert ["must be in steps of 0.01, such as 0.55 or 0.56"] = errors_on(changeset).probability

      for value <- [0.7, 1, "NaN", "seventy"] do
        assert {:error, changeset} = create(agent(), attrs(security, %{"probability" => value}))
        assert [message] = errors_on(changeset).probability
        assert message =~ "must be a decimal string"
      end

      assert count() == 0
    end

    test "an agent's write without a model, an operator's with one", %{security: security} do
      for model <- [nil, "", "   "] do
        assert {:error, changeset} =
                 create(agent(), Map.put(attrs(security), "model", model))

        assert ["is required for an agent's prediction: name the model you run on"] =
                 errors_on(changeset).model
      end

      assert {:error, changeset} = create(agent(), Map.delete(attrs(security), "model"))
      assert [_required] = errors_on(changeset).model

      assert {:error, changeset} = create(operator(), attrs(security))

      assert ["is recorded only for an agent's prediction; the operator's carries none"] =
               errors_on(changeset).model

      assert {:error, changeset} =
               create(agent(), attrs(security, %{"model" => String.duplicate("m", 101)}))

      assert [too_long] = errors_on(changeset).model
      assert too_long =~ "100"

      assert count() == 0
    end

    test "resolves_on 6 days and 1,831 days after the day made", %{security: security} do
      assert {:error, changeset} =
               create(agent(), attrs(security, %{"resolves_on" => "2026-11-11"}))

      assert [
               "must be at least 7 days after the day the prediction is made " <>
                 "(2026-11-05, UTC): 2026-11-12 or later"
             ] = errors_on(changeset).resolves_on

      assert {:error, changeset} =
               create(agent(), attrs(security, %{"resolves_on" => "2031-11-10"}))

      assert [
               "must be at most 1830 days after the day the prediction is made " <>
                 "(2026-11-05, UTC): 2031-11-09 or earlier"
             ] = errors_on(changeset).resolves_on

      assert count() == 0
    end

    test "the made day is the UTC day, whatever the hour" do
      security = security!("Late Call Co.")
      late = ~U[2026-11-05 23:59:59.999999Z]

      assert {:error, changeset} =
               Predictions.create_prediction(
                 agent(),
                 attrs(security, %{"resolves_on" => "2026-11-11"}),
                 now: late
               )

      assert [_six_days] = errors_on(changeset).resolves_on

      assert {:ok, _seven_days} =
               Predictions.create_prediction(
                 agent(),
                 attrs(security, %{"resolves_on" => "2026-11-12"}),
                 now: late
               )
    end

    test "a note_id of another security, and one that does not exist", %{security: security} do
      other_note = note!(security!("Other Co."))

      assert {:error, changeset} =
               create(agent(), attrs(security, %{"note_id" => other_note.id}))

      assert ["must reference a research-log entry of the same security"] =
               errors_on(changeset).note_id

      assert {:error, changeset} = create(agent(), attrs(security, %{"note_id" => 999_999_999}))

      assert ["must reference a research-log entry of the same security"] =
               errors_on(changeset).note_id

      assert count() == 0
    end

    test "a benchmark security not flagged is_benchmark, the security itself, or none",
         %{security: security} do
      plain = security!("Plain Co.")

      for benchmark <- [
            "security:#{plain.id}",
            "security:999999999",
            "security:#{security.id}"
          ] do
        assert {:error, changeset} =
                 create(agent(), attrs(security, %{"benchmark" => benchmark}))

        assert [_refused] = errors_on(changeset).benchmark
      end

      assert {:error, changeset} =
               create(agent(), attrs(security, %{"benchmark" => "security:#{plain.id}"}))

      assert ["is not a benchmark security"] = errors_on(changeset).benchmark

      for benchmark <- [
            nil,
            "",
            "index",
            "security:abc",
            "security:-1",
            "rate:abc",
            "rate:11",
            "rate:NaN",
            7
          ] do
        assert {:error, changeset} =
                 create(agent(), attrs(security, %{"benchmark" => benchmark}))

        assert [_refused] = errors_on(changeset).benchmark
      end

      assert count() == 0
    end

    test "a security that does not exist, and a direction outside the set" do
      assert {:error, changeset} =
               create(agent(), %{
                 "security_id" => 999_999_999,
                 "direction" => "sideways_zz",
                 "probability" => "0.60",
                 "benchmark" => "rate:0",
                 "resolves_on" => "2027-01-01",
                 "model" => "example-model-1"
               })

      errors = errors_on(changeset)
      assert errors.security_id == ["does not exist"]
      assert errors.direction == ["must be outperform or underperform"]
      assert_raise ArgumentError, fn -> String.to_existing_atom("sideways_zz") end
      assert count() == 0
    end

    test "invisible characters in the model and an overlong rationale", %{security: security} do
      assert {:error, changeset} =
               create(agent(), attrs(security, %{"model" => "example#{<<0x200B::utf8>>}model"}))

      assert [_invisible] = errors_on(changeset).model

      assert {:error, changeset} =
               create(agent(), attrs(security, %{"rationale" => String.duplicate("r", 4001)}))

      assert [too_long] = errors_on(changeset).rationale
      assert too_long =~ "4000"
      assert count() == 0
    end
  end

  # User story (ADR-0055 §5, the storage half; F2 adds the status):
  # As the agent coming back to its calls,
  # I want to read one prediction and list them by security, author, model
  # and the date they resolve on,
  # so that I can find the calls that are due.
  #
  # Acceptance criteria:
  # - get_prediction/1 answers the struct or nil.
  # - list_predictions/2 filters by security_id, author, model and
  #   due_before (open, resolves_on on or before the date), newest first; an
  #   author outside the set matches nothing and mints no atom.
  describe "get_prediction/1 and list_predictions/2" do
    test "filter by security, author, model and due_before" do
      a = security!("Alpha Co.")
      b = security!("Beta Co.")

      {:ok, p1} = create(agent(), attrs(a, %{"resolves_on" => "2026-12-01"}))

      {:ok, p2} =
        create(agent(), attrs(b, %{"resolves_on" => "2027-06-01", "model" => "example-model-2"}))

      {:ok, p3} =
        create(operator(), attrs(a, %{"resolves_on" => "2027-01-01"}) |> Map.delete("model"))

      assert Predictions.get_prediction(p1.id).id == p1.id
      assert Predictions.get_prediction(999_999_999) == nil

      # The made day (2026-11-05) is today: every call here is still open.
      ids = fn filters ->
        filters |> Predictions.list_predictions(today: ~D[2026-11-05]) |> Enum.map(& &1.id)
      end

      assert ids.([]) == [p3.id, p2.id, p1.id]
      assert ids.(security_id: a.id) == [p3.id, p1.id]
      assert ids.(author: :agent) == [p2.id, p1.id]
      assert ids.(author: "operator") == [p3.id]
      assert ids.(author: "nobody_zz") == []
      assert ids.(model: "example-model-2") == [p2.id]
      assert ids.(due_before: ~D[2027-01-01]) == [p3.id, p1.id]
      assert ids.(due_before: ~D[2026-11-30]) == []
      assert ids.(security_id: a.id, author: :agent, due_before: ~D[2027-12-31]) == [p1.id]
      assert ids.(limit: 1) == [p3.id]
      assert_raise ArgumentError, fn -> String.to_existing_atom("nobody_zz") end
    end
  end

  # User story (ADR-0055 §3; E25 S6, F53's rule):
  # As the operator whose pages are served from derived values,
  # I want a prediction — a record no walk, quote, rate or rule reads — to
  # leave every portfolio's derived values current,
  # so that an agent recording calls does not keep the refresher
  # recomputing every portfolio's walk.
  #
  # Acceptance criteria:
  # - A prediction write leaves a portfolio's basis version unchanged.
  # - Resolved per struct: a record of another shape still widens.
  describe "the blast radius of a prediction" do
    test "a prediction moves no portfolio's derived values, and widens otherwise" do
      {:ok, portfolio} =
        Portfolios.create_portfolio(operator(), %{
          name: "Radius Folio",
          base_currency_code: "EUR"
        })

      security = security!()
      basis = DataVersion.portfolio_basis(portfolio.id)
      before = DataVersion.current(basis)

      {:ok, _prediction} = create(agent(), attrs(security))

      assert DataVersion.current(basis) == before
      assert BlastRadius.for_write("prediction", %Prediction{}) == []
      assert BlastRadius.for_write("prediction", %{security_id: 1}) == :all
    end

    # User story (the Sprint 25 closing act's correctness lens, reproduced:
    # six securities, one prediction, six security: version events):
    # As the operator whose security pages are served from derived values,
    # I want a prediction write to bump no security's derived basis,
    # so that recording a call does not recompute every security's metrics.
    #
    # Acceptance criteria:
    # - After a prediction write every security's basis version is
    #   unchanged, the called security's and the benchmark's included.
    # - BlastRadius.securities_for_write("prediction", _) is [].
    test "a prediction moves no security's derived basis" do
      securities = for name <- ~w(Alpha Beta Gamma), do: security!(name <> " Radius Co.")
      index = benchmark!("Radius Index")
      bases = Enum.map([index | securities], &DataVersion.security_basis(&1.id))
      before = Enum.map(bases, &DataVersion.current/1)

      {:ok, _prediction} =
        create(agent(), attrs(hd(securities), %{"benchmark" => "security:#{index.id}"}))

      assert Enum.map(bases, &DataVersion.current/1) == before
      assert BlastRadius.securities_for_write("prediction", %Prediction{}) == []
    end
  end
end
