defmodule Portfolixir.CycleFixtures do
  @moduledoc """
  A synthetic coin with halving cycles (FR-58, ADR-0060), for the screen's
  tests and the browser walk of the cycle chart (Sprint 29 H7).

  The same coin as the cycles API test's `coin!/3`
  (`test/portfolixir_web/controllers/api_v1_security_cycles_test.exs`):
  bound to Litecoin, a chain without a source, so its halvings are written
  by hand; five halvings, four confirmed; closes that give both bands, their
  parts and `agree`. Every name, date and close is synthetic.
  """

  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Chains.ChainRead
  alias Portfolixir.Chains.Registry
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Repo

  @halvings [
    {1, "2013-01-10", true},
    {2, "2015-01-10", true},
    {3, "2017-01-10", true},
    {4, "2019-01-10", true},
    {5, "2021-01-05", false}
  ]

  @closes [
    {~D[2013-01-10], "40"},
    {~D[2013-03-01], "50"},
    {~D[2013-06-01], "80"},
    {~D[2014-09-01], "10"},
    {~D[2015-01-10], "9"},
    {~D[2016-03-01], "200"},
    {~D[2016-09-01], "30"},
    {~D[2017-01-10], "50"},
    {~D[2017-08-01], "500"},
    {~D[2018-05-01], "100"},
    {~D[2019-01-10], "470"},
    {~D[2019-10-01], "1500"},
    {~D[2020-05-01], "1000"}
  ]

  @doc """
  The coin, bound to `chain` (`:litecoin` by default), with the halvings
  and closes above. Options: `:name`, `:chain`, `:halvings` (how many of
  the five halving rows to write, all by default), `:closes_from` (the
  first close kept; a later one makes the first window partial),
  `:shift_days` (every date moved by that many days, so a test can put the
  last close near today and the bands past it; Sprint 29 H8),
  `:next_window_days` (the unconfirmed halving written as a window of that
  many days after its date, as the chain reader writes the next one).
  """
  def synthetic_cycle_coin!(opts \\ []) do
    name = Keyword.get(opts, :name, "Synthetic Cycle Coin")
    chain = Keyword.get(opts, :chain, :litecoin)
    count = Keyword.get(opts, :halvings, length(@halvings))
    shift = Keyword.get(opts, :shift_days, 0)
    agent = Actor.api_token_rw("synthetic-agent")

    coin = create_security!(name: name, ticker: nil, asset_class: "crypto", currency: "USD")
    {:ok, coin} = Catalog.update_security(agent, coin, %{halving_chain: chain})

    window = Keyword.get(opts, :next_window_days)

    for {k, date, confirmed} <- Enum.take(@halvings, count) do
      date = date |> Date.from_iso8601!() |> Date.add(shift)

      extra =
        if window && not confirmed,
          do: %{"timing" => "window", "date_end" => Date.add(date, window)},
          else: %{}

      {:ok, _event} =
        halving!(
          coin,
          chain,
          k * Registry.halving_interval(chain),
          Date.to_iso8601(date),
          confirmed,
          extra
        )
    end

    from = Keyword.get(opts, :closes_from, ~D[1900-01-01])

    rows =
      for {date, close} <- @closes,
          Date.compare(date, from) != :lt,
          do: %{date: Date.add(date, shift), close: Decimal.new(close), source: "manual"}

    {:ok, _count} = Quotes.upsert_many(coin.id, rows)
    coin
  end

  @doc """
  The `:shift_days` that puts the coin's last close `days_ago` days before
  `today`: its next low's band then runs past today and its next top's band
  lies after it (Sprint 29 H8, the range „Zyklus“).
  """
  def recent_shift(today, days_ago \\ 30),
    do: Date.diff(today, List.last(@closes) |> elem(0)) - days_ago

  @doc """
  Writes `chain`'s state row (ADR-0059 §8) as a run would have left it:
  `attrs` with `:source_host`, `:last_tried_at`, `:last_ok_at` and
  `:last_error`; `:inserted_at` defaults to the last try.
  """
  def chain_state!(chain, attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    attrs = Map.new(attrs)
    first = attrs[:inserted_at] || attrs[:last_tried_at] || now

    Repo.insert!(
      struct(
        %ChainRead{chain: Atom.to_string(chain), inserted_at: first, updated_at: now},
        attrs
      )
    )
  end

  # A chain without a source takes its halvings by hand (an agent's write);
  # a chain with one only from its reader (ADR-0059 §5), so the fixture
  # writes them as the reader's run does.
  defp halving!(coin, chain, height, date, confirmed, extra) do
    attrs =
      Map.merge(
        %{
          "date" => date,
          "timing" => "exact",
          "confirmed" => confirmed,
          "source_quality" => if(confirmed, do: "primary", else: "unverified")
        },
        extra
      )

    if Registry.has_source?(chain) do
      Events.put_chain_halving(Actor.system_job("chain_read"), coin.id, chain, height, attrs)
    else
      Events.create_event(
        Actor.api_token_rw("synthetic-agent"),
        Map.merge(attrs, %{
          "security_id" => coin.id,
          "kind" => "halving",
          "chain_height" => height,
          "source_quality" => "unverified"
        })
      )
    end
  end
end
