defmodule PortfolixirWeb.Api.V1.SettingsController do
  @moduledoc """
  JSON API for the minimal user preferences (ADR-0024): today only the
  default-view preference the Wealth page and dashboard open on. `view_id` is
  `null` for the built-in Everything scope. No financial decimals are involved.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.View
  alias Portfolixir.Settings

  def show_default_view(conn, _params) do
    json(conn, %{data: default_view_payload()})
  end

  def set_default_view(conn, %{"view_id" => nil}) do
    :ok = Settings.set_default_view(nil)
    json(conn, %{data: default_view_payload()})
  end

  def set_default_view(conn, %{"view_id" => view_id}) when is_integer(view_id) do
    case Buckets.get_view(view_id) do
      %View{} = view ->
        :ok = Settings.set_default_view(view.id)
        json(conn, %{data: default_view_payload()})

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "not found"}})
    end
  end

  def set_default_view(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{detail: "view_id must be a positive integer or null"}})
  end

  defp default_view_payload do
    case Settings.default_view_id() do
      nil ->
        %{view_id: nil, view: nil}

      view_id ->
        view = Buckets.get_view(view_id)
        %{view_id: view_id, view: %{id: view.id, name: view.name}}
    end
  end
end
