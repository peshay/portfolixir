defmodule Portfolixir.DataCase do
  @moduledoc "Case template for context and schema tests (SQL sandbox)."
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias Portfolixir.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Portfolixir.DataCase
    end
  end

  setup tags do
    :ok = Sandbox.checkout(Portfolixir.Repo)

    unless tags[:async] do
      Sandbox.mode(Portfolixir.Repo, {:shared, self()})
    end

    :ok
  end

  def errors_on(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
