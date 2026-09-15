defmodule PortfolixirWeb.BenchmarkScope do
  @moduledoc """
  Remembers the Wealth page's benchmark selection across requests
  (ADR-0046 §4: the selection is explicit per request in v1 — a query
  parameter the page remembers in the session).

  Mirrors `PortfolixirWeb.ViewScope`: the choice arrives as
  `?benchmark[]=security:<id>` entries and/or `?benchmark_rate=<percent>`
  on a full navigation (the picker is a plain GET form), is stored in the
  session (so the LiveView mount can read it) and in a long-lived cookie (so
  it survives a new session). At most two selectors are kept, in the order
  given, securities first and the rate last.

  The plug validates only the **shape** of a selector — a positive integer
  security id, or a finite rate inside the engine's own bound
  (`Portfolixir.Portfolios.Performance.Benchmark.valid_rate?/1`, -99.9999 %
  to 1000 % p.a.) — and stores the rate as the normalised decimal fraction
  the comparison engine reads (`rate:0.02` for 2 %, whether typed as `2` or
  `2.0`).
  Whether an id still names a flagged benchmark is decided where the
  selection is used, so an unflagged or deleted security degrades to
  "not selected". An explicit choice with no valid selector (the form
  submitted with nothing ticked) clears the preference.
  """

  import Plug.Conn

  alias Portfolixir.Portfolios.Performance.Benchmark

  @cookie "portfolixir_benchmarks"
  @session_key "active_benchmarks"
  # 1 year, same horizon as the view and locale cookies.
  @max_age 60 * 60 * 24 * 365
  @max_benchmarks 2
  @hundred Decimal.new(100)
  # The largest id the securities table can hold (int8).
  @max_id 9_223_372_036_854_775_807

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = conn |> fetch_query_params() |> fetch_cookies()
    params = conn.query_params

    if Map.has_key?(params, "benchmark") or Map.has_key?(params, "benchmark_rate") do
      apply_choice(conn, selectors_from_params(params))
    else
      carry_cookie(conn)
    end
  end

  @doc "The session key the LiveView on_mount reads the selectors from."
  def session_key, do: @session_key

  @doc "The cookie name the selection is persisted under."
  def cookie_name, do: @cookie

  @doc """
  The valid selectors of a list of raw strings, in order, at most
  #{@max_benchmarks}: `"security:<id>"` and `"rate:<fraction>"` pass through
  when well-formed, everything else is dropped.
  """
  @spec normalize_selectors([String.t()] | term()) :: [String.t()]
  def normalize_selectors(raw) when is_list(raw) do
    raw
    |> Enum.flat_map(&normalize_selector/1)
    |> Enum.uniq()
    |> Enum.take(@max_benchmarks)
  end

  def normalize_selectors(_raw), do: []

  defp selectors_from_params(params) do
    entries =
      case Map.get(params, "benchmark") do
        list when is_list(list) -> list
        one when is_binary(one) -> [one]
        _none -> []
      end

    normalize_selectors(entries ++ rate_selector(Map.get(params, "benchmark_rate")))
  end

  # The picker's rate field is a percentage; the stored selector carries the
  # fraction the engine reads.
  defp rate_selector(raw) when is_binary(raw) do
    case Decimal.parse(String.trim(raw)) do
      {%Decimal{} = percent, ""} -> rate_fraction(Decimal.div(percent, @hundred))
      _malformed -> []
    end
  end

  defp rate_selector(_raw), do: []

  defp normalize_selector("security:" <> id) do
    case Integer.parse(String.trim(id)) do
      {id, ""} when id > 0 and id <= @max_id -> ["security:#{id}"]
      _ -> []
    end
  end

  defp normalize_selector("rate:" <> rate) do
    case Decimal.parse(String.trim(rate)) do
      {%Decimal{} = fraction, ""} -> rate_fraction(fraction)
      _ -> []
    end
  end

  defp normalize_selector(_other), do: []

  # The engine's bound, and one spelling per rate so `2` and `2.0` cannot
  # fill both slots with the same benchmark.
  defp rate_fraction(fraction) do
    if Benchmark.valid_rate?(fraction),
      do: ["rate:" <> Decimal.to_string(Decimal.normalize(fraction), :normal)],
      else: []
  end

  defp apply_choice(conn, []) do
    conn
    |> put_session(@session_key, [])
    |> delete_resp_cookie(@cookie)
  end

  defp apply_choice(conn, selectors) do
    conn
    |> put_session(@session_key, selectors)
    |> put_resp_cookie(@cookie, Enum.join(selectors, ","), max_age: @max_age, same_site: "Lax")
  end

  defp carry_cookie(conn) do
    selectors =
      case conn.cookies[@cookie] do
        raw when is_binary(raw) -> raw |> String.split(",") |> normalize_selectors()
        _none -> []
      end

    put_session(conn, @session_key, selectors)
  end
end
