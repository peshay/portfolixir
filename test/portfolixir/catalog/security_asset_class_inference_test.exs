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
          {"NOVARIX Corporation", "Corporation"},
          {"Kittredge's Corporation", "Corporation with apostrophe"},
          {"The Brandt Holloway Company", "Company"},
          {"Kora-Vela Co.", "Co. (with period)"},
          {"Datenwerk Aktiengesellschaft", "Aktiengesellschaft"},
          {"Ravelli S.p.A.", "S.p.A."},
          {"Caravella S.p.A. Azioni", "S.p.A. with Azioni"},
          {"Skovlund A/S", "A/S"},
          {"Fjordnett ASA", "ASA"},
          {"Hessler KGaA", "KGaA"},
          {"Ventisca S.A. Acciones", "Acciones"},
          {"Ølstrup A/S Aktier", "Aktier"},
          {"Bertelli & C. S.p.A. Azioni", "Azioni"}
        ] do
      test "classifies #{description} as equity" do
        assert {:ok, security} =
                 Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
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
          {"Daeyang Motor Co GDRs", nil, "GDRs"},
          {"Fjellberg Gruppen Sp.ADR", nil, "Sp.ADR"},
          {"Thatcher & Bramble Canad.Depos.Receipts", nil, "Depos.Receipts compact"},
          {"KAMSTAL GDR", nil, "GDR standalone"}
        ] do
      test "classifies #{description} as equity" do
        assert {:ok, security} =
                 Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
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
               Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
                 name: "KERA-TEC ADV.MATER. INH.ON",
                 currency_code: "EUR"
               })

      assert security.asset_class == "equity"
    end
  end

  describe "knock-out heuristics — TurboP and single-letter Turbo variants" do
    for name <- [
          "Société Générale TurboP 20.06.25 Examplia 40 23450",
          "DZ BANK TurboC Examplia 40 20000",
          "UniCredit TurboA 19.12.25 Examplia Tech 100"
        ] do
      test "classifies '#{name}' as knock_out" do
        assert {:ok, security} =
                 Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
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
                   Portfolixir.Actor.owner_ui(),
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
                 Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
                   name: unquote(name),
                   currency_code: "EUR"
                 })

        assert security.asset_class == "commodity",
               "expected commodity for #{unquote(name)}, got #{inspect(security.asset_class)}"
      end
    end

    test "does not classify 'Talmont Gold Corp' as commodity" do
      assert {:ok, security} =
               Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
                 name: "Talmont Gold Corp",
                 currency_code: "CAD"
               })

      assert security.asset_class == "equity"
    end
  end

  describe "fund heuristics — issuer prefix without ETF token" do
    for {name, description} <- [
          {"AIS-AM.EXMPL EM A. EOC", "AIS-AM prefix"},
          {"Amundi Index Examplia World", "Amundi without ETF"},
          {"iShares Examplia World Fund", "iShares without ETF"},
          {"Xtrackers Examplia World", "Xtrackers without ETF"},
          {"Invesco Examplia Europe", "Invesco without ETF"},
          {"WisdomTree Examplia Europe", "WisdomTree without ETF"}
        ] do
      test "classifies '#{description}' as fund" do
        assert {:ok, security} =
                 Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
                   name: unquote(name),
                   currency_code: "EUR"
                 })

        assert security.asset_class == "fund",
               "expected fund for #{unquote(name)}, got #{inspect(security.asset_class)}"
      end
    end

    test "still classifies an iShares UCITS ETF as etf (not downgraded to fund)" do
      assert {:ok, security} =
               Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
                 name: "iShares Core Examplia World UCITS ETF",
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
              "name" => "V e n t i s c a S . A . A c c i o n e s",
              "isin" => "ESEXMPL30065",
              "currency" => "EUR"
            }
          }
        ]
      }

      {:ok, preview} = JsonParser.parse(Jason.encode!(body))

      [entry] = preview.entries
      assert entry.security.name == "VentiscaS.A.Acciones"
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
              "isin" => "ESEXMPL30065",
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
              "name" => "Arbolia Inc.",
              "isin" => "USEXMPL10014",
              "currency" => "USD"
            }
          }
        ]
      }

      {:ok, preview} = JsonParser.parse(Jason.encode!(body))
      [entry] = preview.entries
      assert entry.security.name == "Arbolia Inc."
    end
  end

  describe "effective_asset_class — read-time inference on stored nil" do
    test "infers correct class at read time even if stored class is nil" do
      security = %Security{
        name: "NOVARIX Corporation",
        isin: "USEXMPL10030",
        ticker_symbol: "NVRX",
        asset_class: nil
      }

      assert Security.effective_asset_class(security) == "equity"
    end

    test "returns nil for pure brand name with no legal suffix" do
      security = %Security{
        name: "Amblewick",
        isin: nil,
        ticker_symbol: nil,
        asset_class: nil
      }

      assert is_nil(Security.effective_asset_class(security))
    end
  end

  # User story:
  # As a maintainer importing securities with friendly short names (e.g.
  # "Amblewick", "Mirelund") that carry no legal-form token, I want a resolved
  # company logo plus an ISIN to classify them as equity (#408), so the
  # "Unsorted"/"Unassigned" bucket isn't full of obvious equities.
  describe "equity fallback from a resolved company logo (#408)" do
    test "a name-unresolved security with an ISIN and a company logo is equity" do
      security = %Security{
        name: "Amblewick",
        isin: "USEXMPL10022",
        ticker_symbol: nil,
        asset_class: nil,
        attributes: %{"logo_path" => "logos/amblewick.png"}
      }

      assert Security.effective_asset_class(security) == "equity"
    end

    test "stays nil without a logo (heuristics still ambiguous)" do
      security = %Security{
        name: "Amblewick",
        isin: "USEXMPL10022",
        asset_class: nil,
        attributes: %{}
      }

      assert is_nil(Security.effective_asset_class(security))
    end

    test "stays nil with a logo but no ISIN (logo alone is not enough)" do
      security = %Security{
        name: "Amblewick",
        isin: nil,
        asset_class: nil,
        attributes: %{"logo_path" => "logos/amblewick.png"}
      }

      assert is_nil(Security.effective_asset_class(security))
    end

    test "a user-set class always wins over the logo fallback" do
      security = %Security{
        name: "Amblewick",
        isin: "USEXMPL10022",
        asset_class: "fund",
        attributes: %{"logo_path" => "logos/amblewick.png"}
      }

      assert Security.effective_asset_class(security) == "fund"
    end
  end
end
