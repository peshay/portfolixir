defmodule Portfolixir.Catalog.IsinTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Catalog.Isin
  alias Portfolixir.Portfolios.Reconcile

  # User story (E25 S5, G23):
  # As the operator whose imports match securities by ISIN,
  # I want one catalog rule for what an ISIN is, check digit included,
  # so that a lookalike identifier is recognised as no ISIN at all instead of
  # as a different security.
  #
  # Acceptance criteria:
  # - valid?/1 accepts twelve characters of the ISIN shape in catalog normal
  #   form whose ISO 6166 check digit agrees.
  # - A wrong check digit, a letter from another script, an invisible
  #   character and lowercase are refused.
  # - The reconcile's ISIN typing is the same predicate.
  test "valid?/1 checks the shape and the check digit" do
    for isin <- ["US0378331005", "DE000ACME008", "DE000EXMPL09"] do
      assert Isin.valid?(isin), isin
    end

    for isin <- [
          "US0378331006",
          "DE000ACME001",
          "D\u0415000ACME008",
          "DE000ACME008\u200B",
          "DE000A\u200BCME08",
          "us0378331005",
          "DE000ACME08",
          nil,
          42
        ] do
      refute Isin.valid?(isin), inspect(isin)
    end
  end

  test "the reconcile's ISIN typing is the catalog predicate" do
    for value <- ["US0378331005", "US0378331006", "D\u0415000ACME008", "DE000ACME008"] do
      assert Reconcile.isin?(value) == Isin.valid?(value), value
    end
  end
end
