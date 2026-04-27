defmodule PortfolixirWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest

      @endpoint PortfolixirWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Portfolixir.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Portfolixir.Repo, {:shared, self()})
    end

    conn = Phoenix.ConnTest.build_conn()
    {:ok, conn: conn}
  end
end
