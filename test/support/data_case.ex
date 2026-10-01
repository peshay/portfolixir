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

  @doc """
  The changeset's errors as `%{field => [message]}`, each message with the
  placeholders it names filled from its opts.

  Only a placeholder the message names is filled (#916): the opts also carry
  entries no message renders, such as an `Ecto.Enum` cast error's
  parameterized type, which has no string form. A placeholder without an opt
  stays as written.
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r/%{(\w+)}/, message, fn placeholder, key ->
        case Enum.find(opts, fn {name, _value} -> Atom.to_string(name) == key end) do
          {_name, value} -> to_string(value)
          nil -> placeholder
        end
      end)
    end)
  end
end
