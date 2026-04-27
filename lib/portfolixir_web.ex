defmodule PortfolixirWeb do
  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]
      import Plug.Conn
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Phoenix.Controller
    end
  end

  def endpoint do
    quote do
      use Phoenix.Endpoint, otp_app: :portfolixir
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/portfolixir_web/templates",
        namespace: PortfolixirWeb
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
