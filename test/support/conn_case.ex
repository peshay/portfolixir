defmodule PortfolixirWeb.ConnCase do
  @moduledoc "Case template for controller and LiveView tests (SQL sandbox)."
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest

      @endpoint PortfolixirWeb.Endpoint
    end
  end

  # The sandbox owner outlives the test process (#927): see
  # `Portfolixir.DataCase.setup_sandbox/1`.
  setup tags do
    owner = Portfolixir.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn(), sandbox_owner: owner}
  end
end
