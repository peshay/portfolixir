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
  # refund (row 6), both sides of a cash and of a depot transfer (rows 11,
  # 12, 15 and 16, four different transfers, so none pairs), and one
  # converter-written row with an empty Gesamtpreis (row 18). Each digest is
  # keyed by its row as a spreadsheet shows the file, the header being row 1
  # (#1128); the row numbers moved by one with that change and the digests
  # did not, because no hash reads the number.
  @hash_pin_csv [
    {2, "29196d3632ecc95ce726b6a190c3f267e2158d44e8e14d0c8b01b2ea15346048"},
    {3, "c617ce890b5f8558e188042a832929939eb17b81bd946bfb581366fa4857ed3b"},
    {4, "c379707c24666abd3c522d026bbf0cfadc3fa6babcff464f332d5f15e90a76a0"},
    {5, "dffd9c1b5d647bb77dfa3c3bc280f5f0b7d71c7f9aa05412ba630405327b2721"},
    {6, "64fc1fc3701ed7b9a0fc7f8c44a8016acb5962b5bcdb680be6def33e4272c259"},
    {"6.tax_refund.1", "b5709e471cdaf67ce537757132a0d7c7d32453dbffae72d204178fd7fc88dfca"},
    {7, "2099337cf552d1c284850b4a5a71f9369e58a024c4ce6ab8527524f0785449af"},
    {8, "233ba136caa384051c60b427adfec9f05690dea4e5a83f259d5a87adf2c144b0"},
    {9, "dfdfb2d4ac2d6e9b176da6954259ce25e0e8a02a4c431ab89242a5d37e669f95"},
    {10, "b42c3b59ff3983089ecd1cffcf6fc20c59bd9107f9229c68091ebffefe23441d"},
    {11, "eae58270522768f84d7bb91cb50feca4a444228e7cd408424e80496dab6ac27b"},
    {12, "df100a768db301e0a9e68c5f0d3a1b1394aae9fa5b66b52dad04628e902df97b"},
    {13, "513586c834f399a6cb96b9a82f52c06fb025b1a50f022f56a89b6f34453d367c"},
    {14, "c176547ab345ef84c9980e52502d733b33c360a5ff204aeae30366af6f549a27"},
    {15, "ce8b0d1fc60434b904932c6a91090f79233e127e6f46252b41891b0bbf84ab7b"},
    {16, "bf3963b61001ba75247cdb13ad68d8e29b2ceb223bfcafe54476500f8c4ea249"},
    {17, "190836c60f621f33401af15083c4a889df387890c58df8e997acfd913b8be83f"},
    {18, "fc5b6246d031d9e5b434a8f88f8c22e370771b5902c364c5ed9410c9c8022452"}
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

  # ADR-0051 I11 (the amendment of 2026-10-09; risk-tier: import
  # idempotency). Taken on b9413da, before the importer keeps the security an
  # INTEREST row names: bond_invented.json's coupon names its bond, and
  # bond_coupon.json (I12's file) holds an account interest naming none and a
  # coupon naming its bond. The hash reads the file's security, never the
  # resolved id, so keeping the id moves none of these.
  @bond_invented_json [
    {1, "bd63431010381e27aca4208e1fdfb580c28cf31bdffe61917066a046c426293d"},
    {2, "8dc2d38d49feb02be9d95c15fac6905547cc53f3b51e7027354c9cde4501b20e"},
    {3, "31448c5617eb01b93e0bdfc071262dc3fa33413b7b5e109ec01ef780749671cc"}
  ]

  @bond_coupon_json [
    {1, "f22016e54cb13465464e33478a813a53738e50118f60a1daf0990eedbc2d4107"},
    {2, "11ad6bb00b99a942fc034002f832b9f9052e38062a163c4e5f607fdf94bdd9b5"},
    {3, "2309f00604e660d0856232b719f8f97e54556d5195e9b8590a9b95beb41d1ca6"},
    {4, "46e5531ceec4cc62ac794ed5e6d8b29ce42f6d188dac154c2a9cf1907cf70e39"}
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

  # User story (#928, Sprint 21 α4; ADR-0051 I11):
  # As the operator of an instance that imported a bond's coupons before the
  # importer kept their security,
  # I want every content hash of those rows to stay byte-identical when the
  # importer starts storing the security an INTEREST row names,
  # so that dropping the same export again books no coupon twice.
  #
  # Acceptance criteria:
  # - Every row of bond_invented.json, its coupon naming the bond included,
  #   hashes to the digest pinned before the change.
  # - Every row of bond_coupon.json, the account interest naming no security
  #   and the coupon naming its bond, hashes to its pinned digest.
  test "a bond's coupon rows keep every content hash pinned before the importer kept their security" do
    assert digests("bond_invented.json") == @bond_invented_json
    assert digests("bond_coupon.json") == @bond_coupon_json
  end

  # ADR-0053 K25 (the amendment of 2026-10-09; risk-tier: import
  # idempotency, ADR-0036). Taken on b9413da, before A8 and A9 make a row
  # error of a negative tax unit on a delivery, a security transfer or a cash
  # transfer, and of a negative FEE unit (#1188, #1177). The files are the
  # identities K16 to K24 (K20 is K17's file, K22 K21's sale): every row of
  # each and every refund split off them. A row the code refuses keeps the
  # digest of the would-be entry the preview keeps beside its row error
  # (`refused_credits`): K19's sale under A5 today, and after A8 and A9 the
  # rows they refuse, whose would-be entries are built as before, so the
  # delivery's split-off refund and the purchase's fees of 7.00 (FEE 5.00 and
  # FEE -2.00 by magnitude) are what they hash.
  @k25_digests %{
    "k16_delivery_negative_tax.json" => [
      {1, "dc10fac8468d021d677aebdd07a6856b2cf626122aa38cbd14a4534934c0d023"},
      {2, "fd3e4beddc8c3432d06db4ff6eea0907bb3207effdb65235fce6130de93410a3"},
      {"2.tax_refund.1", "6289b2e13201085ba718e31dba633fe154d5fceee85ff77c0c432a633b73838a"},
      {3, "cf5f80ccbfd8d0b21712a0b1602d0bd07af9850268db9391627e4682e10b345d"}
    ],
    "k16_delivery_negative_tax.csv" => [
      {2, "dc10fac8468d021d677aebdd07a6856b2cf626122aa38cbd14a4534934c0d023"},
      {3, "e89af8a279bac82a13543d2e2736160ec3c83c48b1984c3607aeeb08761b52f1"},
      {"3.tax_refund.1", "175fbd79cba16d7be13a76a9f7db7192beeca9aa3e6074edb3960af5012a3157"},
      {4, "25ae0c6e804d02f1b2170a10334a7f8c41d00d929dc90bd841d64ea1aacb23d7"}
    ],
    "k17_transfer_negative_tax.json" => [
      {1, "dc10fac8468d021d677aebdd07a6856b2cf626122aa38cbd14a4534934c0d023"},
      {2, "25d48be6ce16873f9335e37e6b2f097d1573d9759b0903dd1de606db2dd8e551"},
      {"2.tax_refund.1", "7a867b922c5fab8dd4b913d659d16ff1be97f85709e753c7a5647fad41a0f552"}
    ],
    "k17_transfer_negative_tax.csv" => [
      {2, "dc10fac8468d021d677aebdd07a6856b2cf626122aa38cbd14a4534934c0d023"},
      {3, "362f35227a09727b61719b428716bed5b7e3847b43550af176277ee45f8e3429"},
      {"3.tax_refund.1", "a3349d74dd8eda7be65ddb21c5815176fda0c7f43b17692d2be8e87fd57ca6d8"}
    ],
    "k18_negative_fee.json" => [
      {1, "8d697a56052e2c685d1c899bf009876ee198a9a0880330d742d26d87bd7f598b"},
      {2, "d8feec373cc9b1ebf521b9353cff831ea49fc1447eb2e6b429b17f25bf1a7c5d"}
    ],
    "k18_converter_negative_fee.csv" => [
      {2, "8d697a56052e2c685d1c899bf009876ee198a9a0880330d742d26d87bd7f598b"},
      {3, "3c59afd0266e9ee7251271f67ec48f2c5012f1b03b4587eefc00ca582bf0dab0"}
    ],
    "k19_refused_sale.json" => [
      {1, "fcd9fc38d26e07686e0fbf62c27c5a8e56896668c5a94af944cfa4eaf3f401d7"},
      {2, "16a19ca0d9b91d3614dee6471ae939679f63dfac4c16ec15742f45fba8cad50a"},
      {3, "abbe6913d056b551ce226f3fbebe25c3339dfe296e0451d4801ec7ee03303a9d"},
      {"3.tax_refund.1", "9b8ca7664a520fa83bc4fa9705983d1fbb03a0720563bbb987db2dd17b2bad5f"}
    ],
    "k21_hand_edit.json" => [
      {1, "891d18370ff0a044c8883413130621a6aacc6dd53968a1954039b8f9adbd0c0a"},
      {2, "a6b25f04e7133dfb8a506898a46656b3a92236b23d4fccef1a98972dcc33c276"},
      {3, "1e4f4f444d464e9394d345a1ee3bb3c1d836f137651b6362cdba82e5315cae9f"},
      {4, "31511e97bef4d55f05c1768aa75a2d1facf9a3856b7484bc0dc97f6dd234af2f"},
      {"4.tax_refund.1", "313b3998236c9f28829ebaa6853a520376b9e20a7f59b437caabf23264e79c4b"}
    ],
    "k23_drifted.json" => [
      {1, "891d18370ff0a044c8883413130621a6aacc6dd53968a1954039b8f9adbd0c0a"},
      {2, "a6b25f04e7133dfb8a506898a46656b3a92236b23d4fccef1a98972dcc33c276"},
      {3, "31511e97bef4d55f05c1768aa75a2d1facf9a3856b7484bc0dc97f6dd234af2f"},
      {"3.tax_refund.1", "313b3998236c9f28829ebaa6853a520376b9e20a7f59b437caabf23264e79c4b"}
    ],
    "k23_drifted_reexport.json" => [
      {1, "891d18370ff0a044c8883413130621a6aacc6dd53968a1954039b8f9adbd0c0a"},
      {2, "a6b25f04e7133dfb8a506898a46656b3a92236b23d4fccef1a98972dcc33c276"},
      {3, "a80a537e0b5215eb8470b731ceb26d038f3ab7d872f4345d51dba58c6860155c"},
      {"3.tax_refund.1", "a8d19980d0ed952544e2c304c6e431f1395179c7ab8b2dd8320da23b067a40d8"}
    ],
    "k24_twins.json" => [
      {1, "891d18370ff0a044c8883413130621a6aacc6dd53968a1954039b8f9adbd0c0a"},
      {2, "3d7ff9278a5af5168760f13f62f906a23751a860e4507271fb78a212cadc7589"},
      {3, "31511e97bef4d55f05c1768aa75a2d1facf9a3856b7484bc0dc97f6dd234af2f"},
      {"3.tax_refund.1", "313b3998236c9f28829ebaa6853a520376b9e20a7f59b437caabf23264e79c4b"},
      {4, "5b32a9c88456c77f5860a6118bb4c958330be610fc1cd0e3d9085d1d82409391"},
      {"4.tax_refund.1", "5d5989ce494c4d1d7d014b292fb28728baaa7e9d594059bd2fc0e13e44dcd202"}
    ],
    "k24_twins_both_moved.json" => [
      {1, "891d18370ff0a044c8883413130621a6aacc6dd53968a1954039b8f9adbd0c0a"},
      {2, "3d7ff9278a5af5168760f13f62f906a23751a860e4507271fb78a212cadc7589"},
      {3, "a80a537e0b5215eb8470b731ceb26d038f3ab7d872f4345d51dba58c6860155c"},
      {"3.tax_refund.1", "a8d19980d0ed952544e2c304c6e431f1395179c7ab8b2dd8320da23b067a40d8"},
      {4, "ff33bec530af2e886835637c8f3841cce7b5ae6e99cf6099d25cf1081f15d27f"},
      {"4.tax_refund.1", "5f433fc99cb77f9ab741612d7b719a9aab9fc5f81cf5ef771fca171f69a44be8"}
    ],
    "k24_twins_b_moved.json" => [
      {1, "891d18370ff0a044c8883413130621a6aacc6dd53968a1954039b8f9adbd0c0a"},
      {2, "3d7ff9278a5af5168760f13f62f906a23751a860e4507271fb78a212cadc7589"},
      {3, "31511e97bef4d55f05c1768aa75a2d1facf9a3856b7484bc0dc97f6dd234af2f"},
      {"3.tax_refund.1", "313b3998236c9f28829ebaa6853a520376b9e20a7f59b437caabf23264e79c4b"},
      {4, "ff33bec530af2e886835637c8f3841cce7b5ae6e99cf6099d25cf1081f15d27f"},
      {"4.tax_refund.1", "5f433fc99cb77f9ab741612d7b719a9aab9fc5f81cf5ef771fca171f69a44be8"}
    ]
  }

  # Sprint 23 R1 (#1370; risk tier: import idempotency, ADR-0036). Taken on
  # 7b822f7, before the CSV parser refuses a time it cannot read: each row's
  # time of day and content hash, in the file's order, for the two CSV
  # fixtures no digest above pins. Every time the fixtures write
  # (00:00:00, 10:00:00, 10:01:00, 10:15:00, 12:25:00, 21:00:00) is read
  # here or in hash_pin.csv and the K16 to K18 files above.
  @sample_csv [
    {2, ~T[10:01:00], "1573a01a79de5cbe3550de4e343f741cda65811b55209ab665208f46bee70c37"},
    {3, ~T[12:25:00], "3b5fd6a34adaeac64dfbf96038ed545f4c0e3ede86862ce62a21be3fd78c5f5e"},
    {4, nil, "73903a514229a9da75b9175aabd13ae063e4bf57140093298756f565cf78be50"},
    {5, nil, "d4b2d714e0abbf940023f0d61b68daeacfe0db13c90f49b82c84b84dbf65df11"},
    {6, nil, "bd9373fc19a1849f134be6b286397b662c805574526997be90ce13d04b4f08af"},
    {7, nil, "0804a11508a2a3117f69b533286794623c220167bf30e930d1f306f610d3f806"},
    {8, nil, "7230b3ee097213851585259c3e84b06227ef2ce4354e7b9d13de55ebfe11ac95"},
    {9, nil, "e11d18952eae3319b5347b2db8824f920aa4480b005a559fda0c85b1020cc3f6"},
    {10, nil, "5699d5851d6c07079cd197896cfe86087f5f299e2e40d9bf4f4c7a2d3a4934da"},
    {11, ~T[10:00:00], "515dd4d46f11ae42cc17b8c708bb742879df00ff14543afdd3f935bacddae94c"},
    {12, nil, "d6d06b53de7072c0a2fd8de8e14d9756b38492940f0c04ae79874b645b6095cf"},
    {13, nil, "8b677882f243e3076dc66727f08e1d2c0d72e065f146d21e7e16d30a5795fa48"},
    {14, ~T[21:00:00], "fb5093423df532e5d104d70b80dc8f167aa9b982f90a2285d1889099f74578cc"}
  ]

  # Row 6 is the receiving side of row 5's transfer, booked once from row 5.
  @transfers_csv [
    {2, nil, "9cc122a685eda8696518cfec1cf4cbb4da0ad33d624ab69348cda74f846f0c0d"},
    {3, ~T[10:00:00], "7c79fb48c08f7015511f0031f5cc05a3c70efb6afcb6652e4615a1c632437294"},
    {4, ~T[10:00:00], "033ab1ad155494ad13e7295f388a6ed2b138a4f8267fd27e78198f9d0f0b854d"},
    {5, ~T[10:00:00], "48ef21fcd25187c892af421cae76e077ce3983afdceabb44a9b3e0dda437c41d"},
    {7, nil, "b8c6d3ca5f183a827bc761acbabfed9c8c1e2500c474403001a8f68d14ad34fd"},
    {8, ~T[21:00:00], "1f3c4d9e9a68668198e25349db5561a601db146723ff1db1faeedaadfb5995c9"}
  ]

  # Every shape of a `Datum` cell the parser reads on 7b822f7, with the time
  # it reads and the hash of a removal of 25,00 on Test-Cash dated with it:
  # the date alone, a blank time and midnight are no time (midnight as
  # HH:MM too: read as no time since the sprint PR's closing act, the hash
  # the date alone gives); a time with
  # seconds is read, its fraction kept, a `T` before it, a zone after it and
  # a second space before it read as without.
  @no_time "ea4cc1348bd07c133b10f52fd798219a507c14a7e215801f8b30508f33e7de53"
  @at_0915 "36f19fba0bdf75cc816dfea5334eb1eafb16a8ad0fb9eb7abe3db077c46ae42f"

  @datum_shapes [
    {"2025-03-03", nil, @no_time},
    {"2025-03-03 ", nil, @no_time},
    {"2025-03-03    ", nil, @no_time},
    {"2025-03-03 00:00:00", nil, @no_time},
    {"2025-03-03 00:00", nil, @no_time},
    {"2025-03-03 09:15:00", ~T[09:15:00], @at_0915},
    {"2025-03-03  09:15:00", ~T[09:15:00], @at_0915},
    {"2025-03-03 T09:15:00", ~T[09:15:00], @at_0915},
    {"2025-03-03 09:15:00Z", ~T[09:15:00], @at_0915},
    {"2025-03-03 09:15:00+01:00", ~T[09:15:00], @at_0915},
    {"2025-03-03 09:15:00.250", ~T[09:15:00.250],
     "af7fe2b340ba56f705372faf7b4529c97b161c31c92dce168af9c66e65caa762"}
  ]

  @csv_header "Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle\n"

  # Each entry's row, time of day and content hash, in the file's order.
  defp timed_digests(body, name) do
    {:ok, preview} = PortfolioPerformance.parse(body, filename: name)

    digests =
      Enum.map(preview.entries, fn entry ->
        {entry.source_row, entry.time, ImportHash.compute(entry, @portfolio_id)}
      end)

    {digests, preview.errors}
  end

  # User story (#1370, Sprint 23 R1):
  # As the operator of an instance that already imported a Portfolio
  # Performance CSV export,
  # I want every time of day the parser reads today read the same, and every
  # content hash of the file's rows byte-identical, when the parser starts to
  # refuse a time it cannot read,
  # so that dropping the same export again books nothing twice.
  #
  # Acceptance criteria:
  # - sample.csv and transfers.csv read every row's time and hash it to the
  #   digest taken on 7b822f7; transfers.csv keeps its one warning, the
  #   receiving side of row 5's transfer, and sample.csv has none.
  # - Every shape of `Datum` read on 7b822f7 reads the same time, or none,
  #   and the same hash, without a row error.
  test "every CSV time read before the time check reads the same and keeps its digest" do
    assert timed_digests(fixture("sample.csv"), "sample.csv") == {@sample_csv, []}

    assert timed_digests(fixture("transfers.csv"), "transfers.csv") ==
             {@transfers_csv,
              [
                %{
                  row: 6,
                  message: "receiving side of the transfer in row 5 — booked once, from that row"
                }
              ]}

    for {datum, time, hash} <- @datum_shapes do
      body = @csv_header <> datum <> ";Entnahme;;;;25,00;;;25,00;Test-Cash;;;\n"
      assert timed_digests(body, "shapes.csv") == {[{2, time, hash}], []}, inspect(datum)
    end
  end

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  # Each row's content hash as `digests_of/2` takes it, the would-be entries
  # of the rows the preview refuses included, in the file's row order. Every
  # row of the file is in the list, entry or would-be entry, so none drops
  # out of it unseen.
  defp all_digests(name) do
    body = File.read!(Path.join(@fixtures, name))
    {:ok, preview} = PortfolioPerformance.parse(body, filename: name)
    refused = Enum.map(preview.refused_credits, & &1.entry)
    rows = (preview.entries ++ refused) |> Enum.map(& &1.source_row) |> Enum.sort()
    first = if String.ends_with?(name, ".csv"), do: 2, else: 1
    count = row_count(body, first)

    assert rows == Enum.to_list(first..(first + count - 1)), "#{name}: #{inspect(preview.errors)}"

    {digests, _parent_hash} =
      (preview.entries ++ refused)
      |> Enum.sort_by(& &1.source_row)
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

  # A CSV file's booking rows follow its header (row 1); a JSON file's are
  # its transactions, numbered from 1.
  defp row_count(body, 2), do: body |> String.split("\n", trim: true) |> length() |> Kernel.-(1)
  defp row_count(body, 1), do: body |> Jason.decode!() |> Map.fetch!("transactions") |> length()

  # User story (ADR-0053 K25, the amendment of 2026-10-09; #1188, #1177):
  # As the operator of an instance that already imported a Portfolio
  # Performance export with a delivery or a transfer carrying a tax refund,
  # a negative fee unit, or a sale stored under the old reading,
  # I want every content hash of those rows to stay byte-identical when the
  # importer starts to refuse such a row,
  # so that dropping the same export again books nothing twice and the
  # correction can still find the booking it stored.
  #
  # Acceptance criteria:
  # - Every row of the K16 to K24 files, JSON and CSV, hashes to the digest
  #   taken on unchanged code, and so does every refund split off them.
  # - A row the preview refuses (A5, A8, A9) hashes as its would-be entry,
  #   which the preview keeps: K16's delivery and its refund, K17's
  #   transfer and its refund, K18's purchase over fees 7.00, K19's sale.
  # - No row of a file drops out of the list.
  test "every row of the K16 to K24 files keeps the digest taken before A8 and A9" do
    for {name, pinned} <- @k25_digests do
      assert all_digests(name) == pinned, name
    end
  end
end
