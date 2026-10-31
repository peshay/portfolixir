defmodule PortfolixirWeb.AccountsCardBandTest do
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Portfolios

  # Sprint 21 γ5, board ux-design-2026-10-09/05-accounts (picks N15 = A and
  # N16 = A, and #1161's before/after). The layout rules are CSS, so the
  # stylesheet is what the CSS half reads; the board measured them in frames
  # as wide as each render. The LiveView half pins the markup the rules
  # select on.

  @css File.read!("priv/static/app.css")

  defp german(conn),
    do:
      PortfolixirWeb.PreferenceCookieHelpers.put_preference_cookie(
        conn,
        "portfolixir_locale",
        "de"
      )

  # Two pairs and a lone cash account, as the board draws them: one pair
  # tagged together, one tagged apart, the lone account without a bucket.
  defp world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Band World",
        base_currency_code: "EUR"
      })

    cash = fn name ->
      {:ok, account} =
        Portfolios.create_cash_account(Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          name: name,
          currency_code: "EUR"
        })

      account
    end

    depot = fn name, cash_account ->
      {:ok, account} =
        Portfolios.create_securities_account(Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          name: name,
          cash_account_id: cash_account.id
        })

      account
    end

    test_cash = cash.("Test-Cash")
    muster = depot.("Depot Muster", test_cash)
    settlement = cash.("Wertpapierverrechnungskonto")
    plan = depot.("Depot Sparplan", settlement)
    lone = cash.("Tagesgeld")

    {:ok, long_term} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Langfristig"})
    {:ok, savings} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Sparplan"})
    {:ok, reserve} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Notgroschen"})

    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), muster, [long_term.id])
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), test_cash, [long_term.id])
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), plan, [savings.id])
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), settlement, [reserve.id])

    %{muster: muster, plan: plan, settlement: settlement, lone: lone}
  end

  # Every `@container accounts (<query>)` block's body, joined.
  defp container(query) do
    ~r/@container accounts \(#{Regex.escape(query)}\) \{(.*?)\n\}/s
    |> Regex.scan(@css, capture: :all_but_first)
    |> List.flatten()
    |> case do
      [] -> flunk("no @container accounts (#{query}) block")
      bodies -> Enum.join(bodies, "\n")
    end
  end

  # The body of `selector`'s rule inside `inner` (a block's body).
  defp rule(inner, selector) do
    case Regex.run(~r/(?:^|\n)\s*#{Regex.escape(selector)} \{([^}]*)\}/, inner) do
      [_, body] -> body
      nil -> flunk("no rule for #{inspect(selector)}")
    end
  end

  defp block(selector) do
    case Regex.run(~r/\n#{Regex.escape(selector)} \{([^}]*)\}/, @css) do
      [_, body] -> body
      nil -> flunk("no top-level rule for #{inspect(selector)}")
    end
  end

  defp coarse(selector) do
    ~r/@media \(pointer: coarse\) \{(.*?)\n\}/s
    |> Regex.scan(@css, capture: :all_but_first)
    |> Enum.find_value(fn [inner] ->
      case Regex.run(~r/(?:^|\n|,)\s*#{Regex.escape(selector)} \{([^}]*)\}/, inner) do
        [_, body] -> body
        nil -> nil
      end
    end) || flunk("no coarse rule for #{inspect(selector)}")
  end

  describe "#1145 — the accounts table is never cut (N15 = A)" do
    # User story (#1145, Sprint 21 γ5; board 05 ①, pick N15 = A):
    # As the operator on a tablet, or on a laptop with the sidebar open,
    # I want the accounts table to become the phone's card wherever it does
    # not fit,
    # so that no width cuts off a row's kebab or its bucket cell.
    #
    # Acceptance criteria:
    # - The table's wrapper is a query container (`container: accounts /
    #   inline-size`) and stays `overflow: visible`, so the bucket picker
    #   still escapes it; the table is the wrapper's direct child.
    # - The card (the hidden head, the stacked band, every kebab at the end
    #   of its own name line, the rows' two ⓘ, the static picker) is chosen
    #   by `@container accounts (width < 840px)`, measured on the wrapper,
    #   not by a viewport breakpoint: no `@media (max-width: 640px)` block
    #   names the accounts table any more.
    # - Rule ⑦ follows the card: the role label is visually hidden only
    #   under `@container accounts (width >= 840px)`, where the table shows
    #   its head, the exact complement of the card's query.
    # - 840 px is the one bound: no other accounts query exists.
    test "the card follows the table's own width, measured on its wrapper", %{conn: conn} do
      world()
      {:ok, _view, html} = live(conn, "/portfolios")
      doc = Floki.parse_document!(html)

      assert [_] = Floki.find(doc, "div.data-table-wrapper > table#accounts-table")

      wrapper = block(".data-table-wrapper:has(> .accounts-table)")
      assert wrapper =~ ~r/container:\s*accounts \/ inline-size;/
      assert block(".data-table-wrapper:has(.accounts-table)") =~ ~r/overflow:\s*visible;/

      phone_blocks =
        Regex.scan(~r/@media \(max-width: 640px\) \{(.*?)\n\}/s, @css, capture: :all_but_first)

      for [inner] <- phone_blocks do
        refute inner =~ ".accounts-table",
               "a 640 px viewport block still lays out the accounts table"
      end

      card = container("width < 840px")
      head = rule(card, ".accounts-table thead")
      assert head =~ ~r/position:\s*absolute;/
      assert head =~ ~r/clip:\s*rect\(0 0 0 0\);/
      assert rule(card, ".accounts-table tbody.account-pair") =~ ~r/display:\s*block;/

      line = rule(card, ".accounts-table tbody.account-pair tr")
      assert line =~ ~r/display:\s*grid;/
      assert line =~ ~r/grid-template-columns:\s*minmax\(0, 1fr\) auto;/

      kebab = rule(card, ".accounts-table tbody.account-pair td.row-actions")
      assert kebab =~ ~r/grid-column:\s*2;/
      assert kebab =~ ~r/grid-row:\s*1;/

      assert rule(card, ".accounts-table tbody.account-pair td.cell-name") =~
               ~r/white-space:\s*normal;/

      assert rule(card, ".accounts-term-info--phone") =~ ~r/display:\s*inline-block;/
      assert rule(card, ".accounts-table thead .metric-tooltip") =~ ~r/display:\s*none;/
      assert rule(card, ".accounts-table .bucket-picker") =~ ~r/position:\s*static;/

      label = rule(container("width >= 840px"), ".accounts-table .liquidity-role-field__label")
      assert label =~ ~r/position:\s*absolute;/
      assert label =~ ~r/clip:\s*rect\(0 0 0 0\);/
      refute @css =~ "@media (width > 640px)"

      queries = Regex.scan(~r/@container accounts \(([^)]*)\)/, @css, capture: :all_but_first)
      assert queries != []
      assert Enum.uniq(List.flatten(queries)) -- ["width < 840px", "width >= 840px"] == []
    end

    # User story (#1145, Sprint 21 γ5; board 05 ①, "any variant" and found
    # while drawing 1):
    # As the operator reading an account's balance,
    # I want the amount and "Saldo setzen" on one line each, and a long
    # account name to break inside its own cell,
    # so that "4.230,15 EUR" never drops its currency to a second line and no
    # stored name moves the width at which the card takes over.
    #
    # Acceptance criteria:
    # - `.cash-balance__amount` and `.cash-balance__action` take
    #   `white-space: nowrap`; the date line keeps wrapping under 1200 px.
    # - The Name column's head takes a 13.5 rem floor, and a name longer than
    #   that breaks inside the cell (`overflow-wrap: anywhere`).
    test "the balance keeps its words whole, and the Name column holds its floor" do
      whole = block(".cash-balance__amount,\n.cash-balance__action")
      assert whole =~ ~r/white-space:\s*nowrap;/
      refute block(".cash-balance__asof") =~ ~r/white-space/

      assert block(".accounts-table thead th:first-child") =~ ~r/min-width:\s*13\.5rem;/
      assert block(".accounts-table .cell-name") =~ ~r/overflow-wrap:\s*anywhere;/
    end
  end

  describe "#1162 — the card names the bucket cell (N16 = A)" do
    # User story (#1162, Sprint 21 γ5; board 05 ②, pick N16 = A):
    # As the operator reading an account's card on a phone,
    # I want the bucket cell to open with the word "Buckets" and its ⓘ
    # beside it,
    # so that the ⓘ explains a word I can see, as the role's ⓘ does.
    #
    # Acceptance criteria:
    # - Every chip group opens with `.bucket-chip-group__label`
    #   (`data-role="bucket-label"`): the head's own msgid "Buckets" and the
    #   row copy of the Buckets ⓘ ("About buckets" / "Zu den Buckets"),
    #   moved there from the scope line.
    # - The scope line keeps its sentence only: no ⓘ trails it.
    # - The label is `display: none` by default (the head names the column
    #   once) and shows only in the card, under the card's container query,
    #   in the role label's voice (11 px, weight 600, text-muted).
    test "the card opens the bucket cell with Buckets ⓘ", %{conn: conn} do
      %{muster: muster, plan: plan, settlement: settlement, lone: lone} = world()
      {:ok, _view, html} = live(german(conn), "/portfolios")
      doc = Floki.parse_document!(html)

      groups = Floki.find(doc, "#accounts-table tbody [data-role='bucket-chips']")

      ids =
        Enum.map(groups, fn group -> group |> Floki.attribute("id") |> List.first() end)

      assert Enum.sort(ids) ==
               Enum.sort([
                 "pair-buckets-#{muster.id}",
                 "depot-buckets-#{plan.id}",
                 "cash-buckets-#{settlement.id}",
                 "cash-buckets-#{lone.id}"
               ])

      for {_tag, _attrs, children} = group <- groups do
        [first | _] = Enum.filter(children, &is_tuple/1)

        assert Floki.attribute([first], "data-role") == ["bucket-label"],
               "the label is not the chip group's first element"

        assert Floki.attribute([first], "class") == ["bucket-chip-group__label"]
        assert first |> Floki.text(deep: false) |> String.trim() == "Buckets"

        assert [_] =
                 Floki.find(
                   [first],
                   "details.accounts-term-info--phone[data-role='buckets-info'] summary[aria-label='Zu den Buckets']"
                 )

        assert [_] = Floki.find([group], "[data-role='buckets-info']")
        assert [scope] = Floki.find([group], "[data-role='bucket-scope']")
        assert Floki.find([scope], "details") == []
        assert scope |> Floki.text() |> String.trim() =~ ~r/^Gilt für /
      end

      assert block(".bucket-chip-group__label") =~ ~r/display:\s*none;/

      shown = rule(container("width < 840px"), ".bucket-chip-group__label")
      assert shown =~ ~r/display:\s*inline-flex;/
      assert shown =~ ~r/font-size:\s*11px;/
      assert shown =~ ~r/font-weight:\s*600;/
      assert shown =~ ~r/color:\s*var\(--color-text-muted\);/
    end
  end

  describe "#1161 — the chip's × on the desktop" do
    # User story (#1161, Sprint 21 γ5; board 05 ③, before/after, and found
    # while drawing 2):
    # As the operator with a mouse,
    # I want a chip's × to sit inside the chip's height, as the + does,
    # so that a chip holding a × is no taller than one without it.
    #
    # Acceptance criteria:
    # - The × is the 22 × 22 that rule ⑧ declares for the +: `width` and
    #   `height` 22 px, `min-height: 0` (the base button's 34 px floor no
    #   longer wins), `padding: 0`, its corners the pill's end
    #   (`0 999px 999px 0`) at every width, and still no shadow.
    # - A chip holding a × gives up its block and right padding outside a
    #   coarse pointer too, so the × fills the pill's end.
    # - Under a coarse pointer the × is still 44 × 44, and that rule comes
    #   after the base rule it overrides.
    # - The × is the chip's direct child, which `:has(> …)` selects on, and
    #   carries its accessible name.
    test "the × is 22 × 22 and its chip gives up its block padding", %{conn: conn} do
      %{muster: muster} = world()
      {:ok, _view, html} = live(conn, "/portfolios")
      doc = Floki.parse_document!(html)

      assert [_] =
               Floki.find(
                 doc,
                 "#pair-buckets-#{muster.id} .bucket-chip > button.bucket-chip__remove[aria-label='Remove bucket Langfristig']"
               )

      remove = block(".bucket-chip__remove")
      assert remove =~ ~r/width:\s*22px;/
      assert remove =~ ~r/\n\s*height:\s*22px;/
      assert remove =~ ~r/min-height:\s*0;/
      assert remove =~ ~r/\n\s*padding:\s*0;/
      assert remove =~ ~r/border-radius:\s*0 999px 999px 0;/
      assert remove =~ ~r/box-shadow:\s*none;/

      chip = block(".bucket-chip:has(> .bucket-chip__remove)")
      assert chip =~ ~r/padding-block:\s*0;/
      assert chip =~ ~r/padding-right:\s*0;/

      touch = coarse(".bucket-chip__remove")
      assert touch =~ ~r/min-width:\s*44px;/
      assert touch =~ ~r/min-height:\s*44px;/

      {base_at, _} = :binary.match(@css, "\n.bucket-chip__remove {")
      {coarse_at, _} = :binary.match(@css, "\n  .bucket-chip__remove {")
      assert coarse_at > base_at
    end
  end
end
