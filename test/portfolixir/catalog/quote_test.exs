defmodule Portfolixir.Catalog.QuoteTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog.Quote, as: SecurityQuote

  # User story:
  # As a local portfolio maintainer,
  # I want stored quotes to carry Decimal closes and a known provenance source,
  # so that chart history is reproducible and auditable from local data.
  #
  # Acceptance criteria:
  # - A quote with `security_id`, `date`, `close` (Decimal) and a valid
  #   `source` is accepted by the changeset.
  # - Missing fields are rejected with errors.
  # - Unknown sources are rejected so we never store unverified provenance.

  test "sources/0 lists the known quote provenance tags" do
    assert SecurityQuote.sources() == ~w(auto manual coingecko portfolio_performance)
  end

  describe "changeset/2" do
    test "accepts a complete quote with a Decimal close" do
      attrs = %{
        security_id: 1,
        date: ~D[2026-05-15],
        close: Decimal.new("123.4500"),
        source: "auto"
      }

      changeset = SecurityQuote.changeset(%SecurityQuote{}, attrs)
      assert changeset.valid?
    end

    test "requires security_id, date, close, source" do
      changeset = SecurityQuote.changeset(%SecurityQuote{}, %{})
      refute changeset.valid?

      errors = errors_on(changeset)

      for field <- [:security_id, :date, :close, :source] do
        assert errors[field], "expected #{inspect(field)} to be required"
      end
    end

    test "rejects unknown sources" do
      changeset =
        SecurityQuote.changeset(%SecurityQuote{}, %{
          security_id: 1,
          date: ~D[2026-05-15],
          close: Decimal.new("1"),
          source: "rumour"
        })

      refute changeset.valid?
      assert errors_on(changeset)[:source]
    end

    test "accepts each known source" do
      for source <- ~w(auto manual coingecko portfolio_performance) do
        changeset =
          SecurityQuote.changeset(%SecurityQuote{}, %{
            security_id: 1,
            date: ~D[2026-05-15],
            close: Decimal.new("1"),
            source: source
          })

        assert changeset.valid?, "expected source #{inspect(source)} to be allowed"
      end
    end

    test "casts a string close into a Decimal value" do
      changeset =
        SecurityQuote.changeset(%SecurityQuote{}, %{
          security_id: 1,
          date: ~D[2026-05-15],
          close: "123.45",
          source: "manual"
        })

      assert changeset.valid?
      assert Decimal.equal?(Ecto.Changeset.get_field(changeset, :close), Decimal.new("123.45"))
    end
  end
end
