defmodule PortfolixirWeb.Api.V1.PredictionController do
  @moduledoc """
  JSON API for predictions (ADR-0055 §5): permanent records of a stated
  call on one security, resolved at read against stored closes in EUR.

  `create` records one call from a `prediction` object. The author and the
  token's name come from the credential and `made_at` from the server's
  clock, as the research log derives its author (ADR-0054 §1): a body that
  carries `made_at`, `author` or `actor` is passed to the context as sent,
  so it is refused by name with a 422 rather than silently dropped. No
  clock is ever forwarded from a request (`create_prediction/3`'s `:now` is
  a test seam). `show` answers one prediction with its resolution.

  There is deliberately no update and no delete action (§2): a mistaken
  prediction stays and counts, and a correction is a new prediction.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Predictions
  alias Portfolixir.Predictions.Prediction
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.PredictionJSON

  plug(PortfolixirWeb.Api.V1.BodyObject, "prediction" when action in [:create])

  def create(conn, params) do
    attrs = Map.get(params, "prediction", %{})

    case Predictions.create_prediction(conn.assigns.actor, attrs) do
      {:ok, prediction} ->
        conn
        |> put_status(:created)
        |> json(%{data: read(prediction)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: JSON.errors(changeset)})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, prediction_id} <- IdParam.parse(id),
         %Prediction{} = prediction <- Predictions.get_prediction(prediction_id) do
      json(conn, %{data: read(prediction)})
    else
      _missing ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "not found"}})
    end
  end

  defp read(prediction) do
    prediction
    |> PredictionJSON.prediction(Predictions.resolve(prediction))
    |> Map.put(:permanence_note, PredictionJSON.permanence_note())
    |> Map.put(:computation_basis, PredictionJSON.resolution_basis())
  end
end
