defmodule Portfolixir.Predictions.PredictionChangesetTest do
  # ADR-0055 §1 (Sprint 25, the closing of Lane F's write path): the
  # changeset's input shapes that the context's tests do not reach — a
  # direction given as an atom, a probability given as a Decimal, a clock
  # without sub-second precision — and the bounds the struct exposes for
  # the API and the MCP schema. Synthetic data only.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Predictions
  alias Portfolixir.Predictions.Prediction
  alias Portfolixir.WorldFixtures

  defp agent, do: Actor.api_token_rw("research-agent")

  defp security!,
    do: WorldFixtures.create_security!(name: "Shape Co.", ticker: nil, asset_class: "equity")

  defp attrs(security, extra) do
    Map.merge(
      %{
        security_id: security.id,
        direction: "outperform",
        probability: "0.70",
        benchmark: "rate:0",
        resolves_on: ~D[2027-05-05],
        model: "example-model-1"
      },
      extra
    )
  end

  defp errors_on_create(extra, now \\ ~U[2026-11-05 14:30:00.000000Z]) do
    security = security!()

    case Predictions.create_prediction(agent(), attrs(security, extra), now: now) do
      {:ok, prediction} -> {:ok, prediction}
      {:error, changeset} -> {:error, errors_on(changeset)}
    end
  end

  # User story (ADR-0055 §1):
  # As the operator's agent recording a call at the moment the server
  # states,
  # I want the write to hold whatever precision the server's clock has,
  # so that a call made on a whole second is stored, not refused.
  #
  # Acceptance criteria:
  # - A clock reading with no sub-second part is stored at microsecond
  #   precision, the instant unchanged.
  test "a made_at without a sub-second part is stored at microsecond precision" do
    assert {:ok, prediction} = errors_on_create(%{}, ~U[2026-11-05 15:00:00Z])

    assert prediction.made_at == ~U[2026-11-05 15:00:00.000000Z]
    assert DateTime.compare(prediction.made_at, ~U[2026-11-05 15:00:00Z]) == :eq
    assert Prediction.made_on(prediction) == ~D[2026-11-05]
  end

  # User story (ADR-0055 §1):
  # As a caller of the context (the API and the MCP companion pass
  # strings; a test or a script may pass the values themselves),
  # I want a direction given as its atom and a probability given as a
  # Decimal accepted exactly as their string forms are,
  # so that one call is one call whatever its spelling.
  #
  # Acceptance criteria:
  # - :underperform and Decimal "0.65" are stored as given.
  # - A direction that is neither a known atom nor a string is refused.
  # - A Decimal that is not finite is refused with the shape message.
  # - A blank direction and a missing benchmark are named as missing.
  test "a direction as its atom and a probability as a Decimal are accepted; other shapes are refused" do
    assert {:ok, prediction} =
             errors_on_create(%{direction: :underperform, probability: Decimal.new("0.65")})

    assert prediction.direction == :underperform
    assert prediction.probability == Decimal.new("0.65")

    assert {:error, %{direction: ["is invalid"]}} = errors_on_create(%{direction: 1})

    assert {:error, %{probability: [nan]}} = errors_on_create(%{probability: Decimal.new("NaN")})
    assert nan =~ ~s(must be a decimal string from "0.50" to "0.99")

    assert {:error, %{direction: ["can't be blank"]}} = errors_on_create(%{direction: ""})

    security = security!()
    no_benchmark = Map.delete(attrs(security, %{}), :benchmark)

    assert {:error, changeset} =
             Predictions.create_prediction(agent(), no_benchmark,
               now: ~U[2026-11-05 14:30:00.000000Z]
             )

    assert %{benchmark: ["can't be blank"]} = errors_on(changeset)
  end

  # User story (ADR-0055 §1):
  # As a caller refused at 0.49 without a direction,
  # I want the refusal to say that a call below 50 % is the opposite call,
  # so that I learn how to state it, even before I name the direction.
  #
  # Acceptance criteria:
  # - With no direction, the refusal names "the other direction" and 0.51.
  test "a probability below 0.50 with no direction names the other direction in general" do
    assert {:error, %{probability: [message]}} =
             errors_on_create(%{direction: nil, probability: "0.49"})

    assert message =~ "record it as the other direction with probability 0.51"
  end

  # User story (ADR-0055 §1; the API and the MCP schema state the bounds):
  # As the API and the companion describing the write,
  # I want the bounds read from the one place that enforces them,
  # so that a stated bound cannot drift from the enforced one.
  #
  # Acceptance criteria:
  # - The accessors answer 0.50, 0.99, 7, 1,830, 100 and 4,000.
  test "the bounds the struct states are the ones it enforces" do
    assert Prediction.min_probability() == Decimal.new("0.50")
    assert Prediction.max_probability() == Decimal.new("0.99")
    assert Prediction.min_days() == 7
    assert Prediction.max_days() == 1830
    assert Prediction.model_max() == 100
    assert Prediction.rationale_max() == 4000

    assert {:error, %{model: [too_long]}} =
             errors_on_create(%{model: String.duplicate("m", Prediction.model_max() + 1)})

    assert too_long =~ "100"
  end
end
