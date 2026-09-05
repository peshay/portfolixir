defmodule Portfolixir.Ledger.ProvenanceTest do
  # Issue #766 (D-4 of the 2026-09-05 triage): the import content hash says
  # "this row came from an import"; only the importer may say so.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction

  defp world do
    w = base_world(name: "Prov Portfolio", cash_name: "Prov Cash", depot_name: "Prov Depot")

    Map.put(
      w,
      :security,
      create_security!(name: "Prov Security", ticker: "PRV", asset_class: "equity")
    )
  end

  defp dividend_attrs(w) do
    %{
      portfolio_id: w.portfolio.id,
      date: ~D[2026-04-01],
      currency_code: "EUR",
      type: "dividend",
      security_id: w.security.id,
      cash_account_id: w.cash.id,
      gross_amount: Decimal.new("12.34")
    }
  end

  # User story:
  # As the operator whose ledger is re-imported from a Portfolio Performance export,
  # I want a hand-entered or API-entered booking never to carry an import hash,
  # so that no caller can make a later import skip a row or fail its unique index.
  #
  # Acceptance criteria:
  # - The public create refuses `import_hash` with a named error.
  # - The public update refuses `import_hash` the same way.
  # - The importer's changeset accepts it.
  test "the public write refuses an import hash" do
    w = world()
    attrs = Map.put(dividend_attrs(w), :import_hash, "sha256-forged")

    assert {:error, changeset} = Ledger.create_transaction(Actor.api_token_rw(), attrs)
    assert errors_on(changeset)[:import_hash] == ["is set by the importer"]

    assert {:ok, tx} = Ledger.create_transaction(Actor.api_token_rw(), dividend_attrs(w))
    assert tx.import_hash == nil

    assert {:error, changeset} =
             Ledger.update_transaction(Actor.api_token_rw(), tx, %{
               "import_hash" => "sha256-forged"
             })

    assert errors_on(changeset)[:import_hash] == ["is set by the importer"]
    assert Ledger.get_transaction(tx.id).import_hash == nil
  end

  test "the importer's changeset carries the hash" do
    w = world()

    changeset =
      Transaction.import_changeset(
        %Transaction{},
        Map.put(dividend_attrs(w), :import_hash, "sha256-real")
      )

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :import_hash) == "sha256-real"
  end
end
