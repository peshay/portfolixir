defmodule Portfolixir.Catalog.SecurityAssetClassInferenceTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Imports.PortfolioPerformance.JsonParser

  # User story:
  # As a local portfolio maintainer importing a real Portfolio Performance export,
  # I want unclassified securities to be automatically classified by heuristics,
  # so that the "Unsorted" bucket contains only truly ambiguous securities
  # (pure brand names without any legal-form or instrument-type token).
  #
  # Acceptance criteria covered here:
  # - Legal-form suffixes: Corporation / Company / Co. / Aktiengesellschaft /
  #   S.p.A. / A/S / ASA / KGaA / Azioni / Acciones / Aktier → equity
  # - ADR / GDR / Depositary Receipts → equity
  # - Abbreviated share-class designations: INH.ON → equity
  # - TurboP (and other single-letter Turbo variants) → knock_out
  # - Dogecoin/DOGE, Avalanche/AVAX, Tron/TRX → crypto
  # - Exact bare precious-metal names → commodity
  # - Known fund-issuer prefix without "ETF" token → fund
  # - Letter-spaced PP names are collapsed before heuristics are applied

  describe "equity heuristics — legal-form suffixes" do
    for {name, description} <- [
          {"NVIDIA Corporation", "Corporation"},
          {"McDonald's Corporation", "Corporation with apostrophe"},
          {"The Kraft Heinz Company", "Company"},
          {"Coca-Cola Co.", "Co. (with period)"},
          {"Software Aktiengesellschaft", "Aktiengesellschaft"},
          {"Prysmian S.p.A.", "S.p.A."},
          {"Leonardo S.p.A. Azioni", "S.p.A. with Azioni"},
          {"Orsted A/S", "A/S"},
          {"Telenor ASA", "ASA"},
          {"Merck KGaA", "KGaA"},
          {"Iberdrola S.A. Acciones", "Acciones"},
          {"Ørsted A/S Aktier", "Aktier"},
          {"Pirelli & C. S.p.A. Azioni", "Azioni"}
        ] do
      test "classifies #{description} as equity" do
        assert {:ok, security} =
                 Catalog.create_security(%{
                   name: unquote(name),
                   currency_code: "EUR"
                 })

        assert security.asset_class == "equity",
               "expected equity for #{unquote(name)}, got #{inspect(security.asset_class)}"
      end
    end
  end

  describe "equity heuristics — ADR / GDR / depositary receipts" do
    for {name, ticker, description} <- [
          {"Hyundai Motor Co GDRs", nil, "GDRs"},
          {"Kongsberg Gruppen Sp.ADR", nil, "Sp.ADR"},
          {"Procter & Gamble Canad.Depos.Receipts", nil, "Depos.Receipts compact"},
          {"SEVERSTAL GDR", nil, "GDR standalone"}
        ] do
      test "classifies #{description} as equity" do
        assert {:ok, security} =
                 Catalog.create_security(%{
                   name: unquote(name),
                   ticker_symbol: unquote(ticker),
                   currency_code: "USD"
                 })

        assert security.asset_class == "equity",
               "expected equity for #{unquote(name)}, got #{inspect(security.asset_class)}"
      end
    end
  end

  describe "equity heuristics — abbreviated share-class designations" do
    test "classifies INH.ON suffix as equity" do
      assert {:ok, security} =
               Catalog.create_security(%{
                 name: "IBU-TEC ADV.MATER. INH.ON",
                 currency_code: "EUR"
               })

      assert security.asset_class == "equity"
    end
  end

  describe "knock-out heuristics — TurboP and single-letter Turbo variants" do
    for name <- [
          "Société Générale TurboP 20.06.25 DAX 23450",
          "DZ BANK TurboC DAX 20000",
          "UniCredit TurboA 19.12.25 NASDAQ"
        ] do
      test "classifies '#{name}' as knock_out" do
        assert {:ok, security} =
                 Catalog.create_security(%{
                   name: unquote(name),
                   currency_code: "EUR"
                 })

        assert security.asset_class == "knock_out",
               "expected knock_out for #{unquote(name)}, got #{inspect(security.asset_class)}"
      end
    end
  end

  describe "crypto heuristics — new coins" do
    for {name, ticker, description} <- [
          {"Dogecoin", nil, "name only"},
          {"dogecoin", nil, "lowercase name"},
          {"Avalanche", nil, "Avalanche by name"},
          {"Tron", nil, "Tron by name"},
          {nil, "DOGE", "DOGE ticker"},
          {nil, "AVAX", "AVAX ticker"},
          {nil, "TRX", "TRX ticker"}
        ] do
      test "classifies Dogecoin/AVAX/TRX — #{description} — as crypto" do
        name = unquote(name) || "Synthetic crypto #{System.unique_integer([:positive])}"
        ticker = unquote(ticker)

        assert {:ok, security} =
                 Catalog.create_security(
                   Map.reject(
                     %{name: name, ticker_symbol: ticker, currency_code: "USD"},
                     fn {_k, v} -> is_nil(v) end
                   )
                 )

        assert security.asset_class == "crypto",
               "expected crypto, got #{inspect(security.asset_class)}"
      end
    end
  end

  describe "commodity heuristics — bare precious-metal names" do
    for name <- ["Gold", "Silber", "Silver", "Platin", "Platinum"] do
      test "classifies exact name '#{name}' as commodity" do
        assert {:ok, security} =
                 Catalog.create_security(%{
                   name: unquote(name),
                   currency_code: "EUR"
                 })

        assert security.asset_class == "commodity",
               "expected commodity for #{unquote(name)}, got #{inspect(security.asset_class)}"
      end
    end

    test "does not classify 'Barrick Gold Corp' as commodity" do
      assert {:ok, security} =
               Catalog.create_security(%{
                 name: "Barrick Gold Corp",
                 currency_code: "CAD"
               })

      assert security.asset_class == "equity"
    end
  end

  describe "fund heuristics — issuer prefix without ETF token" do
    for {name, description} <- [
          {"AIS-AM.MSCI EM A. EOC", "AIS-AM prefix"},
          {"Amundi Index MSCI World", "Amundi without ETF"},
          {"iShares MSCI World Fund", "iShares without ETF"},
          {"Xtrackers MSCI World", "Xtrackers without ETF"},
          {"Invesco MSCI Europe", "Invesco without ETF"},
          {"WisdomTree MSCI Europe", "WisdomTree without ETF"}
        ] do
      test "classifies '#{description}' as fund" do
        assert {:ok, security} =
                 Catalog.create_security(%{
                   name: unquote(name),
                   currency_code: "EUR"
                 })

        assert security.asset_class == "fund",
               "expected fund for #{unquote(name)}, got #{inspect(security.asset_class)}"
      end
    end

    test "still classifies an iShares UCITS ETF as etf (not downgraded to fund)" do
      assert {:ok, security} =
               Catalog.create_security(%{
                 name: "iShares Core MSCI World UCITS ETF",
                 currency_code: "USD"
               })

      assert security.asset_class == "etf"
    end
  end

  describe "letter-spaced name normalisation (PP import path)" do
    test "collapses a fully letter-spaced name before heuristics run" do
      body = %{
        "version" => 1,
        "transactions" => [
          %{
            "type" => "PURCHASE",
            "date" => "2024-01-15",
            "currency" => "EUR",
            "amount" => 500.0,
            "shares" => 100.0,
            "security" => %{
              "name" => "I b e r d r o l a S . A . A c c i o n e s",
              "isin" => "ES0144580Y14",
              "currency" => "EUR"
            }
          }
        ]
      }

      {:ok, preview} = JsonParser.parse(Jason.encode!(body))

      [entry] = preview.entries
      assert entry.security.name == "IberdrolaS.A.Acciones"
    end

    test "handles missing security name (nil) without error" do
      body = %{
        "version" => 1,
        "transactions" => [
          %{
            "type" => "PURCHASE",
            "date" => "2024-01-15",
            "currency" => "EUR",
            "amount" => 500.0,
            "shares" => 10.0,
            "security" => %{
              "isin" => "ES0144580Y14",
              "currency" => "EUR"
            }
          }
        ]
      }

      {:ok, preview} = JsonParser.parse(Jason.encode!(body))

      [entry] = preview.entries
      assert is_nil(entry.security.name)
    end

    test "does not collapse short or normal names" do
      body = %{
        "version" => 1,
        "transactions" => [
          %{
            "type" => "PURCHASE",
            "date" => "2024-01-15",
            "currency" => "USD",
            "amount" => 200.0,
            "shares" => 1.0,
            "security" => %{
              "name" => "Apple Inc.",
              "isin" => "US0378331005",
              "currency" => "USD"
            }
          }
        ]
      }

      {:ok, preview} = JsonParser.parse(Jason.encode!(body))
      [entry] = preview.entries
      assert entry.security.name == "Apple Inc."
    end
  end

  describe "effective_asset_class — read-time inference on stored nil" do
    test "infers correct class at read time even if stored class is nil" do
      security = %Security{
        name: "NVIDIA Corporation",
        isin: "US67066G1040",
        ticker_symbol: "NVDA",
        asset_class: nil
      }

      assert Security.effective_asset_class(security) == "equity"
    end

    test "returns nil for pure brand name with no legal suffix" do
      security = %Security{
        name: "Amazon",
        isin: nil,
        ticker_symbol: nil,
        asset_class: nil
      }

      assert is_nil(Security.effective_asset_class(security))
    end
  end
end
