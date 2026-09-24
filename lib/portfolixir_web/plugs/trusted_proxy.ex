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

  `x-forwarded-proto` follows the same trust rule (E25 S1, F09): it sets the
  scheme only when the connecting address is loopback (a proxy on the same
  host) or a trusted proxy, judged before the address rewrite above. From any
  other peer the header is dropped, so no later plug (`Plug.SSL`'s own
  `rewrite_on` included) can believe it.
  """

  import Plug.Conn

  alias Portfolixir.RuntimeConfig

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{remote_ip: remote_ip} = conn, _opts) do
    blocks = Application.get_env(:portfolixir, :trusted_proxies) || []
    trusted? = blocks != [] and RuntimeConfig.trusted_proxy?(remote_ip, blocks)

    conn
    |> forwarded_proto(trusted? or loopback?(remote_ip))
    |> forwarded_for(trusted?, blocks)
  end

  defp forwarded_proto(conn, true), do: Plug.RewriteOn.call(conn, [:x_forwarded_proto])
  defp forwarded_proto(conn, false), do: delete_req_header(conn, "x-forwarded-proto")

  defp forwarded_for(conn, false, _blocks), do: conn

  defp forwarded_for(conn, true, blocks) do
    with [_ | _] = lines <- get_req_header(conn, "x-forwarded-for"),
         {:ok, client} <- client_address(Enum.join(lines, ","), blocks) do
      %{conn | remote_ip: client}
    else
      _ -> conn
    end
  end

  defp loopback?({127, _, _, _}), do: true
  defp loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp loopback?(_address), do: false

  # Every header line, in order, is one list (RFC 9110 field-line combining,
  # E25 S1 F03): a proxy may append its hop as a line of its own, and reading
  # only the first line would hand the client the choice of source.
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
