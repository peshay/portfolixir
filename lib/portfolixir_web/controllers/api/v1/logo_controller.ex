defmodule PortfolixirWeb.Api.V1.LogoController do
  @moduledoc """
  Read and manage a security's logo: report its status, set a manual override
  from an image URL, remove it (locking "no logo"), or trigger automatic
  re-discovery ("search again").
  """

  use PortfolixirWeb, :controller

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias PortfolixirWeb.Api.V1.JSON

  def show(conn, %{"security_id" => id}) do
    case Catalog.get_security(id) do
      nil -> not_found(conn)
      security -> json(conn, %{data: JSON.logo_status(security)})
    end
  end

  def update(conn, %{"security_id" => id} = params) do
    with %Security{} = security <- Catalog.get_security(id),
         {:ok, url} <- logo_url(params),
         {:ok, updated} <- Catalog.set_logo_override(security, url, logo_opts()) do
      json(conn, %{data: JSON.logo_status(updated)})
    else
      nil -> not_found(conn)
      :error -> missing_url(conn)
      {:error, reason} -> unprocessable(conn, reason)
    end
  end

  def delete(conn, %{"security_id" => id}) do
    with %Security{} = security <- Catalog.get_security(id),
         {:ok, updated} <- Catalog.remove_logo(security, logo_opts()) do
      json(conn, %{data: JSON.logo_status(updated)})
    else
      nil -> not_found(conn)
      {:error, reason} -> unprocessable(conn, reason)
    end
  end

  def discover(conn, %{"security_id" => id}) do
    case Catalog.get_security(id) do
      nil -> not_found(conn)
      security -> json(conn, %{data: discover_payload(security)})
    end
  end

  defp discover_payload(security) do
    result =
      case Catalog.rediscover_logo(security, logo_opts()) do
        {:ok, _updated} -> "updated"
        :skip -> "no_source"
        {:error, _reason} -> "failed"
      end

    security = Catalog.get_security(security.id) || security
    Map.put(JSON.logo_status(security), :result, result)
  end

  # Manual logo operations reuse the same storage dir (and, in tests, the same
  # Req stub) the background discovery worker is configured with.
  defp logo_opts, do: Application.get_env(:portfolixir, :logo_discovery_opts, [])

  defp logo_url(%{"logo" => %{"url" => url}}), do: trimmed_url(url)
  defp logo_url(%{"url" => url}), do: trimmed_url(url)
  defp logo_url(_params), do: :error

  defp trimmed_url(url) when is_binary(url) do
    case String.trim(url) do
      "" -> :error
      trimmed -> {:ok, trimmed}
    end
  end

  defp trimmed_url(_url), do: :error

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end

  defp missing_url(conn) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{url: ["is required"]}})
  end

  defp unprocessable(conn, reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{logo: [to_string_reason(reason)]}})
  end

  # Fixed messages only (#762): the endpoint must be neither a way into the
  # operator's network nor an oracle for what answers there, so no status, no
  # address and no inspected term leaves this function.
  defp to_string_reason(:unsupported_content_type), do: "unsupported image type"
  defp to_string_reason(:too_large), do: "image is too large"

  defp to_string_reason({:url_not_allowed, _reason}),
    do: "image URL not allowed: use a public https address"

  defp to_string_reason(_reason), do: "could not download the image"
end
