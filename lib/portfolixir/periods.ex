defmodule Portfolixir.Periods do
  @moduledoc """
  The period vocabulary (ADR-0062's amendment of 2026-11-25, point 6; I59;
  Sprint 32 T1): every key the dashboards, the widgets and the performance
  family's routes take, resolved against a day into the term the reads
  already take (`Portfolixir.Portfolios.Performance.summarise/2`): one of
  the read's own keys, `{:year, year}` or `{:range, from, to}`.

    * **Rolling**, to today: `1d 1w 1m 3m 6m` are ranges ending today,
      ADR-0061 §3's money window `S + 1` to `T` (`1d` today alone, `1w` the
      seven days after `T − 7`, `1m`, `3m` and `6m` the days after the date
      one, three or six months back), as the dashboard read its short
      periods since Sprint 31; `1y 3y 5y max` are the read's own keys.
    * **Calendar**: `mtd` (this month to today), `prev_month`, `qtd` (this
      quarter to today), `prev_quarter` (both whole, across a year's turn),
      `q1` to `q4` of the current year (a quarter not yet begun is refused,
      not read as empty), `ytd` (the read's own key) and `prev_year`.
    * **Keyed**: `year:YYYY`, one calendar year from 1970 (a year not yet
      begun is refused).

  A range may end after today (`q4` in November); the reads clamp it to
  today, as they clamp `?to=`. `ytd`, `1y`, `3y`, `5y` and `max` resolve
  to themselves, so no figure a key returned before the vocabulary moves.

  Keys are matched as strings against a closed set and parsed with fixed
  patterns; no atom is ever made from one.
  """

  alias Portfolixir.Clock

  @rolling ~w(1d 1w 1m 3m 6m 1y 3y 5y max)
  @calendar ~w(mtd prev_month qtd prev_quarter q1 q2 q3 q4 ytd prev_year)
  @keys @rolling ++ @calendar

  # The read's own keys (`Performance.periods/0`), passed through as they are.
  @read_keys ~w(ytd 1y 3y 5y max)

  @first_year 1970
  @year_key ~r/\Ayear:([0-9]{4})\z/

  @typedoc "A term the performance family's reads take."
  @type read_term :: String.t() | {:year, pos_integer()} | {:range, Date.t(), Date.t()}

  @typedoc "Why a key does not resolve."
  @type refusal :: :unknown_period | :not_begun

  @doc "The rolling keys, shortest first."
  @spec rolling() :: [String.t()]
  def rolling, do: @rolling

  @doc "The calendar keys, in the menu's order."
  @spec calendar() :: [String.t()]
  def calendar, do: @calendar

  @doc "Every fixed key: the rolling ones, then the calendar ones."
  @spec keys() :: [String.t()]
  def keys, do: @keys

  @doc "Whether `key` is a key of the vocabulary, by its form (not whether it resolves today)."
  @spec key?(term()) :: boolean()
  def key?(key) when key in @keys, do: true
  def key?(key) when is_binary(key), do: match?({:ok, _year}, year_key(key))
  def key?(_key), do: false

  @doc """
  The term the reads take for `key` on `today`: `{:ok, term}`,
  `{:error, :not_begun}` for a quarter or a year that has not begun, or
  `{:error, :unknown_period}` for anything that is no key.
  """
  @spec resolve(term(), Date.t()) :: {:ok, read_term()} | {:error, refusal()}
  def resolve(key, today \\ Clock.today())

  def resolve(key, %Date{}) when key in @read_keys, do: {:ok, key}

  def resolve("1d", %Date{} = today), do: {:ok, {:range, today, today}}
  def resolve("1w", %Date{} = today), do: {:ok, {:range, Date.add(today, -6), today}}
  def resolve("1m", %Date{} = today), do: {:ok, {:range, months_back(today, 1), today}}
  def resolve("3m", %Date{} = today), do: {:ok, {:range, months_back(today, 3), today}}
  def resolve("6m", %Date{} = today), do: {:ok, {:range, months_back(today, 6), today}}

  def resolve("mtd", %Date{} = today), do: {:ok, {:range, Date.beginning_of_month(today), today}}

  def resolve("prev_month", %Date{} = today) do
    last = today |> Date.beginning_of_month() |> Date.add(-1)
    {:ok, {:range, Date.beginning_of_month(last), last}}
  end

  def resolve("qtd", %Date{} = today), do: {:ok, {:range, quarter_start(today), today}}

  def resolve("prev_quarter", %Date{} = today) do
    start = today |> quarter_start() |> Date.add(-1) |> quarter_start()
    {:ok, {:range, start, quarter_end(start)}}
  end

  def resolve("q" <> n, %Date{} = today) when n in ~w(1 2 3 4) do
    start = Date.new!(today.year, (String.to_integer(n) - 1) * 3 + 1, 1)

    if Date.after?(start, today),
      do: {:error, :not_begun},
      else: {:ok, {:range, start, quarter_end(start)}}
  end

  def resolve("prev_year", %Date{} = today), do: {:ok, {:year, today.year - 1}}

  def resolve(key, %Date{} = today) when is_binary(key) do
    case year_key(key) do
      {:ok, year} when year > today.year -> {:error, :not_begun}
      {:ok, year} -> {:ok, {:year, year}}
      :error -> {:error, :unknown_period}
    end
  end

  def resolve(_key, _today), do: {:error, :unknown_period}

  # ADR-0061 §3's money window: the day after the date `months` back.
  defp months_back(today, months), do: today |> Date.shift(month: -months) |> Date.add(1)

  defp quarter_start(%Date{year: year, month: month}),
    do: Date.new!(year, div(month - 1, 3) * 3 + 1, 1)

  defp quarter_end(start), do: start |> Date.shift(month: 2) |> Date.end_of_month()

  defp year_key(key) do
    case Regex.run(@year_key, key) do
      [_key, digits] ->
        year = String.to_integer(digits)
        if year >= @first_year, do: {:ok, year}, else: :error

      nil ->
        :error
    end
  end
end
