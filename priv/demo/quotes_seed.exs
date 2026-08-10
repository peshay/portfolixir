# Seeds deterministic synthetic quote history for every demo security, so the
# screenshot pipeline works fully offline (no market-data sync). Weekly closes
# over ~15 months, seeded RNG, anchored at each security's last trade price.
# Run after importing the demo dataset:
#
#   DATABASE_NAME=portfolixir_demo PORT=4003 mix run priv/demo/quotes_seed.exs
alias Portfolixir.Catalog
alias Portfolixir.Catalog.Quotes
alias Portfolixir.Ledger

:rand.seed(:exsss, {42, 42, 42})

today = Date.utc_today()
weeks = 65

for security <- Catalog.list_securities() do
  anchor =
    Ledger.list_transactions()
    |> Enum.filter(&(&1.security_id == security.id and &1.price))
    |> case do
      [] -> Decimal.new("100")
      txs -> txs |> Enum.max_by(& &1.date, Date) |> Map.fetch!(:price)
    end

  anchor_f = Decimal.to_float(anchor)

  {rows, _price} =
    Enum.map_reduce(weeks..0//-1, anchor_f * (0.82 + :rand.uniform() * 0.1), fn back, price ->
      drift = 1.0 + (:rand.uniform() - 0.47) * 0.05
      next = max(price * drift, 0.01)
      date = Date.add(today, -back * 7)
      {%{date: date, close: Float.round(next, 2) |> Float.to_string(), source: "manual"}, next}
    end)

  {:ok, _} = Quotes.upsert_many(security.id, rows)
  IO.puts("quotes seeded: #{security.name}")
end
