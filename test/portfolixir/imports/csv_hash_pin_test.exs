defmodule Portfolixir.Imports.CsvHashPinTest do
  # ADR-0053 K2 (risk-tier: import idempotency, ADR-0036). The digests below
  # were computed on the code before ADR-0053 changed what a Portfolio
  # Performance CSV row books (baseline b14d3d65), and every later commit is
  # held to them. A stored content hash is the re-import contract's first
  # check (ADR-0050 §3): if one of these moved, a re-drop of a file imported
  # before the change would book its rows a second time.
  use ExUnit.Case, async: true

  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.ImportHash
  alias Portfolixir.Imports.PortfolioPerformance

  @fixtures Path.expand("../../support/fixtures/portfolio_performance", __DIR__)

  # The portfolio id the digests were taken for; no real portfolio is needed.
  @portfolio_id 42

  # hash_pin.csv is frozen: a Portfolio Performance-faithful export (Kurs and
  # Betrag the gross values, Gesamtpreis the cash, Gesamtpreis = Betrag ∓
  # (Gebühren + Steuern) to the cent) carrying every kind, fees and taxes on
  # the trades and the income rows, one negative Steuern split off as a
  # refund (row 5), both sides of a cash and of a depot transfer (rows 10,
  # 11, 14 and 15, four different transfers, so none pairs), and one
  # converter-written row with an empty Gesamtpreis (row 17).
  @hash_pin_csv [
    {1, "29196d3632ecc95ce726b6a190c3f267e2158d44e8e14d0c8b01b2ea15346048"},
    {2, "c617ce890b5f8558e188042a832929939eb17b81bd946bfb581366fa4857ed3b"},
    {3, "c379707c24666abd3c522d026bbf0cfadc3fa6babcff464f332d5f15e90a76a0"},
    {4, "dffd9c1b5d647bb77dfa3c3bc280f5f0b7d71c7f9aa05412ba630405327b2721"},
    {5, "64fc1fc3701ed7b9a0fc7f8c44a8016acb5962b5bcdb680be6def33e4272c259"},
    {"5.tax_refund.1", "b5709e471cdaf67ce537757132a0d7c7d32453dbffae72d204178fd7fc88dfca"},
    {6, "2099337cf552d1c284850b4a5a71f9369e58a024c4ce6ab8527524f0785449af"},
    {7, "233ba136caa384051c60b427adfec9f05690dea4e5a83f259d5a87adf2c144b0"},
    {8, "dfdfb2d4ac2d6e9b176da6954259ce25e0e8a02a4c431ab89242a5d37e669f95"},
    {9, "b42c3b59ff3983089ecd1cffcf6fc20c59bd9107f9229c68091ebffefe23441d"},
    {10, "eae58270522768f84d7bb91cb50feca4a444228e7cd408424e80496dab6ac27b"},
    {11, "df100a768db301e0a9e68c5f0d3a1b1394aae9fa5b66b52dad04628e902df97b"},
    {12, "513586c834f399a6cb96b9a82f52c06fb025b1a50f022f56a89b6f34453d367c"},
    {13, "c176547ab345ef84c9980e52502d733b33c360a5ff204aeae30366af6f549a27"},
    {14, "ce8b0d1fc60434b904932c6a91090f79233e127e6f46252b41891b0bbf84ab7b"},
    {15, "bf3963b61001ba75247cdb13ad68d8e29b2ceb223bfcafe54476500f8c4ea249"},
    {16, "190836c60f621f33401af15083c4a889df387890c58df8e997acfd913b8be83f"},
    {17, "fc5b6246d031d9e5b434a8f88f8c22e370771b5902c364c5ed9410c9c8022452"}
  ]

  @sample_json [
    {1, "dfa6f27720b024c67b016c1c09b6b1f37c15caf750a82a3f80f2a8d33071db24"},
    {2, "07571b4a4cb5b1764644d489163b591425da214c6e195b52e812bb025248056e"},
    {3, "9381207bce57fecf0fd1205b9e6ea15526e5eca3d3442234aa80bb64b514d582"},
    {4, "492d43b14f6be466a11c71c73d9ff371a49c42b42460fb2d2203d67ad8423a70"},
    {5, "bd9373fc19a1849f134be6b286397b662c805574526997be90ce13d04b4f08af"},
    {6, "0804a11508a2a3117f69b533286794623c220167bf30e930d1f306f610d3f806"},
    {7, "7230b3ee097213851585259c3e84b06227ef2ce4354e7b9d13de55ebfe11ac95"},
    {8, "e11d18952eae3319b5347b2db8824f920aa4480b005a559fda0c85b1020cc3f6"},
    {9, "5699d5851d6c07079cd197896cfe86087f5f299e2e40d9bf4f4c7a2d3a4934da"},
    {10, "515dd4d46f11ae42cc17b8c708bb742879df00ff14543afdd3f935bacddae94c"},
    {11, "e23ca67d40e01a87079a6cd8c244b5af2a40d26d385e377548fa762536db8ae7"},
    {12, "ff1576fd2c84cf0449cea0d7cc8866d63861fbc9e69a6f33f27789a4c4b59320"},
    {13, "b7cc9e9d45b78399225d187bc3edf32ab5320e0bfb6d4fd8e42f265c26c14d33"}
  ]

  @sample_with_negative_tax_json [
    {1, "d157a1c3916b844d4b03516a99cd4071cf3ba523a7e83de6ca2f23006eba3ae0"},
    {"1.tax_refund.1", "e7ae49ca22957bbf7d071eabc6ef322e9eee5ef2a4b480c29d481bdad30ddb31"}
  ]

  # ADR-0053 K10 (the amendment of 2026-10-07; risk-tier: import
  # idempotency). Taken on 12117072, before the amendment changes what a
  # JSON row with a negative tax unit books and how its price is derived:
  # sale_with_negative_tax.json's sale (amount 120.0, 10 shares, FEE 5.0,
  # TAX -25.0) hashed its `amount` and the price derived then, 12.5. Every
  # later commit is held to these digests, the split-off refund's included.
  @sale_with_negative_tax_json [
    {1, "119dc41cd9a8a7ef8751de58efe225d1d886cd71614da39015e3b9e52d212986"},
    {2, "2a1c9e4f47d23520781659b3c5e99c4fa7b7a3821ce3eaa743c94bdfcad6f405"},
    {3, "3da6386e6fe2d4a2df78a941b444448bb502bba83fee8c72ad54fda0293f4a46"},
    {"3.tax_refund.1", "92d2155b3fb988a734e76f6a09228608daf44a193c1208e8b593dff83a3776ee"}
  ]

  # Each row's content hash, computed as the applier computes it: a row of
  # the file by `ImportHash.compute/2`, a split-off refund by
  # `ImportHash.companion/4` with the hash of the row before it.
  defp digests(name), do: digests_of(File.read!(Path.join(@fixtures, name)), name)

  defp digests_of(body, name) do
    {:ok, preview} = PortfolioPerformance.parse(body, filename: name)

    assert preview.errors == [], "#{name}: #{inspect(preview.errors)}"

    {digests, _parent_hash} =
      preview.entries
      |> Entry.flatten()
      |> Enum.map_reduce(nil, fn
        %Entry{companion_index: nil} = entry, _parent_hash ->
          hash = ImportHash.compute(entry, @portfolio_id)
          {{entry.source_row, hash}, hash}

        %Entry{companion_index: index} = entry, parent_hash ->
          hash = ImportHash.companion(parent_hash, index, entry, @portfolio_id)
          {{entry.source_row, hash}, parent_hash}
      end)

    digests
  end

  # User story (ADR-0053 K2):
  # As the operator of an instance that already imported a Portfolio
  # Performance export,
  # I want every content hash the importer computes for a row of that export
  # to stay byte-identical when the importer changes what the row books,
  # so that dropping the same file again books nothing twice.
  #
  # Acceptance criteria:
  # - Every row of the frozen PP-faithful CSV, its split-off refund included,
  #   hashes to the digest pinned before ADR-0053's change.
  # - Every row of the JSON corpus hashes to its pinned digest, the split-off
  #   refunds of a negative tax included.
  # - Every file parses without a row error, so no row drops out of the list.
  test "a PP-faithful CSV keeps every content hash pinned before ADR-0053" do
    assert digests("hash_pin.csv") == @hash_pin_csv
  end

  # Before ADR-0053 the parser never read the Gesamtpreis, so a row hashes
  # the same with or without one: the hash reads the Betrag, never the cash
  # a row books.
  test "blanking every row's Gesamtpreis leaves every digest unchanged" do
    blanked =
      @fixtures
      |> Path.join("hash_pin.csv")
      |> File.read!()
      |> String.split("\n")
      |> Enum.map_join("\n", fn line ->
        case String.split(line, ";") do
          [_, _, _, _, _, _, _, _, "Gesamtpreis" | _] -> line
          cells when length(cells) == 13 -> cells |> List.replace_at(8, "") |> Enum.join(";")
          _ -> line
        end
      end)

    refute blanked == File.read!(Path.join(@fixtures, "hash_pin.csv"))
    assert digests_of(blanked, "blanked.csv") == @hash_pin_csv
  end

  test "the JSON corpus keeps every content hash pinned before ADR-0053" do
    assert digests("sample.json") == @sample_json
    assert digests("sample_with_negative_tax.json") == @sample_with_negative_tax_json
  end

  # User story (ADR-0053 K10, the amendment of 2026-10-07):
  # As the operator of an instance that imported a Portfolio Performance JSON
  # export whose rows carry a negative tax unit,
  # I want every content hash of those rows to stay byte-identical when the
  # importer changes the cash and the price such a row books,
  # so that dropping the same export again books nothing twice.
  #
  # Acceptance criteria:
  # - Every row of sale_with_negative_tax.json, a sale with a FEE and a
  #   negative TAX unit among them, hashes to the digest pinned before the
  #   amendment's change; so does the refund split off the sale.
  test "a JSON sale with a negative tax unit keeps every content hash pinned before the amendment" do
    assert digests("sale_with_negative_tax.json") == @sale_with_negative_tax_json
  end
end
