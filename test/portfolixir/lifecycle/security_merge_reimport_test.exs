defmodule Portfolixir.Lifecycle.SecurityMergeReimportTest do
  # ADR-0050 §2's post-merge re-import contract for the security merge (L4b,
  # #608; risk-tier: import idempotency, ADR-0036), its §16 invariants
  # written before the security merge carried identifiers:
  #
  #   * 1 — re-applying an applied export creates zero transactions, cash
  #     accounts, depots and securities after a security merge under both
  #     identity choices, with and without collapse; every row is reported
  #     with its layer;
  #   * 5 — a drifted re-import after the merge creates nothing, in both of
  #     ADR-0029 §5's directions: the export carrying the newer ISIN and the
  #     one carrying the older;
  #   * 6 — a newer file naming the merged-away security's ISIN inserts its
  #     new rows once, on the target;
  #   * 14 — after the merge both pre-merge identities, stored and as
  #     imported (the importer's journaled create), resolve to the target.
  #
  # The world is ADR-0050's third example, the wrong-order ISIN duplicate
  # (ADR-0029 §3): "Example Fund" was imported under its older ISIN, and an
  # export carrying the newer ISIN was imported before the change was
  # recorded, which created a second "Example Fund" with a second copy of
  # the history. The exports are synthetic Portfolio Performance JSON; every
  # name, amount and identifier is invented.
  #
  # async: false — the applier's after-commit enrichment runs in a task that
  # needs the shared sandbox connection.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.SecurityResolver
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
  alias Portfolixir.Portfolios

  # Synthetic ISINs whose check digits agree (ISO 6166).
  @isin_old "XS00EXOLDA04"
  @isin_new "XS00EXNEWB00"

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Security import target",
        base_currency_code: "EUR"
      })

    assert {:ok, %Result{created_securities: 1, created_transactions: 4}} =
             Imports.apply(parse!(export(:old)), %{portfolio_id: portfolio.id})

    # The wrong-order import: the newer export's reference is a surfaced
    # decision (the name matches, the ISIN vetoes), and the operator chose
    # to create it — the duplicate.
    newer = parse!(export(:new))
    [key] = Enum.map(Imports.resolve_securities(newer).resolutions, & &1.key)

    assert {:ok, %Result{created_securities: 1, created_transactions: 3}} =
             Imports.apply(newer, %{
               portfolio_id: portfolio.id,
               security_mappings: %{key => :create}
             })

    %{
      portfolio: portfolio,
      target: Repo.one!(from(s in Security, where: s.isin == ^@isin_old)),
      source: Repo.one!(from(s in Security, where: s.isin == ^@isin_new))
    }
  end

  for choice <- [:keep_target_isin, :adopt_source_isin], collapse? <- [false, true] do
    describe "after a security merge with #{choice} and collapse_key_equal #{collapse?}" do
      # User story:
      # As the operator who merged the duplicate "Example Fund" into the
      # original,
      # I want the next import of either export, byte-identical or drifted,
      # to create nothing,
      # so that the merge never books the history a second time, whichever
      # ISIN the export carries.
      #
      # Acceptance criteria:
      # - A byte-identical re-import of either export creates zero
      #   transactions, cash accounts, depots and securities; each row is
      #   reported with its layer: `hash` for a row that stayed or moved,
      #   `retired` for a collapsed row.
      # - A drifted re-import of either export (other decimal precision, so
      #   no content hash matches) creates nothing either: its security
      #   resolves to the target, by its current ISIN or by the former one,
      #   and its rows are caught by the economic layer.
      @tag choice: choice, collapse: collapse?
      test "both exports, byte-identical and drifted, create nothing", ctx do
        merge!(ctx)
        before = counts()

        for {file, security_layer} <- [{:old, :hash}, {:new, moved_layer(ctx.collapse)}] do
          assert {:ok, %Result{} = result} =
                   Imports.apply(parse!(export(file)), %{portfolio_id: ctx.portfolio.id})

          assert_created_nothing(result)
          assert counts() == before

          assert Enum.map(result.duplicate_entries, &{&1.row, &1.layer}) ==
                   [{1, :hash}, {2, security_layer}, {3, security_layer}, {4, security_layer}]

          drifted = parse!(export(file, :drifted))

          assert [%{status: :matched, matched: %{security_id: id}}] =
                   Imports.resolve_securities(drifted).resolutions

          assert id == ctx.target.id

          assert {:ok, %Result{} = result} =
                   Imports.apply(drifted, %{portfolio_id: ctx.portfolio.id})

          assert_created_nothing(result)
          assert counts() == before

          assert Enum.map(result.duplicate_entries, &{&1.row, &1.layer}) ==
                   [{1, :economics}, {2, :economics}, {3, :economics}, {4, :economics}]
        end
      end

      # User story:
      # As the operator importing a later export that still carries the
      # merged-away duplicate's ISIN (or the original's),
      # I want its new rows booked once, on the security I kept,
      # so that the history stays on one security.
      #
      # Acceptance criteria:
      # - A newer export of either ISIN with one new purchase inserts that
      #   purchase on the target and creates no security; applying it again
      #   creates nothing.
      @tag choice: choice, collapse: collapse?
      test "a newer export of either ISIN lands once on the target", ctx do
        merge!(ctx)

        for {file, date} <- [{:new, "2025-06-01"}, {:old, "2025-07-01"}] do
          newer = parse!(export(file) ++ [purchase(fund(file), "1", "110.00", date)])

          assert {:ok, %Result{} = result} =
                   Imports.apply(newer, %{portfolio_id: ctx.portfolio.id})

          assert result.created_transactions == 1
          assert result.created_securities == 0

          assert [%Transaction{security_id: security_id}] =
                   Repo.all(from(t in Transaction, where: t.date == ^Date.from_iso8601!(date)))

          assert security_id == ctx.target.id

          before = counts()

          assert {:ok, %Result{created_transactions: 0, created_securities: 0}} =
                   Imports.apply(newer, %{portfolio_id: ctx.portfolio.id})

          assert counts() == before
        end
      end

      # User story:
      # As the maintainer of the re-import contract,
      # I want every identity through which either security resolved before
      # the merge — as stored, and as the importer's create recorded it — to
      # resolve to the target after it,
      # so that obligation O2 holds for the security merge.
      #
      # Acceptance criteria:
      # - The source's and the target's stored identities and their
      #   as-imported identities resolve to the target on the ladder over
      #   the catalog after the merge.
      @tag choice: choice, collapse: collapse?
      test "both identities, stored and as imported, resolve to the target", ctx do
        identities = [
          stored(ctx.source),
          stored(ctx.target),
          as_imported(ctx.source),
          as_imported(ctx.target)
        ]

        merge!(ctx)
        index = SecurityResolver.load_index()

        for ref <- identities do
          assert {:match, %Security{id: id}, _tier} = SecurityResolver.resolve(ref, index),
                 "#{inspect(ref)} no longer resolves to the target"

          assert id == ctx.target.id
        end
      end
    end
  end

  defp moved_layer(true), do: :retired
  defp moved_layer(false), do: :hash

  # --- the synthetic exports -------------------------------------------------

  defp fund(:old), do: %{"name" => "Example Fund", "isin" => @isin_old, "currency" => "EUR"}
  defp fund(:new), do: %{"name" => "Example Fund", "isin" => @isin_new, "currency" => "EUR"}

  # One deposit and the fund's history: two purchases and a sale. The two
  # exports differ only in the ISIN the fund carries; the drifted variant
  # writes every number with another precision, as a re-export after an edit
  # inside Portfolio Performance would.
  defp export(file, variant \\ :exact) do
    d =
      case variant do
        :exact ->
          %{
            deposit: "10000.00",
            first: {"5", "500.00"},
            second: {"2", "220.00"},
            sold: {"1", "120.00"}
          }

        :drifted ->
          %{
            deposit: "10000.0",
            first: {"5.0", "500.0"},
            second: {"2.00", "220.0"},
            sold: {"1.0", "120.000"}
          }
      end

    [
      %{
        "type" => "DEPOSIT",
        "account" => "Giro",
        "date" => "2025-01-02",
        "currency" => "EUR",
        "amount" => num(d.deposit)
      },
      purchase(fund(file), elem(d.first, 0), elem(d.first, 1), "2025-01-10"),
      purchase(fund(file), elem(d.second, 0), elem(d.second, 1), "2025-03-01"),
      %{
        "type" => "SALE",
        "account" => "Giro",
        "portfolio" => "Depot 1",
        "date" => "2025-04-01",
        "time" => "10:00",
        "currency" => "EUR",
        "amount" => num(elem(d.sold, 1)),
        "shares" => num(elem(d.sold, 0)),
        "security" => fund(file)
      }
    ]
  end

  defp purchase(security, shares, amount, date) do
    %{
      "type" => "PURCHASE",
      "account" => "Giro",
      "portfolio" => "Depot 1",
      "date" => date,
      "time" => "10:00",
      "currency" => "EUR",
      "amount" => num(amount),
      "shares" => num(shares),
      "security" => security
    }
  end

  # A JSON number written as its literal digits, never through a float.
  defp num(digits), do: Jason.Fragment.new(digits)

  defp parse!(rows) do
    body = Jason.encode!(%{"version" => 1, "transactions" => rows})
    {:ok, preview} = Imports.parse_portfolio_performance(body, filename: "synthetic.json")
    preview
  end

  # --- world ------------------------------------------------------------------

  defp merge!(ctx) do
    {:ok, preview} = Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)
    assert preview.identifiers.choice_required
    assert length(preview.key_equal_pairs) == 3

    {:ok, _record, :applied} =
      Lifecycle.merge_security(agent(), ctx.source.id, ctx.target.id, %{
        plan_digest: preview.plan_digest,
        collapse_key_equal: ctx.collapse,
        identity_choice: ctx.choice
      })

    :ok
  end

  defp stored(%Security{} = security) do
    SecurityResolver.normalize_ref(%{
      isin: security.isin,
      wkn: security.wkn,
      ticker: security.ticker_symbol,
      name: security.name,
      currency: security.currency_code
    })
  end

  # The identity the importer's journaled create recorded.
  defp as_imported(%Security{id: id}) do
    %Journal.Entry{after: after_image} =
      Repo.one!(
        from(e in Journal.Entry,
          where:
            e.resource_type == "security" and e.operation == :create and
              e.resource_id == ^to_string(id) and e.actor_type == :import_session
        )
      )

    SecurityResolver.normalize_ref(%{
      isin: after_image["isin"],
      wkn: after_image["wkn"],
      ticker: after_image["ticker_symbol"],
      name: after_image["name"],
      currency: after_image["currency_code"]
    })
  end

  defp assert_created_nothing(%Result{} = result) do
    assert result.created_transactions == 0
    assert result.created_cash_accounts == 0
    assert result.created_securities_accounts == 0
    assert result.created_securities == 0
  end

  defp counts do
    %{
      cash: Portfolios.count_cash_accounts(),
      depots: length(Portfolios.list_securities_accounts()),
      securities: Catalog.count_securities(),
      transactions: Ledger.count_transactions()
    }
  end
end
