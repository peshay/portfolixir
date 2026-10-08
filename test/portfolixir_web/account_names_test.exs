defmodule PortfolixirWeb.AccountNamesTest do
  use ExUnit.Case, async: true

  alias PortfolixirWeb.AccountNames

  # User story (Sprint 19 PR γ U3, the sweep; #884 F1's tag):
  # As a German-speaking operator choosing between two accounts of one name
  # in the import preview or the merge flow,
  # I want the tag that tells them apart by their creation day to read
  # DD.MM.YYYY,
  # so that the pick list reads its dates as every other German date does.
  #
  # Acceptance criteria:
  # - Two same-named cash accounts with no depot, one currency, created on
  #   two days, are tagged "angelegt 03.10.2026" and "angelegt 04.10.2026".
  # - English keeps ISO: "created 2026-10-03".
  test "the creation-day tag reads the page's language" do
    cash = [
      %{
        id: 1,
        name: "Verrechnungskonto",
        currency_code: "EUR",
        inserted_at: ~N[2026-10-03 09:00:00]
      },
      %{
        id: 2,
        name: "Verrechnungskonto",
        currency_code: "EUR",
        inserted_at: ~N[2026-10-04 09:00:00]
      }
    ]

    previous = Gettext.get_locale(PortfolixirWeb.Gettext)

    try do
      Gettext.put_locale(PortfolixirWeb.Gettext, "de")
      tags = AccountNames.tags(cash, [])

      assert AccountNames.label(tags, :cash, Enum.at(cash, 0)) ==
               "Verrechnungskonto · angelegt 03.10.2026"

      assert AccountNames.label(tags, :cash, Enum.at(cash, 1)) ==
               "Verrechnungskonto · angelegt 04.10.2026"

      Gettext.put_locale(PortfolixirWeb.Gettext, "en")
      tags = AccountNames.tags(cash, [])

      assert AccountNames.label(tags, :cash, Enum.at(cash, 0)) ==
               "Verrechnungskonto · created 2026-10-03"
    after
      Gettext.put_locale(PortfolixirWeb.Gettext, previous)
    end
  end

  # User story (#1152; ADR-0050's amendment of 2026-10-07, point 6):
  # As the operator picking an account in the import preview or the merge
  # flow, where the name guard compares names exactly,
  # I want two accounts whose names print the same to be told apart in the
  # options,
  # so that "Demo Depot" and "Demo  Depot", which the guard lets coexist, do
  # not read as one option.
  #
  # Acceptance criteria:
  # - Accounts of one kind whose names differ only in Unicode form or in
  #   inner whitespace are same-named for the options, and each takes the
  #   first feature that tells them apart; a label keeps its own name.
  # - Names that differ in letter case stay two names, untagged.
  # - The guard and the resolution stay exact; only the options' tags fold.
  test "same-named accounts are the names that print the same, whatever their bytes" do
    at = ~N[2026-10-03 09:00:00]

    cash = [
      %{id: 1, name: "Giro", currency_code: "EUR", inserted_at: at},
      %{id: 2, name: "Reserve", currency_code: "EUR", inserted_at: at},
      %{id: 3, name: "Kasse M\u00FCnchen", currency_code: "EUR", inserted_at: at},
      %{id: 4, name: "Kasse Mu\u0308nchen", currency_code: "USD", inserted_at: at}
    ]

    depots = [
      %{id: 10, name: "Demo Depot", cash_account_id: 1, inserted_at: at},
      %{id: 11, name: "Demo  Depot", cash_account_id: 2, inserted_at: at},
      %{id: 12, name: "demo depot", cash_account_id: 1, inserted_at: at}
    ]

    Gettext.with_locale(PortfolixirWeb.Gettext, "en", fn ->
      tags = AccountNames.tags(cash, depots)

      assert tags == %{
               cash: %{3 => "EUR", 4 => "USD"},
               depot: %{10 => "with Giro", 11 => "with Reserve"}
             }

      assert AccountNames.label(tags, :depot, Enum.at(depots, 1)) == "Demo  Depot · with Reserve"
      assert AccountNames.label(tags, :depot, Enum.at(depots, 2)) == "demo depot"
    end)
  end
end
