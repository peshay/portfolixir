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
end
