defmodule Portfolixir.Catalog.SecuritySearch.Properties do
  @moduledoc """
  The allow-list a search provider's free-form `properties` object passes
  before it is merged into a security's `attributes` (#763).

  The attributes map also carries the logo bookkeeping (`logo_path`,
  `logo_source`, `logo_locked`), which the detail pane renders and the
  discovery job trusts, so a provider payload must not be able to write those
  keys; and a payload that is not a map used to crash the confirm dialog.
  """

  @max_keys 50
  @max_key_bytes 64
  @max_value_bytes 500
  @reserved_prefix "logo_"

  @doc "Bounded scalar properties under non-reserved string keys; anything else is dropped."
  @spec sanitize(term()) :: %{optional(String.t()) => String.t() | number() | boolean()}
  def sanitize(properties) when is_map(properties) do
    properties
    |> Enum.filter(&keep?/1)
    |> Enum.take(@max_keys)
    |> Map.new()
  end

  def sanitize(_not_a_map), do: %{}

  defp keep?({key, value}) when is_binary(key) do
    byte_size(key) > 0 and byte_size(key) <= @max_key_bytes and
      not String.starts_with?(key, @reserved_prefix) and scalar?(value)
  end

  defp keep?(_pair), do: false

  defp scalar?(value) when is_binary(value), do: byte_size(value) <= @max_value_bytes
  defp scalar?(value) when is_number(value) or is_boolean(value), do: true
  defp scalar?(_value), do: false
end
