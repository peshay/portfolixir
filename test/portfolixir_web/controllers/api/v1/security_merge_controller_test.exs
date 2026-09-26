defmodule PortfolixirWeb.Api.V1.SecurityMergeControllerTest do
  # ADR-0050 §9, §10 and §12 over the API (L4b, #608; risk-tier: quantity
  # identity and import idempotency, ADR-0036): the security merge preview,
  # a read, and the apply, which takes the preview's digest, the answer to
  # the duplicate question and — when both securities carry an ISIN — the
  # identity choice; and §12's answer for a merged-away id, a 404 naming the
  # survivor for a security, a cash account and a depot alike. §16 invariant
  # 12 (the preview's after-figures equal the API reads right after the
  # apply) and 13 (each refusal answers its code and writes nothing) are
  # pinned here on the wire. Every name, amount, identifier and quote is
  # synthetic.
  use PortfolixirWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Classifications
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Ledger
  alias Portfolixir.Lifecycle
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets

  # Synthetic ISINs whose check digits agree (ISO 6166).
  @isin_source "XS00EXSRCE01"
  @isin_target "XS00EXTGTF03"

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Security Merge API",
        base_currency_code: "EUR"
      })

    cash = cash!(portfolio, "Broker cash")

    %{
      conn: conn,
      portfolio: portfolio,
      cash: cash,
      depot: depot!(portfolio, cash, "Depot 1"),
      target:
        security!(%{name: "Harbour Income Fund", isin: @isin_target, ticker_symbol: "HBRI"}),
      source:
        security!(%{
          name: "Harbour Income Fund (duplicate)",
          isin: @isin_source,
          wkn: "HBR001",
          ticker_symbol: "HBRD"
        })
    }
  end

  # User story:
  # As the agent repairing a duplicate security,
  # I want a preview of merging it into the security I keep that states
  # every position, quote, configuration row, event and identifier the
  # merge touches, for each answer to both questions, with a digest I send
  # back,
  # so that I can show the operator the consequence before anything is
  # written.
  #
  # Acceptance criteria:
  # - GET /api/v1/securities/:id/merge_preview?target_id= answers 200 with
  #   plan_digest, both securities, the guards, the key-equal pairs, the
  #   splits, the split events, the bucket plan per depot, the quotes (counts
  #   and the manual collisions), the configuration (category assignments and
  #   position targets, each with its action), the events, the identifiers
  #   after each identity choice with what the target adopts and every
  #   difference, and outcome_by_collapse_key_equal for "false" and "true".
  # - Every quantity, close, weight and financial decimal is a string.
  # - It writes nothing.
  test "the preview answers every part of the merge, decimals as strings, and writes nothing",
       ctx do
    world!(ctx)
    mark = journal_mark()

    preview = preview!(ctx)

    assert preview["kind"] == "security"
    assert "sha256:" <> _ = preview["plan_digest"]
    assert Enum.all?(preview["guards"], & &1["passed"])
    assert preview["choice_required"] == true
    assert preview["identity_choice_required"] == true
    assert preview["source"]["isin"] == @isin_source
    assert preview["target"]["isin"] == @isin_target
    assert [%{"quantity" => "2", "price" => "50"}] = preview["key_equal_pairs"]

    assert %{
             "source_count" => 2,
             "moved_count" => 1,
             "collision_count" => 1,
             "manual_collisions" => [
               %{
                 "date" => "2025-03-03",
                 "source_close" => "48.5",
                 "target_close" => "50",
                 "target_source" => "auto"
               }
             ]
           } = preview["quotes"]

    assert [%{"action" => "move", "classification_name" => "Region"}] =
             preview["configuration"]["category_assignments"]

    assert [%{"action" => "move", "reason" => nil, "target_weight" => "0.2"}] =
             preview["configuration"]["position_targets"]

    assert [%{"kind" => "earnings", "date" => "2026-10-30"}] = preview["events"]["moved"]

    identifiers = preview["identifiers"]
    assert identifiers["choice_required"] == true

    assert %{
             "keep_target_isin" => %{"isin" => @isin_target, "former_isins" => [@isin_source]},
             "adopt_source_isin" => %{"isin" => @isin_source, "former_isins" => [@isin_target]}
           } = identifiers["after_by_identity_choice"]

    assert identifiers["adopted"] == [%{"field" => "wkn", "value" => "HBR001"}]

    assert %{"field" => "ticker_symbol", "source" => "HBRD", "target" => "HBRI"} in identifiers[
             "differences"
           ]

    %{"false" => keep, "true" => collapse} = preview["outcome_by_collapse_key_equal"]
    [position] = keep["positions"]
    assert position["securities_account_id"] == ctx.depot.id
    assert %{"quantity" => "5", "cost_basis" => "250"} = position["source"]
    assert %{"quantity" => "12", "cost_basis" => "600"} = position["target"]
    assert position["after"]["quantity"] == "17"
    assert hd(collapse["positions"])["after"]["quantity"] == "15"
    assert preview["positions_basis"] =~ "moving-average"
    assert preview["reimport_note"] =~ "former ISIN"
    assert journal_mark() == mark
  end

  # User story:
  # As the operator whose agent merged the duplicate I approved,
  # I want the figures and identifiers the API reads right after the merge
  # to be the ones the preview promised, and the merged-away id to name the
  # security I kept,
  # so that what I approved is what I got, and a stale link still leads
  # somewhere.
  #
  # Acceptance criteria:
  # - POST /api/v1/securities/:id/merge with target_id, plan_digest,
  #   collapse_key_equal, identity_choice and isin_changed_on answers 201
  #   with the merge record.
  # - Right after, the holdings show the preview's after-figures; GET
  #   /api/v1/securities/:target carries the preview's identifiers after the
  #   choice made, its former ISINs among the identifier aliases with the
  #   operator's date; its quotes number the target's plus the moved ones.
  # - GET /api/v1/securities/:source answers 404 with errors.merged_into.
  # - A retry answers 200 with the same record and journals nothing.
  test "the apply lands on the preview's figures and identifiers; the source answers merged_into",
       ctx do
    world!(ctx)
    preview = preview!(ctx)
    outcome = preview["outcome_by_collapse_key_equal"]["true"]
    promised = preview["identifiers"]["after_by_identity_choice"]["keep_target_isin"]

    body = %{
      target_id: ctx.target.id,
      plan_digest: preview["plan_digest"],
      collapse_key_equal: true,
      identity_choice: "keep_target_isin",
      isin_changed_on: "2025-05-01"
    }

    assert %{"data" => record, "already_applied" => false} =
             ctx.conn
             |> post("/api/v1/securities/#{ctx.source.id}/merge", body)
             |> json_response(201)

    assert record["kind"] == "security"
    assert record["portfolio_id"] == nil

    assert record["manifest"]["choices"] == %{
             "collapse_key_equal" => true,
             "identity_choice" => "keep_target_isin",
             "isin_changed_on" => "2025-05-01"
           }

    holdings =
      ctx.conn
      |> get("/api/v1/portfolios/#{ctx.portfolio.id}/holdings")
      |> json_response(200)
      |> Map.fetch!("data")

    for %{"securities_account_id" => depot_id, "after" => after_figures} <- outcome["positions"] do
      holding =
        Enum.find(
          holdings,
          &(&1["securities_account_id"] == depot_id and &1["security_id"] == ctx.target.id)
        )

      for field <- ["quantity", "cost_basis", "avg_cost"] do
        assert Decimal.equal?(Decimal.new(holding[field]), Decimal.new(after_figures[field]))
      end
    end

    kept = ctx.conn |> get("/api/v1/securities/#{ctx.target.id}") |> json_response(200)

    for field <- ["isin", "wkn", "ticker_symbol", "name", "asset_class"],
        do: assert(kept["data"][field] == promised[field], field)

    assert Enum.sort(Enum.map(kept["data"]["identifier_aliases"], & &1["former_isin"])) ==
             promised["former_isins"]

    assert [%{"changed_on" => "2025-05-01"}] = kept["data"]["identifier_aliases"]

    quotes =
      ctx.conn
      |> get("/api/v1/securities/#{ctx.target.id}/quotes")
      |> json_response(200)
      |> Map.fetch!("data")

    assert length(quotes) == 1 + preview["quotes"]["moved_count"]

    assert %{"errors" => %{"merged_into" => %{"kind" => "security", "id" => survivor}}} =
             ctx.conn |> get("/api/v1/securities/#{ctx.source.id}") |> json_response(404)

    assert survivor == ctx.target.id

    mark = journal_mark()

    assert %{"data" => again, "already_applied" => true} =
             ctx.conn
             |> post("/api/v1/securities/#{ctx.source.id}/merge", body)
             |> json_response(200)

    assert again["id"] == record["id"]
    assert journal_mark() == mark
  end

  # User story:
  # As the agent whose security merge was refused,
  # I want the answer to name its code and what to do,
  # so that I never retry blindly, never choose for the operator and never
  # half-merge.
  #
  # Acceptance criteria:
  # - Without identity_choice while both carry an ISIN: 422 on
  #   identity_choice naming both ISINs; an unknown choice 422; an
  #   isin_changed_on that is not a date 422; without collapse_key_equal
  #   while pairs exist 422 — each writing nothing.
  # - A source whose imported identity would no longer resolve answers 409
  #   identity_unresolvable with errors.unresolvable naming it.
  # - A stale digest answers 409 plan_changed with the fresh preview; an
  #   unknown source 404; a missing target_id 422.
  test "each refusal answers its code and writes nothing", ctx do
    ctx = world!(ctx)
    preview = preview!(ctx)
    path = "/api/v1/securities/#{ctx.source.id}/merge"
    base = %{target_id: ctx.target.id, plan_digest: preview["plan_digest"]}
    mark = journal_mark()

    assert %{"errors" => %{"identity_choice" => [message]}} =
             ctx.conn
             |> post(path, Map.put(base, :collapse_key_equal, false))
             |> json_response(422)

    assert message =~ @isin_source
    assert message =~ @isin_target

    assert %{
             "errors" => %{"identity_choice" => ["must be keep_target_isin or adopt_source_isin"]}
           } =
             ctx.conn
             |> post(path, Map.merge(base, %{collapse_key_equal: false, identity_choice: "both"}))
             |> json_response(422)

    assert %{"errors" => %{"isin_changed_on" => [_]}} =
             ctx.conn
             |> post(
               path,
               Map.merge(base, %{
                 collapse_key_equal: false,
                 identity_choice: "keep_target_isin",
                 isin_changed_on: "yesterday"
               })
             )
             |> json_response(422)

    assert %{"errors" => %{"collapse_key_equal" => [_]}} =
             ctx.conn
             |> post(path, Map.put(base, :identity_choice, "adopt_source_isin"))
             |> json_response(422)

    assert %{"errors" => %{"target_id" => ["can't be blank"]}} =
             ctx.conn
             |> get("/api/v1/securities/#{ctx.source.id}/merge_preview")
             |> json_response(422)

    assert ctx.conn
           |> get("/api/v1/securities/999999999/merge_preview?target_id=#{ctx.target.id}")
           |> json_response(404)

    assert journal_mark() == mark

    {:ok, _} = Ledger.update_transaction(Actor.owner_ui(), ctx.buy, %{price: "51.00"})

    assert %{"errors" => %{"code" => "plan_changed", "preview" => fresh}} =
             ctx.conn
             |> post(
               path,
               Map.merge(base, %{collapse_key_equal: false, identity_choice: "keep_target_isin"})
             )
             |> json_response(409)

    assert fresh["kind"] == "security"

    {:ok, imported} =
      Catalog.create_security(Actor.import_session(), %{
        name: "Solo Harbour Fund",
        currency_code: "EUR"
      })

    {:ok, _} = Catalog.update_security(Actor.owner_ui(), imported, %{ticker_symbol: "SOLO"})
    mark = journal_mark()

    assert %{"errors" => errors} =
             ctx.conn
             |> get("/api/v1/securities/#{imported.id}/merge_preview?target_id=#{ctx.target.id}")
             |> json_response(409)

    assert errors["code"] == "identity_unresolvable"
    assert errors["detail"] =~ "Solo Harbour Fund"

    imported_id = imported.id

    assert Enum.any?(
             errors["unresolvable"],
             &match?(
               %{
                 "security_id" => ^imported_id,
                 "identity" => "imported",
                 "ref" => %{"name" => "Solo Harbour Fund"}
               },
               &1
             )
           )

    assert journal_mark() == mark
  end

  # User story:
  # As the agent holding an id from before a merge,
  # I want a read of a merged-away security, cash account or depot to answer
  # which row it lives on now, following later merges to the live end,
  # so that I can follow the history instead of losing it.
  #
  # Acceptance criteria:
  # - GET /api/v1/cash_accounts/:id and /securities_accounts/:id of a
  #   merged-away row answer 404 with errors.merged_into {kind, id}.
  # - A security merged into one that was merged again names the last one.
  # - An id no merge names answers the plain 404.
  test "a merged-away id answers 404 with merged_into, following the chain", ctx do
    cash_2 = cash!(ctx.portfolio, "Broker cash 2")

    {:ok, cash_preview} = Lifecycle.preview_cash_merge(cash_2.id, ctx.cash.id)

    {:ok, _record, :applied} =
      Lifecycle.merge_cash_account(Actor.owner_ui(), cash_2.id, ctx.cash.id, %{
        plan_digest: cash_preview.plan_digest
      })

    assert %{"errors" => %{"merged_into" => %{"kind" => "cash_account", "id" => cash_id}}} =
             ctx.conn |> get("/api/v1/cash_accounts/#{cash_2.id}") |> json_response(404)

    assert cash_id == ctx.cash.id

    depot_2 = depot!(ctx.portfolio, ctx.cash, "Depot 2")
    {:ok, depot_preview} = Lifecycle.preview_depot_merge(depot_2.id, ctx.depot.id)

    {:ok, _record, :applied} =
      Lifecycle.merge_depot(Actor.owner_ui(), depot_2.id, ctx.depot.id, %{
        plan_digest: depot_preview.plan_digest
      })

    assert %{
             "errors" => %{"merged_into" => %{"kind" => "securities_account", "id" => depot_id}}
           } = ctx.conn |> get("/api/v1/securities_accounts/#{depot_2.id}") |> json_response(404)

    assert depot_id == ctx.depot.id

    # Each created when the one before is gone: two live securities of one
    # name would leave that name ambiguous, which the merge refuses (§9).
    first = security!(%{name: "Chain Fund"})
    second = security!(%{name: "Chain Fund"})
    merge_security!(first, second)
    last = security!(%{name: "Chain Fund"})
    merge_security!(second, last)

    assert %{"errors" => %{"merged_into" => %{"kind" => "security", "id" => live}}} =
             ctx.conn |> get("/api/v1/securities/#{first.id}") |> json_response(404)

    assert live == last.id

    assert %{"errors" => errors} =
             ctx.conn |> get("/api/v1/securities/999999999") |> json_response(404)

    refute Map.has_key?(errors, "merged_into")
  end

  # --- world ------------------------------------------------------------------

  # The target holds 12 (bought 10 and 2); the source holds 5 (a buy of 3
  # and the same buy of 2 on the same day as the target's, the key-equal
  # pair). Each has a quote on 2025-03-03 (the source's typed by hand); the
  # source also has one on 2025-03-04, a Region assignment, a position
  # target in the active plan and an earnings date.
  defp world!(ctx) do
    buy!(ctx, ctx.target, "10", "50.00", ~D[2025-01-10])
    buy!(ctx, ctx.target, "2", "50.00", ~D[2025-02-01])
    buy = buy!(ctx, ctx.source, "3", "50.00", ~D[2025-01-20])
    buy!(ctx, ctx.source, "2", "50.00", ~D[2025-02-01])

    {:ok, _} =
      Quotes.upsert_many(ctx.target.id, [%{date: ~D[2025-03-03], close: "50.00", source: "auto"}])

    {:ok, _} =
      Catalog.upsert_quotes(Actor.owner_ui(), ctx.source.id, [
        %{"date" => "2025-03-03", "close" => "48.50"}
      ])

    {:ok, _} =
      Quotes.upsert_many(ctx.source.id, [%{date: ~D[2025-03-04], close: "49.00", source: "auto"}])

    {:ok, region} = Classifications.create_classification(Actor.owner_ui(), %{name: "Region"})

    {:ok, europe} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: region.id,
        name: "Europe"
      })

    {:ok, _} =
      Classifications.assign_security(Actor.owner_ui(), ctx.source.id, region.id, europe.id)

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), ctx.portfolio.id, region.id, [
        %{category_id: europe.id, security_id: ctx.source.id, target_weight: "0.2"}
      ])

    {:ok, _} =
      Events.create_event(Actor.owner_ui(), %{
        security_id: ctx.source.id,
        kind: "earnings",
        date: ~D[2026-10-30],
        timing: "exact",
        source_quality: "primary"
      })

    Map.put(ctx, :buy, buy)
  end

  defp preview!(ctx) do
    ctx.conn
    |> get("/api/v1/securities/#{ctx.source.id}/merge_preview?target_id=#{ctx.target.id}")
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp merge_security!(source, target) do
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    {:ok, _record, :applied} =
      Lifecycle.merge_security(Actor.owner_ui(), source.id, target.id, %{
        plan_digest: preview.plan_digest
      })
  end

  defp cash!(portfolio, name) do
    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: "EUR"
      })

    cash
  end

  defp depot!(portfolio, cash, name) do
    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: name
      })

    depot
  end

  defp security!(attrs) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(%{currency_code: "EUR", asset_class: "etf"}, attrs)
      )

    security
  end

  defp buy!(ctx, security, quantity, price, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: ctx.portfolio.id,
        securities_account_id: ctx.depot.id,
        cash_account_id: ctx.cash.id,
        security_id: security.id,
        type: "buy",
        date: date,
        quantity: quantity,
        price: price,
        currency_code: "EUR"
      })

    tx
  end

  defp journal_mark do
    Portfolixir.Repo.one(from(e in Journal.Entry, select: max(e.id))) || 0
  end
end
