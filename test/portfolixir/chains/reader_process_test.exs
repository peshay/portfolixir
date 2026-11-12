defmodule Portfolixir.Chains.ReaderProcessTest do
  # ADR-0059 §10 (Sprint 29, H3): the supervised chain reader. Not async:
  # the reader's own task reads the database, so the sandbox is shared. Every
  # answer is synthetic (Portfolixir.EsploraFixtures); no test touches the
  # network.
  use Portfolixir.DataCase, async: false

  import Portfolixir.EsploraFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.QuoteSync
  alias Portfolixir.Chains.Reader
  alias Portfolixir.Knowledge.Events

  defp security!(chain) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Synthetic Coin #{System.unique_integer([:positive])}",
        currency_code: "USD",
        asset_class: "crypto"
      })

    {:ok, bound} =
      Catalog.update_security(Actor.api_token_rw("synthetic-agent"), security, %{
        halving_chain: chain
      })

    bound
  end

  # A tick an hour away, sent by hand: the run is the test's to wait for, so
  # no read outlives the test's sandbox.
  defp start_reader!(enabled?) do
    reader =
      start_supervised!(
        {Reader, name: nil, enabled?: enabled?, first_tick_ms: :timer.hours(1)},
        id: make_ref()
      )

    Req.Test.allow(Portfolixir.Chains.Esplora, self(), reader)
    reader
  end

  defp wait_until(check, tries \\ 100) do
    cond do
      check.() -> :ok
      tries == 0 -> flunk("condition never held")
      true -> Process.sleep(20) && wait_until(check, tries - 1)
    end
  end

  # User story:
  # As the operator,
  # I want the chain reader to run exactly where the quote sync runs, every
  # 6 hours, and a security bound to Bitcoin to be its only opt-in,
  # so that there is no second switch to forget and a chain nobody bound
  # reaches no host (ADR-0059 §10).
  #
  # Acceptance criteria:
  # - The supervision tree starts the reader with the quote sync's
  #   `enabled?`: on in production, in development with
  #   PORTFOLIXIR_BACKGROUND_FETCH, off in tests; no config gives it a
  #   switch of its own.
  # - The interval is 6 hours.
  # - An enabled reader's tick reads the chain and writes a bound security's
  #   halvings; with nothing bound it asks no host; a disabled reader never
  #   ticks.
  test "it is enabled exactly where the quote sync is, every 6 hours" do
    {Reader, opts} =
      Enum.find(Portfolixir.Application.children(), &match?({Reader, _}, &1))

    quote_sync = Application.get_env(:portfolixir, QuoteSync, [])
    assert Keyword.fetch!(opts, :enabled?) == Keyword.get(quote_sync, :enabled?, false)
    assert Keyword.fetch!(opts, :enabled?) == false
    assert Reader.interval_ms() == 6 * 60 * 60 * 1000

    assert {Task.Supervisor, name: Portfolixir.Chains.Tasks} in Portfolixir.Application.children()

    for path <- ~w(config/config.exs config/dev.exs config/prod.exs config/runtime.exs) do
      refute File.read!(path) =~ "Chains.Reader",
             "#{path} gives the chain reader a switch of its own"
    end
  end

  test "an enabled reader's tick writes a bound security's halvings" do
    security = security!(:bitcoin)
    serve(%{"mempool.space" => {:chain, 870_000}})
    reader = start_reader!(true)

    send(reader, :tick)
    assert_receive {:esplora, "mempool.space", _path}, 2_000
    wait_until(fn -> :sys.get_state(reader).running == nil end)

    assert Events.count_halvings(security.id) == 5
  end

  test "with no security bound to Bitcoin a tick asks no host" do
    security!(:litecoin)
    serve(%{"mempool.space" => {:chain, 870_000}})
    reader = start_reader!(true)

    send(reader, :tick)
    wait_until(fn -> :sys.get_state(reader).running == nil end)

    refute_received {:esplora, _host, _path}
    assert Reader.state(:bitcoin) == nil
  end

  test "a disabled reader never ticks" do
    security!(:bitcoin)
    serve(%{"mempool.space" => {:chain, 870_000}})

    start_supervised!({Reader, name: nil, enabled?: false, first_tick_ms: 20})

    refute_receive {:esplora, _host, _path}, 200
  end
end
