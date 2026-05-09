# ADR 0003: Market Data Strategy

## Status

Accepted for MVP draft.

## Decision

Market data is implemented through provider behaviours first. Concrete providers are added later.

The MVP must support two concepts:

1. **Symbol search**: Given a user input such as `AAPL`, return possible provider symbols such as
   `AAPL`, `AAPL.F`, `AAPL.SG`.
2. **Quote lookup**: Given a provider symbol, return latest price, currency and timestamp.

## Why provider behaviours first

Market-data providers differ in symbol format, exchange naming, rate limits, terms of service and
currency handling. Tests must not depend on live network data.

## Initial behaviour shape

```elixir
defmodule Portfolixir.MarketData.Provider do
  @callback search_symbols(String.t()) :: {:ok, list(map())} | {:error, term()}
  @callback latest_quote(String.t()) :: {:ok, map()} | {:error, term()}
end
```

## MVP fake provider examples

Input:

```text
AAPL
```

Candidates:

```text
AAPL     Apple Inc.        NASDAQ   USD
AAPL.F   Apple Inc.        Frankfurt EUR
AAPL.SG  Apple Inc.        Stuttgart EUR
```

## Non-goals

- No live provider integration in the first batch.
- No intraday streaming.
- No InfluxDB/TimescaleDB requirement.
- No provider API keys in source.
