defmodule Portfolixir.Imports.UnseenNameProbeTest do
  # ADR-0050 §2's first limit, and the probe its amendment of 2026-10-07
  # builds (#904; risk-tier: import idempotency, ADR-0036): a file's cash
  # account or depot name is **unknown to the stored history** when none of
  # the rows listed under it has a content hash held by a live transaction or
  # a retired hash, while at least one other name of the same file in the
  # same portfolio has such a hit (point 1). The hash layers
  # `reimport_counts` already reads decide the first pass; the amendment of
  # 2026-10-09 (#1195) lets the refined pass release a name whose importable
  # rows the dry run finds all booked on its resolution, and a stopped dry
  # run releases nothing. Names compare as exact strings after trimming
  # surrounding whitespace (point 6, #973).
  #
  # These tests pin the signal itself; what the preview does with it, and
  # identities P1 to P5 end to end, are pinned in
  # `PortfolixirWeb.ImportsUnseenNameLiveTest`.
  #
  # The exports are synthetic Portfolio Performance JSON; every name, amount
  # and identifier is invented.
  #
  # async: false — the applier's after-commit enrichment runs in a task that
  # needs the shared sandbox connection.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Lifecycle
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount

  @fund %{"name" => "Example Fund", "isin" => "DE000EXMPL17", "currency" => "EUR"}

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Import target",
        base_currency_code: "EUR"
      })

    %{portfolio: portfolio}
  end

  # User story:
  # As the operator who renamed an imported account in Portfolio
  # Performance and dropped its export again,
  # I want the preview to know that no booking was ever imported under the
  # new name, while the file's other names were,
  # so that it can stop the default that would book the account's whole
  # history a second time.
  #
  # Acceptance criteria (amendment point 1; the signal of P1 and P5):
  # - After "Tagesgeld" is renamed "Tagesgeld Extra" in the file (one of its
  #   rows a transfer from "Test-Cash"), "Tagesgeld Extra" is the one name
  #   unknown to the stored history; "Test-Cash" and "Depot Muster", whose
  #   other rows are hash hits, are not.
  # - A depot renamed in the file is unknown the same way.
  # - The first pass (hash layers alone) and the refined pass say the same:
  #   the refined pass books the renamed name's rows on an account it would
  #   create, so they count new.
  describe "a name renamed in Portfolio Performance is unknown to the stored history" do
    test "a renamed cash account, one of its rows a transfer to another account", %{
      portfolio: portfolio
    } do
      applied!(portfolio, history())
      drop = parse!(history(savings: "Tagesgeld Extra"))

      for dry_run <- [false, true] do
        counts = Imports.reimport_counts(drop, portfolio_id: portfolio.id, dry_run: dry_run)

        assert counts.unseen_names == %{cash_accounts: ["Tagesgeld Extra"], depots: []}
        assert %{hash: 0, retired: 0} = counts.cash_accounts["Tagesgeld Extra"]
        assert counts.cash_accounts["Test-Cash"].hash == 2
      end
    end

    test "a renamed depot", %{portfolio: portfolio} do
      applied!(portfolio, history())
      drop = parse!(history(depot: "Depot Muster Neu"))

      for dry_run <- [false, true] do
        assert Imports.reimport_counts(drop, portfolio_id: portfolio.id, dry_run: dry_run).unseen_names ==
                 %{cash_accounts: [], depots: ["Depot Muster Neu"]}
      end
    end
  end

  # User story:
  # As the operator importing a file for the first time, or an export of
  # only new bookings,
  # I want the preview's prefill to stay as it is,
  # so that the probe costs nothing where no history could be booked twice.
  #
  # Acceptance criteria (amendment point 4; the signal of P3 and P4):
  # - A file in which no name has a hit names nothing — on a fresh portfolio,
  #   and with accounts of those names created by hand.
  # - A file in which every name has a hit names nothing, a new booking
  #   among them.
  describe "when the probe does not trip" do
    test "no name of the file has a hit", %{portfolio: portfolio} do
      first = parse!(history())

      assert Imports.reimport_counts(first, portfolio_id: portfolio.id).unseen_names ==
               %{cash_accounts: [], depots: []}

      cash!(portfolio, "Test-Cash")
      cash!(portfolio, "Tagesgeld")

      assert Imports.reimport_counts(first, portfolio_id: portfolio.id).unseen_names ==
               %{cash_accounts: [], depots: []}
    end

    test "every name of the file has a hit", %{portfolio: portfolio} do
      applied!(portfolio, history())
      newer = parse!(history() ++ [interest("Tagesgeld", "1.40", "2026-03-31")])

      counts = Imports.reimport_counts(newer, portfolio_id: portfolio.id)

      assert counts.unseen_names == %{cash_accounts: [], depots: []}
      assert counts.cash_accounts["Tagesgeld"].new == 1
    end
  end

  # User story:
  # As the operator whose file repeats a booking exactly,
  # I want such a repeat not to count as a booking the stored history
  # holds,
  # so that a first import is never mistaken for a file that overlaps it.
  #
  # Acceptance criteria (point 1, "held by a live transaction or a retired
  # hash"):
  # - On a fresh portfolio, a file in which "Test-Cash" repeats one deposit
  #   counts that repeat as a hash hit for the row (what the apply will do)
  #   but names no name unknown: nothing is stored.
  test "a repeat inside the file is not a hit of the stored history", %{portfolio: portfolio} do
    rows = history() ++ [deposit("Test-Cash", "2000.00", "2026-01-02")]
    counts = Imports.reimport_counts(parse!(rows), portfolio_id: portfolio.id)

    assert counts.cash_accounts["Test-Cash"].hash == 1
    assert counts.unseen_names == %{cash_accounts: [], depots: []}
  end

  # User story (found by the α closing act, edge-case hunter EC-F3):
  # As the operator whose export holds a booking the import never books (a
  # fee of 0.00) under a name of its own,
  # I want that name not to count as unknown to the stored history,
  # so that a row the apply skips before any name resolves never makes me
  # map an account nothing will be booked on.
  #
  # Acceptance criteria:
  # - The history applied, then dropped again with a fee of 0.00 on
  #   "Spesenkonto" (unimportable: a cash kind without a positive amount),
  #   names no name unknown, in the first pass and the refined one; the row
  #   counts as unimportable under the name.
  # - So does a removal without an amount on "Nebenkonto" whose negative
  #   tax splits a refund off: the refund is skipped with its row.
  test "a name whose only rows are unimportable is not unknown", %{portfolio: portfolio} do
    applied!(portfolio, history())

    removal = %{
      "type" => "REMOVAL",
      "account" => "Nebenkonto",
      "date" => "2026-02-16",
      "currency" => "EUR",
      "units" => [%{"type" => "TAX", "amount" => num("-1.00")}]
    }

    drop = parse!(history() ++ [fee("Spesenkonto", "0.00", "2026-02-15"), removal])
    assert drop.errors == []

    for dry_run <- [false, true] do
      counts = Imports.reimport_counts(drop, portfolio_id: portfolio.id, dry_run: dry_run)

      assert counts.cash_accounts["Spesenkonto"].unimportable == 1
      assert counts.cash_accounts["Nebenkonto"].unimportable == 2
      assert counts.unseen_names == %{cash_accounts: [], depots: []}
    end
  end

  # User story:
  # As the operator re-importing after a merge removed a booking,
  # I want a name whose only booking is a retired content hash to count as
  # known,
  # so that a merge never makes a file's names look renamed.
  #
  # Acceptance criteria (point 1, "or a retired hash"):
  # - "Festgeld" names only a transfer from "Test-Cash"; after "Festgeld" is
  #   merged into "Test-Cash", that transfer is removed and its hash retired.
  #   Dropping the same file again names no name unknown.
  test "a retired hash is a hit", %{portfolio: portfolio} do
    rows = [
      deposit("Test-Cash", "2000.00", "2026-01-02"),
      transfer("Test-Cash", "Festgeld", "300.00", "2026-01-05")
    ]

    applied!(portfolio, rows)

    {:ok, preview} =
      Lifecycle.preview_cash_merge(named!("Festgeld").id, named!("Test-Cash").id)

    {:ok, _record, :applied} =
      Lifecycle.merge_cash_account(agent(), named!("Festgeld").id, named!("Test-Cash").id, %{
        plan_digest: preview.plan_digest,
        collapse_key_equal: false
      })

    counts = Imports.reimport_counts(parse!(rows), portfolio_id: portfolio.id)

    assert counts.cash_accounts["Festgeld"].retired == 1
    assert counts.unseen_names == %{cash_accounts: [], depots: []}
  end

  # User story (#1195, Sprint 21 α8; ADR-0050 as amended on 2026-10-09, P8):
  # As the operator who re-drops an export whose rows under one name drifted
  # (a time moved), or who renamed an account in Portfolixir and in
  # Portfolio Performance alike,
  # I want a name whose rows the dry run finds all booked on its resolution
  # to count as known once the dry run answers,
  # so that a drop that would book nothing under the name stops asking on
  # every drop.
  #
  # Acceptance criteria (amendment point 1):
  # - The purchase re-exported at 10:30 instead of 10:00: the first pass
  #   (hash layers alone) names "Depot Muster" unknown; the refined pass,
  #   which finds the purchase already booked on Depot Muster against
  #   Test-Cash, names nothing. Its row counts economics 1, new 0.
  # - "Tagesgeld" renamed "Tagesgeld Extra" on both sides: the first pass
  #   names "Tagesgeld Extra"; the refined pass, which counts its three rows
  #   economics, names nothing.
  test "a name whose rows are all booked on its resolution is known once the dry run answers",
       %{portfolio: portfolio} do
    applied!(portfolio, history())
    drifted = parse!(history(time: "10:30"))

    assert Imports.reimport_counts(drifted, portfolio_id: portfolio.id, dry_run: false).unseen_names ==
             %{cash_accounts: [], depots: ["Depot Muster"]}

    refined = Imports.reimport_counts(drifted, portfolio_id: portfolio.id)

    assert %{hash: 0, retired: 0, economics: 1, new: 0} = refined.depots["Depot Muster"]
    assert refined.unseen_names == %{cash_accounts: [], depots: []}

    {:ok, _renamed} =
      Portfolios.update_cash_account(agent(), named!("Tagesgeld"), %{name: "Tagesgeld Extra"})

    both = parse!(history(savings: "Tagesgeld Extra"))

    assert Imports.reimport_counts(both, portfolio_id: portfolio.id, dry_run: false).unseen_names ==
             %{cash_accounts: ["Tagesgeld Extra"], depots: []}

    refined = Imports.reimport_counts(both, portfolio_id: portfolio.id)

    assert %{hash: 0, retired: 0, economics: 3, new: 0} =
             refined.cash_accounts["Tagesgeld Extra"]

    assert refined.unseen_names == %{cash_accounts: [], depots: []}
  end

  # User story (#1195, Sprint 21 α8; ADR-0050 as amended on 2026-10-09, P9):
  # As the operator whose renamed account carries one booking the stored
  # history lacks,
  # I want the name to stay unknown after the dry run answers,
  # so that a name whose rows would book anything still asks before the
  # history lands anywhere.
  #
  # Acceptance criteria (amendment point 4):
  # - "Tagesgeld" renamed "Tagesgeld Extra" on both sides, and the export
  #   adds 1.35 EUR of interest on 2026-03-31: the refined pass counts
  #   economics 3, new 1, and still names "Tagesgeld Extra".
  # - The rename the stored history never saw (P1): the dry run books the
  #   three rows on an account it would create, so they count new, and the
  #   name stays unknown.
  test "a name booked but for one new row stays unknown", %{portfolio: portfolio} do
    applied!(portfolio, history())

    unseen = parse!(history(savings: "Tagesgeld Extra"))

    assert Imports.reimport_counts(unseen, portfolio_id: portfolio.id).unseen_names ==
             %{cash_accounts: ["Tagesgeld Extra"], depots: []}

    {:ok, _renamed} =
      Portfolios.update_cash_account(agent(), named!("Tagesgeld"), %{name: "Tagesgeld Extra"})

    newer =
      parse!(
        history(savings: "Tagesgeld Extra") ++ [interest("Tagesgeld Extra", "1.35", "2026-03-31")]
      )

    refined = Imports.reimport_counts(newer, portfolio_id: portfolio.id)

    assert %{hash: 0, retired: 0, economics: 3, new: 1} =
             refined.cash_accounts["Tagesgeld Extra"]

    assert refined.unseen_names == %{cash_accounts: ["Tagesgeld Extra"], depots: []}
  end

  # User story (#1195, Sprint 21 α8; ADR-0050 as amended on 2026-10-09, P7):
  # As the operator who mapped a renamed name onto its old account with
  # "Remember this mapping" ticked,
  # I want the remembered former name to vouch for nothing on its own,
  # so that a name Portfolio Performance has since given to another account
  # is never prefilled onto the wrong one.
  #
  # Acceptance criteria (amendment point 3):
  # - P1's file applied with "Tagesgeld Extra" mapped onto Tagesgeld and
  #   remembered (it inserts nothing). A later export that adds 1.35 EUR of
  #   interest on 2026-03-31 under "Tagesgeld Extra" still names it unknown
  #   after the dry run answers: economics 3, new 1.
  # - P1's file without the new booking is named by the first pass and
  #   released by the refined one.
  test "a former name alone does not make a name known", %{portfolio: portfolio} do
    applied!(portfolio, history())
    tagesgeld = named!("Tagesgeld")
    renamed = history(savings: "Tagesgeld Extra")

    assert {:ok, %Result{created_transactions: 0}} =
             Imports.apply(parse!(renamed), %{
               portfolio: {:existing, portfolio.id},
               cash_accounts: %{
                 "Test-Cash" => {:existing, named!("Test-Cash").id},
                 "Tagesgeld Extra" => {:existing, tagesgeld.id}
               },
               depots: %{
                 "Depot Muster" => %{
                   target: {:existing, depot_named!("Depot Muster").id},
                   cash: "Test-Cash"
                 }
               }
             })

    assert Repo.reload!(tagesgeld).former_names == ["Tagesgeld Extra"]

    later = parse!(renamed ++ [interest("Tagesgeld Extra", "1.35", "2026-03-31")])
    refined = Imports.reimport_counts(later, portfolio_id: portfolio.id)

    assert %{hash: 0, economics: 3, new: 1} = refined.cash_accounts["Tagesgeld Extra"]
    assert refined.unseen_names == %{cash_accounts: ["Tagesgeld Extra"], depots: []}

    same = parse!(renamed)

    assert Imports.reimport_counts(same, portfolio_id: portfolio.id, dry_run: false).unseen_names ==
             %{cash_accounts: ["Tagesgeld Extra"], depots: []}

    assert Imports.reimport_counts(same, portfolio_id: portfolio.id).unseen_names ==
             %{cash_accounts: [], depots: []}
  end

  # User story (#1195, Sprint 21 α8; ADR-0050 as amended on 2026-10-09, P10):
  # As the operator whose file carries a name two of my accounts share from
  # before the name guard,
  # I want a dry run that stops to release nothing,
  # so that a name is never prefilled on counts the apply's own run did not
  # finish.
  #
  # Acceptance criteria (amendment point 2):
  # - P8's drifted drop with a new deposit of 300.00 EUR under "Festgeld",
  #   which two accounts carry: the dry run stops, the counts stay on the
  #   hash layers (the purchase counts new, not economics), and both
  #   "Festgeld" and "Depot Muster" stay unknown.
  test "a stopped dry run releases nothing", %{portfolio: portfolio} do
    applied!(portfolio, history())
    legacy_cash!(portfolio, "Festgeld")
    legacy_cash!(portfolio, "Festgeld")

    drop = parse!(history(time: "10:30") ++ [deposit("Festgeld", "300.00", "2026-03-02")])
    refined = Imports.reimport_counts(drop, portfolio_id: portfolio.id)

    assert %{economics: 0, new: 1} = refined.depots["Depot Muster"]
    assert refined.unseen_names == %{cash_accounts: ["Festgeld"], depots: ["Depot Muster"]}
  end

  # User story:
  # As the operator whose Portfolio Performance names are exact,
  # I want a name that differs from a stored one only in letter case,
  # Unicode form or inner whitespace to count as another name, and a name
  # padded with spaces as the same one,
  # so that the probe compares names exactly as resolution and the guard do
  # (#973).
  #
  # Acceptance criteria (amendment point 6):
  # - "TAGESGELD", "Tages  geld" and "Tagesgeld" in decomposed Unicode
  #   ("Tagesgeld" has none to decompose, so "Café-Konto" stands in) are each
  #   unknown to the stored history.
  # - " Tagesgeld " is "Tagesgeld" after trimming, and is known.
  test "names compare as exact strings after trimming", %{portfolio: portfolio} do
    applied!(portfolio, history(savings: "Café-Konto"))
    applied!(portfolio, history())

    nfd = :unicode.characters_to_nfd_binary("Café-Konto")
    refute nfd == "Café-Konto"

    for variant <- ["TAGESGELD", "Tages  geld", nfd] do
      assert Imports.reimport_counts(parse!(history(savings: variant)),
               portfolio_id: portfolio.id
             ).unseen_names == %{cash_accounts: [variant], depots: []},
             variant
    end

    assert Imports.reimport_counts(parse!(history(savings: " Tagesgeld ")),
             portfolio_id: portfolio.id
           ).unseen_names == %{cash_accounts: [], depots: []}
  end

  # --- the exports ---------------------------------------------------------------

  # The history the instance imported: Test-Cash, Tagesgeld and Depot
  # Muster (board 01 ①). `names` renames any of them as Portfolio
  # Performance would export it after a rename; `time` moves the purchase,
  # as a drifted re-export does.
  defp history(names \\ []) do
    cash = Keyword.get(names, :cash, "Test-Cash")
    savings = Keyword.get(names, :savings, "Tagesgeld")
    depot = Keyword.get(names, :depot, "Depot Muster")
    time = Keyword.get(names, :time, "10:00")

    [
      deposit(cash, "2000.00", "2026-01-02"),
      transfer(cash, savings, "500.00", "2026-01-05"),
      %{
        "type" => "PURCHASE",
        "account" => cash,
        "portfolio" => depot,
        "date" => "2026-01-15",
        "time" => time,
        "currency" => "EUR",
        "amount" => num("1000.00"),
        "shares" => num("10"),
        "security" => @fund
      },
      interest(savings, "1.25", "2026-01-31"),
      interest(savings, "1.30", "2026-02-28")
    ]
  end

  defp deposit(account, amount, date) do
    %{
      "type" => "DEPOSIT",
      "account" => account,
      "date" => date,
      "currency" => "EUR",
      "amount" => num(amount)
    }
  end

  defp transfer(from, to, amount, date) do
    %{
      "type" => "CASH_TRANSFER",
      "account" => from,
      "otherAccount" => to,
      "date" => date,
      "currency" => "EUR",
      "amount" => num(amount)
    }
  end

  defp fee(account, amount, date) do
    %{
      "type" => "FEE",
      "account" => account,
      "date" => date,
      "currency" => "EUR",
      "amount" => num(amount)
    }
  end

  defp interest(account, amount, date) do
    %{
      "type" => "INTEREST",
      "account" => account,
      "date" => date,
      "currency" => "EUR",
      "amount" => num(amount)
    }
  end

  # A JSON number written as its literal digits, never through a float.
  defp num(digits), do: Jason.Fragment.new(digits)

  defp parse!(rows) do
    body = Jason.encode!(%{"version" => 1, "transactions" => rows})
    {:ok, preview} = Imports.parse_portfolio_performance(body, filename: "synthetic.json")
    preview
  end

  defp applied!(portfolio, rows) do
    assert {:ok, %Result{}} = Imports.apply(parse!(rows), %{portfolio_id: portfolio.id})
  end

  # --- the world -------------------------------------------------------------

  defp named!(name), do: Repo.one!(from(a in CashAccount, where: a.name == ^name))

  defp depot_named!(name), do: Repo.one!(from(a in SecuritiesAccount, where: a.name == ^name))

  # A duplicate name from before the name guard, inserted the way the old
  # writer did.
  defp legacy_cash!(portfolio, name) do
    {:ok, %{account: account}} =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(
        :account,
        Ecto.Changeset.change(%CashAccount{}, %{
          portfolio_id: portfolio.id,
          name: name,
          currency_code: "EUR"
        })
      )
      |> Portfolixir.Journal.record(Actor.owner_ui(),
        resource_type: "cash_account",
        operation: :create,
        source: :account
      )
      |> Repo.transaction()

    account
  end

  defp cash!(portfolio, name) do
    {:ok, cash} =
      Portfolios.create_cash_account(agent(), %{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: "EUR"
      })

    cash
  end
end
