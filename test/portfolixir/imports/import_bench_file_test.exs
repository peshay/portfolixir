defmodule Portfolixir.Imports.ImportBenchFileTest do
  # Sprint 21 β9 (#971): the synthetic large file the import apply's per-row
  # cost is measured with. The measurement itself is not a test and leaves
  # no file behind; this pins only that the generator writes a file the
  # importer books whole, and books once.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.ImportBenchFile
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier
  alias Portfolixir.Portfolios

  # User story (#971, Sprint 21 β9):
  # As the maintainer deciding #925 on a measurement,
  # I want a synthetic Portfolio Performance CSV of any size, the same bytes
  # for the same size, that the importer books row for row,
  # so that a timed apply on two commits compares the same work, and the
  # file carries no real name.
  #
  # Acceptance criteria:
  # - ImportBenchFile.csv(n) parses to n entries and no row error, and the
  #   same n yields the same bytes.
  # - Its account and security names are synthetic ("Bench …").
  # - Applied into a fresh portfolio it books n transactions; applied again,
  #   it books none and counts every row as already imported by its hash.
  test "the bench file books every row once" do
    csv = ImportBenchFile.csv(240)
    assert csv == ImportBenchFile.csv(240)

    assert {:ok, preview} = Imports.parse_portfolio_performance(csv)
    assert length(preview.entries) == 240
    assert preview.errors == []

    names =
      preview.entries
      |> Enum.flat_map(fn entry ->
        [
          entry.pp_portfolio_name,
          entry.pp_account_name,
          entry.pp_counter_portfolio_name,
          entry.pp_counter_account_name,
          entry.security && entry.security[:name]
        ]
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    assert names != [] and Enum.all?(names, &String.starts_with?(&1, "Bench "))

    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Bench", base_currency_code: "EUR"})

    params = %{portfolio_id: portfolio.id, default_currency_code: "EUR"}

    assert {:ok, %{created_transactions: 240}} = Applier.apply(preview, params)

    assert {:ok, %{created_transactions: 0, already_imported: %{hash: 240}}} =
             Applier.apply(preview, params)
  end
end
