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
    {:ok, sandbox_owner: setup_sandbox(tags)}
  end

  @doc """
  Checks out the test's sandbox connection under an owner process of its own,
  stopped by `on_exit` (#927).

  ExUnit stops what a test started (a LiveView, its `start_async` loads, a
  supervised task) only after the test process has exited, and runs `on_exit`
  after that. With the test process as the owner, the connection went with
  it, and whatever was still mid-query crashed with "owner exited" into the
  log. An owner that outlives the test keeps the connection until everything
  the test started is down.

  The test process is allowed on the connection, so processes that name it
  as a caller (`$callers`: tasks, LiveViews) reach the connection in async
  tests too; a sync test shares it with every process.
  """
  def setup_sandbox(tags) do
    owner = Sandbox.start_owner!(Portfolixir.Repo, shared: not tags[:async])
    on_exit(fn -> stop_sandbox(owner) end)
    scope_isin_write_lock()
    # A log event the run did not capture names the tests around it (#927).
    Portfolixir.LogNoise.track(tags)
    owner
  end

  # Every ISIN writer takes the ISIN write lock, one transaction-scoped
  # advisory lock for the whole database (`Portfolixir.Catalog.IdentifierAliases`).
  # A sandboxed test never commits, so it held that lock until it ended, and
  # every other async test writing an ISIN waited for it (#1018). The setting,
  # local to the test's transaction, scopes the lock to the test's connection:
  # the test's own writers still serialize, another test's never wait.
  defp scope_isin_write_lock do
    Portfolixir.Repo.query!(
      "SELECT set_config('portfolixir.isin_write_lock_scope', pg_backend_pid()::text, true)"
    )
  end

  @doc """
  Stops a sandbox owner, rolling its transaction back; a no-op for an owner a
  test already stopped (to start over on a fresh connection).
  """
  def stop_sandbox(owner) do
    if Process.alive?(owner), do: Sandbox.stop_owner(owner), else: :ok
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
