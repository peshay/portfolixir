defmodule PortfolixirWeb.Api.V1.NewsLabelController do
  @moduledoc """
  The labeller's surface of the news layer (ADR-0056 §7; Sprint 28, N1):

    * `PUT /api/v1/news/labels` (`news.label_put`) stores one label:
      `{"label": {cluster_id, model, prompt_version, event_type,
      materiality, tone, confidence, thesis_note_id?, clause_idx?,
      suggested_security_id?, machine_generated?}}`. A new label answers
      201, a put of a stored `(cluster_id, model, prompt_version)` replaces
      it in place and answers 200 (an equal put writes nothing and answers
      200 too). See `Portfolixir.News.Labels`.
    * `GET /api/v1/news/unlabeled` (`news.unlabeled`) answers the stories
      without a label of `prompt_version` (required), at most `limit` (10,
      at most 25), newest first: `rows` (id, security_id or category_id,
      title, excerpt, domain, tier, at), `truncated`, and once per answer
      the `universe` (id, name of at most 20 characters, isin), the rows'
      `categories` and per security of the rows its intact thesis's
      invalidation condition as numbered `clauses` with its `note_id`. See
      `Portfolixir.News.Labels.unlabeled/2`. Closed: any other parameter
      answers 422 naming it.

  **Closed** (§7): a key outside those fields, inside `label` or beside it,
  answers 422 naming it (`PortfolixirWeb.Api.V1.ClosedBody`), and so does a
  value of the wrong JSON type, a value outside §7's ranges, and a story,
  security, thesis or clause that is not there. `confidence` is a decimal
  string; a JSON number answers `"must be a decimal string"` (ADR-0003).
  Every write is journaled under the token that made it (§14 item 6,
  ADR-0054 §3). Answers are compact by §9's rule: null fields left out,
  `confidence` a string.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.News
  alias Portfolixir.News.Label
  alias PortfolixirWeb.Api.V1.ClosedBody
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ListLimit

  plug(PortfolixirWeb.Api.V1.BodyObject, "label" when action in [:put_label])

  @unlabeled_params ~w(prompt_version limit)
  @unlabeled_default 10
  @unlabeled_max 25

  def put_label(conn, _params) do
    with :ok <- ClosedBody.check(conn, "label", Label.fields()),
         {:ok, attrs} <- label_attrs(conn.body_params),
         {:ok, written, label} <- News.put_label(conn.assigns.actor, attrs) do
      conn
      |> put_status(if written == :created, do: :created, else: :ok)
      |> json(%{data: label_json(label)})
    else
      {:error, %Ecto.Changeset{} = changeset} -> ClosedBody.refuse(conn, JSON.errors(changeset))
      {:error, errors} -> ClosedBody.refuse(conn, errors)
    end
  end

  def unlabeled(conn, params) do
    with :ok <- closed(conn.query_params),
         {:ok, version} <- prompt_version(params["prompt_version"]),
         {:ok, limit} <- limit(params) do
      answer = News.unlabeled(version, limit)

      data =
        compact(%{
          prompt_version: version,
          limit: limit,
          truncated: answer.truncated,
          rows:
            Enum.map(answer.rows, &(&1 |> Map.update!(:at, fn at -> time(at) end) |> compact())),
          universe: Enum.map(answer.universe, &compact/1),
          categories: if(answer.categories == [], do: nil, else: answer.categories),
          theses: Enum.map(answer.theses, &compact/1)
        })

      json(conn, %{data: data})
    else
      {:error, errors} -> ClosedBody.refuse(conn, errors)
    end
  end

  # A closed query of single values: a key not taken, or a list or a map
  # (`prompt_version[]=v1`), is named.
  defp closed(query) do
    unknown =
      for key <- Map.keys(query), key not in @unlabeled_params, into: %{} do
        {key, ["is unknown: this read takes only #{Enum.join(@unlabeled_params, ", ")}"]}
      end

    not_single =
      for {key, value} <- query, key in @unlabeled_params, not is_binary(value), into: %{} do
        {key, ["must be a single value, not a list or a map"]}
      end

    case Map.merge(not_single, unknown) do
      empty when empty == %{} -> :ok
      errors -> {:error, errors}
    end
  end

  defp prompt_version(value) when value in [nil, ""],
    do: {:error, %{"prompt_version" => ["can't be blank"]}}

  defp prompt_version(value) do
    if Label.identifier?(value),
      do: {:ok, value},
      else:
        {:error,
         %{
           "prompt_version" => [
             "must be 1 to 64 letters, digits or . _ : / @ + -, starting with a letter or a digit"
           ]
         }}
  end

  defp limit(params) do
    case ListLimit.parse(params, @unlabeled_default, @unlabeled_max) do
      {:ok, limit} -> {:ok, limit}
      {:error, :limit} -> {:error, %{"limit" => ["must be a positive integer"]}}
    end
  end

  defp compact(map), do: map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()

  # BodyObject has answered a `label` that is not an object; one that is
  # absent is named here.
  defp label_attrs(%{"label" => %{} = attrs}), do: {:ok, attrs}
  defp label_attrs(_body), do: {:error, %{"label" => ["can't be blank"]}}

  defp label_json(%Label{} = label) do
    %{
      id: label.id,
      cluster_id: label.cluster_id,
      model: label.model,
      prompt_version: label.prompt_version,
      event_type: label.event_type,
      materiality: label.materiality,
      tone: label.tone,
      confidence: Decimal.to_string(label.confidence, :normal),
      thesis_note_id: label.thesis_note_id,
      clause_idx: label.clause_idx,
      suggested_security_id: label.suggested_security_id,
      machine_generated: label.machine_generated,
      created_at: time(label.created_at),
      updated_at: time(label.updated_at)
    }
    |> compact()
  end

  defp time(%DateTime{} = at), do: at |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
