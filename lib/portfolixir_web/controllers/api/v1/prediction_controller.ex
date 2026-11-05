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

  `index` lists them newest first, each with its resolution, filtered by
  `security_id`, `status` (`open`, `resolved`, `unresolved`, derived at
  read), `author` (`operator`, `agent`), `model` and `due_before` (the due
  query: open predictions whose `resolves_on` is on or before the date),
  with `limit` (default 100, at most 500) and `truncated`. `calibration` is
  the report of ADR-0055 §4, filtered by `author`, `model` and the
  `resolves_on` range `from` / `to` (both inclusive). Every read carries its
  `computation_basis`; a malformed filter answers 422 naming it, and `to`
  before `from` answers 422 on `to`.

  There is deliberately no update and no delete action (§2): a mistaken
  prediction stays and counts, and a correction is a new prediction.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Clock
  alias Portfolixir.Predictions
  alias Portfolixir.Predictions.Prediction
  alias PortfolixirWeb.Api.V1.DateParam
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ListLimit
  alias PortfolixirWeb.Api.V1.PredictionJSON
  alias PortfolixirWeb.Api.V1.TextParam

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

  # A bound, not a page: each row is resolved at read from up to four
  # stored closes and their rates, as the sale hindsight read's rows are.
  @default_limit 100
  @max_limit 500

  @statuses ~w(open resolved unresolved)
  @authors Prediction.authors()

  def index(conn, params) do
    with {:ok, security_id} <- id_filter(params, "security_id"),
         {:ok, status} <- closed_filter(params, "status", @statuses),
         {:ok, author} <- closed_filter(params, "author", @authors),
         {:ok, model} <- text_filter(params, "model"),
         {:ok, due_before} <- date_filter(params, "due_before"),
         {:ok, limit} <- ListLimit.parse(params, @default_limit, @max_limit) do
      filters = %{
        security_id: security_id,
        status: status,
        author: author,
        model: model,
        due_before: due_before
      }

      {entries, truncated} =
        filters
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Keyword.new()
        |> Keyword.put(:limit, ListLimit.fetch(limit))
        |> Predictions.list_with_resolution()
        |> ListLimit.page(limit)

      json(conn, %{
        data: %{
          as_of: JSON.date(Clock.today()),
          filters: %{filters | due_before: JSON.date(due_before)},
          limit: limit,
          truncated: truncated,
          predictions:
            Enum.map(entries, &PredictionJSON.prediction(&1.prediction, &1.resolution)),
          permanence_note: PredictionJSON.permanence_note(),
          computation_basis: PredictionJSON.resolution_basis()
        }
      })
    else
      {:error, field} -> unprocessable(conn, %{field => ["is invalid"]})
    end
  end

  def calibration(conn, params) do
    with {:ok, author} <- closed_filter(params, "author", @authors),
         {:ok, model} <- text_filter(params, "model"),
         {:ok, from} <- date_filter(params, "from"),
         {:ok, to} <- date_filter(params, "to"),
         :ok <- ordered(from, to) do
      report =
        [author: author, model: model, resolves_from: from, resolves_to: to]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Predictions.calibration_report()

      json(conn, %{
        data:
          report
          |> PredictionJSON.calibration()
          |> Map.merge(%{
            as_of: JSON.date(Clock.today()),
            filters: %{author: author, model: model, from: JSON.date(from), to: JSON.date(to)},
            permanence_note: PredictionJSON.permanence_note()
          })
      })
    else
      {:error, :invalid_range} -> unprocessable(conn, %{to: ["must be on or after from"]})
      {:error, field} -> unprocessable(conn, %{field => ["is invalid"]})
    end
  end

  defp id_filter(params, key) do
    case Map.get(params, key) do
      value when value in [nil, ""] ->
        {:ok, nil}

      value ->
        case IdParam.parse(value) do
          {:ok, id} -> {:ok, id}
          :error -> {:error, key}
        end
    end
  end

  # A closed set is matched as text and handed on as text: the context
  # turns a known value into its atom, so no atom is made from input.
  defp closed_filter(params, key, allowed) do
    case Map.get(params, key) do
      value when value in [nil, ""] -> {:ok, nil}
      value when is_binary(value) -> if value in allowed, do: {:ok, value}, else: {:error, key}
      _not_text -> {:error, key}
    end
  end

  defp text_filter(params, key) do
    case TextParam.parse(params, key) do
      {:ok, text} -> {:ok, text}
      :error -> {:error, key}
    end
  end

  defp date_filter(params, key) do
    case DateParam.parse(params, key) do
      {:ok, date} -> {:ok, date}
      :error -> {:error, key}
    end
  end

  defp ordered(%Date{} = from, %Date{} = to) do
    if Date.compare(to, from) == :lt, do: {:error, :invalid_range}, else: :ok
  end

  defp ordered(_from, _to), do: :ok

  defp unprocessable(conn, errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end

  defp read(prediction) do
    prediction
    |> PredictionJSON.prediction(Predictions.resolve(prediction))
    |> Map.put(:permanence_note, PredictionJSON.permanence_note())
    |> Map.put(:computation_basis, PredictionJSON.resolution_basis())
  end
end
