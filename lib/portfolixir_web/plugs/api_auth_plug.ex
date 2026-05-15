defmodule PortfolixirWeb.ApiAuthPlug do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    configured_token = api_token()
    provided_token = bearer_token(conn)

    if valid_token?(provided_token, configured_token) do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{errors: %{detail: "unauthorized"}})
      |> halt()
    end
  end

  defp api_token do
    Application.get_env(:portfolixir, :api_token) ||
      System.get_env("PORTFOLIXIR_API_TOKEN")
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> token
      _ -> nil
    end
  end

  defp valid_token?(provided, configured)
       when is_binary(provided) and is_binary(configured) and configured != "" do
    byte_size(provided) == byte_size(configured) and
      Plug.Crypto.secure_compare(provided, configured)
  end

  defp valid_token?(_provided, _configured), do: false
end
