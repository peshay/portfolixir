defmodule Portfolixir.MCP.ReadOnlyToolsTest do
  use ExUnit.Case, async: true

  alias Portfolixir.MCP.ReadOnlyTools

  test "tools map only to authenticated read API GET endpoints" do
    for tool <- ReadOnlyTools.tools() do
      assert tool.method == :get
      assert String.starts_with?(tool.path, "/api/read/")
    end
  end

  test "call returns path and normalized query for known tools" do
    assert {:ok, %{method: :get, path: "/api/read/positions", query: %{portfolio_id: "12"}}} =
             ReadOnlyTools.call("positions", %{"portfolio_id" => "12"})

    assert {:ok, %{method: :get, path: "/api/read/transactions", query: %{}}} =
             ReadOnlyTools.call("transactions")
  end

  test "call rejects unknown tools and invalid params" do
    assert {:error, :unknown_tool} = ReadOnlyTools.call("create_trade", %{})
    assert {:error, :invalid_params} = ReadOnlyTools.call("positions", %{"portfolio_id" => "0"})
    assert {:error, :invalid_params} = ReadOnlyTools.call("positions", %{"portfolio_id" => "abc"})
  end
end
