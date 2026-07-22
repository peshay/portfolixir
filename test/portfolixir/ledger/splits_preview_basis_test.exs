defmodule Portfolixir.Ledger.SplitsPreviewBasisTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Ledger.Splits

  defp insert_quote!(security, date, close, source) do
    {:ok, _} =
      %SecurityQuote{}
      |> SecurityQuote.changeset(%{
        security_id: security.id,
        date: date,
        close: Decimal.new(close),
        source: source
      })
      |> Repo.insert()
  end

  defp preview!(security, opts \\ []) do
    {:ok, preview} =
      Splits.preview_split(%{
        security_id: security.id,
        date: Keyword.get(opts, :date, ~D[2026-02-02]),
        ratio_numerator: Keyword.get(opts, :numerator, 10),
        ratio_denominator: Keyword.get(opts, :denominator, 1)
      })

    preview
  end

  defp world_with_security do
    world = base_world(name: "PG World", cash_name: "PG Cash", depot_name: "PG Depot")
    security = create_security!(name: "PG Co", ticker: "PGG")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])
    {world, security}
  end

  # User story (ADR-0028 §2 misclassification guard, issue #590):
  # As a maintainer previewing a split booking,
  # I want the preview to render the stored closes around the effective date
  # and check the observed jump against the per-row basis classification,
  # so that a contradiction warns me BEFORE booking instead of silently
  # double-adjusting (the Portfolio Performance #4223 failure mode), and too
  # few quotes state "insufficient" instead of implying a clean check.
  describe "preview quote-basis guard" do
    test "a raw series with the expected jump verifies consistent and shows the closes" do
      {_world, security} = world_with_security()
      insert_quote!(security, ~D[2026-02-01], "100", "manual")
      insert_quote!(security, ~D[2026-02-02], "10", "manual")

      preview = preview!(security)

      assert preview.quote_basis_check.status == :consistent
      assert preview.quote_basis_check.expected_basis == :raw
      assert preview.quote_basis_check.observed == :jump
      assert preview.warnings == []

      assert [
               %{date: ~D[2026-02-01], source: "manual"} = before_row,
               %{date: ~D[2026-02-02], source: "manual"} = after_row
             ] = preview.quotes_around

      assert Decimal.equal?(before_row.close, Decimal.new("100"))
      assert Decimal.equal?(after_row.close, Decimal.new("10"))
    end

    test "a continuous provider mirror verifies consistent" do
      {_world, security} = world_with_security()
      insert_quote!(security, ~D[2026-02-01], "10", "coingecko")
      insert_quote!(security, ~D[2026-02-02], "10.2", "coingecko")

      preview = preview!(security)

      assert preview.quote_basis_check.status == :consistent
      assert preview.quote_basis_check.expected_basis == :provider_mirror
      assert preview.warnings == []
    end

    test "a continuous series classified raw warns about the contradiction" do
      {_world, security} = world_with_security()
      insert_quote!(security, ~D[2026-02-01], "10", "manual")
      insert_quote!(security, ~D[2026-02-02], "10.2", "manual")

      preview = preview!(security)

      assert preview.quote_basis_check.status == :contradiction
      assert :quote_basis_contradiction in preview.warnings
    end

    test "a jumping provider mirror warns — the escape hatch is the raw override" do
      {_world, security} = world_with_security()
      insert_quote!(security, ~D[2026-02-01], "100", "coingecko")
      insert_quote!(security, ~D[2026-02-02], "10", "coingecko")

      preview = preview!(security)

      assert preview.quote_basis_check.status == :contradiction
      assert :quote_basis_contradiction in preview.warnings

      # Setting the per-security override reclassifies the series as raw and
      # the same closes verify consistent.
      {:ok, _} =
        Catalog.update_security(Actor.owner_ui(), security, %{treat_quotes_as_raw: true})

      preview = preview!(security)
      assert preview.quote_basis_check.status == :consistent
      assert preview.quote_basis_check.expected_basis == :raw
      assert preview.warnings == []
    end

    test "too few quotes around the effective date report insufficient instead of a clean check" do
      {_world, security} = world_with_security()

      preview = preview!(security)

      assert preview.quote_basis_check.status == :insufficient_quotes
      assert :insufficient_quotes_to_verify_basis in preview.warnings
      assert preview.quotes_around == []
    end
  end
end
