defmodule Portfolixir.MCP.ReadOnlyTools do
  @moduledoc """
  Read-only MCP tool definitions mapped to authenticated `/api/read/*` endpoints.

  This module intentionally defines **no write-capable tools**.
  It must not expose broker, banking, trading, payment, order, or rebalance actions.
  """

  @type tool_definition :: %{
          name: String.t(),
          description: String.t(),
          method: :get,
          path: String.t(),
          params_schema: map()
        }

  @optional_portfolio_schema %{
    type: "object",
    properties: %{
      portfolio_id: %{
        type: "integer",
        minimum: 1,
        description: "Optional portfolio identifier. Defaults to the first portfolio."
      }
    },
    additionalProperties: false
  }

  @tools [
    %{
      name: "portfolio_snapshot",
      description: "Read a portfolio snapshot with positions and cash balances.",
      method: :get,
      path: "/api/read/portfolio_snapshot",
      params_schema: @optional_portfolio_schema
    },
    %{
      name: "positions",
      description: "Read current positions for a portfolio.",
      method: :get,
      path: "/api/read/positions",
      params_schema: @optional_portfolio_schema
    },
    %{
      name: "transactions",
      description: "Read transactions for a portfolio.",
      method: :get,
      path: "/api/read/transactions",
      params_schema: @optional_portfolio_schema
    },
    %{
      name: "cash_balances",
      description: "Read cash balances for a portfolio.",
      method: :get,
      path: "/api/read/cash_balances",
      params_schema: @optional_portfolio_schema
    }
  ]

  @spec tools() :: [tool_definition()]
  def tools, do: @tools

  @spec call(String.t(), map()) :: {:ok, map()} | {:error, :unknown_tool | :invalid_params}
  def call(tool_name, params \\ %{}) when is_binary(tool_name) and is_map(params) do
    with {:ok, tool} <- fetch_tool(tool_name),
         {:ok, query} <- validate_params(params) do
      {:ok, %{method: tool.method, path: tool.path, query: query}}
    end
  end

  defp fetch_tool(tool_name) do
    case Enum.find(@tools, &(&1.name == tool_name)) do
      nil -> {:error, :unknown_tool}
      tool -> {:ok, tool}
    end
  end

  defp validate_params(%{} = params) do
    case Map.get(params, "portfolio_id") do
      nil -> {:ok, %{}}
      portfolio_id -> normalize_portfolio_id(portfolio_id)
    end
  end

  defp normalize_portfolio_id(portfolio_id) when is_integer(portfolio_id) and portfolio_id > 0 do
    {:ok, %{portfolio_id: Integer.to_string(portfolio_id)}}
  end

  defp normalize_portfolio_id(portfolio_id) when is_binary(portfolio_id) do
    case Integer.parse(portfolio_id) do
      {id, ""} when id > 0 -> {:ok, %{portfolio_id: Integer.to_string(id)}}
      _ -> {:error, :invalid_params}
    end
  end

  defp normalize_portfolio_id(_), do: {:error, :invalid_params}
end
