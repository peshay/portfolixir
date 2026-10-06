defmodule PortfolixirWeb.Securities.BondStrip do
  @moduledoc """
  The bond block on a bond's Overview and its two-scales note (#330,
  ADR-0052; Sprint 18 pick H3 = A, board
  `ux-design-2026-10-02/03-bond-master-data`, `DESIGN.md` → "Amendment
  2026-10-03 — Securities detail: bond master data and key metrics").

  Both read `Portfolixir.Portfolios.Bonds.reading/2`, the reading the API's
  detail read serves, so the screen and the agent read the same figures.
  The block is a reading surface (C7-A, #804): it renders no input, and its
  one control, the remedy of the empty state, opens the security dialog
  behind "Edit". Dates stay ISO, as everywhere else in the detail pane.
  """

  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format

  attr(:security, :map, required: true)
  attr(:bond, :map, default: nil)

  @doc """
  The block under the Overview's six figures: what was entered in the first
  row, what follows from it in the second, one basis line underneath. With
  no master data at all, one sentence and its remedy instead (A2).
  """
  def strip(%{bond: nil} = assigns), do: ~H""

  def strip(assigns) do
    assigns = assign(assigns, :entered?, entered?(assigns.security))

    ~H"""
    <section class="bond-strip" aria-labelledby="bond-strip-head" data-role="bond-strip">
      <div class="bond-strip__head">
        <h3 id="bond-strip-head"><%= gettext("Bond") %></h3>
      </div>
      <%= if @entered? do %>
        <dl class="overview-metrics" data-role="bond-metrics">
          <.maturity_cell security={@security} />
          <.coupon_cell security={@security} />
          <.nominal_cell security={@security} bond={@bond} />
          <.term_cell security={@security} bond={@bond} />
          <.current_yield_cell security={@security} bond={@bond} />
          <.yield_to_maturity_cell bond={@bond} />
        </dl>
        <p class="detail-tab-hint" data-role="bond-basis">
          <%= gettext(
            "Coupon and price in percent of face: one unit held is a hundredth of the nominal, so the price is also the price per unit. Current yield = coupon ÷ price. Remaining term in calendar days from today, a year of 365 days. Yield to maturity linearly approximated: (coupon + (100 − price) ÷ remaining term in years) ÷ price, without compounding. Without accrued interest, fees and taxes. Reported, not evaluated."
          ) %>
        </p>
      <% else %>
        <p class="detail-tab-empty" data-role="bond-empty">
          <%= gettext(
            "Coupon, maturity and denomination are not entered; without them there is no remaining term and no yield."
          ) %>
          <button
            type="button"
            class="link-button"
            phx-click="row_action"
            phx-value-action="edit"
            phx-value-id={@security.id}
          >
            <%= gettext("Enter bond data…") %>
          </button>
        </p>
        <p :if={held?(@bond)} class="detail-tab-hint" data-role="bond-nominal-hint">
          <%= gettext(
            "Nominal held: %{amount} %{currency}, %{quantity} units × 100 %{currency} (one unit is a hundredth of the nominal).",
            amount: Format.decimal(@bond.nominal_held.amount, 2),
            currency: @bond.nominal_held.currency_code,
            quantity: Format.exact(@bond.quantity)
          ) %>
        </p>
      <% end %>
    </section>
    """
  end

  attr(:security, :map, required: true)

  defp maturity_cell(assigns) do
    ~H"""
    <div class="overview-metric" data-role="bond-maturity">
      <dt><%= gettext("Maturity") %></dt>
      <dd>
        <%= if @security.maturity_date do %>
          <%= Date.to_iso8601(@security.maturity_date) %>
          <small :if={@security.issue_date} class="overview-metric__sub">
            <%= gettext("Issued") %>
            <time datetime={Date.to_iso8601(@security.issue_date)}>
              <%= Date.to_iso8601(@security.issue_date) %>
            </time>
          </small>
        <% else %>
          <span data-role="metric-not-entered"><%= gettext("not entered") %></span>
        <% end %>
      </dd>
    </div>
    """
  end

  attr(:security, :map, required: true)

  defp coupon_cell(assigns) do
    ~H"""
    <div class="overview-metric" data-role="bond-coupon">
      <dt><%= gettext("Coupon") %></dt>
      <dd>
        <%= if @security.coupon_rate do %>
          <%= Format.exact(@security.coupon_rate) %> %
          <small class="overview-metric__unit"><%= gettext("p. a.") %></small>
          <small :if={payment(@security)} class="overview-metric__sub">
            <%= payment(@security) %>
          </small>
        <% else %>
          <span data-role="metric-not-entered"><%= gettext("not entered") %></span>
        <% end %>
      </dd>
    </div>
    """
  end

  attr(:security, :map, required: true)
  attr(:bond, :map, required: true)

  # The nominal is derived, and the cell says from what: the convention as a
  # sum here, as a sentence in the basis line (the issue: stated wherever the
  # face amount is derived).
  defp nominal_cell(assigns) do
    ~H"""
    <div class="overview-metric" data-role="bond-nominal">
      <dt><%= gettext("Nominal held") %></dt>
      <dd>
        <%= if held?(@bond) do %>
          <%= Format.decimal(@bond.nominal_held.amount, 2) %>
          <small class="overview-metric__unit"><%= @bond.nominal_held.currency_code %></small>
          <small class="overview-metric__sub">
            <span class="nowrap">
              <%= gettext("%{quantity} units × 100 %{currency}",
                quantity: Format.exact(@bond.quantity),
                currency: @bond.nominal_held.currency_code
              ) %>
            </span>
            <%= if @security.face_value do %>
              · <%= gettext("Denomination") %>
              <span class="nowrap">
                <%= Format.exact(@security.face_value) %> <%= @bond.nominal_held.currency_code %>
              </span>
            <% end %>
          </small>
        <% else %>
          —
        <% end %>
      </dd>
    </div>
    """
  end

  attr(:security, :map, required: true)
  attr(:bond, :map, required: true)

  defp term_cell(assigns) do
    ~H"""
    <div class="overview-metric" data-role="bond-remaining-term">
      <dt><%= gettext("Remaining term") %></dt>
      <dd>
        <%= cond do %>
          <% @bond.remaining_term.matured -> %>
            <%= gettext("matured") %>
            <small class="overview-metric__sub">
              <%= gettext("since") %>
              <time datetime={Date.to_iso8601(@security.maturity_date)}>
                <%= Date.to_iso8601(@security.maturity_date) %>
              </time>
            </small>
          <% @bond.remaining_term.insufficient_data -> %>
            <span data-role="metric-not-entered"><%= gettext("not entered") %></span>
          <% true -> %>
            <%= gettext("%{years} y %{months} m",
              years: @bond.remaining_term.whole_years,
              months: @bond.remaining_term.whole_months
            ) %>
            <small class="overview-metric__sub">
              <%= gettext("%{years} years from", years: Format.decimal(@bond.remaining_term.years, 2)) %>
              <time datetime={Date.to_iso8601(@bond.as_of)}><%= Date.to_iso8601(@bond.as_of) %></time>
            </small>
        <% end %>
      </dd>
    </div>
    """
  end

  attr(:security, :map, required: true)
  attr(:bond, :map, required: true)

  defp current_yield_cell(assigns) do
    yield = assigns.bond.current_yield

    assigns =
      assigns
      |> assign(:yield, yield)
      |> assign(:ratio, ratio_text(assigns.security.coupon_rate, yield.price.value))

    ~H"""
    <div class="overview-metric" data-role="bond-current-yield">
      <dt><%= gettext("Current yield") %></dt>
      <dd>
        <%= if @yield.value do %>
          <%= percent(@yield.value) %> %
          <small class="overview-metric__sub">
            <span class="nowrap"><%= @ratio %></span><.price_source price={@yield.price} />
          </small>
        <% else %>
          <.unavailable metric={@yield} />
        <% end %>
      </dd>
    </div>
    """
  end

  attr(:bond, :map, required: true)

  defp yield_to_maturity_cell(assigns) do
    assigns = assign(assigns, :yield, assigns.bond.yield_to_maturity)

    ~H"""
    <div class="overview-metric" data-role="bond-yield-to-maturity">
      <dt><%= gettext("Yield to maturity") %></dt>
      <dd>
        <%= if @yield.value do %>
          ≈ <%= percent(@yield.value) %> %
          <small class="overview-metric__sub"><%= gettext("linear approximation") %></small>
        <% else %>
          <.unavailable metric={@yield} />
        <% end %>
      </dd>
    </div>
    """
  end

  attr(:metric, :map, required: true)

  # A figure that cannot be computed says so in the tone of "not entered",
  # with the reason under it: matured, a missing input, no price, or a trade
  # price on the unit scale.
  defp unavailable(assigns) do
    ~H"""
    <span data-role="metric-na"><%= gettext("not computable") %></span>
    <small class="overview-metric__sub"><%= unavailable_reason(@metric) %></small>
    """
  end

  defp unavailable_reason(%{matured: true}), do: gettext("matured")

  # The trade-price fallback on the unit scale (closing act on U7, finding
  # 3): the price per unit of a booking of the nominal, not percent of face.
  defp unavailable_reason(%{price_on_unit_scale: true, price: price}),
    do:
      gettext("trade price %{price} per unit, not percent of face",
        price: Format.exact(price.value)
      )

  defp unavailable_reason(%{missing: missing}) do
    cond do
      "coupon_rate" in missing -> gettext("no coupon entered")
      "maturity_date" in missing -> gettext("no maturity entered")
      true -> gettext("no price")
    end
  end

  attr(:security, :map, required: true)
  attr(:bond, :map, default: nil)

  @doc """
  The two-scales problem note (W1): at the top of the Overview panel, above
  the figures it concerns. It names both scales and the booking (a buy or a
  priced inbound delivery), says what
  follows, and links to the security's Transactions tab, where the quantity
  is checked against the statement. It converts nothing.

  It renders the forward direction only (quotes near 100, bookings near 1),
  the one its sentence states. The reverse direction (#1068) is named in
  Wealth's `dq-two-scales-reverse` note and served in the API's reading
  with its direction; this pane has no board for it yet, so it says
  nothing rather than the forward sentence.
  """
  def two_scales_note(%{bond: %{two_scales: %{direction: :forward} = finding}} = assigns) do
    assigns = assign(assigns, :finding, finding)

    ~H"""
    <AppShell.data_note severity={:problem} data-role="two-scales-note">
      <strong><%= gettext("Priced on two scales:") %></strong>
      <%= gettext("quotes around 100 (latest %{close} on %{date}),",
        close: Format.exact(@finding.latest_quote.close),
        date: Date.to_iso8601(@finding.latest_quote.date)
      ) %>
      <%= ngettext(
        "booked price per unit around 1 (1 booking: %{price} on %{date}).",
        "booked price per unit around 1 (%{count} bookings, the last %{price} on %{date}).",
        @finding.unit_scale_bookings,
        price: Format.exact(@finding.last_unit_scale_booking.price),
        date: Date.to_iso8601(@finding.last_unit_scale_booking.date)
      ) %>
      <%= gettext(
        "That means the nominal was booked as the quantity, and value, gain and weight are a hundred times too high; the return (TTWROR) does not show it. Check the quantity against the nominal on the statement:"
      ) %>
      <.link patch={"/securities/#{@security.id}?tab=transactions"}>
        <%= gettext("Transactions") %>
      </.link>
    </AppShell.data_note>
    """
  end

  def two_scales_note(assigns), do: ~H""

  # A1 against A2: the block shows its grid once any master data is entered;
  # a cell whose input is missing then says "not entered" (the board's note
  # on partial data).
  defp entered?(security) do
    Enum.any?([security.coupon_rate, security.maturity_date, security.face_value], &(&1 != nil))
  end

  defp held?(%{quantity: %Decimal{} = quantity}), do: Decimal.compare(quantity, 0) == :gt
  defp held?(_bond), do: false

  defp payment(%{coupon_rate: %Decimal{} = rate} = security) do
    cond do
      Decimal.equal?(rate, 0) -> gettext("no interest payment")
      security.coupon_frequency == "annual" -> gettext("annual")
      security.coupon_frequency == "semi_annual" -> gettext("semi-annual")
      true -> nil
    end
  end

  defp payment(_security), do: nil

  defp percent(ratio), do: ratio |> Decimal.mult(100) |> Format.decimal(2)

  # "2,5 ÷ 97,25": the coupon over the price the valuation uses, both as
  # stored (the closing act on U7: a 4,125 % coupon read 4,13, beside a yield
  # computed from 4,125). Only the computed figures are rounded.
  defp ratio_text(%Decimal{} = coupon_rate, %Decimal{} = price),
    do: "#{Format.exact(coupon_rate)} ÷ #{Format.exact(price)}"

  defp ratio_text(_coupon_rate, _price), do: ""

  attr(:price, :map, required: true)

  # Which price the yield used: the quote's date, or the trade it fell back
  # to (board A4). Written on one line, so no space falls before the comma.
  defp price_source(%{price: %{source: :trade}} = assigns),
    do: ~H|<%= gettext(", last own trade price") %>|

  defp price_source(%{price: %{date: %Date{}}} = assigns),
    do:
      ~H| (<time datetime={Date.to_iso8601(@price.date)}><%= Date.to_iso8601(@price.date) %></time>)|

  defp price_source(assigns), do: ~H""
end
