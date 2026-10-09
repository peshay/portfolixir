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
  alias Portfolixir.RuntimeConfig

  def init(opts), do: opts

  # The token is compared first (#974, the Sprint 20 plan's D-11) when every
  # configured token meets the 32-byte floor (`RuntimeConfig.min_token_bytes/0`):
  # a correct token passes whether its source is locked out (#771) or not, so a
  # stale client sharing the operator's address (every host client behind the
  # Compose port) cannot lock the agent out. A wrong token counts against its
  # source, locked or not, and is answered 429 while the lock lasts. The cost:
  # a locked guesser who guesses right is let in, which the floor makes
  # infeasible. A release holds every token to it at boot
  # (`RuntimeConfig.api_tokens!/3`), and so does a from-source server with
  # PORTFOLIXIR_API_TOKENS or PORTFOLIXIR_API_PRINCIPAL set; one that reads
  # PORTFOLIXIR_API_TOKEN alone holds it to none. While any configured token
  # is shorter, the order stays lock-first, as before #974: a locked source is
  # answered 429 before its token is compared, so a short token is never
  # guessed through the lock. The UI password stays lock-first
  # (`SessionController`).
  def call(conn, _opts) do
    source = Throttle.source_key(conn.remote_ip)
    principals = principals()

    if Enum.all?(principals, &sound_token?/1) do
      authenticate(conn, source, principals)
    else
      case Throttle.check(:api, source) do
        {:locked, seconds} -> locked(conn, seconds)
        :ok -> authenticate(conn, source, principals)
      end
    end
  end

  defp sound_token?({_name, token}), do: byte_size(token) >= RuntimeConfig.min_token_bytes()

  defp authenticate(conn, source, principals) do
    case matching_principal(bearer_token(conn), principals) do
      {:ok, name} ->
        admit(source)
        # Every configured token is read-write, with the same full authority
        # (ADR-0054 §1, which superseded the architecture's read-only D4).
        assign(conn, :actor, Portfolixir.Actor.api_token_rw(name))

      :error ->
        refuse(conn, source)
    end
  end

  # A correct token clears its source's count, as before, unless the source is
  # locked: then the lock stays for the wrong tokens still to come from that
  # address, so the agent's requests never lift a guesser's lock.
  defp admit(source) do
    case Throttle.check(:api, source) do
      :ok -> Throttle.success(:api, source)
      {:locked, _seconds} -> :ok
    end
  end

  # The failure that reaches the threshold is answered 401; a wrong token from
  # a source already locked is answered 429, with the lock its own failure
  # extended.
  defp refuse(conn, source) do
    state = Throttle.check(:api, source)
    Throttle.failure(:api, source)

    case {state, Throttle.check(:api, source)} do
      {{:locked, _before}, {:locked, seconds}} ->
        locked(conn, seconds)

      _unlocked ->
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
