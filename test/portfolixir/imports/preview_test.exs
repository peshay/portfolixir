defmodule Portfolixir.Imports.PreviewTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.Preview

  # User story:
  # As a local portfolio maintainer previewing a Portfolio Performance import,
  # I want the parsed entries summarised by kind, by unique security and by
  # PP account pair,
  # so that the preview screen can tell me exactly what the apply step would
  # create before I commit to it.
  #
  # Acceptance criteria:
  # - counts_by_kind/1 tallies entries per kind.
  # - unique_securities/1 dedupes by ISIN when present, otherwise by
  #   {name, currency}, and by name alone when no currency is given.
  # - unique_pp_account_pairs/1 dedupes the (portfolio, account) pairs and
  #   drops the empty {nil, nil} pair.

  defp entry(attrs), do: struct(Entry, attrs)

  defp preview(entries), do: %Preview{entries: entries}

  test "counts_by_kind/1 tallies entries per kind" do
    pv =
      preview([
        entry(kind: "buy"),
        entry(kind: "buy"),
        entry(kind: "dividend")
      ])

    assert Preview.counts_by_kind(pv) == %{"buy" => 2, "dividend" => 1}
  end

  test "unique_securities/1 dedupes by ISIN, then {name, currency}, then name" do
    pv =
      preview([
        entry(security: %{isin: "DE0001", name: "A", currency: "EUR"}),
        # Same ISIN, different name -> still one security.
        entry(security: %{isin: "DE0001", name: "A renamed", currency: "USD"}),
        # No ISIN: keyed by {name, currency}.
        entry(security: %{name: "B", currency: "EUR"}),
        entry(security: %{name: "B", currency: "USD"}),
        # No ISIN and no currency: keyed by name alone.
        entry(security: %{name: "C"}),
        entry(security: %{name: "C"}),
        # No security at all -> rejected.
        entry(security: nil)
      ])

    securities = Preview.unique_securities(pv)

    assert length(securities) == 4
    assert Enum.find(securities, &(&1[:isin] == "DE0001"))
    assert Enum.count(securities, &(&1[:name] == "B")) == 2
    assert Enum.count(securities, &(&1[:name] == "C")) == 1
  end

  test "unique_pp_account_pairs/1 dedupes pairs and drops the empty pair" do
    pv =
      preview([
        entry(pp_portfolio_name: "PF", pp_account_name: "Cash"),
        entry(pp_portfolio_name: "PF", pp_account_name: "Cash"),
        entry(pp_portfolio_name: "PF", pp_account_name: "Depot"),
        entry(pp_portfolio_name: nil, pp_account_name: nil)
      ])

    assert Preview.unique_pp_account_pairs(pv) == [{"PF", "Cash"}, {"PF", "Depot"}]
  end
end
