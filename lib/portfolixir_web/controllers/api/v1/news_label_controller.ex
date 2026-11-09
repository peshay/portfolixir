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

  plug(PortfolixirWeb.Api.V1.BodyObject, "label" when action in [:put_label])

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
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp time(%DateTime{} = at), do: at |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
