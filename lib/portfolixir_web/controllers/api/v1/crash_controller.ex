defmodule PortfolixirWeb.Api.V1.CrashController do
  @moduledoc """
  The crash windows over the API (FR-54, ADR-0058 §9; Sprint 29, C5), each
  answer rendered by `PortfolixirWeb.Api.V1.CrashJSON` from
  `Portfolixir.Crashes`:

    * `GET /api/v1/crashes` — the windows the rule detects over the crash
      benchmark's closes, each with its name; the manual windows; the names
      whose key matches no window detected now (`unmatched_names`); the
      crash benchmark, or `reason` when none is chosen; the rule's
      computation basis. Takes no parameter.
    * `GET /api/v1/crashes/:key/rankings` — one list of the window `key`:
      `list` (`losers`, the default, `winners` or `rebounders`), `universe`
      (`catalogue`, the default, or `view:<id>`, the securities the view
      holds today), `limit` (default 8, capped at 50 and echoed) and
      `include_unanswered` (`true` lists the securities without an answer).
    * `PUT /api/v1/crashes/:key` — `{"window": {"name"}}` names a detected
      window (`d:<benchmark_security_id>:<start>`), or renames it;
      `{"window": {name, start, trough}}`, any of them, edits a manual one
      (`m:<id>`).
    * `POST /api/v1/crashes` — `{"window": {name, start, trough}}` draws a
      manual window (201); `{"window": {from_name, trough, name?}}` makes
      the name stored under the detected key `from_name`, which no window
      detected now carries, into a manual window from its stored start and
      the trough given (the amendment's F1), and deletes the name.
    * `DELETE /api/v1/crashes/:key` — a detected key's name, or a manual
      window.

  Every read and write is closed: a parameter or field it does not take
  answers 422 naming it. A key that names no window (or, for a delete, no
  name or manual window) answers 404, as does a view that does not exist.
  Every write is journaled under the request's token.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Crashes
  alias Portfolixir.Crashes.Rankings
  alias PortfolixirWeb.Api.V1.ClosedBody
  alias PortfolixirWeb.Api.V1.CrashJSON
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ListLimit

  plug(PortfolixirWeb.Api.V1.BodyObject, "window" when action in [:create, :update])

  @rankings_params ~w(list universe limit include_unanswered)
  @default_limit 8
  @name_fields ~w(name)
  @manual_fields ~w(name start trough)
  @from_name_fields ~w(from_name name trough)

  def index(conn, _params) do
    case ClosedBody.check(conn, nil, []) do
      :ok -> json(conn, %{data: CrashJSON.windows(Crashes.list_windows())})
      {:error, errors} -> ClosedBody.refuse(conn, errors)
    end
  end

  def rankings(conn, %{"key" => key}) do
    params = conn.query_params

    with :ok <- closed_read(conn),
         {:ok, opts} <- rankings_opts(params),
         {:ok, payload} <- Crashes.rankings(key, defaulted(params, "universe", "catalogue"), opts) do
      json(conn, %{data: CrashJSON.rankings(payload)})
    else
      {:error, refusal} -> refuse(conn, refusal)
    end
  end

  def update(conn, %{"key" => key} = params) do
    with {:ok, fields} <- put_fields(key),
         :ok <- ClosedBody.check(conn, "window", fields),
         {:ok, written} <- Crashes.put_window(conn.assigns.actor, key, window(params)) do
      json(conn, %{data: CrashJSON.written(written)})
    else
      {:error, refusal} -> refuse(conn, refusal)
    end
  end

  def create(conn, params) do
    attrs = window(params)
    from_name? = Map.has_key?(attrs, "from_name")

    with :ok <- ClosedBody.check(conn, "window", create_fields(from_name?)),
         {:ok, written} <- create_window(conn.assigns.actor, attrs, from_name?) do
      conn
      |> put_status(:created)
      |> json(%{data: CrashJSON.written(written)})
    else
      {:error, refusal} -> refuse(conn, refusal)
    end
  end

  def delete(conn, %{"key" => key}) do
    with :ok <- ClosedBody.check(conn, nil, []),
         {:ok, deleted} <- Crashes.delete_window(conn.assigns.actor, key) do
      json(conn, %{data: CrashJSON.deleted(deleted)})
    else
      {:error, refusal} -> refuse(conn, refusal)
    end
  end

  # --- the read's parameters ---

  defp closed_read(conn) do
    body = if is_map(conn.body_params), do: conn.body_params, else: %{}

    case ClosedBody.unknown(Map.merge(conn.query_params, body), @rankings_params, "this read") do
      empty when empty == %{} -> :ok
      errors -> {:error, errors}
    end
  end

  defp rankings_opts(params) do
    with {:ok, limit} <- limit(params),
         {:ok, include_unanswered} <- include_unanswered(params) do
      {:ok,
       [
         list: defaulted(params, "list", "losers"),
         limit: limit,
         include_unanswered: include_unanswered
       ]}
    end
  end

  # The limit family's contract (#771): absent or blank the default, above
  # the maximum capped (and echoed in the answer), zero or text refused.
  defp limit(params) do
    case ListLimit.parse(params, @default_limit, Rankings.max_limit()) do
      {:ok, limit} -> {:ok, limit}
      {:error, :limit} -> {:error, %{limit: ["is invalid: a positive integer, at most 50"]}}
    end
  end

  defp include_unanswered(params) do
    case Map.get(params, "include_unanswered") do
      value when value in [nil, "", "false"] -> {:ok, false}
      "true" -> {:ok, true}
      _other -> {:error, %{include_unanswered: ["is invalid: true or false"]}}
    end
  end

  defp defaulted(params, key, default) do
    case Map.get(params, key) do
      value when value in [nil, ""] -> default
      value -> value
    end
  end

  # --- the writes ---

  defp window(params) do
    case Map.get(params, "window") do
      %{} = attrs when not is_struct(attrs) -> attrs
      _absent -> %{}
    end
  end

  # A detected window takes only a name; a manual one its fields; any other
  # key names nothing.
  defp put_fields("d:" <> _rest), do: {:ok, @name_fields}
  defp put_fields("m:" <> _rest), do: {:ok, @manual_fields}
  defp put_fields(_key), do: {:error, :not_found}

  defp create_fields(true), do: @from_name_fields
  defp create_fields(false), do: @manual_fields

  defp create_window(actor, attrs, false), do: Crashes.create_manual_window(actor, attrs)

  defp create_window(actor, %{"from_name" => key} = attrs, true) when is_binary(key) do
    case Crashes.manual_window_from_name(actor, key, Map.delete(attrs, "from_name")) do
      {:error, :not_found} ->
        {:error,
         %{from_name: ["names no stored name: a detected window's key under unmatched_names"]}}

      {:error, :name_has_window} ->
        {:error,
         %{
           from_name: [
             "names a window the rule still detects: it keeps its name (PUT /api/v1/crashes/:key)"
           ]
         }}

      answer ->
        answer
    end
  end

  defp create_window(_actor, _attrs, true),
    do:
      {:error,
       %{from_name: ["is invalid: a detected window's key, d:<benchmark_security_id>:<start>"]}}

  # --- the refusals ---

  defp refuse(conn, :not_found), do: not_found(conn)
  defp refuse(conn, :view_not_found), do: not_found(conn)

  defp refuse(conn, :invalid_list),
    do: ClosedBody.refuse(conn, %{list: ["is invalid: losers, winners or rebounders"]})

  defp refuse(conn, :invalid_universe),
    do: ClosedBody.refuse(conn, %{universe: ["is invalid: catalogue or view:<id>"]})

  defp refuse(conn, :invalid_limit),
    do: ClosedBody.refuse(conn, %{limit: ["is invalid: a positive integer, at most 50"]})

  defp refuse(conn, %Ecto.Changeset{} = changeset),
    do: ClosedBody.refuse(conn, JSON.errors(changeset))

  defp refuse(conn, {:unknown_fields, errors}), do: ClosedBody.refuse(conn, errors)
  defp refuse(conn, errors) when is_map(errors), do: ClosedBody.refuse(conn, errors)

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end
end
