defmodule PortfolixirWeb.SecurityNamesCatalogTest do
  # `SecurityNames.put_catalog_twin_ids/2` (#1155, Sprint 21 γ8; board
  # ux-design-2026-10-09/08-shared-copy, N14 = A): the table rule for a
  # payload whose rows carry a security's id and name but no identifier — the
  # closed trades, the allocation's positions. Every name and identifier is
  # synthetic.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias PortfolixirWeb.SecurityNames

  # This module's own ISINs (#1018: unique instance-wide, async writers).
  @arbolia_a "XSG8TWIN0036"
  @arbolia_b "XSG8TWIN0044"

  defp security!(name, attrs) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(%{name: name, currency_code: "EUR", asset_class: "equity"}, attrs)
      )

    security
  end

  # User story (#1155, Sprint 21 γ8; board 08, N14 = A):
  # As the operator reading my closed trades and my allocation,
  # I want two securities stored under one name told apart there too,
  # so that a payload that carries no ISIN still tags a twin the way the
  # Positions table does.
  #
  # Acceptance criteria:
  # - Each row of a twin carries the identifier the catalog's ISIN and WKN
  #   give it (ISIN, else WKN, else the number), one security on several rows
  #   the same one.
  # - A unique name, a row without a security id (the flat positions' cash
  #   entry) and a row the catalog does not know carry `nil`.
  # - Nothing else of a row changes.
  test "put_catalog_twin_ids/2 tags a twin from the catalog" do
    a = security!("Arbolia Inc.", %{isin: @arbolia_a})
    b = security!("Arbolia Inc.", %{isin: @arbolia_b})
    c = security!("Larkspur Rail AG", %{wkn: "G8LRK1"})
    d = security!("Wrenfield Gardens AG", %{wkn: "G8WRN1"})
    e = security!("Wrenfield Gardens AG", %{})

    rows = [
      %{security_id: a.id, security_name: "Arbolia Inc.", value: 1},
      %{security_id: b.id, security_name: "Arbolia Inc.", value: 2},
      %{security_id: a.id, security_name: "Arbolia Inc.", value: 3},
      %{security_id: c.id, security_name: "Larkspur Rail AG", value: 4},
      %{security_id: d.id, security_name: "Wrenfield Gardens AG", value: 5},
      %{security_id: e.id, security_name: "Wrenfield Gardens AG", value: 6},
      %{security_id: :cash, security_name: "Cash", value: 7}
    ]

    tagged = SecurityNames.put_catalog_twin_ids(rows, & &1.security_name)

    assert Enum.map(tagged, & &1.twin_id) == [
             {:isin, @arbolia_a},
             {:isin, @arbolia_b},
             {:isin, @arbolia_a},
             nil,
             {:number, d.id},
             {:number, e.id},
             nil
           ]

    assert Enum.map(tagged, &Map.delete(&1, :twin_id)) == rows
  end
end
