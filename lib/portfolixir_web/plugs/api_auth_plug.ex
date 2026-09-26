defmodule PortfolixirWeb.ApiAuthPlug do
  @moduledoc """
  The JSON API's bearer-token check (FR-28, ADR-0017, #761, #771).

  **Named principals** (E25 S7, G26; the architecture's FU-6): the API
  accepts a list of `{name, token}` entries (`config :portfolixir,
  :api_tokens`, built at boot by `Portfolixir.RuntimeConfig.api_tokens!/3`
  from `PORTFOLIXIR_API_TOKENS`, `PORTFOLIXIR_API_TOKEN` and
  `PORTFOLIXIR_API_PRINCIPAL`). The actor of a request is derived from the
  entry the presented token matches — its name becomes the journal's actor
  label — never from anything the caller sends. The default
  (`PORTFOLIXIR_API_TOKEN`) journals no label, as before, unless
  `PORTFOLIXIR_API_PRINCIPAL` names it.
  Every entry carries the same full authority: a name attributes a write, it
  does not narrow what the token may do.
  """

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
    case matching_principal(bearer_token(conn), principals()) do
      {:ok, name} ->
        Throttle.success(:api, source)
        # Every configured token is read-write (FR-28 / ADR-0017). A future
        # read-only token (D4) assigns :api_token_ro here instead.
        assign(conn, :actor, Portfolixir.Actor.api_token_rw(name))

      :error ->
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

  # The configured principals. A release has them from runtime.exs, and so
  # does development when PORTFOLIXIR_API_TOKENS or PORTFOLIXIR_API_PRINCIPAL
  # is set (S7E-7); otherwise (development without them, the test
  # configuration) the one token of `:api_token` or PORTFOLIXIR_API_TOKEN is
  # the unnamed default, unchecked as before.
  defp principals do
    case Application.get_env(:portfolixir, :api_tokens) do
      list when is_list(list) ->
        list

      _unset ->
        case Application.get_env(:portfolixir, :api_token) ||
               System.get_env("PORTFOLIXIR_API_TOKEN") do
          token when is_binary(token) and token != "" -> [{nil, token}]
          _none -> []
        end
    end
  end

  # Every entry is compared, so the time taken does not depend on which one
  # matched; tokens are distinct by construction (`api_tokens!/3`).
  defp matching_principal(provided, principals) when is_binary(provided) do
    Enum.reduce(principals, :error, fn {name, token}, found ->
      if valid_token?(provided, token), do: {:ok, name}, else: found
    end)
  end

  defp matching_principal(_provided, _principals), do: :error

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
