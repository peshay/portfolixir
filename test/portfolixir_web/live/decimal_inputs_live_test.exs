defmodule PortfolixirWeb.DecimalInputsLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Repo
  alias Portfolixir.Tax

  # Board ux-design-2026-09-24/05-numeric-inputs (#869, the numeric half).
  # Synthetic figures only: 1 EUR = 1.10 USD on the booking date.

  defp german(conn), do: Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")

  defp open_booking(conn) do
    {:ok, view, _html} = live(conn, "/transactions")
    view |> element("#open-booking") |> render_click()
    view
  end

  defp change(view, params, target) do
    view
    |> element("#transaction-form")
    |> render_change(%{"_target" => ["transaction", target], "transaction" => params})
  end

  defp input(view, form, name) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(~s(#{form} input[name="#{name}"]))
  end

  defp input_value(view, form, name) do
    view |> input(form, name) |> Floki.attribute("value") |> List.first()
  end

  defp trade(world, security, overrides) do
    Map.merge(
      %{
        "type" => "buy",
        "date" => "2026-04-01",
        "securities_account_id" => to_string(world.depot.id),
        "security_id" => to_string(security.id),
        "quantity" => "10",
        "price" => "200",
        "fees" => "",
        "taxes" => "",
        "notes" => ""
      },
      overrides
    )
  end

  defp usd_world do
    world = base_world(name: "Zahlen", cash_name: "Girokonto", depot_name: "Depot 1")
    usd = create_security!(name: "Kestrel Industrial Group NV", ticker: "KIG", currency: "USD")
    eur = create_security!(name: "Heron Test AG", ticker: "HTA", currency: "EUR")

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-04-01],
          rate: "1.10",
          source: "manual"
        }
      ])

    %{world: world, usd: usd, eur: eur}
  end

  # User story (#869; board 05, "Buchungsschublade"):
  # As the operator booking a cross-currency trade on a German page,
  # I want the prefilled settlement amount and rate to read like the figures I
  # type — with a decimal comma — and every figure of the drawer to stand
  # right-aligned in tabular digits,
  # so that one form does not carry two ways of writing a number.
  #
  # Acceptance criteria:
  # - The prefilled amount reads "1818,18", the derived rate "0,909091".
  # - A typed amount derives the rate in the page's locale ("0,9"), and the
  #   typed amount itself stays as typed.
  # - Quantity, price, fees, taxes, amount and rate each carry class "num".
  # - On an English page the same prefill reads with a point.
  test "the settlement block renders its prefill in the page's locale", %{conn: conn} do
    %{world: w, usd: usd} = usd_world()

    view = conn |> german() |> open_booking()
    change(view, trade(w, usd, %{}), "security_id")

    assert input_value(view, "#transaction-form", "transaction[settlement_amount]") == "1818,18"
    assert input_value(view, "#transaction-form", "transaction[settlement_fx_rate]") == "0,909091"

    change(view, trade(w, usd, %{"settlement_amount" => "1800"}), "settlement_amount")
    assert input_value(view, "#transaction-form", "transaction[settlement_fx_rate]") == "0,9"
    assert input_value(view, "#transaction-form", "transaction[settlement_amount]") == "1800"

    for field <- ~w(quantity price fees taxes settlement_amount settlement_fx_rate) do
      classes =
        view |> input("#transaction-form", "transaction[#{field}]") |> Floki.attribute("class")

      assert classes != [] and hd(classes) =~ "num", "#{field} carries no class num"
    end

    english = open_booking(conn)
    change(english, trade(w, usd, %{}), "security_id")

    assert input_value(english, "#transaction-form", "transaction[settlement_amount]") ==
             "1818.18"

    assert input_value(english, "#transaction-form", "transaction[settlement_fx_rate]") ==
             "0.909091"
  end

  # User story (#869; board 05, "Preis, beim Bearbeiten"):
  # As the operator correcting a stored booking on a German page,
  # I want its figures to open with a decimal comma,
  # so that the edit drawer reads like the one I booked it in.
  #
  # Acceptance criteria:
  # - A stored price of 45.6 opens as "45,6" (the digits as stored, only the
  #   separator swapped); a quantity of 40 as "40".
  # - Saved unchanged, the booking keeps its figures exactly.
  test "an edited booking opens with its figures in the page's locale", %{conn: conn} do
    %{world: w, eur: eur} = usd_world()
    tx = buy!(w, eur, quantity: "40", price: "45.6", fees: "1.5", date: ~D[2026-04-01])

    view = conn |> german() |> open_booking()
    render_click(view, "edit_transaction", %{"id" => to_string(tx.id)})

    assert input_value(view, "#transaction-form", "transaction[price]") == "45,6"
    assert input_value(view, "#transaction-form", "transaction[quantity]") == "40"
    assert input_value(view, "#transaction-form", "transaction[fees]") == "1,5"

    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" =>
        trade(w, eur, %{
          "quantity" => "40",
          "price" => "45,6",
          "fees" => "1,5",
          "date" => "2026-04-01"
        })
    })

    stored = Repo.get!(Transaction, tx.id)
    assert Decimal.equal?(stored.price, Decimal.new("45.6"))
    assert Decimal.equal?(stored.fees, Decimal.new("1.5"))
  end

  # User story (#869; board 05, "Warum ohne Tausenderpunkt"):
  # As the operator typing a figure,
  # I want a figure that reads two ways to be refused and named on its field,
  # so that "1.664" on a German page is never stored as 1.664 when I meant
  # 1664, nor "1,664" on an English page the other way round.
  #
  # Acceptance criteria:
  # - Nothing is booked; the quantity field carries the reason in the page's
  #   language and aria-invalid.
  # - Every figure stays exactly as typed ("1.664", "45,60").
  test "a figure that reads two ways is refused on its field", %{conn: conn} do
    %{world: w, eur: eur} = usd_world()

    view = conn |> german() |> open_booking()

    html =
      view
      |> element("#transaction-form")
      |> render_submit(%{
        "transaction" => trade(w, eur, %{"quantity" => "1.664", "price" => "45,60"})
      })

    assert Repo.all(Transaction) == []
    assert html =~ "ist mehrdeutig: ohne Tausendertrennzeichen eingeben"

    assert [_] =
             Floki.find(
               Floki.parse_document!(html),
               ~s(input[name="transaction[quantity]"][aria-invalid="true"])
             )

    assert input_value(view, "#transaction-form", "transaction[quantity]") == "1.664"
    assert input_value(view, "#transaction-form", "transaction[price]") == "45,60"

    english = open_booking(conn)

    html =
      english
      |> element("#transaction-form")
      |> render_submit(%{"transaction" => trade(w, eur, %{"fees" => "1,250"})})

    assert Repo.all(Transaction) == []
    assert html =~ "is ambiguous: enter it without a thousands separator"
  end

  # User story (#869; board 05, "Getipptes wird nicht umgeschrieben"):
  # As the operator whose booking was refused for another reason,
  # I want the figures I typed to come back exactly as I typed them,
  # so that a refusal does not rewrite "2,5" into "2.5" behind my back.
  test "a refused booking keeps the figures as typed", %{conn: conn} do
    %{world: w, eur: eur} = usd_world()

    view = conn |> german() |> open_booking()

    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" => trade(w, eur, %{"quantity" => "2,5", "price" => "", "fees" => "0,99"})
    })

    assert Repo.all(Transaction) == []
    assert input_value(view, "#transaction-form", "transaction[quantity]") == "2,5"
    assert input_value(view, "#transaction-form", "transaction[fees]") == "0,99"
  end

  # User story (#869, Lane C review round DC-C1):
  # As the operator whose fee was refused,
  # I want the costs section to stay open while I correct the fee,
  # so that my first keystroke does not fold it shut around the field I am
  # typing in.
  #
  # Acceptance criteria:
  # - A refused fee opens the costs section and names the reason there.
  # - The section carries the DisclosureState hook: LiveView removes every
  #   attribute the server does not render, `open` included, so the hook
  #   remembers the toggle — the operator's or the server's — and restores it
  #   after each patch. (LiveViewTest does not run the client patch; the
  #   hook's contract is pinned on its source.)
  test "a refused fee opens the costs, and a patch does not fold them", %{conn: conn} do
    %{world: w, eur: eur} = usd_world()

    view = conn |> german() |> open_booking()

    assert has_element?(view, ~s(details#transaction-costs[phx-hook="DisclosureState"]))
    refute has_element?(view, "details#transaction-costs[open]")

    view
    |> element("#transaction-form")
    |> render_submit(%{"transaction" => trade(w, eur, %{"fees" => "1.664"})})

    assert has_element?(view, "details#transaction-costs[open] #tx-error-fees")

    hook = hook_source("DisclosureState")
    assert hook =~ ~r/mounted: function \(\) \{.*this\.open = this\.el\.open;/s
    assert hook =~ ~r/addEventListener\("toggle", this\.onToggle\)/
    assert hook =~ ~r/self\.open = self\.el\.open;/

    assert hook =~
             ~r/updated: function \(\) \{\s*if \(this\.open && !this\.el\.open\) this\.el\.setAttribute\("open", ""\);/s

    assert hook =~ ~r/removeEventListener\("toggle", this\.onToggle\)/
  end

  # A hook's source in layout_view.ex, up to the next hook.
  defp hook_source(name) do
    "lib/portfolixir_web/layout_view.ex"
    |> File.read!()
    |> String.split("Hooks.#{name} = ")
    |> Enum.at(1, "")
    |> String.split("Hooks.")
    |> hd()
  end

  defp rule_world do
    world = base_world(name: "Regeln")

    nordic =
      create_security!(name: "Nordic Timber Holdings AB", ticker: "NTH", asset_class: "equity")

    buy!(world, nordic,
      quantity: "10",
      price: "124",
      date: Date.add(Portfolixir.Clock.today(), -5)
    )

    put_quote!(nordic, Date.add(Portfolixir.Clock.today(), -5), "124")

    {:ok, rule} =
      PolicyRules.create_rule(
        Actor.owner_ui(),
        %{
          portfolio_id: world.portfolio.id,
          name: "Einzeltitel begrenzen",
          version: %{
            subject_type: "security",
            security_id: nordic.id,
            measure: "weight",
            kind: "cap",
            threshold: "7.5",
            severity: "hard",
            valid_from: Date.add(Portfolixir.Clock.today(), -3)
          }
        },
        today: Date.add(Portfolixir.Clock.today(), -3)
      )

    %{world: world, rule: rule}
  end

  # User story (#869; board 05, "Regeldialog"):
  # As the operator changing a rule's line on a German page,
  # I want the line to open as "7,5" — as the sentence below it and the
  # version list write it — and to accept "12,5",
  # so that the dialog shows one number one way.
  #
  # Acceptance criteria:
  # - The line opens as "7,5" on a German page and "7.5" on an English one.
  # - "12,5" saves a version with 12.5; a grouped "1.000" is refused on its
  #   field and saves nothing.
  test "the rule dialog's line reads and saves in the page's locale", %{conn: conn} do
    %{rule: rule} = rule_world()

    {:ok, view, _html} = live(german(conn), "/risk")
    view |> element("#policy-findings button[phx-value-id='#{rule.id}']") |> render_click()
    assert input_value(view, "#policy-rule-form", "rule[threshold]") == "7,5"

    html = view |> form("#policy-rule-form", rule: %{threshold: "1.000"}) |> render_submit()
    assert html =~ "ist mehrdeutig"
    assert length(PolicyRules.get_rule(rule.id).versions) == 1

    view |> form("#policy-rule-form", rule: %{threshold: "12,5"}) |> render_submit()
    refute has_element?(view, "dialog#policy-rule-dialog")

    latest = rule.id |> PolicyRules.get_rule() |> Map.fetch!(:versions) |> List.last()
    assert Decimal.equal?(latest.threshold, Decimal.new("12.5"))

    {:ok, english, _html} = live(conn, "/risk")
    english |> element("#policy-findings button[phx-value-id='#{rule.id}']") |> render_click()
    assert input_value(english, "#policy-rule-form", "rule[threshold]") =~ ~r/\A\d+(\.\d+)?\z/
  end

  # User story (#869, Lane C review round DC-C4; UX-DR13):
  # As the operator using a screen reader in the rule dialog or the
  # set-balance dialog,
  # I want a refused figure's reason to be announced and tied to its field,
  # as the booking drawer, the settlement block and Tax already do,
  # so that I hear which field to fix and why.
  #
  # Acceptance criteria:
  # - A refused line, from or to in the rule dialog carries aria-invalid and
  #   aria-describedby naming its error, which has that id and role="alert".
  # - A refused balance amount carries aria-invalid and aria-describedby
  #   naming the dialog's error (role="alert"); the date does not, and a
  #   refused date is tied to the date field instead.
  test "a refused figure in the rule and balance dialogs is tied to its field", %{conn: conn} do
    %{rule: rule} = rule_world()

    {:ok, view, _html} = live(german(conn), "/risk")
    view |> element("#policy-findings button[phx-value-id='#{rule.id}']") |> render_click()

    view |> form("#policy-rule-form", rule: %{threshold: "1.000"}) |> render_submit()

    assert has_element?(
             view,
             ~s(#policy-rule-form input[name="rule[threshold]"][aria-invalid="true"][aria-describedby="rule-error-threshold"])
           )

    assert has_element?(view, ~s(#policy-rule-form #rule-error-threshold[role="alert"]))

    view |> form("#policy-rule-form", rule: %{kind: "band"}) |> render_change()

    view
    |> form("#policy-rule-form", rule: %{kind: "band", lower: "1.000", upper: "2.500"})
    |> render_submit()

    for field <- ~w(lower upper) do
      assert has_element?(
               view,
               ~s(#policy-rule-form input[name="rule[#{field}]"][aria-invalid="true"][aria-describedby="rule-error-#{field}"])
             )

      assert has_element?(view, ~s(#policy-rule-form #rule-error-#{field}[role="alert"]))
    end

    %{world: w} = usd_world()
    {:ok, accounts, _html} = live(german(conn), "/portfolios")
    accounts |> element("#set-balance-#{w.cash.id}") |> render_click()

    accounts
    |> form("#balance-dialog form", %{"balance" => %{"date" => "2026-04-01", "amount" => "1.250"}})
    |> render_submit()

    assert has_element?(
             accounts,
             ~s(#balance-dialog input[name="balance[amount]"][aria-invalid="true"][aria-describedby="balance-error"])
           )

    assert has_element?(accounts, ~s(#balance-dialog #balance-error[role="alert"]))
    refute has_element?(accounts, ~s(#balance-dialog input[name="balance[date]"][aria-invalid]))

    accounts
    |> form("#balance-dialog form", %{"balance" => %{"date" => "2026-02-30", "amount" => "10"}})
    |> render_submit()

    assert has_element?(
             accounts,
             ~s(#balance-dialog input[name="balance[date]"][aria-invalid="true"][aria-describedby="balance-error"])
           )

    refute has_element?(accounts, ~s(#balance-dialog input[name="balance[amount]"][aria-invalid]))
  end

  # User story (#869; board 05, "Steuern"):
  # As the operator copying a German tax statement into the app,
  # I want its figures to be accepted as printed — "12000,00", "140,25" —
  # and a statement I correct to open with them,
  # so that the Tax page does not refuse the decimal comma the rest of the
  # app accepts.
  #
  # Acceptance criteria:
  # - The statement and the Freistellungsauftrag store the typed figures.
  # - A correction opens with its figures in the page's locale, trailing
  #   zeros dropped ("12000", "140,25").
  # - A grouped "1.000" is refused and nothing is stored.
  test "the tax forms read and show figures in the page's locale", %{conn: conn} do
    {:ok, view, _html} = live(german(conn), "/tax?holder=Owner&year=2025")

    view
    |> form("#tax-statement-form", %{
      "statement" => %{
        "institution" => "Beispielbank",
        "as_of" => "2025-12-31",
        "taxable_income" => "12000,00",
        "solidarity_surcharge_withheld" => "140,25"
      }
    })
    |> render_submit()

    [stored] = Tax.list_snapshots(holder: "Owner", tax_year: 2025)
    assert Decimal.equal?(stored.taxable_income, Decimal.new("12000.00"))
    assert Decimal.equal?(stored.solidarity_surcharge_withheld, Decimal.new("140.25"))

    render_click(view, "edit_statement", %{"id" => to_string(stored.id)})

    assert input_value(view, "#tax-statement-form", "statement[taxable_income]") == "12000"

    assert input_value(view, "#tax-statement-form", "statement[solidarity_surcharge_withheld]") ==
             "140,25"

    html =
      view
      |> form("#tax-order-form", %{
        "order" => %{"institution" => "Beispielbank", "amount_granted" => "1.000"}
      })
      |> render_submit()

    assert html =~ "ist mehrdeutig"
    assert Tax.list_allowance_orders(holder: "Owner", tax_year: 2025) == []

    view
    |> form("#tax-order-form", %{
      "order" => %{"institution" => "Beispielbank", "amount_granted" => "801,50"}
    })
    |> render_submit()

    assert [order] = Tax.list_allowance_orders(holder: "Owner", tax_year: 2025)
    assert Decimal.equal?(order.amount_granted, Decimal.new("801.50"))
  end

  # User story (#869; board 05, "Saldo, Platzhalter"):
  # As the operator setting a cash balance on a German page,
  # I want the field's example and my figure to use the decimal comma,
  # so that the balance I read off the bank's page goes in as printed.
  #
  # Acceptance criteria:
  # - The placeholder reads "4250,00"; "1250,50" sets a balance of 1250.50.
  # - A grouped "1.250" is refused in the dialog and sets nothing.
  test "the balance dialog reads and shows figures in the page's locale", %{conn: conn} do
    %{world: w} = usd_world()

    {:ok, view, _html} = live(german(conn), "/portfolios")
    view |> element("#set-balance-#{w.cash.id}") |> render_click()

    assert [_] =
             view
             |> input("#balance-dialog form", "balance[amount]")
             |> Floki.find(~s([placeholder="4250,00"]))

    html =
      view
      |> form("#balance-dialog form", %{
        "balance" => %{"date" => "2026-04-01", "amount" => "1.250"}
      })
      |> render_submit()

    assert html =~ "ist mehrdeutig"
    assert Ledger.cash_balances(portfolio_id: w.portfolio.id) |> Map.get(w.cash.id) == nil

    view
    |> form("#balance-dialog form", %{
      "balance" => %{"date" => "2026-04-01", "amount" => "1250,50"}
    })
    |> render_submit()

    refute has_element?(view, "#balance-dialog")
    balances = Ledger.cash_balances(portfolio_id: w.portfolio.id)
    assert Decimal.equal?(Map.fetch!(balances, w.cash.id), Decimal.new("1250.50"))
  end
end
