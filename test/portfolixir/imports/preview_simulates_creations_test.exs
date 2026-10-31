defmodule Portfolixir.Imports.PreviewSimulatesCreationsTest do
  # #1203 (Sprint 21 α9; risk-tier: import idempotency, ADR-0036): the
  # preview's security plan resolves every reference of a file as the apply
  # will. The apply resolves each row against a live index that holds the
  # securities the same run created on earlier rows (ADR-0029 §2); the plan
  # resolved every reference against the catalog as it stood, so a later row
  # that matches or conflicts with an earlier row's creation read one way in
  # the preview and went another in the apply. The plan now simulates the
  # run's own creations in file order.
  #
  # The exports are synthetic Portfolio Performance JSON; every name, amount
  # and identifier is invented.
  #
  # async: false: the applier's after-commit enrichment runs in a task that
  # needs the shared sandbox connection.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Isin
  alias Portfolixir.Imports
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Import target",
        base_currency_code: "EUR"
      })

    %{portfolio: portfolio}
  end

  # User story (#1203, Sprint 21 α9):
  # As the operator confirming a file that creates a security on one row and
  # names one alike on a later row,
  # I want the preview to say what the apply will do with the later row,
  # so that what I confirm is what is booked.
  #
  # Acceptance criteria (each case: the plan, then the apply of the same
  # file under the preview's defaults):
  # - "Foo AG" with ISIN XF…1 on row 1 and with ISIN XF…2 on row 2: the plan
  #   shows the first "+ Create new" and the second a decision (a likely
  #   match differs on a stronger identifier: the security row 1 creates);
  #   the apply creates one security and leaves row 2 unresolved.
  # - "Bar Holding" with an ISIN on row 1 and without one on row 2: the plan
  #   shows the second matched by name onto the security row 1 creates; the
  #   apply creates one security and books both rows on it.
  # - The issue's case: "Bar Holding" is in the catalog; row 1 creates "Foo
  #   Neu AG" with WKN FN0001, row 2 names "Bar Holding" with that WKN. The
  #   plan shows row 2 a decision (different identifiers point at different
  #   securities: the one row 1 creates and the stored one); the apply leaves
  #   it unresolved.
  # - In every case the plan's creations are the apply's creations, its
  #   decisions the apply's unresolved rows, and its matches the rows the
  #   apply resolves onto a security.
  test "a later row resolves in the preview as the apply resolves it", %{portfolio: portfolio} do
    vetoed = [buy(1, "Foo AG", isin: isin(1)), buy(2, "Foo AG", isin: isin(2))]
    plan = plan(vetoed)

    assert plan[isin(1)].status == :create
    assert plan[isin(2)].status == :needs_decision
    assert plan[isin(2)].conflict.type == :identifier_veto
    assert Enum.map(plan[isin(2)].candidates, & &1.name) == ["Foo AG"]
    assert_agrees(vetoed, portfolio)

    matched = [buy(3, "Bar Holding", isin: isin(3)), buy(4, "Bar Holding")]
    plan = plan(matched)

    assert plan[isin(3)].status == :create
    assert plan["Bar Holding"].status == :matched
    assert plan["Bar Holding"].matched.tier == :name
    assert plan["Bar Holding"].security.name == "Bar Holding"
    assert_agrees(matched, portfolio)

    {:ok, stored} =
      Catalog.create_security(Actor.owner_ui(), %{name: "Baz Holding", currency_code: "EUR"})

    crossed = [buy(5, "Foo Neu AG", wkn: "FN0001"), buy(6, "Baz Holding", wkn: "FN0001")]
    plan = plan(crossed)

    assert plan["Foo Neu AG"].status == :create
    assert plan["Baz Holding"].status == :needs_decision
    assert plan["Baz Holding"].conflict.type == :cross_tier

    assert plan["Baz Holding"].candidates |> Enum.map(& &1.name) |> Enum.sort() ==
             ["Baz Holding", "Foo Neu AG"]

    assert stored.id in Enum.map(plan["Baz Holding"].candidates, & &1.id)
    assert_agrees(crossed, portfolio)
  end

  # User story (#1203, Sprint 21 α9):
  # As the operator confirming a file whose later row matches a security an
  # earlier row creates,
  # I want the confirm to pass the apply's check of what I approved,
  # so that a preview that now reads the run's own creations never aborts
  # the import it describes.
  #
  # Acceptance criteria:
  # - The plan row matched onto a creation carries the approval the apply
  #   checks against the catalog as it stands: `:create`, as the catalog
  #   alone resolves it; a row matched onto a stored security carries
  #   `{:matched, id}`.
  # - Applied with every plan row's approval, the file creates one security
  #   and books both rows on it.
  test "a row matched onto a creation is approved as the catalog resolves it",
       %{portfolio: portfolio} do
    {:ok, stored} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Qux AG",
        isin: isin(9),
        currency_code: "EUR"
      })

    rows = [
      buy(7, "Bar Holding", isin: isin(7)),
      buy(8, "Bar Holding"),
      buy(9, "Qux AG", isin: isin(9))
    ]

    plan = plan(rows)

    assert plan[isin(7)].approval == :create
    assert plan["Bar Holding"].approval == :create
    assert plan[isin(9)].approval == {:matched, stored.id}

    approved = Map.new(plan, fn {_label, res} -> {res.key, res.approval} end)

    assert {:ok, result} =
             Imports.apply(parse!(rows), %{
               portfolio_id: portfolio.id,
               approved_resolutions: approved
             })

    assert result.created_securities == 1
    assert result.created_transactions == 3
    assert result.unresolved_entries == []
  end

  # The plan agrees with the apply of the same file under the preview's
  # defaults (the auto-resolving apply, which the dry run runs too): its
  # decisions are the apply's unresolved rows, its creations the apply's,
  # and every created or matched row is booked, a matched row on the
  # security it was matched onto.
  defp assert_agrees(rows, portfolio) do
    plan = rows |> plan() |> Map.values()
    created = for res <- plan, res.status == :create, row <- res.rows, do: row
    decided = for res <- plan, res.status == :needs_decision, row <- res.rows, do: row
    matched = for res <- plan, res.status == :matched, do: res
    marker = Repo.one(from(t in Transaction, select: max(t.id))) || 0

    assert {:ok, result} = Imports.apply(parse!(rows), %{portfolio_id: portfolio.id})

    assert result.unresolved_entries |> Enum.map(& &1.row) |> Enum.sort() == Enum.sort(decided)
    assert result.created_securities == length(created)

    assert result.created_transactions ==
             length(created) + Enum.sum(Enum.map(matched, &length(&1.rows)))

    booked_on =
      from(t in Transaction, where: t.id > ^marker, select: t.security_id)
      |> Repo.all()
      |> MapSet.new()

    for res <- matched do
      name = res.security.name
      on = Repo.all(from(s in Catalog.Security, where: s.name == ^name, select: s.id))
      assert Enum.any?(on, &MapSet.member?(booked_on, &1))
    end
  end

  # The plan by label (the ISIN where the reference has one, else its name).
  defp plan(rows) do
    %{resolutions: resolutions} = Imports.resolve_securities(parse!(rows))
    Map.new(resolutions, &{&1.ref.isin || &1.ref.name, &1})
  end

  # --- the exports ---------------------------------------------------------------

  # A synthetic ISIN with a valid check digit.
  defp isin(n) do
    base = "XF" <> String.pad_leading(Integer.to_string(n), 9, "0")
    Enum.find_value(0..9, fn d -> if Isin.valid?(base <> "#{d}"), do: base <> "#{d}" end)
  end

  defp buy(day, name, ids \\ []) do
    security =
      %{"name" => name, "currency" => "EUR"}
      |> put_id("isin", ids[:isin])
      |> put_id("wkn", ids[:wkn])

    %{
      "type" => "PURCHASE",
      "account" => "Synthetic Cash",
      "portfolio" => "Synthetic Depot",
      "date" => Date.to_iso8601(Date.add(~D[2026-01-01], day)),
      "currency" => "EUR",
      "amount" => Jason.Fragment.new("100.00"),
      "shares" => Jason.Fragment.new("1"),
      "security" => security
    }
  end

  defp put_id(security, _field, nil), do: security
  defp put_id(security, field, value), do: Map.put(security, field, value)

  defp parse!(rows) do
    body = Jason.encode!(%{"version" => 1, "transactions" => rows})
    {:ok, preview} = Imports.parse_portfolio_performance(body, filename: "synthetic.json")
    preview
  end
end
