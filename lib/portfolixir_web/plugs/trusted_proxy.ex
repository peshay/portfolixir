defmodule PortfolixirWeb.TrustedProxy do
  @moduledoc """
  The client address behind a trusted reverse proxy (#771, ADR-0045 §2).

  The throttle keys on `conn.remote_ip`. Behind the documented deployment
  (a proxy on the host, the container on the Docker bridge) that address is
  the proxy's for every client, so ten wrong passwords from anyone would lock
  the operator out as well. When the connecting address lies inside
  `PORTFOLIXIR_TRUSTED_PROXIES`, the last `x-forwarded-for` hop that is not
  itself a trusted proxy becomes `remote_ip`. With no trusted proxies (the
  default) the header is never believed: a client cannot pick its own source.
  """

  import Plug.Conn

  alias Portfolixir.RuntimeConfig

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{remote_ip: remote_ip} = conn, _opts) do
    blocks = Application.get_env(:portfolixir, :trusted_proxies, [])

    with [_ | _] <- blocks,
         true <- RuntimeConfig.trusted_proxy?(remote_ip, blocks),
         [header | _] <- get_req_header(conn, "x-forwarded-for"),
         {:ok, client} <- client_address(header, blocks) do
      %{conn | remote_ip: client}
    else
      _ -> conn
    end
  end

  # Right to left: the proxies append, so the first untrusted hop from the
  # right is the client the trusted chain vouches for.
  defp client_address(header, blocks) do
    header
    |> String.split(",")
    |> Enum.reverse()
    |> Enum.map(&parse_address/1)
    |> Enum.find(fn
      {:ok, ip} -> not RuntimeConfig.trusted_proxy?(ip, blocks)
      :error -> true
    end)
    |> case do
      {:ok, ip} -> {:ok, ip}
      _ -> :error
    end
  end

  defp parse_address(value) do
    case :inet.parse_strict_address(value |> String.trim() |> to_charlist()) do
      {:ok, ip} -> {:ok, ip}
      {:error, _} -> :error
    end
  end
end
