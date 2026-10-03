defmodule Portfolixir.Catalog.SecurityBondFieldsTest do
  # #330 (ADR-0052 §1): a bond's master data as six typed, nullable columns,
  # validated by the security's own changeset. The bond is invented.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security

  @bond %{
    "name" => "Musterland Anleihe 2031",
    "isin" => "XSFIELDS0319",
    "currency_code" => "EUR",
    "asset_class" => "government_bond"
  }

  defp errors_on_create(attrs) do
    {:error, changeset} = Catalog.create_security(Actor.owner_ui(), Map.merge(@bond, attrs))
    errors_on(changeset)
  end

  # User story (#330, ADR-0052 §1):
  # As the operator entering a bond's master data,
  # I want its coupon, payment frequency, maturity, issue date and
  # denomination stored as typed values,
  # so that the bond's figures are computed from what I entered and an
  # impossible value is refused on its own field.
  #
  # Acceptance criteria:
  # - The six fields are stored as Decimal, date and closed-set values; the
  #   denomination's currency is upper-cased.
  # - Each can be cleared again, and none is required.
  # - They are journaled with the security's update.
  test "stores a bond's master data as typed values, clearable and journaled" do
    {:ok, bond} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(@bond, %{
          "coupon_rate" => "2.5",
          "coupon_frequency" => "semi_annual",
          "maturity_date" => "2031-06-15",
          "issue_date" => "2021-06-15",
          "face_value" => "1000",
          "face_value_currency_code" => "eur"
        })
      )

    assert %Security{
             coupon_frequency: "semi_annual",
             maturity_date: ~D[2031-06-15],
             issue_date: ~D[2021-06-15],
             face_value_currency_code: "EUR"
           } = bond

    assert Decimal.equal?(bond.coupon_rate, Decimal.new("2.5"))
    assert Decimal.equal?(bond.face_value, Decimal.new("1000"))

    {:ok, cleared} =
      Catalog.update_security(Actor.api_token_rw(), bond, %{
        "coupon_rate" => nil,
        "coupon_frequency" => "",
        "issue_date" => nil
      })

    assert cleared.coupon_rate == nil
    assert cleared.coupon_frequency == nil
    assert cleared.issue_date == nil
    assert cleared.maturity_date == ~D[2031-06-15]

    [entry | _] =
      Portfolixir.Journal.list_entries(
        resource_type: "security",
        resource_id: Integer.to_string(bond.id)
      )

    assert entry.operation == :update
    assert Decimal.equal?(Decimal.new(entry.before["coupon_rate"]), Decimal.new("2.5"))
    assert entry.after["coupon_rate"] == nil

    {:ok, bare} =
      Catalog.create_security(Actor.owner_ui(), %{@bond | "isin" => "XSFIELDS0293"})

    assert bare.coupon_rate == nil and bare.maturity_date == nil and bare.face_value == nil
  end

  # User story (#330, ADR-0052 §1):
  # As the operator or the agent typing a bond's master data,
  # I want a value no bond can carry refused on the field that holds it,
  # with nothing stored,
  # so that a typo never becomes a figure.
  #
  # Acceptance criteria:
  # - The coupon is a percent from 0 to 100: -0.5 and 250 are refused, and
  #   it is rounded to the column's six places.
  # - The denomination is above 0; the frequency is annual or semi_annual;
  #   the denomination's currency is a supported one.
  # - A maturity on or before the issue date is refused on maturity_date;
  #   a date outside 1900–2999 is refused on its field.
  test "refuses a value no bond carries, on its own field" do
    assert %{coupon_rate: [_]} = errors_on_create(%{"coupon_rate" => "-0.5"})
    assert %{coupon_rate: [_]} = errors_on_create(%{"coupon_rate" => "250"})
    assert %{face_value: [_]} = errors_on_create(%{"face_value" => "0"})

    assert %{coupon_frequency: ["is invalid"]} =
             errors_on_create(%{"coupon_frequency" => "monthly"})

    assert %{face_value_currency_code: ["is invalid"]} =
             errors_on_create(%{"face_value_currency_code" => "XXQ"})

    assert %{maturity_date: ["must be after the issue date"]} =
             errors_on_create(%{"maturity_date" => "2021-06-15", "issue_date" => "2021-06-15"})

    assert %{issue_date: [_]} = errors_on_create(%{"issue_date" => "1899-12-31"})

    changeset = Security.changeset(%Security{}, Map.put(@bond, "coupon_rate", "2.1234567"))
    assert Decimal.to_string(Ecto.Changeset.get_change(changeset, :coupon_rate)) == "2.123457"
  end

  # User story (#330, ADR-0052 §1):
  # As the operator who set a security's class to a bond by mistake and
  # entered master data,
  # I want the data kept when I change the class back,
  # so that switching the class is never a silent delete.
  #
  # Acceptance criteria:
  # - After the class changes to equity the master data is still stored.
  test "keeps the master data when the asset class changes away from a bond" do
    {:ok, bond} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(@bond, %{"coupon_rate" => "2.5", "maturity_date" => "2031-06-15"})
      )

    {:ok, equity} = Catalog.update_security(Actor.owner_ui(), bond, %{"asset_class" => "equity"})

    assert equity.asset_class == "equity"
    assert Decimal.equal?(equity.coupon_rate, Decimal.new("2.5"))
    assert equity.maturity_date == ~D[2031-06-15]
  end
end
