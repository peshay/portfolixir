defmodule PortfolixirWeb.Api.V1.PlanController do
  @moduledoc """
  Plan versions over the JSON API (ADR-0027, AR-11 parity with the SOLL
  editor): list a portfolio's plan versions, duplicate one into a draft,
  rename it, activate it (archiving the previously active plan of the same
  scope), and delete a version.
  """

  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.Targets
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, pid} <- parse_id(portfolio_id),
         %Portfolio{} <- Portfolios.get_portfolio(pid) do
      opts =
        case params["classification_id"] do
          nil ->
            []

          value ->
            case parse_id(value) do
              {:ok, cid} -> [classification_id: cid]
              :error -> []
            end
        end

      plans = Targets.list_plans(pid, opts)
      json(conn, %{data: %{plans: Enum.map(plans, &JSON.plan/1)}})
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
    end
  end

  def duplicate(conn, %{"id" => id} = params) do
    with {:ok, plan_id} <- parse_id(id),
         {:ok, copy} <-
           Targets.duplicate_plan(conn.assigns.actor, plan_id, Map.take(params, ["name"])) do
      conn |> put_status(201) |> json(%{data: JSON.plan(copy)})
    else
      :error -> not_found(conn)
      {:error, :not_found} -> not_found(conn)
      {:error, %Ecto.Changeset{} = changeset} -> unprocessable(conn, JSON.errors(changeset))
    end
  end

  def activate(conn, %{"id" => id}) do
    with {:ok, plan_id} <- parse_id(id),
         {:ok, plan} <- Targets.activate_plan(conn.assigns.actor, plan_id) do
      json(conn, %{data: JSON.plan(plan)})
    else
      :error -> not_found(conn)
      {:error, :not_found} -> not_found(conn)
      {:error, %Ecto.Changeset{} = changeset} -> unprocessable(conn, JSON.errors(changeset))
    end
  end

  def rename(conn, %{"id" => id} = params) do
    with {:ok, plan_id} <- parse_id(id),
         name when is_binary(name) and name != "" <- params["name"],
         {:ok, plan} <- Targets.rename_plan(conn.assigns.actor, plan_id, name) do
      json(conn, %{data: JSON.plan(plan)})
    else
      :error -> not_found(conn)
      {:error, :not_found} -> not_found(conn)
      {:error, %Ecto.Changeset{} = changeset} -> unprocessable(conn, JSON.errors(changeset))
      _ -> unprocessable(conn, %{name: ["is required"]})
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, plan_id} <- parse_id(id),
         {:ok, plan} <- Targets.delete_plan_version(conn.assigns.actor, plan_id) do
      json(conn, %{data: JSON.plan(plan)})
    else
      :error -> not_found(conn)
      {:error, :not_found} -> not_found(conn)
    end
  end

  defp parse_id(value) when is_integer(value), do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_id(_value), do: :error

  defp unprocessable(conn, errors) do
    conn |> put_status(422) |> json(%{errors: errors})
  end

  defp not_found(conn) do
    conn |> put_status(404) |> json(%{errors: %{detail: "Not found"}})
  end
end
