defmodule Portfolixir.Catalog.SecuritySearch.PortfolioPerformance do
  @moduledoc """
  Adapter for the public Portfolio Performance search API
  (https://api.portfolio-performance.info/v1/search).

  The API returns objects of the shape:

      {"description": "APPLE INC",
       "isin": "US0378331005",
       "type": "Common Stock",
       "provider": "PP",
       "markets": [{"symbol": "AAPL", "currency": "USD", "exchange": "XNAS"}, ...]}

  Mapping is defensive: missing ISIN/WKN/symbol become `nil`, missing markets
  collapses to `[]`, and duplicate market entries within one hit are removed.
  PP does not return a stable per-result id, so we use the ISIN as
  `online_id` (which is the natural key in their catalogue).
  """

  @behaviour Portfolixir.Catalog.SecuritySearch.Provider

  alias Portfolixir.Catalog.SecuritySearch.{Market, SearchResult}

  @endpoint "https://api.portfolio-performance.info/v1/search"
  @feed_id "PORTFOLIO_PERFORMANCE"

  @impl true
  def id, do: :portfolio_performance

  @impl true
  def search(query, opts \\ []) when is_binary(query) do
    req = req(opts)

    case Req.get(req, url: @endpoint, params: [q: query]) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, decode(body)}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp req(opts) do
    base =
      Req.new(
        headers: [{"user-agent", "portfolixir/0.1 (+https://github.com/portfolixir)"}],
        receive_timeout: 5_000,
        retry: false
      )

    case opts[:req] do
      nil -> base
      overrides when is_list(overrides) -> Req.merge(base, overrides)
    end
  end

  defp decode(body) when is_list(body) do
    body
    |> Enum.map(&to_result/1)
    |> Enum.reject(&is_nil/1)
  end

  defp decode(_), do: []

  defp to_result(%{"description" => description} = entry) when is_binary(description) do
    isin = nilify(Map.get(entry, "isin"))

    markets =
      entry
      |> Map.get("markets", [])
      |> List.wrap()
      |> Enum.map(&to_market/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(fn %Market{symbol: s, exchange_code: e, currency_code: c} -> {s, e, c} end)

    first_market = List.first(markets)

    %SearchResult{
      provider: :portfolio_performance,
      # PP catalogue is keyed by ISIN — use it so conflict detection works
      online_id: isin,
      name: titleize(description),
      isin: isin,
      wkn: nilify(Map.get(entry, "wkn")),
      ticker_symbol: first_market && first_market.symbol,
      currency_code: first_market && first_market.currency_code,
      asset_class: map_asset_class(Map.get(entry, "type"), description),
      feed: @feed_id,
      markets: markets,
      raw: entry
    }
  end

  defp to_result(_), do: nil

  defp to_market(%{"symbol" => _} = entry) do
    %Market{
      symbol: nilify(Map.get(entry, "symbol")),
      currency_code: nilify(Map.get(entry, "currency")),
      exchange_code: nilify(Map.get(entry, "exchange")),
      exchange_name: nilify(Map.get(entry, "exchangeName") || Map.get(entry, "exchange_name")),
      url: nilify(Map.get(entry, "url") || Map.get(entry, "marketUrl")),
      properties: Map.get(entry, "properties") || %{}
    }
  end

  defp to_market(_), do: nil

  # Maps PP's free-form "type" string to our canonical asset_class codes.
  # Unknown types fall back to "other" so a search result is always selectable.
  defp map_asset_class(type, description) when is_binary(type) do
    normalized = type |> String.downcase() |> String.trim()

    cond do
      government_bond_type?(normalized) ->
        "government_bond"

      normalized in ["bond", "fixed income"] and government_bond_description?(description) ->
        "government_bond"

      normalized in ["common stock", "preferred stock", "stock", "share", "equity", "adr", "gdr"] ->
        "equity"

      normalized in ["etf", "exchange-traded fund"] ->
        "etf"

      normalized in ["etp", "etn", "etc"] ->
        "etf"

      normalized in ["mutual fund", "open-end fund", "fund", "investment fund"] ->
        "fund"

      normalized in ["bond", "fixed income"] ->
        "bond"

      normalized in ["cryptocurrency", "crypto"] ->
        "crypto"

      normalized in ["commodity", "futures"] ->
        "commodity"

      normalized in ["index"] ->
        "index"

      true ->
        "other"
    end
  end

  defp map_asset_class(_, description) do
    if government_bond_description?(description), do: "government_bond", else: "other"
  end

  defp government_bond_type?(normalized) do
    normalized in [
      "government bond",
      "sovereign bond",
      "treasury",
      "treasury bond",
      "treasury note",
      "treasury bill",
      "govt bond",
      "public bond",
      "staatsanleihe",
      "bundesanleihe"
    ]
  end

  defp government_bond_description?(description) when is_binary(description) do
    Regex.match?(
      ~r/(bundesrepublik|bundesanleihe|bundesobligation|bundesschatz|staatsanleihe|treasury\s+(note|bond|bill)|government\s+bond|sovereign\s+bond|republic\s+of|kingdom\s+of)/i,
      description
    )
  end

  # PP descriptions are usually upper-case (`APPLE INC`). Reduce to Title Case
  # for nicer display while leaving acronyms intact (e.g. `ETF`, `S&P`).
  defp titleize(string) when is_binary(string) do
    string
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&titleize_word/1)
    |> Enum.join(" ")
  end

  # Words that should always stay upper-case (legal-form suffixes, indices, etc.)
  @preserve_acronyms ~w(AG SA NV PLC GmbH LLC LP LLP ETF ETN ETP ETC REIT UCITS USD EUR GBP CHF JPY)

  defp titleize_word(word) do
    cond do
      word in @preserve_acronyms -> word
      String.match?(word, ~r/\d/) -> word
      String.contains?(word, ".") -> word
      String.contains?(word, "&") -> word
      true -> word |> String.downcase() |> :string.titlecase() |> to_string()
    end
  end

  defp nilify(nil), do: nil
  defp nilify(""), do: nil
  defp nilify(value) when is_binary(value), do: value |> String.trim() |> empty_to_nil()
  defp nilify(value), do: value

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
