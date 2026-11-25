defmodule PortfolixirWeb.Api.V1.PeriodController do
  @moduledoc """
  The operator's own periods over the API (ADR-0062's amendment of
  2026-11-25, point 6; Sprint 32 T2), from `Portfolixir.Periods`:

    * `GET /api/v1/periods` — the stored periods in the order they were
      made, each with `id`, `key` (`saved:<id>`, the key every read of the
      vocabulary takes), `name`, `from`, `to` (`null`: until today) and
      `lock_version`.
    * `POST /api/v1/periods` — `{"period": {name, from, to?}}` stores one
      (201); the 51st answers 422 `too_many_periods`.
    * `PUT /api/v1/periods/:id` — `{"period": {name, from, to,
      lock_version}}` replaces; a stale lock_version answers 409 with the
      period as stored under `errors.stored`.
    * `DELETE /api/v1/periods/:id` — 204; a pin that names it dangles.
    * `GET /api/v1/periods/quick` — the quick choice of the dashboard's top
      bar (Sprint 32 T3): `keys` in their order (the default while none is
      stored, `default: true`), `dropped` (the keys of deleted periods the
      read left out) and `max`.
    * `PUT /api/v1/periods/quick` — `{"quick": {"keys": [...]}}` stores up
      to six keys of the vocabulary; a refused list answers 422 on `keys`.

  Every read and write is closed: a parameter or field it does not take
  answers 422 naming it. Every write is journaled under the request's
  token (ADR-0017).
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Periods
  alias Portfolixir.Periods.SavedPeriod
  alias PortfolixirWeb.Api.V1.ClosedBody
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON

  plug(PortfolixirWeb.Api.V1.BodyObject, "period" when action in [:create, :replace])
  plug(PortfolixirWeb.Api.V1.BodyObject, "quick" when action in [:put_quick])

  @create_fields ~w(name from to)
  @replace_fields ~w(name from to lock_version)

  def index(conn, _params) do
    case ClosedBody.check(conn, nil, []) do
      :ok -> json(conn, %{data: Enum.map(Periods.list_saved(), &period/1)})
      {:error, errors} -> ClosedBody.refuse(conn, errors)
    end
  end

  def create(conn, _params) do
    with :ok <- ClosedBody.check(conn, "period", @create_fields),
         {:ok, period} <- Periods.create_saved(conn.assigns.actor, wrapped(conn)) do
      conn
      |> put_status(:created)
      |> json(%{data: period(period)})
    else
      refusal -> refuse(conn, refusal)
    end
  end

  def replace(conn, %{"id" => id}) do
    with {:ok, period_id} <- id(id),
         :ok <- ClosedBody.check(conn, "period", @replace_fields),
         {:ok, period} <- Periods.replace_saved(conn.assigns.actor, period_id, wrapped(conn)) do
      json(conn, %{data: period(period)})
    else
      refusal -> refuse(conn, refusal)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, period_id} <- id(id),
         {:ok, _deleted} <- Periods.delete_saved(conn.assigns.actor, period_id) do
      send_resp(conn, :no_content, "")
    else
      refusal -> refuse(conn, refusal)
    end
  end

  def quick(conn, _params) do
    case ClosedBody.check(conn, nil, []) do
      :ok -> json(conn, %{data: quick_choice()})
      {:error, errors} -> ClosedBody.refuse(conn, errors)
    end
  end

  def put_quick(conn, _params) do
    keys =
      case conn.body_params do
        %{"quick" => %{"keys" => keys}} -> keys
        _absent -> nil
      end

    with :ok <- ClosedBody.check(conn, "quick", ~w(keys)),
         {:ok, _keys} <- Periods.put_quick_choice(conn.assigns.actor, keys) do
      json(conn, %{data: quick_choice()})
    else
      {:error, {reason, message}} when is_atom(reason) ->
        ClosedBody.refuse(conn, %{keys: [message]})

      refusal ->
        refuse(conn, refusal)
    end
  end

  defp quick_choice do
    choice = Periods.quick_choice()
    Map.put(choice, :max, Periods.max_quick())
  end

  @doc "One stored period as the API answers it."
  @spec period(SavedPeriod.t()) :: map()
  def period(%SavedPeriod{} = period) do
    %{
      id: period.id,
      key: "saved:#{period.id}",
      name: period.name,
      from: Date.to_iso8601(period.from),
      to: period.to && Date.to_iso8601(period.to),
      lock_version: period.lock_version
    }
  end

  defp id(raw) do
    case IdParam.parse(raw) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp wrapped(conn) do
    case conn.body_params do
      %{"period" => %{} = attrs} when not is_struct(attrs) -> attrs
      _absent -> %{}
    end
  end

  defp refuse(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end

  defp refuse(conn, {:error, :stale, %SavedPeriod{} = stored}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      errors: %{
        code: "stale",
        detail:
          "the period changed since it was read and nothing was written: it is stored with " <>
            "lock_version #{stored.lock_version}, as errors.stored shows; build on it and " <>
            "send that lock_version",
        stored: period(stored)
      }
    })
  end

  defp refuse(conn, {:error, :too_many_periods}) do
    ClosedBody.refuse(conn, %{
      code: "too_many_periods",
      detail:
        "at most #{Periods.max_saved()} periods are stored: delete one before adding another"
    })
  end

  defp refuse(conn, {:error, %Ecto.Changeset{} = changeset}),
    do: ClosedBody.refuse(conn, JSON.errors(changeset))

  defp refuse(conn, {:error, {:unknown_fields, errors}}), do: ClosedBody.refuse(conn, errors)
  defp refuse(conn, {:error, {:missing_fields, errors}}), do: ClosedBody.refuse(conn, errors)
  defp refuse(conn, {:error, errors}) when is_map(errors), do: ClosedBody.refuse(conn, errors)
end
