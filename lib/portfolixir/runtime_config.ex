defmodule Portfolixir.RuntimeConfig do
  @moduledoc """
  Small deterministic helpers for runtime configuration parsing.

  Everything here is a pure function over the raw environment strings so the
  release-time decisions in `config/runtime.exs` can be pinned by unit tests
  instead of by a deployment (ADR-0045 §2, #758).
  """

  @true_values ["1", "true", "yes"]
  @loopback {127, 0, 0, 1}
  @any {0, 0, 0, 0}
  @always_allowed_hosts ["localhost", "127.0.0.1"]

  def database_ssl?(value \\ System.get_env("DATABASE_SSL", "false"))

  def database_ssl?(value) when is_binary(value), do: truthy?(value)
  def database_ssl?(_value), do: false

  @doc """
  The address the HTTP listener binds. Loopback unless `PHX_BIND_ALL` is one of
  the accepted true values — the same switch and default `config/dev.exs` has
  had all along; production gets it here.
  """
  @spec bind_ip(String.t() | nil) :: :inet.ip4_address()
  def bind_ip(value \\ System.get_env("PHX_BIND_ALL"))
  def bind_ip(value) when is_binary(value), do: if(truthy?(value), do: @any, else: @loopback)
  def bind_ip(_value), do: @loopback

  @doc """
  The Host names a request may carry (`PortfolixirWeb.HostGuard`): `PHX_HOST`,
  the two loopback names, and whatever `PORTFOLIXIR_ALLOWED_HOSTS` adds
  (comma-separated; a reverse-proxy name, a LAN address). Lower-cased, trimmed,
  blanks dropped, duplicates removed, order kept.
  """
  @spec allowed_hosts(String.t() | nil, String.t() | nil) :: [String.t()]
  def allowed_hosts(
        phx_host \\ System.get_env("PHX_HOST"),
        extra \\ System.get_env("PORTFOLIXIR_ALLOWED_HOSTS")
      )

  def allowed_hosts(phx_host, extra) do
    ([phx_host | @always_allowed_hosts] ++ split_hosts(extra))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&normalize_host/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  @doc """
  The startup check behind ADR-0045 §2: bound beyond loopback with no UI
  password is a state the operator must have chosen knowingly, so it is named
  in the log rather than left silent. Pure; `Portfolixir.Application` logs it.
  """
  @spec exposure_warning(:inet.ip_address(), String.t() | nil) :: :ok | {:warn, String.t()}
  def exposure_warning(@loopback, _password), do: :ok
  def exposure_warning({0, 0, 0, 0, 0, 0, 0, 1}, _password), do: :ok

  def exposure_warning(_ip, password) when is_binary(password) and password != "", do: :ok

  def exposure_warning(_ip, _password) do
    {:warn,
     "The web UI is bound beyond loopback and PORTFOLIXIR_UI_PASSWORD is not set: " <>
       "every page and every write is reachable by anyone who can reach this port. " <>
       "Set PORTFOLIXIR_UI_PASSWORD, or put reverse-proxy authentication in front " <>
       "(ADR-0045)."}
  end

  defp truthy?(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> then(&(&1 in @true_values))
  end

  defp split_hosts(nil), do: []
  defp split_hosts(extra) when is_binary(extra), do: String.split(extra, ",")

  defp normalize_host(host), do: host |> String.trim() |> String.downcase()
end
