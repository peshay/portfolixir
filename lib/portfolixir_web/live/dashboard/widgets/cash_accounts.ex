defmodule PortfolixirWeb.Dashboard.Widgets.CashAccounts do
  @moduledoc """
  The section widget „Verrechnungskonten“ `cash_accounts` (I57; Sprint 32
  W1; ADR-0062's amendment of 2026-11-25, point 3; planning board
  `ux-design-2026-11-25-sprint32/02` ①): Wealth's section „Cash accounts“
  of the tab „Bestände“, moved here so that one code path draws it on
  Wealth (`table/1`, which `PortfolixirWeb.PortfolioLive` renders) and on a
  dashboard (`widget/1`).

  Its figures are the view valuation's (ADR-0024), `Portfolixir.Portfolios.Valuation.for_view/2`,
  the read `GET /api/v1/valuation` and `GET /api/v1/views/:view_id/valuation`
  answer: `cash_balances`, each account's balance in its own currency,
  and at S `total_cash`, the cash of every valued account, reserves and
  credit lines included (the cash quote counts only the deployable share,
  `counting_cash`). Both are read in the first portfolio's base currency,
  as Wealth reads them.
  Setting a balance stays on „Konten & Depots“, linked (ADR-0022's
  amendment of 2026-11-21, point 3).

    * **Zeile** — the section as Wealth draws it: the table of accounts
      and balances, an account outside the cash quote muted with its role;
    * **S** — the scope's cash and how many accounts it sums: the valued
      ones, an account without a rate path left out of both;
    * **compact** — one row per account, the balance at the right, an
      account without a rate path marked as on the wide form.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Buckets
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Valuation
  alias PortfolixirWeb.AccountNames
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Format

  # -- the read -----------------------------------------------------------------

  @doc """
  The widget's read for the scope `view_id` (`nil`: Everything), in the
  page's background task: the view valuation in the first portfolio's
  base currency and the twin cash accounts' portfolio tags (#1333). A view
  that vanished meanwhile reads Everything, as the value card does.
  """
  @spec read(integer() | nil) :: %{valuation: map(), tags: map()}
  def read(view_id) do
    base_currency =
      case Portfolios.first_portfolio() do
        %{base_currency_code: code} -> code
        nil -> "EUR"
      end

    view_id = view_id && Buckets.get_view(view_id) && view_id

    valuation =
      case Valuation.for_view(view_id, base_currency: base_currency) do
        {:error, :view_not_found} -> Valuation.for_view(nil, base_currency: base_currency)
        valuation -> valuation
      end

    %{valuation: valuation, tags: AccountNames.load_portfolio_tags()}
  end

  # -- Wealth's section, moved ---------------------------------------------------

  attr(:valuation, :map, required: true, doc: "the view valuation")
  attr(:tags, :map, required: true, doc: "`AccountNames.load_portfolio_tags/0`")

  @doc """
  The table of Wealth's section „Cash accounts“, as Wealth drew it: each
  account and its balance in its own currency, an account the cash quote
  leaves out muted and named by its role, an account without a rate path
  marked; then the pointer to where a balance is set (issue 670).
  """
  def table(assigns) do
    ~H"""
    <div class="data-table-wrapper">
      <table class="cash-table">
        <thead>
          <tr>
            <th><%= gettext("Account") %></th>
            <th class="num"><%= gettext("Balance") %></th>
          </tr>
        </thead>
        <tbody>
          <%= for cash <- @valuation.cash_balances do %>
            <tr
              class={if cash.deployable, do: nil, else: "is-muted"}
              data-role="cash-account"
              data-cash-account-id={cash.cash_account_id}
            >
              <td>
                <%= cash.name %>
                <AccountNames.portfolio_tag tags={@tags} kind={:cash} id={cash.cash_account_id} />
                <%= if not cash.deployable do %>
                  <span class="hint"><%= liquidity_role_hint(cash.liquidity_role) %></span>
                <% end %>
              </td>
              <td class="num">
                <%= Format.money(cash.balance) %> <%= cash.currency %>
                <span
                  :if={not cash.valued}
                  class="cash-unvalued"
                  data-role="cash-unvalued"
                >
                  ⚠ <%= gettext("no exchange rate") %>
                </span>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>

    <%!-- Issue 670 (UX-DR3/UX-DR11): setting a balance moved into the
         account row on Accounts & depots, where the account is
         already chosen. This surface keeps the read-only table. --%>
    <p data-role="cash-edit-pointer">
      <a href="/portfolios"><%= gettext("Set balances on Accounts & depots") %></a>
    </p>
    """
  end

  @doc "The role an account outside the cash quote is named by."
  @spec liquidity_role_hint(String.t() | nil) :: String.t()
  def liquidity_role_hint("credit_line"), do: gettext("credit line")
  def liquidity_role_hint("reserve"), do: gettext("reserve")
  def liquidity_role_hint(_role), do: gettext("not in cash quote")

  # -- the widget ---------------------------------------------------------------

  attr(:item, :map, required: true)
  attr(:card, :any, required: true, doc: "nil while the read runs, :error, or `read/1`'s answer")
  attr(:scope_label, :string, default: nil)

  @doc "The widget „Verrechnungskonten“ at its size, with its compact form."
  def widget(assigns) do
    assigns = assign(assigns, :valuation, valuation(assigns.card))

    ~H"""
    <Widget.frame
      id={"dashboard-cash-accounts" <> @item.uid}
      item={@item}
      title={if @item.size == "S", do: gettext("Cash"), else: Portfolixir.Dashboards.Widgets.title("cash_accounts")}
      scope_label={@scope_label}
      full_href="/portfolio"
      full_label={gettext("Full view →")}
      full_role="cash-accounts-full-view"
    >
      <:info>
        <%= gettext("Each cash account of the view with its balance in its own currency, as Wealth lists them: the view valuation, GET /api/v1/valuation and GET /api/v1/views/:id/valuation, its cash_balances. A reserve or a credit line is muted: the cash quote leaves it out.") %>
      </:info>
      <:info :if={@item.size == "S"}>
        <%= gettext("The figure is the cash of all valued cash accounts of the view in the base currency, reserves and credit lines included: the valuation's total_cash; an account without an exchange rate is left out. The cash quote counts only the deployable share, the valuation's counting_cash.") %>
      </:info>
      <:shared>
        <p :if={is_nil(@card)} class="section-skeleton" aria-busy="true" data-role="cash-skeleton"></p>
        <p :if={@card == :error} class="hint" data-role="cash-failed">
          <%= gettext("Couldn't load the cash accounts.") %>
        </p>
      </:shared>
      <%= if @valuation do %>
        <%= if @item.size == "S" do %>
          <%!-- At S the head says „Cash“: the kind's title does not fit
               the 3-column tile beside its ⓘ and ⋯ (the anatomy walk). --%>
          <Widget.figure size={:secondary} role="cash-total">
            <%= Format.money(@valuation.total_cash) %>
            <:unit><%= @valuation.base_currency %></:unit>
            <:sub>
              <%= ngettext("%{count} account", "%{count} accounts", summed_count(@valuation.cash_balances)) %>
            </:sub>
          </Widget.figure>
        <% else %>
          <.table valuation={@valuation} tags={@card.tags} />
        <% end %>
      <% end %>
      <:compact>
        <%= if @valuation do %>
          <Widget.row
            :for={cash <- @valuation.cash_balances}
            data-compact-role="cash-account"
            data-cash-account-id={cash.cash_account_id}
            title={cash.name}
          >
            <:name><%= cash.name %></:name>
            <:sub :if={not cash.deployable}><%= liquidity_role_hint(cash.liquidity_role) %></:sub>
            <:figure>
              <%= Format.money(cash.balance) %> <%= cash.currency %>
              <span :if={not cash.valued} class="cash-unvalued" data-role="cash-unvalued">
                ⚠ <%= gettext("no exchange rate") %>
              </span>
            </:figure>
          </Widget.row>
        <% end %>
      </:compact>
    </Widget.frame>
    """
  end

  # The accounts total_cash sums: the valued ones (`Valuation`'s cash
  # summary leaves an account without a rate path out of the total).
  defp summed_count(balances), do: Enum.count(balances, & &1.valued)

  defp valuation(%{valuation: %{} = valuation}), do: valuation
  defp valuation(_card), do: nil
end
