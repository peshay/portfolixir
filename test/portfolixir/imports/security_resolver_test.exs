defmodule Portfolixir.Imports.SecurityResolverTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Imports.SecurityResolver
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets

  defp security!(attrs) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(%{name: "Example AG", currency_code: "EUR"}, attrs)
      )

    security
  end

  defp transact!(security) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "P " <> security.isin,
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Cash " <> security.isin,
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot " <> security.isin
      })

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        type: "buy",
        date: ~D[2024-01-02],
        currency_code: "EUR",
        security_id: security.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        quantity: Decimal.new("1"),
        price: Decimal.new("10"),
        gross_amount: Decimal.new("10")
      })

    security
  end

  defp resolve(ref) do
    SecurityResolver.resolve(SecurityResolver.normalize_ref(ref), SecurityResolver.load_index())
  end

  # User story:
  # As a local portfolio maintainer re-importing a PP export,
  # I want securities in the file resolved through the full ADR-0029 §2
  # identity ladder (ISIN incl. aliases, WKN, ticker+currency,
  # name+currency),
  # so that renamed or partially-identified securities match my existing
  # records deterministically instead of minting duplicates.
  #
  # Acceptance criteria:
  # - Each tier applies only when its field is present on both sides.
  # - A tier with zero candidates falls through; a unique candidate matches.
  # - Comparisons use the catalog normal form (trim/upcase identifiers).
  # - An entry without a currency skips tiers 3-4.
  describe "resolve/2 descending tiers" do
    test "tier 2: a unique WKN match resolves when the entry has no ISIN" do
      security = security!(%{wkn: "ABC123"})
      _decoy = security!(%{name: "Other AG", wkn: "ZZZ999"})

      assert {:match, matched, :wkn} =
               resolve(%{isin: nil, wkn: "abc123", ticker: nil, name: "Renamed", currency: "EUR"})

      assert matched.id == security.id
    end

    test "tier 3: a unique (ticker, currency) match resolves below a missing WKN" do
      security = security!(%{ticker_symbol: "EXA"})

      assert {:match, matched, :ticker} =
               resolve(%{isin: nil, wkn: nil, ticker: " exa ", name: "Renamed", currency: "EUR"})

      assert matched.id == security.id
    end

    test "tier 3 with a different currency has zero candidates and falls through to name" do
      security = security!(%{ticker_symbol: "EXA", currency_code: "USD", name: "Example AG"})
      _same_name_eur = security!(%{name: "Example EUR AG"})

      # Ticker matches only in USD; the EUR entry falls through tier 3 and
      # then misses tier 4 (no EUR security named "Example AG") -> create.
      assert :create =
               resolve(%{isin: nil, wkn: nil, ticker: "EXA", name: "Example AG", currency: "EUR"})

      assert {:match, matched, :ticker} =
               resolve(%{isin: nil, wkn: nil, ticker: "EXA", name: "Example AG", currency: "USD"})

      assert matched.id == security.id
    end

    test "tier 4: (name, currency) stays the last tier" do
      security = security!(%{name: "Nameonly Corp"})

      assert {:match, matched, :name} =
               resolve(%{
                 isin: nil,
                 wkn: nil,
                 ticker: nil,
                 name: " Nameonly Corp ",
                 currency: "EUR"
               })

      assert matched.id == security.id
    end

    test "an entry without a currency skips tiers 3-4 entirely" do
      _security = security!(%{name: "Bitcoin", ticker_symbol: "BTC"})

      assert :create =
               resolve(%{isin: nil, wkn: nil, ticker: "BTC", name: "Bitcoin", currency: nil})
    end

    test "no tier applicable or matching resolves to :create" do
      assert :create =
               resolve(%{isin: nil, wkn: nil, ticker: nil, name: "Brand New", currency: "EUR"})
    end
  end

  # User story:
  # As a local portfolio maintainer,
  # I want an ambiguous tier (two candidates share the identifier) surfaced
  # as a decision instead of silently picking or falling through (ADR-0029 §2),
  # so that a wrong silent merge can never happen.
  #
  # Acceptance criteria:
  # - >= 2 candidates on a tier produce a surfaced conflict.
  # - The ambiguous tier does NOT fall through to a weaker tier, even when a
  #   weaker tier would match uniquely.
  describe "resolve/2 ambiguity" do
    test "two securities sharing a WKN surface a decision, never a pick" do
      a = security!(%{name: "Share Class A", wkn: "AMB001"})
      b = security!(%{name: "Share Class B", wkn: "AMB001"})

      assert {:conflict, %{type: :ambiguous, tier: :wkn, candidates: candidates}} =
               resolve(%{
                 isin: nil,
                 wkn: "AMB001",
                 ticker: nil,
                 name: "Whatever",
                 currency: "EUR"
               })

      assert Enum.sort(Enum.map(candidates, & &1.id)) == Enum.sort([a.id, b.id])
    end

    test "an ambiguous WKN does not fall through to a unique ticker match" do
      _a = security!(%{name: "Share Class A", wkn: "AMB001"})
      _b = security!(%{name: "Share Class B", wkn: "AMB001", ticker_symbol: "SCB"})

      assert {:conflict, %{type: :ambiguous, tier: :wkn}} =
               resolve(%{isin: nil, wkn: "AMB001", ticker: "SCB", name: "X", currency: "EUR"})
    end

    test "two securities sharing (name, currency) surface a decision" do
      a = security!(%{name: "Duplicate Name AG"})
      b = security!(%{name: "Duplicate Name AG"})

      assert {:conflict, %{type: :ambiguous, tier: :name, candidates: candidates}} =
               resolve(%{
                 isin: nil,
                 wkn: nil,
                 ticker: nil,
                 name: "Duplicate Name AG",
                 currency: "EUR"
               })

      assert Enum.sort(Enum.map(candidates, & &1.id)) == Enum.sort([a.id, b.id])
    end
  end

  # User story:
  # As a local portfolio maintainer,
  # I want a weaker-tier match vetoed when a stronger identifier disagrees
  # (ADR-0029 §2 stronger-identifier veto), and cross-tier disagreement
  # surfaced,
  # so that the ladder never converts a safe duplicate into a silent wrong
  # merge.
  #
  # Acceptance criteria:
  # - Entry ISIN differing from a WKN-matched candidate's ISIN is a conflict.
  # - Entry WKN differing from a name-matched candidate's WKN is a conflict.
  # - WKN selecting A while ticker+currency selects B is a conflict.
  # - An alias-tier (former ISIN) hit is NOT vetoed by the candidate's
  #   different current ISIN.
  describe "resolve/2 stronger-identifier veto and cross-tier disagreement" do
    test "a WKN match with a differing entry ISIN is surfaced, not merged" do
      security = security!(%{isin: "DE000OLD0009", wkn: "WRG111"})

      assert {:conflict, %{type: :identifier_veto, tier: :wkn, candidates: [candidate]}} =
               resolve(%{
                 isin: "DE000NEW0007",
                 wkn: "WRG111",
                 ticker: nil,
                 name: "X",
                 currency: "EUR"
               })

      assert candidate.id == security.id
    end

    test "a name match with a differing entry WKN is surfaced" do
      _security = security!(%{name: "Veto AG", wkn: "AAA111"})

      assert {:conflict, %{type: :identifier_veto, tier: :name}} =
               resolve(%{isin: nil, wkn: "BBB222", ticker: nil, name: "Veto AG", currency: "EUR"})
    end

    test "cross-tier disagreement (WKN selects A, ticker selects B) is surfaced" do
      a = security!(%{name: "Paper A", wkn: "CRS111"})
      b = security!(%{name: "Paper B", ticker_symbol: "CRSB"})

      assert {:conflict, %{type: :cross_tier, candidates: candidates}} =
               resolve(%{isin: nil, wkn: "CRS111", ticker: "CRSB", name: "X", currency: "EUR"})

      assert Enum.sort(Enum.map(candidates, & &1.id)) == Enum.sort([a.id, b.id])
    end

    test "an alias hit resolves despite the candidate's different current ISIN" do
      security = security!(%{isin: "DE0001234567"})

      {:ok, %{security: security}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654321")

      assert {:match, matched, :former_isin} =
               resolve(%{isin: "DE0001234567", wkn: nil, ticker: nil, name: "X", currency: "EUR"})

      assert matched.id == security.id
    end

    test "a name match with a differing entry ticker is surfaced, not booked onto the twin" do
      # Two share classes with no ISIN/WKN, same name+currency, distinct
      # tickers: the ticker+currency tier (3) is strictly stronger than
      # name+currency (4), so a name hit contradicted by the ticker must be a
      # surfaced decision, never a silent merge onto TWNA (ADR-0029 §2).
      twna = security!(%{name: "Twin Fund", currency_code: "EUR", ticker_symbol: "TWNA"})

      assert {:conflict, %{type: :identifier_veto, tier: :name, candidates: [candidate]}} =
               resolve(%{
                 isin: nil,
                 wkn: nil,
                 ticker: "TWNB",
                 name: "Twin Fund",
                 currency: "EUR"
               })

      assert candidate.id == twna.id
    end

    test "a name match with a matching entry ticker still resolves cleanly" do
      twna = security!(%{name: "Twin Fund", currency_code: "EUR", ticker_symbol: "TWNA"})

      # A matching ticker rides tier 3 directly; assert it matches the same
      # security and is not vetoed.
      assert {:match, matched, :ticker} =
               resolve(%{
                 isin: nil,
                 wkn: nil,
                 ticker: "TWNA",
                 name: "Twin Fund",
                 currency: "EUR"
               })

      assert matched.id == twna.id
    end

    test "a name match with the ticker absent on one side still matches" do
      twna = security!(%{name: "Twin Fund", currency_code: "EUR", ticker_symbol: "TWNA"})

      # Entry carries no ticker: tier 3 cannot contradict, so the name tier
      # matches cleanly.
      assert {:match, matched, :name} =
               resolve(%{isin: nil, wkn: nil, ticker: nil, name: "Twin Fund", currency: "EUR"})

      assert matched.id == twna.id
    end
  end

  # User story:
  # As a local portfolio maintainer with stored strategy configuration,
  # I want a to-be-created security that near-matches a config-bearing
  # existing security flagged as config-at-risk (ADR-0029 §2, FR-7),
  # and config-bearing securities matched by zero entries listed by the
  # pre-apply inverse check,
  # so that a re-import can never silently strand my category assignments or
  # position targets.
  #
  # Acceptance criteria:
  # - Same name in a different currency or same ticker near-matches.
  # - Only existing securities carrying assignments or position targets flag.
  # - The inverse check lists config-bearing transacted securities matching
  #   zero entries and excludes matched and watch-only (untransacted) ones.
  describe "config-at-risk and the pre-apply inverse check" do
    defp attach_assignment!(security) do
      {:ok, classification} =
        Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

      {:ok, category} =
        Classifications.create_category(Actor.owner_ui(), %{
          classification_id: classification.id,
          name: "Core"
        })

      {:ok, _} =
        Classifications.assign_security(
          Actor.owner_ui(),
          security.id,
          classification.id,
          category.id
        )

      {classification, category}
    end

    test "a creation near-matching a config-bearing security is flagged" do
      security = security!(%{name: "Config AG", currency_code: "USD"})
      attach_assignment!(security)

      index = SecurityResolver.load_index()

      ref =
        SecurityResolver.normalize_ref(%{
          isin: nil,
          wkn: nil,
          ticker: nil,
          name: "Config AG",
          currency: "EUR"
        })

      assert :create = SecurityResolver.resolve(ref, index)
      assert [at_risk] = SecurityResolver.config_at_risk(ref, index)
      assert at_risk.security.id == security.id
      assert at_risk.assignments?
      refute at_risk.position_targets?
    end

    test "a creation near a security without config is not flagged" do
      _security = security!(%{name: "Plain AG", currency_code: "USD"})

      index = SecurityResolver.load_index()

      ref =
        SecurityResolver.normalize_ref(%{
          isin: nil,
          wkn: nil,
          ticker: nil,
          name: "Plain AG",
          currency: "EUR"
        })

      assert SecurityResolver.config_at_risk(ref, index) == []
    end

    test "position targets alone flag a near-match (ADR-0030)" do
      security = security!(%{name: "Target AG", currency_code: "USD"})
      {classification, category} = attach_assignment!(security)
      # Move the assignment off, keep only the position target? Assignments
      # are needed for a valid position target's category, so this security
      # legitimately carries both; use a second security with target only via
      # its category membership.
      {:ok, portfolio} =
        Portfolios.create_portfolio(Actor.owner_ui(), %{
          name: "P",
          base_currency_code: "EUR"
        })

      {:ok, _} =
        Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
          %{"category_id" => category.id, "security_id" => security.id, "target_weight" => "0.5"}
        ])

      index = SecurityResolver.load_index()

      ref =
        SecurityResolver.normalize_ref(%{
          isin: nil,
          wkn: nil,
          ticker: nil,
          name: "Target AG",
          currency: "EUR"
        })

      assert [at_risk] = SecurityResolver.config_at_risk(ref, index)
      assert at_risk.position_targets?
    end

    test "the inverse check lists config-bearing transacted securities matching zero entries" do
      leftover = security!(%{name: "Leftover AG", isin: "DE000LEFT001"})
      matched = security!(%{name: "Matched AG", isin: "DE000MTCH001"})
      watch_only = security!(%{name: "Watch Only AG", isin: "DE000WTCH001"})

      attach_assignment!(leftover)

      {:ok, classification} =
        Classifications.create_classification(Actor.owner_ui(), %{name: "Second"})

      {:ok, category} =
        Classifications.create_category(Actor.owner_ui(), %{
          classification_id: classification.id,
          name: "Cat"
        })

      for sec <- [matched, watch_only] do
        {:ok, _} =
          Classifications.assign_security(
            Actor.owner_ui(),
            sec.id,
            classification.id,
            category.id
          )
      end

      {:ok, portfolio} =
        Portfolios.create_portfolio(Actor.owner_ui(), %{name: "P", base_currency_code: "EUR"})

      {:ok, cash} =
        Portfolios.create_cash_account(Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          name: "Cash",
          currency_code: "EUR"
        })

      {:ok, depot} =
        Portfolios.create_securities_account(Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          cash_account_id: cash.id,
          name: "Depot"
        })

      for sec <- [leftover, matched] do
        {:ok, _} =
          Ledger.create_transaction(Actor.owner_ui(), %{
            portfolio_id: portfolio.id,
            type: "buy",
            date: ~D[2024-01-02],
            currency_code: "EUR",
            security_id: sec.id,
            securities_account_id: depot.id,
            cash_account_id: cash.id,
            quantity: Decimal.new("1"),
            price: Decimal.new("10"),
            gross_amount: Decimal.new("10")
          })
      end

      preview = %Preview{
        format: :json,
        entries: [
          %Entry{
            source_row: 1,
            kind: "buy",
            date: ~D[2024-05-01],
            currency_code: "EUR",
            gross_amount: Decimal.new("10"),
            quantity: Decimal.new("1"),
            price: Decimal.new("10"),
            security: %{
              isin: "DE000MTCH001",
              wkn: nil,
              ticker: nil,
              name: "Matched AG",
              currency: "EUR"
            },
            pp_portfolio_name: "Depot",
            pp_account_name: "Cash"
          }
        ]
      }

      %{resolutions: resolutions, unmatched_config: unmatched} =
        Imports.resolve_securities(preview)

      assert [%{status: :matched, matched: %{security_id: matched_id, tier: :isin}}] = resolutions
      assert matched_id == matched.id

      # Leftover: config-bearing, transacted, zero entries -> listed.
      # Matched: resolves -> excluded. Watch-only: no transactions -> excluded.
      assert [leftover_row] = unmatched
      assert leftover_row.security.id == leftover.id
    end
  end

  # User story:
  # As a local portfolio maintainer reviewing an import,
  # I want each unique security reference in the file classified into
  # matched / create / needs-decision / config-at-risk with a stable key,
  # so that the preview can gate apply on explicit decisions.
  #
  # Acceptance criteria:
  # - The plan carries one row per unique normalized reference.
  # - Keys are stable strings safe for form field names.
  # - Statuses reflect the ladder outcome.
  describe "resolution_plan/2" do
    test "classifies unique refs and derives stable keys" do
      matched = security!(%{isin: "DE000MTCH001"})
      _amb_a = security!(%{name: "Amb AG", wkn: "AMB001"})
      _amb_b = security!(%{name: "Amb 2 AG", wkn: "AMB001"})

      entry = fn row, sec ->
        %Entry{
          source_row: row,
          kind: "buy",
          date: ~D[2024-05-01],
          currency_code: "EUR",
          gross_amount: Decimal.new("10"),
          quantity: Decimal.new("1"),
          price: Decimal.new("10"),
          security: sec,
          pp_portfolio_name: "Depot",
          pp_account_name: "Cash"
        }
      end

      preview = %Preview{
        format: :json,
        entries: [
          entry.(1, %{
            isin: "DE000MTCH001",
            wkn: nil,
            ticker: nil,
            name: "Matched AG",
            currency: "EUR"
          }),
          entry.(2, %{isin: nil, wkn: "AMB001", ticker: nil, name: "Amb AG", currency: "EUR"}),
          entry.(3, %{isin: nil, wkn: nil, ticker: nil, name: "Brand New", currency: "EUR"}),
          # Same ref twice collapses to one plan row with both source rows.
          entry.(4, %{isin: nil, wkn: nil, ticker: nil, name: "Brand New", currency: "EUR"})
        ]
      }

      %{resolutions: resolutions} = Imports.resolve_securities(preview)

      by_status = Enum.group_by(resolutions, & &1.status)

      assert [%{matched: %{security_id: matched_id}}] = by_status[:matched]
      assert matched_id == matched.id

      assert [%{candidates: [_, _]}] = by_status[:needs_decision]

      assert [create_row] = by_status[:create]
      assert create_row.rows == [3, 4]
      assert create_row.key =~ ~r/^[a-f0-9]+$/
    end

    # User story (2026-07-29, issue #609):
    # As a maintainer importing an export in which a security was renamed,
    # I want the matched row to say the file calls it something else,
    # so that a rename is visible even though matching deliberately never
    # mutates stored master data (ADR-0029 §2).
    #
    # Acceptance criteria:
    # - A matched row whose file name differs from the stored name carries
    #   name_differs with the file's name.
    # - An identical name (ignoring case and surrounding whitespace) does not.
    # - Nothing about the stored security changes.
    test "a matched row flags a name that differs in the file" do
      stored = security!(%{isin: "DE000RENAME1", name: "Stored AG"})

      entry = fn row, name ->
        %Entry{
          source_row: row,
          kind: "buy",
          date: ~D[2024-05-01],
          currency_code: "EUR",
          gross_amount: Decimal.new("10"),
          quantity: Decimal.new("1"),
          price: Decimal.new("10"),
          security: %{
            isin: "DE000RENAME1",
            wkn: nil,
            ticker: nil,
            name: name,
            currency: "EUR"
          },
          pp_portfolio_name: "Depot",
          pp_account_name: "Cash"
        }
      end

      preview = %Preview{format: :json, entries: [entry.(1, "Renamed AG")]}
      %{resolutions: [row]} = Imports.resolve_securities(preview)

      assert row.status == :matched
      assert row.name_differs == "Renamed AG"
      assert Catalog.get_security(stored.id).name == "Stored AG"

      same = %Preview{format: :json, entries: [entry.(1, "  stored ag ")]}
      %{resolutions: [unchanged]} = Imports.resolve_securities(same)

      assert unchanged.status == :matched
      assert unchanged.name_differs == nil
    end
  end

  describe "unmatched_config_securities/2 scoping (#607)" do
    # User story (2026-07-29, issue #607):
    # As a maintainer adding a few bookings from a small export,
    # I want the untouched-config panel to stay quiet,
    # so that the one genuinely renamed security is not buried under every
    # other configured security in the portfolio.
    #
    # Acceptance criteria:
    # - A full re-export (covering most transacted, config-bearing securities)
    #   still surfaces its leftovers.
    # - An incremental import surfaces none, and reports the scope decision so
    #   the surface can say why rather than silently showing nothing.

    defp configured!(name, isin) do
      security = security!(%{name: name, isin: isin})

      {:ok, classification} =
        Classifications.create_classification(Actor.owner_ui(), %{name: "Tree " <> isin})

      {:ok, category} =
        Classifications.create_category(Actor.owner_ui(), %{
          classification_id: classification.id,
          name: "Cat " <> isin
        })

      {:ok, _} =
        Classifications.assign_security(
          Actor.owner_ui(),
          security.id,
          classification.id,
          category.id
        )

      transact!(security)
      security
    end

    defp import_of(securities) do
      entries =
        securities
        |> Enum.with_index(1)
        |> Enum.map(fn {security, row} ->
          %Entry{
            source_row: row,
            kind: "buy",
            date: ~D[2024-05-01],
            currency_code: "EUR",
            gross_amount: Decimal.new("10"),
            quantity: Decimal.new("1"),
            price: Decimal.new("10"),
            security: %{
              isin: security.isin,
              wkn: nil,
              ticker: nil,
              name: security.name,
              currency: "EUR"
            },
            pp_portfolio_name: "Depot",
            pp_account_name: "Cash"
          }
        end)

      %Preview{format: :json, entries: entries}
    end

    test "a full re-export still surfaces its leftovers" do
      a = configured!("Alpha AG", "DE000SCOPE01")
      b = configured!("Beta AG", "DE000SCOPE02")
      _left = configured!("Gamma AG", "DE000SCOPE03")

      result = Imports.resolve_securities(import_of([a, b]))

      assert result.unmatched_config_scope == :full_export
      assert Enum.map(result.unmatched_config, & &1.security.name) == ["Gamma AG"]
    end

    test "a short leftover list is shown even on an incremental file" do
      a = configured!("Alpha AG", "DE000SCOPE21")
      _left = configured!("Beta AG", "DE000SCOPE22")

      # Coverage is 1 of 2 here; the point of the assertion is the floor, so
      # add transacted securities the import does not touch to push it down.
      for isin <- ~w(DE000SCOPE23 DE000SCOPE24 DE000SCOPE25 DE000SCOPE26) do
        isin |> then(&security!(%{name: "Plain " <> &1, isin: &1})) |> transact!()
      end

      result = Imports.resolve_securities(import_of([a]))

      assert result.unmatched_config_scope == :full_export
      assert Enum.map(result.unmatched_config, & &1.security.name) == ["Beta AG"]
    end

    test "an incremental import surfaces none and says the scope it decided" do
      a = configured!("Alpha AG", "DE000SCOPE11")

      for {name, isin} <- [
            {"Beta AG", "DE000SCOPE12"},
            {"Gamma AG", "DE000SCOPE13"},
            {"Delta AG", "DE000SCOPE14"},
            {"Epsilon AG", "DE000SCOPE15"},
            {"Zeta AG", "DE000SCOPE16"},
            {"Eta AG", "DE000SCOPE17"},
            {"Theta AG", "DE000SCOPE18"}
          ] do
        configured!(name, isin)
      end

      result = Imports.resolve_securities(import_of([a]))

      assert result.unmatched_config_scope == :incremental
      assert result.unmatched_config == []
    end
  end
end
