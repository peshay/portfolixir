# Synthetic Fixtures

Use only synthetic data in tests.

## Example currencies

```text
EUR — Euro
USD — US Dollar
CHF — Swiss Franc
GBP — Pound Sterling
SEK — Swedish Krona
NOK — Norwegian Krone
DKK — Danish Krone
JPY — Japanese Yen
```

## Example securities

```text
AAPL     Apple Inc. Synthetic NASDAQ      USD
AAPL.F   Apple Inc. Synthetic Frankfurt   EUR
AAPL.SG  Apple Inc. Synthetic Stuttgart   EUR
TEST.DE  Test ETF Synthetic XETRA         EUR
```

These may use real-looking symbols for recognizability, but no real holdings, account numbers or user-specific values may be included.

## Example buy transaction

```text
Portfolio: Demo Portfolio EUR
Security: AAPL
Trade date: 2026-01-02
Quantity: 10
Gross amount: 1000.00
Currency: USD
Fees: 1.00
Taxes: 0.00
```

## Example quote

```text
Symbol: AAPL
Price: 100.00
Currency: USD
Quoted at: 2026-01-03T12:00:00Z
```

## Example valuation

```text
10 AAPL * 100.00 USD = 1000.00 USD
1000.00 USD * 0.90 = 900.00 EUR
```
