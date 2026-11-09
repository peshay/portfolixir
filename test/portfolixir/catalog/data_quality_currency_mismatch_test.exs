defmodule Portfolixir.Catalog.DataQualityCurrencyMismatchTest do
  # #1415 (Sprint 28 Q3, OQ-2 of the triage of 2026-11-07): the
  # `currency_mismatch` set over the provider currency each sync keeps.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.DataQuality

  @read_at ~U[2026-11-09 08:15:00Z]

  defp security!(name, currency, attrs \\ %{}) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(
          %{name: name, currency_code: currency, provider: "portfolio_performance"},
          attrs
        )
      )

    security
  end

  defp stated!(security, currency) do
    {:ok, security} =
      Catalog.put_provider_currency(
        Portfolixir.Actor.system_job("quote_sync"),
        security,
        currency,
        @read_at
      )

    security
  end

  defp names(rows), do: rows |> Enum.map(& &1.security.name) |> Enum.sort()

  # User story (#1415):
  # As the operator and as the agent working the catalog,
  # I want every security whose provider stated another currency than its
  # own in one data-quality set,
  # so that a series stored in the wrong currency before the sync's check,
  # or by a ticker that moved to another listing, is named and can be fixed.
  #
  # Acceptance criteria:
  # - The set holds a security whose stored provider currency differs from
  #   its currency_code: USD for EUR, and GBp (pence) for GBP, compared as
  #   written.
  # - A security whose provider stated its own currency is not in it, nor
  #   one no sync has read a currency for (null: not yet known).
  # - Benchmarks and retired securities are left out, as from the other
  #   catalog-hygiene sets, in the query half and on rows loaded without it.
  # - Its count is its list's length, with and without a caller's narrowing.
  test "currency_mismatch holds the securities whose provider stated another currency" do
    stated!(security!("Dollar Line", "EUR"), "USD")
    stated!(security!("Pence Line", "GBP"), "GBp")
    stated!(security!("Own Line", "EUR"), "EUR")
    security!("Never Read", "EUR")
    stated!(security!("Benchmark Line", "EUR", %{is_benchmark: true}), "USD")
    stated!(security!("Retired Line", "EUR", %{is_retired: true}), "USD")

    assert "currency_mismatch" in DataQuality.ids()
    assert DataQuality.valid?("currency_mismatch")

    assert names(DataQuality.list("currency_mismatch")) == ["Dollar Line", "Pence Line"]
    assert DataQuality.count("currency_mismatch") == 2

    assert DataQuality.list_opts("currency_mismatch") == [is_benchmark: false, is_retired: false]

    # Rows loaded without the query half: the retired one stays out.
    rows = Catalog.list_securities_with_metrics()

    refute "Retired Line" in names(DataQuality.refine(rows, "currency_mismatch"))

    # A caller's narrowing that contradicts the set matches nothing, by list
    # and by count alike.
    assert DataQuality.list("currency_mismatch", is_retired: true) == []
    assert DataQuality.count("currency_mismatch", is_retired: true) == 0
  end

  # User story (#1415; the AGENTS.md metric rule):
  # As the agent reading the set,
  # I want its rule stated beside it, and each listed security's stored
  # provider currency and the time it was read,
  # so that I can check a finding without fetching anything.
  #
  # Acceptance criteria:
  # - `findings/1` names, per security, its currency_code, the stored
  #   provider currency and when it was read.
  # - `computation_basis("currency_mismatch")` names the input (the stored
  #   provider currency and provider_currency_at), the reference
  #   (currency_code), the window (the read that stored it), the gaps (null
  #   is not yet known, never a mismatch) and the threshold (any difference,
  #   letter case included).
  test "the set's findings and basis name the stored provider currency and when it was read" do
    dollar = stated!(security!("Dollar Line", "EUR"), "USD")

    assert [
             %{
               security_id: id,
               currency_code: "EUR",
               provider_currency: "USD",
               provider_currency_at: @read_at
             }
           ] = DataQuality.currency_mismatch_findings([dollar])

    assert id == dollar.id

    basis = DataQuality.computation_basis("currency_mismatch")

    assert basis.input_series =~ "provider_currency"
    assert basis.input_series =~ "provider_currency_at"
    assert basis.reference =~ "currency_code"
    assert basis.window =~ "stored"
    assert basis.gaps =~ "not yet known"
    assert basis.threshold =~ "GBp"
    assert basis.assumptions =~ "benchmark"
  end
end
