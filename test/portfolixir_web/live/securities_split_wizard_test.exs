defmodule PortfolixirWeb.SecuritiesSplitWizardTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits

  defp world_with_position do
    world = base_world(name: "Wizard World", cash_name: "Wizard Cash", depot_name: "Wizard Depot")
    security = create_security!(name: "Wizard Co", ticker: "WIZ", asset_class: "equity")
    buy!(world, security, quantity: "10", price: "100", date: Date.add(Date.utc_today(), -40))
    {world, security}
  end

  defp open_wizard(conn, security) do
    {:ok, view, _html} = live(conn, "/securities/#{security.id}")
    view |> element("#detail-record-split") |> render_click()
    view
  end

  defp wizard_change(view, numerator, denominator, date) do
    view
    |> form("#split-wizard-form", %{
      "split" => %{
        "ratio_numerator" => numerator,
        "ratio_denominator" => denominator,
        "date" => Date.to_iso8601(date)
      }
    })
    |> render_change()
  end

  defp wizard_submit(view, numerator, denominator, date) do
    view
    |> form("#split-wizard-form", %{
      "split" => %{
        "ratio_numerator" => numerator,
        "ratio_denominator" => denominator,
        "date" => Date.to_iso8601(date)
      }
    })
    |> render_submit()
  end

  defp split_transactions(security) do
    security.id
    |> Ledger.list_transactions_for_security()
    |> Enum.filter(&(&1.type == "split"))
  end

  # User story (ADR-0028 §1, UX-DR9, issue #591):
  # As a local portfolio maintainer working in the UI,
  # I want a "Record split" affordance on the security detail page that opens
  # an accessible guided dialog,
  # so that I can book a split without knowing the ledger representation.
  #
  # Acceptance criteria:
  # - The detail pane offers a "Record split" trigger.
  # - The dialog satisfies UX-DR9: role="dialog", aria-modal="true", a label,
  #   and focus moved to the first field on open.
  # - Esc closes the dialog.
  test "the security detail offers a Record split trigger opening an accessible dialog", %{
    conn: conn
  } do
    {_world, security} = world_with_position()

    view = open_wizard(conn, security)

    assert has_element?(
             view,
             "#split-wizard-dialog [role='dialog'][aria-modal='true'][aria-labelledby]"
           )

    assert has_element?(view, "#split-wizard-form input[name='split[ratio_numerator]']")
    assert has_element?(view, "#split-wizard-form input[name='split[ratio_denominator]']")
    assert has_element?(view, "#split-wizard-form input[name='split[date]'][type='date']")

    # Focus lands on the first field when the dialog mounts (UX-DR9).
    assert has_element?(view, "input[name='split[ratio_numerator]'][phx-mounted]")

    # Esc is wired to close the dialog (UX-DR9) and the close event removes it.
    assert view |> element("#split-wizard-dialog") |> render() =~ "Escape"
    view |> element("#split-wizard-dialog button[aria-label='Close']") |> render_click()
    refute has_element?(view, "#split-wizard-dialog")
  end

  # User story (ADR-0028 §1 + §2, issue #591):
  # As a local portfolio maintainer entering a split,
  # I want a live preview of the per-portfolio fan-out with every warning,
  # so that I see the effect — and any basis doubt — before confirming.
  #
  # Acceptance criteria:
  # - Entering a 2:1 ratio and an effective date previews quantity before/after
  #   and the resulting current position per portfolio.
  # - With no quotes around the effective date, the preview shows the
  #   insufficient-quotes basis warning (#590 guard).
  test "entering a 2:1 ratio and date previews per-portfolio quantities and warnings", %{
    conn: conn
  } do
    {_world, security} = world_with_position()

    view = open_wizard(conn, security)
    wizard_change(view, "2", "1", Date.add(Date.utc_today(), -10))

    assert has_element?(view, "#split-wizard-preview td[data-role='qty-before']", "10")
    assert has_element?(view, "#split-wizard-preview td[data-role='qty-after']", "20")
    assert has_element?(view, "#split-wizard-preview td[data-role='qty-current']", "20")
    assert has_element?(view, "#split-wizard-preview td[data-role='portfolio']", "Wizard World")

    assert has_element?(
             view,
             "#split-wizard-warnings [data-warning='insufficient_quotes_to_verify_basis']"
           )
  end

  # User story (ADR-0028 §1 PP-rewritten-history guard, issue #591):
  # As a maintainer whose imported history may already be post-split,
  # I want the preview to warn when the effective date predates the earliest
  # transaction,
  # so that I do not double-apply a split PP already rewrote.
  test "an effective date before the imported history renders the history warning", %{conn: conn} do
    {_world, security} = world_with_position()

    view = open_wizard(conn, security)
    wizard_change(view, "2", "1", Date.add(Date.utc_today(), -60))

    assert has_element?(
             view,
             "#split-wizard-warnings [data-warning='effective_date_before_history']"
           )
  end

  # User story (ADR-0028 §2 misclassification guard, issues #590/#591):
  # As a maintainer booking a split against stored manual quotes,
  # I want the preview to render the stored closes around the effective date
  # and warn when they contradict their basis classification,
  # so that no PP-style silent double adjustment can happen.
  #
  # Acceptance criteria:
  # - Continuous manual (raw-classified) closes across the effective date
  #   trigger the contradiction warning, and the warning names the
  #   treat-quotes-as-raw override flag.
  # - The stored closes around the effective date are visible in the dialog.
  test "contradicting quotes around the effective date warn before confirming", %{conn: conn} do
    {_world, security} = world_with_position()
    effective_date = Date.add(Date.utc_today(), -10)
    put_quote!(security, Date.add(effective_date, -1), "100")
    put_quote!(security, Date.add(effective_date, 1), "100")

    view = open_wizard(conn, security)
    wizard_change(view, "2", "1", effective_date)

    assert has_element?(view, "#split-wizard-warnings [data-warning='quote_basis_contradiction']")

    warning =
      view
      |> element("#split-wizard-warnings [data-warning='quote_basis_contradiction']")
      |> render()

    assert warning =~ "Treat synced quotes as raw"

    quotes_html = view |> element("#split-wizard-quotes") |> render()
    assert quotes_html =~ Date.to_iso8601(Date.add(effective_date, -1))
    assert quotes_html =~ "100"
  end

  # User story (ADR-0028 §1, issue #591):
  # As a local portfolio maintainer confirming the previewed split,
  # I want the confirmation to create exactly the Story-17.2 ledger event,
  # so that the wizard stays a UI layer over `book_split/2`, never a second
  # write path.
  #
  # Acceptance criteria:
  # - Confirming books one `split` row for the positioned portfolio with the
  #   ratio normalized to lowest terms (4:2 → 2:1), like `book_split/2`.
  # - Holdings reflect the scaled quantity.
  # - The dialog closes on success.
  test "confirming books the split ledger event and refreshes holdings", %{conn: conn} do
    {world, security} = world_with_position()
    effective_date = Date.add(Date.utc_today(), -10)

    view = open_wizard(conn, security)
    wizard_change(view, "4", "2", effective_date)
    wizard_submit(view, "4", "2", effective_date)

    assert [split] = split_transactions(security)
    assert split.portfolio_id == world.portfolio.id
    assert split.date == effective_date
    assert split.split_ratio_numerator == 2
    assert split.split_ratio_denominator == 1

    assert [holding] = Ledger.holdings_for_security(security.id)
    assert Decimal.equal?(holding.quantity, Decimal.new("20"))

    refute has_element?(view, "#split-wizard-dialog")
  end

  # User story (ADR-0028 §1, issue #591):
  # As a maintainer who mistyped the ratio,
  # I want an identity ratio rejected inline,
  # so that a meaningless 1:1 split can never be booked.
  test "an identity ratio renders an inline error and books nothing", %{conn: conn} do
    {_world, security} = world_with_position()

    view = open_wizard(conn, security)
    wizard_change(view, "3", "3", Date.add(Date.utc_today(), -10))

    assert has_element?(view, "#split-wizard-error")
    assert view |> element("#split-wizard-error") |> render() =~ "1:1"

    wizard_submit(view, "3", "3", Date.add(Date.utc_today(), -10))
    assert split_transactions(security) == []
    assert has_element?(view, "#split-wizard-dialog")
  end

  # User story (ADR-0028 §1 write idempotency, issue #591):
  # As a maintainer retrying a booking that already exists,
  # I want the same-day duplicate rejected with a message naming the existing
  # event,
  # so that a retried timeout can never compound a multiplicative event.
  test "a same-day duplicate is rejected naming the existing event", %{conn: conn} do
    {_world, security} = world_with_position()
    effective_date = Date.add(Date.utc_today(), -10)

    {:ok, _transactions} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: effective_date,
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    view = open_wizard(conn, security)
    wizard_submit(view, "3", "1", effective_date)

    error = view |> element("#split-wizard-error") |> render()
    assert error =~ "already booked"
    assert error =~ "2:1"
    assert error =~ "Wizard World"

    assert length(split_transactions(security)) == 1
    assert has_element?(view, "#split-wizard-dialog")
  end
end
