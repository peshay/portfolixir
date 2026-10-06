defmodule PortfolixirWeb.FieldLabelTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Buckets.Bucket
  alias Portfolixir.Catalog.IdentifierAlias
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias PortfolixirWeb.FieldLabel

  # The schemas an import's apply and the booking drawer write: a refusal can
  # name any field they store. The keys nobody writes are left out.
  @schemas [
    Transaction,
    Security,
    CashAccount,
    SecuritiesAccount,
    Portfolio,
    Bucket,
    IdentifierAlias
  ]
  @unwritten [:id, :inserted_at, :updated_at]

  # The ISIN change refuses a field no schema stores: the ISIN it records.
  @virtual [:new_isin]

  defp written_fields do
    @schemas
    |> Enum.flat_map(& &1.__schema__(:fields))
    |> Enum.concat(@virtual)
    |> Enum.uniq()
    |> Kernel.--(@unwritten)
  end

  # User story (board ux-design-2026-10-04/09-import-correction, found while
  # drawing):
  # As an operator whose import or booking is refused by a rule it broke,
  # I want the refusal to name the field by the word the screen uses,
  # so that no changeset key such as `isin` or `counter_cash_account_id`
  # reaches a page.
  #
  # Acceptance criteria:
  # - Every field the schemas an import writes store has a label that is not
  #   its key and carries no underscore, so a field added later without a
  #   label fails here.
  # - The counter fields read "Counter account" and "Counter depot"
  #   ("Gegenkonto" and "Gegendepot" in German).
  # - An unknown key falls back to the key.
  test "every field an import or a booking can be refused on reads as a label" do
    unlabelled =
      for field <- written_fields(),
          label = FieldLabel.label(field),
          label == Atom.to_string(field) or label =~ "_" or label == "",
          do: field

    assert unlabelled == []

    assert FieldLabel.label(:isin) == "ISIN"
    assert FieldLabel.label(:notes) == "Notes"
    assert FieldLabel.label(:counter_cash_account_id) == "Counter account"
    assert FieldLabel.label(:counter_securities_account_id) == "Counter depot"
    assert FieldLabel.label(:some_unknown_field) == "some_unknown_field"
  end

  test "the labels read in German" do
    Gettext.put_locale(PortfolixirWeb.Gettext, "de")

    assert FieldLabel.label(:counter_cash_account_id) == "Gegenkonto"
    assert FieldLabel.label(:counter_securities_account_id) == "Gegendepot"
    assert FieldLabel.label(:cash_account_id) == "Verrechnungskonto"
    assert FieldLabel.label(:currency_code) == "Währung"
    assert FieldLabel.label(:settlement_fx_rate) == "Wechselkurs"
    assert FieldLabel.label(:new_isin) == "Neue ISIN"
  end

  # User story (the review round):
  # As an operator reading a refusal in German,
  # I want the field and the rule both in my language, joined one way on
  # every page,
  # so that no English rule and no changeset key reaches a German screen.
  #
  # Acceptance criteria:
  # - `changeset_message/1` reads "<label> <message>" per field, messages of
  #   one field joined by ", ", fields joined by "; ", each message through
  #   the `errors` domain.
  # - A message naming another field (`%{field}`) names it by its label.
  test "a changeset reads as labels and translated messages, joined one way" do
    Gettext.put_locale(PortfolixirWeb.Gettext, "de")

    changeset =
      %Transaction{}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.add_error(:isin, "has already been taken")
      |> Ecto.Changeset.add_error(
        :settlement_fx_rate,
        "is required for a cross-currency settlement"
      )
      |> Ecto.Changeset.add_error(:counter_cash_account_id, "must differ from %{field}",
        field: :cash_account_id
      )
      |> Ecto.Changeset.add_error(
        :counter_cash_account_id,
        "must match the transaction currency (%{currency})",
        currency: "EUR"
      )

    message = FieldLabel.changeset_message(changeset)

    assert message
           |> String.split("; ")
           |> Enum.sort() == [
             "Gegenkonto muss der Währung der Buchung entsprechen (EUR), " <>
               "muss sich von Verrechnungskonto unterscheiden",
             "ISIN ist bereits vergeben",
             "Wechselkurs ist für eine Abrechnung in einer anderen Währung erforderlich"
           ]
  end
end
