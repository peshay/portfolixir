defmodule PortfolixirWeb.Api.V1.TaxConfigurationController do
  @moduledoc """
  The tax configuration layer over the JSON API (ADR-0031 §3, AR-11 parity with
  the entry surface): year-scoped statutory parameters, effective-dated
  taxpayer profiles, and configured Freistellungsaufträge.

  Every financial decimal serializes as a string, rates included — they are
  fractions (`"0.25"`), never percentages.

  An unseeded tax year is a 404, never a fallback to a neighbouring year: a
  silently wrong Sparer-Pauschbetrag is exactly what this configuration exists
  to prevent.
  """

  use PortfolixirWeb, :controller

  alias Portfolixir.Tax
  alias PortfolixirWeb.Api.V1.JSON

  def index_parameters(conn, params) do
    parameters = Tax.list_parameters(jurisdiction: params["jurisdiction"])
    json(conn, %{data: Enum.map(parameters, &JSON.tax_parameters/1)})
  end

  def upsert_parameters(conn, params) do
    attrs = Map.get(params, "parameters", %{})

    case Tax.upsert_parameters(conn.assigns.actor, attrs) do
      {:ok, parameters} -> json(conn, %{data: JSON.tax_parameters(parameters)})
      {:error, changeset} -> unprocessable(conn, changeset)
    end
  end

  def index_profiles(conn, %{"holder" => holder}) do
    json(conn, %{data: Enum.map(Tax.list_profiles(holder), &JSON.tax_profile/1)})
  end

  def index_profiles(conn, _params), do: missing_param(conn, "holder")

  def create_profile(conn, params) do
    attrs = Map.get(params, "profile", %{})

    case Tax.create_profile(conn.assigns.actor, attrs) do
      {:ok, profile} -> conn |> put_status(201) |> json(%{data: JSON.tax_profile(profile)})
      {:error, changeset} -> unprocessable(conn, changeset)
    end
  end

  def update_profile(conn, %{"id" => id} = params) do
    attrs = Map.get(params, "profile", %{})

    with {:ok, profile_id} <- parse_id(id),
         {:ok, profile} <- Tax.fetch_profile(profile_id) do
      case Tax.update_profile(conn.assigns.actor, profile, attrs) do
        {:ok, updated} -> json(conn, %{data: JSON.tax_profile(updated)})
        {:error, changeset} -> unprocessable(conn, changeset)
      end
    else
      _otherwise -> not_found(conn)
    end
  end

  def delete_profile(conn, %{"id" => id}) do
    with {:ok, profile_id} <- parse_id(id),
         {:ok, profile} <- Tax.delete_profile(conn.assigns.actor, profile_id) do
      json(conn, %{data: JSON.tax_profile(profile)})
    else
      _otherwise -> not_found(conn)
    end
  end

  def index_allowance_orders(conn, params) do
    orders =
      Tax.list_allowance_orders(
        holder: params["holder"],
        institution: params["institution"],
        tax_year: parse_year(params["tax_year"])
      )

    json(conn, %{data: Enum.map(orders, &JSON.allowance_order/1)})
  end

  def put_allowance_order(conn, params) do
    attrs = Map.get(params, "allowance_order", %{})

    case Tax.put_allowance_order(conn.assigns.actor, attrs) do
      {:ok, order} -> json(conn, %{data: JSON.allowance_order(order)})
      {:error, changeset} -> unprocessable(conn, changeset)
    end
  end

  def delete_allowance_order(conn, %{"id" => id}) do
    with {:ok, order_id} <- parse_id(id),
         {:ok, order} <- Tax.delete_allowance_order(conn.assigns.actor, order_id) do
      json(conn, %{data: JSON.allowance_order(order)})
    else
      _otherwise -> not_found(conn)
    end
  end

  defp parse_id(value) when is_integer(value), do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _other -> :error
    end
  end

  defp parse_id(_value), do: :error

  defp parse_year(nil), do: nil

  defp parse_year(value) when is_binary(value) do
    case Integer.parse(value) do
      {year, ""} -> year
      _other -> nil
    end
  end

  defp parse_year(value) when is_integer(value), do: value

  defp missing_param(conn, param) do
    conn |> put_status(422) |> json(%{errors: %{param => ["is required"]}})
  end

  defp unprocessable(conn, changeset) do
    conn |> put_status(422) |> json(%{errors: JSON.errors(changeset)})
  end

  defp not_found(conn) do
    conn |> put_status(404) |> json(%{errors: %{detail: "Not found"}})
  end
end
