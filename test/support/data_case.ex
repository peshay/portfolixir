defmodule Portfolixir.DataCase do
  use ExUnit.CaseTemplate

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
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Portfolixir.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Portfolixir.Repo, {:shared, self()})
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
