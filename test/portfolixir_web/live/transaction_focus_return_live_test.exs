defmodule PortfolixirWeb.TransactionFocusReturnLiveTest do
  # Sprint 18 U1 (#912), the closing act's R3 (board
  # `ux-review-2026-10-03/02-delete-dialog-repairs`): the delete dialog's
  # opener, the row menu's item, is gone when the dialog opens, so every
  # exit sent the focus to the history's heading and the browser scrolled
  # the page to the top; the Edit drawer had no fallback and dropped it on
  # <body>. Both now name the row's kebabs as where the focus returns, the
  # heading only as the fallback when the row is gone, and the page's result
  # as what a close brings into view (WCAG 2.4.3). The hook's behaviour is
  # pinned on its source here, as the row menu's is
  # (test/invariants/row_menu_keyboard_test.exs), and was walked in a real
  # browser.
  #
  # Every name, figure and date is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3]

  setup do
    world = base_world(name: "Hauptportfolio", cash_name: "Girokonto", depot_name: "Depot 1")
    security = create_security!(name: "Global Aktien ETF", ticker: "GAE")
    deposit = deposit!(world, "5000", ~D[2026-09-03])
    buy = buy!(world, security, quantity: "40", price: "62.50", date: ~D[2026-09-22])
    %{buy: buy, deposit: deposit}
  end

  defp menu_item(view, tx, item) do
    view |> element("#tx-kebab-#{tx.id}") |> render_click()
    view |> element("##{item}-#{tx.id}") |> render_click()
    view
  end

  @fallback ~s([data-focus-fallback="#transaction-history-heading"])
  @result ~s([data-focus-result="[data-role='page-result']"])

  defp returns(tx),
    do: ~s([data-focus-return="#tx-kebab-) <> "#{tx.id}, #tx-phone-kebab-#{tx.id}" <> ~s("])

  # User story (U1, #912; WCAG 2.4.3; the closing act, R3):
  # As a keyboard operator closing the delete dialog or the Edit drawer of a
  # row far down the history,
  # I want the focus back on that row's kebab, with the page where it was,
  # so that I do not lose my place — and only when the row is gone does the
  # focus go to the history's heading, with the result in view.
  #
  # Acceptance criteria:
  # - The delete dialog, the buy/sell drawer and the notes-only drawer each
  #   name the row's table and phone kebabs as where the focus returns, the
  #   history's heading as the fallback, and the page's result slot as what a
  #   close brings into view.
  # - The page's result carries the slot's role.
  test "the delete dialog and the Edit drawer return the focus to the row's kebab",
       %{conn: conn, buy: buy, deposit: deposit} do
    {:ok, view, _html} = live(conn, "/transactions")

    menu_item(view, buy, "tx-delete")

    assert has_element?(
             view,
             "dialog#booking-delete-dialog" <> returns(buy) <> @fallback <> @result
           )

    view |> element("[data-role='booking-delete-cancel']") |> render_click()
    menu_item(view, buy, "tx-edit")

    assert has_element?(
             view,
             "dialog#booking-drawer" <> returns(buy) <> @fallback <> @result
           )

    view |> element("#booking-cancel") |> render_click()
    menu_item(view, deposit, "tx-edit")

    assert has_element?(
             view,
             "dialog#booking-drawer" <> returns(deposit) <> @fallback
           )

    view |> form("#note-form", %{"note" => %{"notes" => "per statement"}}) |> render_submit()
    assert has_element?(view, ".alert-success[data-role='page-result']", "Note saved")

    # A drawer opened from "Record transaction" keeps its opener, the button.
    view |> element("#open-booking") |> render_click()
    refute has_element?(view, "dialog#booking-drawer[data-focus-return]")
  end

  # Acceptance criteria (the hook):
  # - On close, an opener still on the page takes the focus; else the first
  #   of the named return targets that is on the page and visible (the phone
  #   row's kebab under 560 px, the table's above); else the fallback.
  # - The focus moves only when it was lost with the dialog — a dialog that
  #   opened from this one keeps it.
  # - A shown result is brought into view first; the target takes the focus
  #   without scrolling, and is brought into view only when it is out of it —
  #   below the sticky top bar, which the targets' scroll margin states.
  test "the ModalDialog hook returns the focus to a visible return target" do
    hook =
      "lib/portfolixir_web/layout_view.ex"
      |> File.read!()
      |> String.split("Hooks.ModalDialog")
      |> Enum.at(1)
      |> String.split("Hooks.PopoverDisclosure")
      |> hd()

    assert hook =~ ~s{getAttribute("data-focus-return")}
    assert hook =~ ~s{getAttribute("data-focus-result")}
    assert hook =~ "querySelectorAll"
    assert hook =~ "getClientRects().length"
    assert hook =~ "preventScroll: true"
    assert hook =~ ~s[scrollIntoView({ block: "nearest" })]
    assert hook =~ "document.activeElement"
    # "In view" is below the sticky top bar: the targets' scroll margin.
    assert hook =~ "scrollMarginTop"

    css = File.read!("priv/static/app.css")

    assert css =~
             ~r/#transactions-workspace > \[data-role="page-result"\],\s*#transaction-history-heading,\s*#transaction-list \.row-actions__kebab,\s*#transaction-phone-rows \.row-actions__kebab \{\s*scroll-margin-top: calc\(var\(--topbar-height\) \+ var\(--space-3\)\);/
  end
end
