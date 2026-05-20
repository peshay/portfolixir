defmodule Portfolixir.Catalog.LogoDiscovery do
  @moduledoc """
  Small background queue for filling missing security logos.

  The queue is intentionally conservative: it processes one security at a
  time, reloads the row before doing network work, and skips securities that
  already have a stored `logo_path` or whose visible fallback is not a remote
  logo.
  """

  use GenServer
  import Ecto.Query
  require Logger

  alias Portfolixir.Catalog.LogoLookup
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Repo

  # -- public API ------------------------------------------------------------

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  def enqueue_security(security_or_id, name \\ __MODULE__)

  def enqueue_security(%Security{id: id}, name) do
    enqueue_security_ids([id], name)
  end

  def enqueue_security(id, name) when is_integer(id) do
    enqueue_security_ids([id], name)
  end

  def enqueue_security_ids(ids, name \\ __MODULE__) when is_list(ids) do
    if enabled?() do
      safe_cast(name, {:enqueue, Enum.filter(ids, &is_integer/1)})
    end

    :ok
  end

  def enqueue_missing_security_logos(name \\ __MODULE__) do
    if enabled?() do
      safe_cast(name, :enqueue_missing)
    end

    :ok
  end

  # -- GenServer callbacks --------------------------------------------------

  @impl true
  def init(_opts) do
    if enabled?(), do: send(self(), :enqueue_missing)
    {:ok, %{queue: :queue.new(), queued: MapSet.new(), scheduled?: false}}
  end

  @impl true
  def handle_cast({:enqueue, ids}, state) do
    state =
      ids
      |> Enum.uniq()
      |> Enum.reduce(state, &put_queued/2)
      |> schedule_drain()

    {:noreply, state}
  end

  @impl true
  def handle_cast(:enqueue_missing, state) do
    state =
      if enabled?() do
        missing_logo_candidate_ids()
        |> Enum.reduce(state, &put_queued/2)
        |> schedule_drain()
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:drain, state) do
    case :queue.out(state.queue) do
      {{:value, id}, queue} ->
        process_security(id)

        state =
          %{state | queue: queue, queued: MapSet.delete(state.queued, id), scheduled?: false}
          |> schedule_drain()

        {:noreply, state}

      {:empty, queue} ->
        {:noreply, %{state | queue: queue, scheduled?: false}}
    end
  end

  @impl true
  def handle_info(:enqueue_missing, state) do
    state =
      if enabled?() do
        missing_logo_candidate_ids()
        |> Enum.reduce(state, &put_queued/2)
        |> schedule_drain()
      else
        state
      end

    {:noreply, state}
  end

  # -- queue internals -------------------------------------------------------

  defp put_queued(id, state) do
    if MapSet.member?(state.queued, id) do
      state
    else
      %{state | queue: :queue.in(id, state.queue), queued: MapSet.put(state.queued, id)}
    end
  end

  defp schedule_drain(%{scheduled?: true} = state), do: state

  defp schedule_drain(state) do
    if :queue.is_empty(state.queue) do
      state
    else
      send(self(), :drain)
      %{state | scheduled?: true}
    end
  end

  defp process_security(id) do
    if enabled?() do
      case Repo.get(Security, id) do
        %Security{} = security ->
          if missing_logo?(security) and logo_candidate?(security) do
            case LogoLookup.run(security, logo_lookup_opts()) do
              {:ok, _security} ->
                :ok

              :skip ->
                :ok

              {:error, reason} ->
                Logger.warning("logo discovery failed for ##{id}: #{inspect(reason)}")
            end
          end

        nil ->
          :ok
      end
    end
  rescue
    exception ->
      Logger.warning("logo discovery crashed for ##{id}: #{Exception.message(exception)}")
  catch
    kind, reason ->
      Logger.warning("logo discovery exited for ##{id}: #{inspect({kind, reason})}")
  end

  defp missing_logo?(%Security{attributes: attributes}) do
    not is_binary(get_in(attributes || %{}, ["logo_path"]))
  end

  defp logo_candidate?(%Security{} = security) do
    Security.effective_asset_class(security) in ~w(equity etf fund crypto)
  end

  defp missing_logo_candidate_ids do
    Security
    |> where([s], is_nil(fragment("? ->> ?", s.attributes, ^"logo_path")))
    |> Repo.all()
    |> Enum.filter(&logo_candidate?/1)
    |> Enum.map(& &1.id)
  end

  defp enabled? do
    Application.get_env(:portfolixir, :enable_logo_discovery, false)
  end

  defp logo_lookup_opts do
    Application.get_env(:portfolixir, :logo_discovery_opts, [])
  end

  defp safe_cast(name, message) do
    GenServer.cast(name, message)
  catch
    :exit, _reason -> :ok
  end
end
