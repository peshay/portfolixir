defmodule Portfolixir.Net.FakeResolver do
  @moduledoc """
  The DNS resolver the test suite plugs into `Portfolixir.Net.UrlPolicy`, so
  no test resolves a real name. Hosts under `.test` map to the address class
  their label says; every other host resolves to a public address.
  """

  @public {93, 184, 216, 34}

  @spec resolve(String.t()) :: {:ok, [:inet.ip_address()]} | {:error, term()}
  def resolve("internal.test"), do: {:ok, [{10, 0, 0, 5}]}
  def resolve("lan.test"), do: {:ok, [{192, 168, 1, 20}]}
  def resolve("loopback.test"), do: {:ok, [{127, 0, 0, 1}]}
  def resolve("meta.test"), do: {:ok, [{169, 254, 169, 254}]}
  def resolve("cgnat.test"), do: {:ok, [{100, 64, 0, 1}]}
  def resolve("v6loopback.test"), do: {:ok, [{0, 0, 0, 0, 0, 0, 0, 1}]}
  def resolve("v6local.test"), do: {:ok, [{0xFC00, 0, 0, 0, 0, 0, 0, 1}]}
  def resolve("v6mapped.test"), do: {:ok, [{0, 0, 0, 0, 0, 0xFFFF, 0x0A00, 0x0001}]}
  def resolve("mixed.test"), do: {:ok, [@public, {10, 0, 0, 5}]}
  def resolve("unresolvable.test"), do: {:error, :nxdomain}
  def resolve(_host), do: {:ok, [@public]}
end
