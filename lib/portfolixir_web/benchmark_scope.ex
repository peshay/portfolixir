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
  to 1000 % p.a.) and exact at the engine's scale
  (`Benchmark.exact_rate/1`) — and stores the rate as the normalised decimal
  fraction the comparison engine reads (`rate:0.02` for 2 %, whether typed as
  `2` or `2.0`), a short string by construction. The query, the picker form
  and the remembered cookie all pass through `parse_rate/1`, so a selector
  remembered before a bound existed is dropped on the next request and the
  cookie rewritten without it (E25 S4, F06).
  Whether an id still names a flagged benchmark is decided where the
  selection is used, so an unflagged or deleted security degrades to
  "not selected". An explicit choice with no valid selector (the form
  submitted with nothing ticked) clears the preference. A choice arriving
  from another site (`Sec-Fetch-Site` other than `same-origin` or `none`)
  applies to that request only and leaves the cookie and the session as they
  were (`PortfolixirWeb.FetchSite`, E25 S7, F18 and the review round's
  S7E-4): the page it opens reads it from its own address
  (`PortfolixirWeb.LiveBenchmarkScope`).
  """

  import Plug.Conn

  alias Portfolixir.Portfolios.Performance.Benchmark
  alias PortfolixirWeb.FetchSite

  @cookie "portfolixir_benchmarks"
  @session_key "active_benchmarks"
  # 1 year, same horizon as the view and locale cookies.
  @max_age 60 * 60 * 24 * 365
  @max_benchmarks 2
  @hundred Decimal.new(100)
  # Longer than any rate the engine holds exactly (sign, two integer digits,
  # the point and fifteen places), so a raw value past it is never parsed.
  @max_rate_chars 32
  # The largest id the securities table can hold (int8).
  @max_id 9_223_372_036_854_775_807

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = conn |> fetch_query_params() |> fetch_cookies()
    params = conn.query_params

    case choice(params) do
      {:ok, selectors} -> apply_choice(conn, selectors)
      :none -> carry_cookie(conn)
    end
  end

  @doc """
  The selectors a request's query parameters choose — `{:ok, selectors}`,
  valid ones only, when `benchmark` or `benchmark_rate` is present (an empty
  list clears the choice) — or `:none` when they choose nothing.
  """
  @spec choice(term()) :: {:ok, [String.t()]} | :none
  def choice(params) when is_map(params) do
    if Map.has_key?(params, "benchmark") or Map.has_key?(params, "benchmark_rate"),
      do: {:ok, selectors_from_params(params)},
      else: :none
  end

  def choice(_params), do: :none

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

  @doc """
  The rate a remembered `rate:<fraction>` selector names, through the one
  bound every path shares: `{:ok, rate}` exact at the engine's scale, or
  `:error`.
  """
  @spec parse_rate(term()) :: {:ok, Decimal.t()} | :error
  def parse_rate(raw) when is_binary(raw) do
    with {:ok, fraction} <- parse_decimal(raw), do: Benchmark.exact_rate(fraction)
  end

  def parse_rate(_raw), do: :error

  # The picker's rate field is a percentage; the stored selector carries the
  # fraction the engine reads.
  defp rate_selector(raw) when is_binary(raw) do
    case parse_decimal(raw) do
      {:ok, percent} -> rate_fraction(Decimal.div(percent, @hundred))
      :error -> []
    end
  end

  defp rate_selector(_raw), do: []

  defp parse_decimal(raw) do
    trimmed = String.trim(raw)

    with true <- byte_size(trimmed) <= @max_rate_chars,
         {%Decimal{} = decimal, ""} <- Decimal.parse(trimmed) do
      {:ok, decimal}
    else
      _malformed -> :error
    end
  end

  defp normalize_selector("security:" <> id) do
    case Integer.parse(String.trim(id)) do
      {id, ""} when id > 0 and id <= @max_id -> ["security:#{id}"]
      _ -> []
    end
  end

  defp normalize_selector("rate:" <> rate) do
    case parse_decimal(rate) do
      {:ok, fraction} -> rate_fraction(fraction)
      :error -> []
    end
  end

  defp normalize_selector(_other), do: []

  # The engine's bound and scale, and one spelling per rate so `2` and `2.0`
  # cannot fill both slots with the same benchmark.
  defp rate_fraction(fraction) do
    case Benchmark.exact_rate(fraction) do
      {:ok, rate} -> ["rate:" <> Decimal.to_string(rate, :normal)]
      :error -> []
    end
  end

  # A choice in the query goes into the session and the cookie only when the
  # request may remember it (`PortfolixirWeb.FetchSite`, E25 S7, F18);
  # otherwise the session keeps the remembered selection (S7E-4) and the page
  # reads its own from its address.
  defp apply_choice(conn, selectors) do
    if FetchSite.remember?(conn) do
      conn
      |> put_session(@session_key, selectors)
      |> remember(selectors)
    else
      carry_cookie(conn)
    end
  end

  defp remember(conn, []), do: delete_resp_cookie(conn, @cookie)

  defp remember(conn, selectors),
    do:
      put_resp_cookie(conn, @cookie, Enum.join(selectors, ","),
        max_age: @max_age,
        same_site: "Lax"
      )

  # The remembered selection is re-validated on every request; one that no
  # longer passes is dropped from the session and from the cookie. The
  # rewrite takes nothing from the request, so it happens whatever site the
  # request came from.
  defp carry_cookie(conn) do
    case conn.cookies[@cookie] do
      raw when is_binary(raw) ->
        selectors = raw |> String.split(",") |> normalize_selectors()
        conn = put_session(conn, @session_key, selectors)
        if Enum.join(selectors, ",") == raw, do: conn, else: remember(conn, selectors)

      _none ->
        put_session(conn, @session_key, [])
    end
  end
end
