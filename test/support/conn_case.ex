defmodule PortfolixirWeb.ConnCase do
  @moduledoc "Case template for controller and LiveView tests (SQL sandbox)."
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest

      @endpoint PortfolixirWeb.Endpoint
    end
  end

  setup tags do
    :ok = Sandbox.checkout(Portfolixir.Repo)

    unless tags[:async] do
      Sandbox.mode(Portfolixir.Repo, {:shared, self()})
    end

    conn = Phoenix.ConnTest.build_conn()
    {:ok, conn: conn}
  end
end
