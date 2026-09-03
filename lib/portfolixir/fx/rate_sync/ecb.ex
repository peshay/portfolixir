defmodule Portfolixir.Fx.RateSync.Ecb do
  @moduledoc """
  Fetches the European Central Bank daily euro foreign-exchange reference
  rates:

      GET https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml

  and, for the one-shot historical backfill (issue #737, Sprint 9 D-1), the
  full published series:

      GET https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.xml

  The feed is EUR-based (`1 EUR = rate <currency>`) — exactly Portfolixir's hub
  convention — and publishes one `<Cube currency=.. rate=..>` per currency under
  a dated `<Cube time=..>`. Currencies outside `Catalog.Currencies` are dropped
  so the upsert only ever sees supported codes.
  """

  @behaviour Portfolixir.Fx.RateSync.Provider

  alias Portfolixir.Catalog.Currencies

  @endpoint "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml"
  @history_endpoint "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.xml"
  @hub "EUR"
  @source "ecb"

  @impl true
  def id, do: :ecb

  @impl true
  def fetch(opts) do
    case Req.get(req(opts), url: @endpoint) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, parse(body)}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def fetch_history(opts) do
    # The series is a few MB; give it more room than the daily feed.
    case Req.get(req(Keyword.put_new(opts, :req, receive_timeout: 60_000)),
           url: @history_endpoint
         ) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, parse_history(body)}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Parses the ECB historical XML — one dated `<Cube time=..>` block per
  published day, each carrying its currency rows — into EUR-hub rate rows.
  Public for tests. Unsupported currency codes are dropped like in `parse/1`;
  a date the ECB did not publish (a weekend, a holiday) is simply absent, so
  a booking on such a day stays excluded and named downstream.
  """
  def parse_history(body) when is_binary(body) do
    ~r/<Cube\s+time=['"](\d{4}-\d{2}-\d{2})['"]\s*>(.*?)<\/Cube>/s
    |> Regex.scan(body)
    |> Enum.flat_map(fn [_, iso, block] ->
      case Date.from_iso8601(iso) do
        {:ok, date} -> block |> pairs() |> Enum.flat_map(&row(&1, date))
        _ -> []
      end
    end)
  end

  def parse_history(_body), do: []

  @doc "Parses the ECB daily XML into EUR-hub rate rows. Public for tests."
  def parse(body) when is_binary(body) do
    case reference_date(body) do
      nil -> []
      date -> body |> pairs() |> Enum.flat_map(&row(&1, date))
    end
  end

  def parse(_body), do: []

  defp reference_date(body) do
    case Regex.run(~r/time=['"](\d{4}-\d{2}-\d{2})['"]/, body) do
      [_, iso] ->
        case Date.from_iso8601(iso) do
          {:ok, date} -> date
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp pairs(body) do
    Regex.scan(~r/currency=['"]([A-Za-z]{3})['"]\s+rate=['"]([0-9.]+)['"]/, body)
  end

  defp row([_, currency, rate], date) do
    code = String.upcase(currency)

    if Currencies.supported?(code) do
      [%{base_currency: @hub, quote_currency: code, date: date, rate: rate, source: @source}]
    else
      []
    end
  end

  defp req(opts) do
    base =
      Req.new(
        headers: [{"user-agent", "portfolixir/0.1 (+https://github.com/portfolixir)"}],
        receive_timeout: 10_000,
        retry: false
      )

    case opts[:req] do
      nil -> base
      overrides when is_list(overrides) -> Req.merge(base, overrides)
    end
  end
end
