defmodule Portfolixir.Portfolios.Performance.Warmup do
  @moduledoc """
  Warms the performance memo at boot and on each day rollover (ADR-0032 §5).

  The derived-value layer (`Portfolixir.Derived`, ADR-0039) removes the
  repeat wait; this removes the first wait after a restart, so the first page
  of the day opens warm — and for the durable lifetime it re-materializes the
  operative entries after any invalidating write landed while the app was
  down.

  Rules from the ADR, all load-bearing:

  - it runs **after** the supervision tree is up and never blocks it — the
    work happens in `handle_continue`, and every scope is warmed inside a
    `try/rescue`, so a failing portfolio cannot take the process (or the app)
    down with it;
  - it warms **through the same API a request uses** (`Performance.analysis/2`)
    — there is no second computation path that could disagree with a request;
  - it is **bounded**: every portfolio at the `:unscoped` scope plus the
    default view where one is set — the scopes the dashboard and Wealth page
    actually open. Periods cost nothing (`summarise/2` re-chains);
  - it is disabled by the **same switch** as the derived layer, so "off" is
    one testable state, not two.

  Day rollover: `today` is part of the memo key, so yesterday's entries simply
  stop matching at midnight. This process re-warms shortly after local
  midnight so the first visit of the new day is warm too.
  """

  use GenServer

  require Logger

  alias Portfolixir.Buckets
  alias Portfolixir.Derived
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Settings

  # A minute past local midnight: comfortably on the new day without assuming
  # anything about clock precision at the boundary.
  @rollover_slack_ms 60_000

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Warms every portfolio's unscoped analysis plus the default view's, through
  the request path. Returns `:ok` always — a scope that raises is logged and
  skipped, never fatal (§5: a failing warm-up must not prevent serving).
  """
  @spec warm() :: :ok
  def warm do
    if Derived.enabled?() do
      default_view_id = default_view_id()

      Enum.each(Portfolios.list_portfolios(), &warm_portfolio(&1.id, default_view_id))
      warm_global(default_view_id)
    end

    :ok
  end

  @doc """
  Warms the operative scopes of **one** data-version basis, through the same
  request path `warm/0` uses.

  This is what `Portfolixir.Derived.Refresher` calls when a write invalidates a
  basis (ADR-0039 amendment §1, issue #710): the refresher schedules, this
  module stays the single place that knows which scopes are operative, and
  there is still no second computation path. An unrecognised basis is a no-op —
  a basis naming something this module cannot warm is not an error, it simply
  has nothing here to re-materialize.
  """
  @spec warm_basis(String.t()) :: :ok
  def warm_basis(basis) when is_binary(basis) do
    if Derived.enabled?(), do: do_warm_basis(basis)
    :ok
  end

  defp do_warm_basis("global"), do: warm_global(default_view_id())

  defp do_warm_basis("portfolio:" <> portfolio_id) do
    case Integer.parse(portfolio_id) do
      {id, ""} -> warm_portfolio(id, default_view_id())
      _not_an_id -> :ok
    end
  end

  defp do_warm_basis(_other), do: :ok

  defp warm_portfolio(portfolio_id, default_view_id) do
    warm_scope(portfolio_id, nil)
    if default_view_id, do: warm_scope(portfolio_id, default_view_id)
    :ok
  end

  # The cross-portfolio view walk (#577) is what the Wealth page and the
  # dashboard card open: the Everything scope plus the default view, in the
  # base currency those surfaces request (the first portfolio's).
  defp warm_global(default_view_id) do
    warm_view_scope(nil)
    if default_view_id, do: warm_view_scope(default_view_id)
    :ok
  end

  @impl true
  def init(opts) do
    if Keyword.get(opts, :enabled?, true) and Derived.enabled?() do
      {:ok, %{}, {:continue, :warm}}
    else
      :ignore
    end
  end

  @impl true
  def handle_continue(:warm, state) do
    warm()
    schedule_rollover()
    {:noreply, state}
  end

  @impl true
  def handle_info(:rollover, state) do
    warm()
    schedule_rollover()
    {:noreply, state}
  end

  defp warm_scope(portfolio_id, view_id) do
    Performance.analysis(portfolio_id, view: view_id)
  rescue
    error ->
      Logger.warning(
        "performance warm-up skipped portfolio #{portfolio_id} " <>
          "(view #{inspect(view_id)}): #{Exception.message(error)}"
      )

      :ok
  end

  defp warm_view_scope(view_id) do
    case Portfolios.first_portfolio() do
      %{base_currency_code: base_currency} ->
        Performance.view_analysis(view_id, base_currency: base_currency)

      _no_portfolio ->
        :ok
    end
  rescue
    error ->
      Logger.warning(
        "performance warm-up skipped view scope #{inspect(view_id)}: " <>
          Exception.message(error)
      )

      :ok
  end

  defp default_view_id do
    Settings.default_view_id() && Buckets.get_view(Settings.default_view_id()) &&
      Settings.default_view_id()
  rescue
    _error -> nil
  end

  defp schedule_rollover do
    Process.send_after(self(), :rollover, ms_until_next_local_day())
  end

  defp ms_until_next_local_day do
    {_date, {hours, minutes, seconds}} = :calendar.local_time()
    elapsed_ms = ((hours * 60 + minutes) * 60 + seconds) * 1000
    max(:timer.hours(24) - elapsed_ms + @rollover_slack_ms, @rollover_slack_ms)
  end
end
