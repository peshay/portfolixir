defmodule Portfolixir.RuntimeConfig do
  @moduledoc "Small deterministic helpers for runtime configuration parsing."

  @true_values ["1", "true", "yes"]

  def database_ssl?(value \\ System.get_env("DATABASE_SSL", "false"))

  def database_ssl?(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> then(&(&1 in @true_values))
  end

  def database_ssl?(_value), do: false
end
