defmodule PortfolixirWeb.Plugs.BrowserApiKeyAuth do
  @moduledoc "API key auth plug for browser/LiveView and CSV export surfaces."

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    config = Application.get_env(:portfolixir, __MODULE__, [])

    if Keyword.get(config, :enabled, false) do
      expected_key = Keyword.get(config, :api_key)

      case {expected_key, request_key(conn)} do
        {key, provided}
        when is_binary(key) and is_binary(provided) and byte_size(key) > 0 and
               byte_size(provided) > 0 ->
          if Plug.Crypto.secure_compare(provided, key) do
            conn
          else
            unauthorized(conn)
          end

        _ ->
          unauthorized(conn)
      end
    else
      conn
    end
  end

  defp request_key(conn) do
    conn
    |> get_req_header("x-api-key")
    |> List.first()
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(:unauthorized, "unauthorized")
    |> halt()
  end
end
