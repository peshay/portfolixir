defmodule PortfolixirWeb.ApiAuthPlug do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Portfolixir.Auth.Throttle

  def init(opts), do: opts

  # A locked-out source (#771) is answered 429 before the token is even
  # compared, right token or wrong; a wrong token counts against the source
  # and a right one clears it.
  def call(conn, _opts) do
    source = Throttle.source_key(conn.remote_ip)

    case Throttle.check(:api, source) do
      {:locked, seconds} -> locked(conn, seconds)
      :ok -> authenticate(conn, source)
    end
  end

  defp authenticate(conn, source) do
    if valid_token?(bearer_token(conn), api_token()) do
      Throttle.success(:api, source)
      # The single configured bearer token is read-write (FR-28 / ADR-0017).
      # A future read-only token (D4) assigns :api_token_ro here instead.
      assign(conn, :actor, Portfolixir.Actor.api_token_rw())
    else
      Throttle.failure(:api, source)

      conn
      |> put_status(:unauthorized)
      |> json(%{errors: %{detail: "unauthorized"}})
      |> halt()
    end
  end

  defp locked(conn, seconds) do
    conn
    |> put_resp_header("retry-after", Integer.to_string(seconds))
    |> put_status(:too_many_requests)
    |> json(%{errors: %{detail: "too many failed attempts; retry later"}})
    |> halt()
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
