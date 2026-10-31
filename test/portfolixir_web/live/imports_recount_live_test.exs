defmodule PortfolixirWeb.ImportsRecountLiveTest do
  # Board 07 ② of the 2026-10-09 pass, pick N20 A (#1180; close to the risk
  # tier, import idempotency): a mapping row's count after the operator's
  # choice. A change starts the page's dry run again under the operator's
  # mapping; while it runs, the changed row's count dims and, once the
  # answer has not come within the seconds-class rule's half second, carries
  # the cue "counted before the choice · recomputing"; its answer is what
  # the confirm then skips and books. The context's equality is pinned in
  # `Portfolixir.Imports.ReimportCountsMappingTest`.
  #
  # The board's world: Test-Cash, Tagesgeld and Depot Muster, imported from
  # Portfolio Performance; then "Tagesgeld" is renamed "Tagesgeld Extra" in
  # Portfolio Performance and exported again. Every name, amount and
  # identifier is synthetic.
  use PortfolixirWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Mapping
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Repo

  @fund %{"name" => "Example Fund", "isin" => "DE000EXMPL17", "currency" => "EUR"}

  # User story (#1180, Sprint 21 γ7, pick N20 A): As the operator who maps a
  # renamed Portfolio Performance account onto the account it was renamed
  # from, I want the row's count to follow my choice, so that "N bookings
  # new" is what the confirm books and not the count made before I chose.
  #
  # Acceptance criteria:
  # - Before the choice the withheld row reads "4 bookings new" (every row
  #   under the new name misses its hash).
  # - Mapped onto Tagesgeld, the row reads "3 bookings already imported ·
  #   1 new" once the recount answers.
  # - The confirm then books exactly the one booking the row counts new and
  #   skips the five the file's rows count already imported: the page's
  #   "Created transactions: 1 · Skipped duplicates: 5", and one booking
  #   more in the ledger.
  test "a row's count follows the operator's choice, and the confirm books what it says",
       %{conn: conn} do
    portfolio = portfolio!()
    applied!(portfolio, history())
    tagesgeld = named!(CashAccount, "Tagesgeld")

    drop =
      history(savings: "Tagesgeld Extra") ++ [interest("Tagesgeld Extra", "1.40", "2026-03-31")]

    {:ok, view, _html} = live(conn, "/imports")
    upload!(view, drop)

    assert count_text(view, "cash", "Tagesgeld Extra") == "4 bookings new"

    view
    |> element("form#pp-import-apply")
    |> render_change(keyed(%{"cash" => %{"Tagesgeld Extra" => "existing:#{tagesgeld.id}"}}))

    render_async(view)

    assert count_text(view, "cash", "Tagesgeld Extra") ==
             "3 bookings already imported · 1 new"

    before = Ledger.count_transactions()
    view |> element("form#pp-import-apply") |> render_submit()
    html = render_async(view, 2_000)

    assert html =~ "Created transactions: 1"
    assert html =~ "Skipped duplicates: 5"
    assert Ledger.count_transactions() == before + 1
  end

  # User story (#1180, Sprint 21 γ7, pick N20 A; board 07, found while
  # drawing 10): As the operator who has just chosen an account, I want the
  # row to say that its count was made before my choice while the recount
  # runs, and to say nothing for a recount that answers at once, so that I
  # neither read the old count as the new one nor see a cue flicker.
  #
  # Acceptance criteria:
  # - While the recount runs, the changed row's count is `aria-busy` at
  #   once and its figure dims (`.stale-value`); the cue is not shown yet.
  # - After half a second without an answer the cue stands under it:
  #   "counted before the choice · recomputing". A row the operator did not
  #   change carries neither.
  # - The answer replaces the count, and the cue and the busy state go.
  test "while the recount runs, the changed row dims at once and carries the cue after half a second",
       %{conn: conn} do
    portfolio = portfolio!()
    applied!(portfolio, history())
    tagesgeld = named!(CashAccount, "Tagesgeld")

    drop =
      history(savings: "Tagesgeld Extra") ++ [interest("Tagesgeld Extra", "1.40", "2026-03-31")]

    {:ok, view, _html} = live(conn, "/imports")
    upload!(view, drop)

    hold_refine!()

    view
    |> element("form#pp-import-apply")
    |> render_change(keyed(%{"cash" => %{"Tagesgeld Extra" => "existing:#{tagesgeld.id}"}}))

    count = row("cash", "Tagesgeld Extra") <> " [data-role='mapping-count']"
    assert has_element?(view, count <> "[aria-busy='true'] .stale-value")
    refute render(view) =~ "counted before the choice"

    Process.sleep(600)

    assert view |> element(count <> " .recomputing-cue") |> render() |> text() ==
             "counted before the choice · recomputing"

    refute has_element?(
             view,
             row("cash", "Test-Cash") <> " [data-role='mapping-count'][aria-busy]"
           )

    release_refine!()
    render_async(view)

    refute has_element?(view, count <> "[aria-busy]")
    refute render(view) =~ "counted before the choice"
    assert count_text(view, "cash", "Tagesgeld Extra") == "3 bookings already imported · 1 new"
  end

  # User story (#1180, Sprint 21 γ7, pick N20 A): As the operator whose
  # choice makes a whole file a re-import, I want the lead note and the
  # cards to follow the recount, while the row I chose keeps its control,
  # so that the page says the import books nothing and I can still change
  # my choice.
  #
  # Acceptance criteria:
  # - The renamed history mapped onto Tagesgeld recounts to "3 bookings
  #   already imported · nothing to create".
  # - The lead note "nothing to import" now leads the preview.
  # - The row keeps its select with the choice selected (a recount never
  #   swaps a row the operator chose for the "No mapping needed" line).
  test "a recount that finds nothing new leads with the note and keeps the chosen row's select",
       %{conn: conn} do
    portfolio = portfolio!()
    applied!(portfolio, history())
    tagesgeld = named!(CashAccount, "Tagesgeld")

    {:ok, view, _html} = live(conn, "/imports")
    upload!(view, history(savings: "Tagesgeld Extra"))

    refute has_element?(view, "[data-role='nothing-to-import']")

    view
    |> element("form#pp-import-apply")
    |> render_change(keyed(%{"cash" => %{"Tagesgeld Extra" => "existing:#{tagesgeld.id}"}}))

    render_async(view)

    assert count_text(view, "cash", "Tagesgeld Extra") ==
             "3 bookings already imported · nothing to create"

    assert has_element?(view, "[data-role='nothing-to-import']")

    assert has_element?(
             view,
             row("cash", "Tagesgeld Extra") <>
               " select[name='cash[#{row_key("cash", "Tagesgeld Extra")}]'] option[selected][value='existing:#{tagesgeld.id}']"
           )
  end

  # --- the exports ---------------------------------------------------------------

  defp history(names \\ []) do
    savings = Keyword.get(names, :savings, "Tagesgeld")

    [
      %{
        "type" => "DEPOSIT",
        "account" => "Test-Cash",
        "date" => "2026-01-02",
        "currency" => "EUR",
        "amount" => num("2000.00")
      },
      %{
        "type" => "CASH_TRANSFER",
        "account" => "Test-Cash",
        "otherAccount" => savings,
        "date" => "2026-01-05",
        "currency" => "EUR",
        "amount" => num("500.00")
      },
      %{
        "type" => "PURCHASE",
        "account" => "Test-Cash",
        "portfolio" => "Depot Muster",
        "date" => "2026-01-15",
        "time" => "10:00",
        "currency" => "EUR",
        "amount" => num("1000.00"),
        "shares" => num("10"),
        "security" => @fund
      },
      interest(savings, "1.25", "2026-01-31"),
      interest(savings, "1.30", "2026-02-28")
    ]
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

  defp num(digits), do: Jason.Fragment.new(digits)

  defp body(rows), do: Jason.encode!(%{"version" => 1, "transactions" => rows})

  defp applied!(portfolio, rows) do
    {:ok, preview} = Imports.parse_portfolio_performance(body(rows), filename: "synthetic.json")
    {:ok, _result} = Imports.apply(preview, %{portfolio_id: portfolio.id})
    :ok
  end

  defp upload!(view, rows) do
    file_input(view, "#pp-import-form", :pp_file, [
      %{
        name: "synthetic.json",
        content: body(rows),
        type: "application/json",
        last_modified: 1_700_000_000_000
      }
    ])
    |> render_upload("synthetic.json")

    render_async(view)
  end

  # The page's dry run, once started on this test's behalf, waits until
  # `release_refine!/0` (the seam ADR-0050's amendment of 2026-10-09 opened).
  defp hold_refine! do
    Application.put_env(:portfolixir, :imports_refine_gate, self())
    on_exit(fn -> Application.delete_env(:portfolixir, :imports_refine_gate) end)
  end

  defp release_refine! do
    assert_receive {:imports_refine_gate, task}, 5_000
    Application.delete_env(:portfolixir, :imports_refine_gate)
    send(task, {:imports_refine_gate, :release})
  end

  # --- reading the page --------------------------------------------------------------

  defp row_key(kind, name), do: Mapping.row_key(kind, name)

  defp row(kind, name), do: "#mapping-#{kind}-#{row_key(kind, name)}"

  defp count_text(view, kind, name) do
    view
    |> element(row(kind, name) <> " [data-role='mapping-count']")
    |> render()
    |> text()
  end

  defp text(html) do
    html
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp keyed(%{} = params) do
    Map.new(params, fn {kind, rows} ->
      {kind, Map.new(rows, fn {name, v} -> {row_key(kind, name), v} end)}
    end)
  end

  # --- the world -------------------------------------------------------------

  defp portfolio! do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "PP Import Target",
        base_currency_code: "EUR"
      })

    portfolio
  end

  defp named!(schema, name), do: Repo.one!(from(a in schema, where: a.name == ^name))
end
