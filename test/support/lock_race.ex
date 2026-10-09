defmodule Portfolixir.LockRace do
  @moduledoc """
  The two-connection lock-order harness (Sprint 17, Lane G-2, #996): two
  writers on two real connections, interleaved by a barrier, with a deadlock
  read as a failure.

  The SQL sandbox runs every connection of a test on one, so a lock cycle
  between two writers can never form under it: Sprint 16's lock tests could
  only pin the order of the statements one writer sends (and
  `Portfolixir.Interleave` runs the other writer on the same connection).
  `race!/3` runs both writers for real, each in a process of its own holding
  one connection of a scratch database at head (`Portfolixir.ScratchDatabase`,
  started by the case module's `setup_all`):

    1. the **first** writer runs until a query its pause predicate matches has
       returned -- typically its first lock, see `lock?/1` -- and holds there,
       inside its open transaction;
    2. the **second** writer then runs until the database reports it blocked
       by the first (`pg_blocking_pids/1`) -- a second writer that ends
       without ever waiting on the first fails the race, which then tested no
       lock order;
    3. the first writer resumes, and both run to their end.

  That is the interleaving in which two writers taking the same two locks in
  opposite orders deadlock: each then holds the lock the other waits for.
  Taken in one order, the second waits for the first and both finish. The
  barrier waits on states, never on a duration: the first writer reports its
  pause, and the second writer's lock wait is read from the database every
  few milliseconds until it shows (PostgreSQL announces no lock wait). The
  only timed waits are the limits after which a stuck race fails.

  `second: :passes` turns step 2 around, for a lock a writer no longer takes
  (#922): the second writer must end while the first is held, and one the
  database reports blocked by the first fails the race. The first then
  resumes, as in step 3.

  A deadlock is read from every query each writer sends (the repo's
  telemetry event carries the query's result): an `ERROR 40P01
  (deadlock_detected)` fails the race even when the writer rescues it -- as
  the hardened delete does, answering a lost lock cycle with
  `{:error, :raced}`. A writer that raises fails it too.

  The rows a case writes live in the scratch database, which is dropped
  after the module; each case builds its own.
  """

  import ExUnit.Assertions, only: [flunk: 1]

  alias Portfolixir.Repo
  alias Portfolixir.ScratchDatabase

  require Logger

  # A row lock, or a transaction's advisory lock, in a query's text.
  @lock ~r/\bFOR (?:NO KEY UPDATE|UPDATE|KEY SHARE|SHARE)\b|\bpg_advisory_xact_lock\b/

  @step_timeout 10_000
  @poll_interval 5

  # The writers the current race started, in the test's process dictionary.
  @writers {__MODULE__, :writers}

  @doc """
  A scratch database at head for a module of lock-order cases, from its
  `setup_all`: three connections, one per writer and one for the barrier's
  reads of the database's lock waits.
  """
  @spec database!() :: ScratchDatabase.t()
  def database! do
    db = ScratchDatabase.start!(suffix: "locks", pool_size: 3)
    ScratchDatabase.migrate!(db, :head)
    db
  end

  @doc "Whether a query (the repo's telemetry metadata) takes a lock."
  @spec lock?(map()) :: boolean()
  def lock?(%{query: query}) when is_binary(query), do: Regex.match?(@lock, query)
  def lock?(_metadata), do: false

  @doc "A pause predicate: the query's text contains `fragment`."
  @spec query?(String.t()) :: (map() -> boolean())
  def query?(fragment) when is_binary(fragment) do
    fn
      %{query: query} when is_binary(query) -> String.contains?(query, fragment)
      _metadata -> false
    end
  end

  @doc """
  Runs `first` (paused after the first query `pause_after?` matches) and
  `second` against `db` through the barrier above, and answers what each
  returned, `{first, second}`. Fails the test on a deadlock, on a writer that
  raises or exits, on a second writer that never waits on the first (with
  `opts[:second]` `:passes`, on one that does), and on a step of the barrier
  not reached within `opts[:timeout]` milliseconds (default 10 s; the
  harness's own tests shorten it). Every writer still running when the race
  ends, however it ends, is killed with its transaction.
  """
  @spec race!(ScratchDatabase.t(), {(-> a), (map() -> boolean())}, (-> b), keyword()) :: {a, b}
        when a: term(), b: term()
  def race!(%ScratchDatabase{} = db, {first, pause_after?}, second, opts \\ [])
      when is_function(first, 0) and is_function(pause_after?, 1) and is_function(second, 0) do
    timeout = Keyword.get(opts, :timeout, @step_timeout)

    try do
      held = start_writer(db, :first, first, pause_after?)
      await!(held, :paused, timeout)
      waiting = start_writer(db, :second, second, nil)

      case Keyword.get(opts, :second, :waits) do
        :waits -> await_blocked!(db, waiting, held, timeout)
        :passes -> await_passed!(db, waiting, held, timeout)
      end

      send(held.pid, {:resume, held.ref})

      outcomes = Enum.map([held, waiting], &{&1.role, await!(&1, :done, timeout)})
      deadlocks!([held, waiting])
      [first_result, second_result] = Enum.map(outcomes, &result!/1)
      {first_result, second_result}
    after
      stop_writers()
    end
  end

  # -- the writers --------------------------------------------------------------

  defp start_writer(db, role, fun, pause_after?) do
    parent = self()
    ref = make_ref()

    {pid, monitor} =
      spawn_monitor(fn ->
        try do
          ScratchDatabase.run(db, fn ->
            Repo.checkout(fn -> run_writer(parent, ref, fun, pause_after?) end)
          end)
        catch
          kind, reason when kind in [:error, :throw] -> crash(role, kind, reason, __STACKTRACE__)
        end
      end)

    Process.put(@writers, [{pid, monitor} | Process.get(@writers, [])])

    writer = %{role: role, pid: pid, ref: ref, monitor: monitor}
    Map.put(writer, :backend, await!(writer, :backend, @step_timeout))
  end

  # A writer that raises or throws outside its function -- one that cannot
  # get a connection, say -- logs its crash report itself and then exits with
  # the reason an uncaught error or throw gives (#1046). The runtime hands its
  # own report of either to the logger's proxy process as the writer dies,
  # and the proxy logs it in its own time: a test capturing the log around
  # the race could see the writer's exit and end its capture first, and the
  # report then reached the console. Logged here, in the writer's process,
  # the report is written before the exit the race awaits. An exit is left
  # alone: the runtime writes no report for it.
  defp crash(role, kind, reason, stacktrace) do
    Logger.error(
      "the #{role} writer #{verb(kind)}:\n\n" <> Exception.format(kind, reason, stacktrace)
    )

    exit(uncaught(kind, reason, stacktrace))
  end

  defp verb(:error), do: "raised"
  defp verb(:throw), do: "threw"

  defp uncaught(:error, reason, stacktrace), do: {reason, stacktrace}
  defp uncaught(:throw, value, stacktrace), do: {{:nocatch, value}, stacktrace}

  # Kills every writer this race started and drops its messages: a paused or
  # blocked writer would otherwise hold its locks and its connection.
  defp stop_writers do
    for {pid, monitor} <- Process.delete(@writers) || [] do
      Process.demonitor(monitor, [:flush])
      Process.exit(pid, :kill)
    end
  end

  # On the one connection the writer holds for its whole run: its backend
  # pid for the barrier, then the writer under the telemetry handler that
  # reports a deadlock and holds at the pause point.
  defp run_writer(parent, ref, fun, pause_after?) do
    %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
    send(parent, {:backend, ref, backend})

    handler = "lock-race-#{inspect(ref)}"
    config = %{writer: self(), parent: parent, ref: ref, pause_after?: pause_after?}
    :ok = :telemetry.attach(handler, [:portfolixir, :repo, :query], &__MODULE__.observe/4, config)

    outcome =
      try do
        {:returned, fun.()}
      catch
        kind, reason -> {:raised, kind, reason, __STACKTRACE__}
      after
        :telemetry.detach(handler)
      end

    send(parent, {:done, ref, outcome})
  end

  @doc false
  # The telemetry handler, run in the process that sent the query: only the
  # writer's own queries count. A deadlock is reported; the first query the
  # pause predicate matches holds the writer until the barrier resumes it.
  def observe(_event, _measurements, metadata, %{writer: writer} = config)
      when writer == self() do
    if deadlock?(metadata), do: send(config.parent, {:deadlock, config.ref, metadata.query})

    if config.pause_after? && !Process.get({__MODULE__, :paused}) &&
         config.pause_after?.(metadata) do
      Process.put({__MODULE__, :paused}, true)
      send(config.parent, {:paused, config.ref, :paused})

      receive do
        {:resume, ref} when ref == config.ref -> :ok
      end
    end
  end

  def observe(_event, _measurements, _metadata, _config), do: :ok

  defp deadlock?(%{result: {:error, %Postgrex.Error{postgres: %{code: :deadlock_detected}}}}),
    do: true

  defp deadlock?(_metadata), do: false

  # -- the barrier --------------------------------------------------------------

  # What each awaited message means, as "did not <present>" and
  # "before it <past>".
  @steps %{
    backend: {"get a connection", "got a connection"},
    paused: {"reach its pause point", "reached its pause point"},
    done: {"end", "ended"}
  }

  # The writer's `step` message, failing the race when the writer ends or
  # exits before it, or when it does not come within `timeout`.
  defp await!(%{role: role, ref: ref, monitor: monitor}, step, timeout) do
    {present, past} = Map.fetch!(@steps, step)

    receive do
      {^step, ^ref, value} ->
        value

      {:done, ^ref, outcome} ->
        flunk("the #{role} writer ended before it #{past}:\n#{format(outcome)}")

      {:DOWN, ^monitor, :process, _pid, reason} ->
        flunk("the #{role} writer exited before it #{past}: #{inspect(reason)}")
    after
      timeout -> flunk("the #{role} writer did not #{present} within #{timeout} ms")
    end
  end

  # Until the database reports the second writer blocked by the first. A
  # second writer that ends first never met the first one's lock: the pause
  # point is not inside the conflict, and the race would test nothing.
  defp await_blocked!(db, second, first, timeout, waited \\ 0) do
    cond do
      blocked_by?(db, second.backend, first.backend) ->
        :blocked

      done?(second) ->
        flunk("""
        the second writer ended without waiting on the first, so the race tested
        no lock order: pause the first writer after a lock the second one takes
        """)

      waited >= timeout ->
        flunk("the second writer neither waited on the first nor ended within #{timeout} ms")

      true ->
        receive do
        after
          @poll_interval -> await_blocked!(db, second, first, timeout, waited + @poll_interval)
        end
    end
  end

  # `second: :passes`: until the second writer ends while the first is held.
  # One the database reports blocked by the first takes a lock the first
  # holds, the lock the case pins as gone.
  defp await_passed!(db, second, first, timeout, waited \\ 0) do
    cond do
      done?(second) ->
        :passed

      blocked_by?(db, second.backend, first.backend) ->
        flunk("""
        the second writer waited on the first, which it was to pass: it takes a
        lock the first one holds
        """)

      waited >= timeout ->
        flunk("the second writer neither ended nor waited on the first within #{timeout} ms")

      true ->
        receive do
        after
          @poll_interval -> await_passed!(db, second, first, timeout, waited + @poll_interval)
        end
    end
  end

  defp done?(%{ref: ref}) do
    {:messages, messages} = Process.info(self(), :messages)
    Enum.any?(messages, &match?({:done, ^ref, _outcome}, &1))
  end

  defp blocked_by?(db, backend, blocker) do
    %{rows: [[blocked?]]} =
      ScratchDatabase.query!(db, "SELECT $2::integer = ANY(pg_blocking_pids($1))", [
        backend,
        blocker
      ])

    blocked?
  end

  defp deadlocks!(writers) do
    for %{role: role, ref: ref} <- writers do
      receive do
        {:deadlock, ^ref, query} ->
          flunk("""
          a deadlock (40P01): the database aborted the #{role} writer at

            #{query}

          The two writers take the same locks in opposite orders.
          """)
      after
        0 -> :ok
      end
    end
  end

  defp result!({_role, {:returned, value}}), do: value
  defp result!({role, outcome}), do: flunk("the #{role} writer #{format(outcome)}")

  defp format({:returned, value}), do: "returned #{inspect(value)}"

  defp format({:raised, kind, reason, stacktrace}),
    do: "raised:\n\n" <> Exception.format(kind, reason, stacktrace)
end
