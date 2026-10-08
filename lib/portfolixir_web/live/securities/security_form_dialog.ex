defmodule PortfolixirWeb.Securities.SecurityFormDialog do
  @moduledoc "Modal dialog for creating and editing a security."
  use Phoenix.LiveComponent
  use Gettext, backend: PortfolixirWeb.Gettext

  # The errors key of a message about the security itself rather than one of
  # its fields; no input carries this name.
  @record_error "_record"

  # #330 (ADR-0052): the bond section's fields, read here rather than by
  # `to_overrides/1`, so a figure follows the page's separator and an emptied
  # field clears its value. A fixed map: a form key never mints an atom.
  @bond_fields %{
    "coupon_rate" => :coupon_rate,
    "coupon_frequency" => :coupon_frequency,
    "maturity_date" => :maturity_date,
    "issue_date" => :issue_date,
    "face_value" => :face_value,
    "face_value_currency_code" => :face_value_currency_code
  }
  @bond_decimals ~w(coupon_rate face_value)

  # #942 (the F15 allow-list, T-5): the fields the form renders outside the
  # bond section, read by `to_overrides/1`. A fixed map: a key the form does
  # not render — the provider marker, the online id, the security flags, the
  # latest feed — never reaches the write, and no key is turned into an atom.
  @form_fields %{
    "name" => :name,
    "ticker_symbol" => :ticker_symbol,
    "isin" => :isin,
    "wkn" => :wkn,
    "currency_code" => :currency_code,
    "exchange_code" => :exchange_code,
    "asset_class" => :asset_class,
    "feed" => :feed,
    "feed_url" => :feed_url,
    "treat_quotes_as_raw" => :treat_quotes_as_raw,
    "note" => :note
  }

  alias Phoenix.LiveView.JS
  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.AssetClasses
  alias Portfolixir.Catalog.Currencies
  alias Portfolixir.Catalog.Feeds
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecuritySearch
  alias Portfolixir.Catalog.SecuritySearch.SearchResult
  alias Portfolixir.Lifecycle.Freeze
  alias Portfolixir.Portfolios.Bonds
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.DecimalInput
  alias PortfolixirWeb.LiveEventGuard
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.NamedRecordRefusal
  alias PortfolixirWeb.ReferenceCounts

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> LiveEventGuard.attach()
     |> assign(:step, :choose)
     |> assign(:mode, nil)
     |> assign(:query, "")
     |> assign(:results, [])
     |> assign(:selected_result, nil)
     |> assign(:selected_market, nil)
     |> assign(:form, %{})
     |> assign(:errors, %{})
     |> assign(:conflict, nil)
     |> assign(:editing, nil)
     |> assign(:search_loading?, false)
     |> assign(:search_error, nil)}
  end

  @impl true
  def update(%{editing: %Portfolixir.Catalog.Security{} = security} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:step, :confirm)
      |> assign(:mode, "edit")
      |> assign(:editing, security)
      |> assign(:form, security_to_form(security))
      |> assign(:conflict, nil)
      |> assign(:errors, %{})

    {:ok, socket}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  defp security_to_form(security) do
    %{
      "name" => security.name || "",
      "ticker_symbol" => security.ticker_symbol || "",
      "isin" => security.isin || "",
      "wkn" => security.wkn || "",
      "currency_code" => security.currency_code || "",
      "exchange_code" => security.exchange_code || "",
      "asset_class" => Security.effective_asset_class(security) || "",
      "feed" => security.feed || "",
      "feed_url" => security.feed_url || "",
      "treat_quotes_as_raw" => to_string(security.treat_quotes_as_raw == true),
      "note" => security.note || "",
      "coupon_rate" => decimal_value(security.coupon_rate),
      "coupon_frequency" => security.coupon_frequency || "",
      "maturity_date" => date_value(security.maturity_date),
      "issue_date" => date_value(security.issue_date),
      "face_value" => decimal_value(security.face_value),
      "face_value_currency_code" => security.face_value_currency_code
    }
  end

  # The bond section shows while the class reads one of the two bond
  # classes, and — #1068, D-15 — while it reads no class for a security that
  # carries a maturity date or a coupon, which `Bonds.bond?/1` reads as a
  # bond: its bond data stays visible and clearable where it was entered.
  defp bond_fieldset?(form, editing) do
    form["asset_class"] in Bonds.classes() or
      (form["asset_class"] in [nil, ""] and stored_bond_terms?(editing))
  end

  defp stored_bond_terms?(%Security{maturity_date: maturity, coupon_rate: coupon}),
    do: not is_nil(maturity) or not is_nil(coupon)

  defp stored_bond_terms?(_editing), do: false

  defp decimal_value(nil), do: ""
  defp decimal_value(%Decimal{} = value), do: value |> Decimal.normalize() |> DecimalInput.value()

  defp date_value(nil), do: ""
  defp date_value(%Date{} = date), do: Date.to_iso8601(date)

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Native dialog (UX-DR9, issue 646): the ModalDialog hook opens it
         with showModal(), which supplies the focus trap, background
         inertness and Esc handling; cancel pushes the close event. --%>
    <dialog
      id={@id}
      class="modal"
      phx-hook="ModalDialog"
      data-close-event="close"
      aria-labelledby={"#{@id}-title"}
    >
        <header class="modal-head">
          <h2 id={"#{@id}-title"}><%= dialog_title(@step, @mode) %></h2>
          <button
            type="button"
            class="icon-button"
            aria-label={gettext("Close")}
            phx-click="close"
            phx-target={@myself}
          >
            <AppShell.icon name={:x} />
          </button>
        </header>

        <div class="modal-body">
          <%= case @step do %>
            <% :choose -> %>
              <%= render_choose(assigns) %>
            <% :search -> %>
              <%= render_search(assigns) %>
            <% :market -> %>
              <%= render_market(assigns) %>
            <% :confirm -> %>
              <%= render_confirm(assigns) %>
          <% end %>
        </div>
    </dialog>
    """
  end

  defp render_choose(assigns) do
    ~H"""
    <div class="dialog-choose" role="group" aria-label={gettext("Source type")}>
      <button
        type="button"
        class="choose-card"
        phx-click="choose_mode"
        phx-value-mode="security"
        phx-target={@myself}
      >
        <span class="choose-title"><%= gettext("New security") %></span>
        <span class="choose-sub">
          <%= gettext("Search stocks, ETFs, funds and bonds via Portfolio Performance.") %>
        </span>
      </button>

      <button
        type="button"
        class="choose-card"
        phx-click="choose_mode"
        phx-value-mode="crypto"
        phx-target={@myself}
      >
        <span class="choose-title"><%= gettext("New cryptocurrency") %></span>
        <span class="choose-sub">
          <%= gettext("Search coins via CoinGecko.") %>
        </span>
      </button>

      <%!-- Manual escape hatch (#491): instruments no provider knows are
           still recordable — straight to the details form. --%>
      <button
        type="button"
        class="choose-card"
        phx-click="choose_mode"
        phx-value-mode="manual"
        phx-target={@myself}
      >
        <span class="choose-title"><%= gettext("Manual entry") %></span>
        <span class="choose-sub">
          <%= gettext("Enter the details yourself — for instruments no search knows.") %>
        </span>
      </button>
    </div>
    """
  end

  defp render_search(assigns) do
    ~H"""
    <form id="security-dialog-search-form" phx-change="search_change" phx-submit="search_submit" phx-target={@myself}>
      <label class="search-field">
        <AppShell.icon name={:search} />
        <input
          type="search"
          name="dialog_query"
          value={@query}
          phx-debounce="300"
          placeholder={gettext("Search by name, ISIN or ticker…")}
          autocomplete="off"
          phx-mounted={JS.focus()}
        />
      </label>

      <%= if @search_error do %>
        <p class="alert-error" role="alert"><%= @search_error %></p>
      <% end %>

      <ul id={"#{@id}-results"} class="search-results">
        <%= if @search_loading? do %>
          <li class="search-result-empty"><%= gettext("Searching…") %></li>
        <% end %>
        <%= for {result, idx} <- Enum.with_index(@results) do %>
          <li>
            <button
              type="button"
              class="search-result"
              phx-click="pick_result"
              phx-value-idx={idx}
              phx-target={@myself}
            >
              <span class="result-title"><%= result.name %></span>
              <span class="result-meta">
                <%= [result.ticker_symbol, result.isin, result.asset_class]
                  |> Enum.reject(&is_nil/1)
                  |> Enum.join(" · ") %>
              </span>
              <span class="provider-badge"><%= provider_label(result.provider) %></span>
            </button>
          </li>
        <% end %>
        <%= if @query != "" and @results == [] and not @search_loading? do %>
          <li class="search-result-empty"><%= gettext("No matches") %></li>
        <% end %>
      </ul>

      <p class="dialog-help">
        <button
          type="button"
          class="button-ghost"
          data-role="manual-entry-link"
          phx-click="choose_mode"
          phx-value-mode="manual"
          phx-target={@myself}
        >
          <%= gettext("Not listed? Enter manually") %>
        </button>
      </p>
    </form>
    """
  end

  defp render_market(assigns) do
    # Recommended market first (#491): XETR, else the first EUR market, else
    # the provider's first — one-click confirmation instead of a wall of MIC
    # codes; the rest sit behind a disclosure.
    {recommended, rest} = split_markets(assigns.selected_result.markets)
    assigns = assign(assigns, recommended: recommended, rest: rest)

    ~H"""
    <p class="dialog-help"><%= gettext("Market for %{name}", name: @selected_result.name) %></p>
    <div data-role="market-recommended">
      <.market_button market={elem(@recommended, 0)} idx={elem(@recommended, 1)} myself={@myself}>
        <span class="provider-badge"><%= gettext("Recommended") %></span>
      </.market_button>
    </div>
    <%= if @rest != [] do %>
      <details data-role="market-more" class="market-more">
        <summary class="disclosure-summary">
          <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
          <%= gettext("More markets") %>
        </summary>
        <ul class="market-list">
          <li :for={{market, idx} <- @rest}>
            <.market_button market={market} idx={idx} myself={@myself} />
          </li>
        </ul>
      </details>
    <% end %>
    <div class="modal-footer">
      <button type="button" class="button-ghost" phx-click="back_to_search" phx-target={@myself}>
        <%= gettext("Back") %>
      </button>
    </div>
    """
  end

  attr(:market, :any, required: true)
  attr(:idx, :integer, required: true)
  attr(:myself, :any, required: true)
  slot(:inner_block)

  defp market_button(assigns) do
    ~H"""
    <button
      type="button"
      class="search-result"
      phx-click="pick_market"
      phx-value-idx={@idx}
      phx-target={@myself}
    >
      <span class="result-title">
        <%= @market.exchange_name || @market.exchange_code || gettext("Market") %>
      </span>
      <span class="result-meta">
        <%= [@market.symbol, @market.currency_code] |> Enum.reject(&is_nil/1) |> Enum.join(" · ") %>
      </span>
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  # The sensible default first: XETR, else the first EUR-denominated market,
  # else the provider's first. Indexes stay the provider-list indexes so
  # pick_market addresses the original list.
  defp split_markets(markets) do
    indexed = Enum.with_index(markets)

    recommended =
      Enum.find(indexed, fn {market, _idx} -> market.exchange_code == "XETR" end) ||
        Enum.find(indexed, fn {market, _idx} -> market.currency_code == "EUR" end) ||
        List.first(indexed)

    {recommended, Enum.reject(indexed, &(&1 == recommended))}
  end

  defp render_confirm(assigns) do
    assigns = assign(assigns, :record_error, assigns.errors[@record_error])

    ~H"""
    <form id="security-dialog-form" phx-change="form_change" phx-submit="save" phx-target={@myself}>
      <p :if={@record_error} class="alert-error" role="alert"><%= @record_error %></p>
      <%= if @conflict do %>
        <div class="alert-warning" role="alert">
          <strong><%= gettext("This security already exists") %></strong>
          <p><%= conflict_description(@conflict) %></p>
          <div class="alert-actions">
            <button
              type="button"
              class="button-ghost"
              phx-click="merge_into_existing"
              phx-target={@myself}
            >
              <%= gettext("Merge online fields") %>
            </button>
            <button
              type="button"
              class="button-ghost"
              phx-click="open_existing"
              phx-value-id={@conflict.id}
              phx-target={@myself}
            >
              <%= gettext("Show existing") %>
            </button>
          </div>
        </div>
      <% end %>

      <%= if @mode == "crypto" and (@form["currency_code"] == "EUR") do %>
        <p class="alert-info" role="status">
          <%= gettext("Default currency EUR — please confirm or edit.") %>
        </p>
      <% end %>

      <div class="form-grid">
        <.text_field
          name="name"
          label={gettext("Name")}
          value={@form["name"]}
          required={true}
          errors={@errors}
        />
        <.text_field
          name="ticker_symbol"
          label={gettext("Ticker")}
          value={@form["ticker_symbol"]}
          errors={@errors}
        />
        <.text_field
          name="isin"
          label={gettext("ISIN")}
          value={@form["isin"]}
          errors={@errors}
        />
        <.text_field
          name="wkn"
          label={gettext("WKN")}
          value={@form["wkn"]}
          errors={@errors}
        />
        <.select_field
          name="currency_code"
          label={gettext("Currency")}
          value={@form["currency_code"]}
          options={Currencies.options()}
          required={true}
          errors={@errors}
        />
        <.text_field
          name="exchange_code"
          label={gettext("Exchange")}
          value={@form["exchange_code"]}
          errors={@errors}
        />
        <.select_field
          name="asset_class"
          label={gettext("Asset class")}
          value={@form["asset_class"]}
          options={AssetClasses.options()}
          errors={@errors}
        />
        <.select_field
          name="feed"
          label={gettext("Quote feed")}
          value={@form["feed"]}
          options={Feeds.options()}
          errors={@errors}
        />
        <.text_field
          name="feed_url"
          label={gettext("Quote feed URL")}
          value={@form["feed_url"]}
          errors={@errors}
        />
      </div>

      <.bond_fieldset :if={bond_fieldset?(@form, @editing)} form={@form} errors={@errors} />

      <%!-- ADR-0028 §2 escape hatch for providers that never back-adjust
           after a split: forces the raw basis (split factors apply) for this
           security's synced rows. It followed the rest of the master data
           here when issue 804 turned the overview tab into a reading
           surface. Hidden false + checkbox true is the standard
           unchecked-submits-false pattern; the helper is a ⓘ (UX-DR11), not
           three lines under the control. --%>
      <div class="dialog-toggle">
        <label class="dialog-toggle__control">
          <input type="hidden" name="security[treat_quotes_as_raw]" value="false" />
          <input
            type="checkbox"
            name="security[treat_quotes_as_raw]"
            value="true"
            checked={@form["treat_quotes_as_raw"] == "true"}
          />
          <span><%= gettext("Treat synced quotes as raw") %></span>
        </label>
        <details class="metric-tooltip metric-tooltip--inline" data-role="raw-quotes-info">
          <summary aria-label={gettext("About raw quotes")}>ⓘ</summary>
          <p role="tooltip">
            <%= gettext(
              "For providers that never back-adjust pre-split quotes — the display applies the split factors instead."
            ) %>
          </p>
        </details>
      </div>

      <label class="full-width">
        <span><%= gettext("Note") %></span>
        <textarea name="security[note]" rows="3"><%= @form["note"] %></textarea>
      </label>

      <div class="modal-footer">
        <%= if @editing do %>
          <button
            type="button"
            class="button-ghost"
            phx-click="close"
            phx-target={@myself}
          >
            <%= gettext("Cancel") %>
          </button>
          <button type="submit" class="button-primary">
            <%= gettext("Save changes") %>
          </button>
        <% else %>
          <button
            type="button"
            class="button-ghost"
            phx-click="back_from_confirm"
            phx-target={@myself}
          >
            <%= gettext("Back") %>
          </button>
          <button type="submit" class="button-primary">
            <%= if @conflict, do: gettext("Update existing"), else: gettext("Save") %>
          </button>
        <% end %>
      </div>
    </form>
    """
  end

  attr(:form, :map, required: true)
  attr(:errors, :map, required: true)

  # #330 (pick H3, F1 and F2): the bond section, shown while the asset class
  # reads one of the two bond classes, on create and on edit alike. Its
  # anatomy is the booking drawer's settlement block: a block that stands
  # only when it applies. The denomination's currency starts on the
  # security's until someone changes it, and is written only beside a
  # denomination (read_params/2).
  defp bond_fieldset(assigns) do
    assigns =
      assign(
        assigns,
        :face_currency,
        assigns.form["face_value_currency_code"] || assigns.form["currency_code"]
      )

    ~H"""
    <fieldset class="bond-fieldset" data-role="bond-fields">
      <legend><%= gettext("Bond data") %></legend>
      <div class="form-grid">
        <.decimal_field
          name="coupon_rate"
          label={gettext("Coupon p. a. (%)")}
          value={@form["coupon_rate"]}
          errors={@errors}
        />
        <.select_field
          name="coupon_frequency"
          label={gettext("Interest payment")}
          value={@form["coupon_frequency"]}
          options={[{gettext("annual"), "annual"}, {gettext("semi-annual"), "semi_annual"}]}
          errors={@errors}
        />
        <.date_field
          name="maturity_date"
          label={gettext("Maturity")}
          value={@form["maturity_date"]}
          errors={@errors}
        />
        <.date_field
          name="issue_date"
          label={gettext("Issue date (optional)")}
          value={@form["issue_date"]}
          errors={@errors}
        />
        <.decimal_field
          name="face_value"
          label={gettext("Denomination (face value)")}
          value={@form["face_value"]}
          errors={@errors}
        />
        <.select_field
          name="face_value_currency_code"
          label={gettext("Face value currency")}
          value={@face_currency}
          options={Currencies.options()}
          errors={@errors}
        />
      </div>
      <p class="form-help">
        <%= gettext(
          "In the holding, one unit is a hundredth of the nominal: 100 units are a nominal of 10,000. That is how a Portfolio Performance export books a percent-quoted bond, and why its price reads as percent of face."
        ) %>
      </p>
    </fieldset>
    """
  end

  attr(:name, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :string, default: "")
  attr(:errors, :map, default: %{})

  # The numeric-input rule (DESIGN.md → Numeric inputs): the page's
  # separator, never grouped, read strictly by `DecimalInput`.
  defp decimal_field(assigns) do
    ~H"""
    <label>
      <span><%= @label %></span>
      <input
        type="text"
        inputmode="decimal"
        class="num"
        name={"security[" <> @name <> "]"}
        value={@value || ""}
        aria-invalid={@errors[@name] && "true"}
      />
      <%= if msg = @errors[@name] do %>
        <span class="field-error"><%= msg %></span>
      <% end %>
    </label>
    """
  end

  attr(:name, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :string, default: "")
  attr(:errors, :map, default: %{})

  # An ISO text field (UX-DR19), as in the other dialogs.
  defp date_field(assigns) do
    ~H"""
    <label>
      <span><%= @label %></span>
      <input
        type="text"
        placeholder="YYYY-MM-DD"
        pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}"
        maxlength="10"
        name={"security[" <> @name <> "]"}
        value={@value || ""}
        aria-invalid={@errors[@name] && "true"}
      />
      <%= if msg = @errors[@name] do %>
        <span class="field-error"><%= msg %></span>
      <% end %>
    </label>
    """
  end

  attr(:name, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :string, default: "")
  attr(:required, :boolean, default: false)
  attr(:maxlength, :any, default: nil)
  attr(:errors, :map, default: %{})

  defp text_field(assigns) do
    ~H"""
    <label>
      <span><%= @label %></span>
      <input
        type="text"
        name={"security[" <> @name <> "]"}
        value={@value || ""}
        required={@required}
        maxlength={@maxlength}
      />
      <%= if msg = @errors[@name] do %>
        <span class="field-error"><%= msg %></span>
      <% end %>
    </label>
    """
  end

  attr(:name, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :string, default: nil)
  attr(:options, :list, required: true, doc: "List of `{label, value}` tuples or plain values.")
  attr(:required, :boolean, default: false)
  attr(:errors, :map, default: %{})

  defp select_field(assigns) do
    assigns = assign(assigns, :options, normalize_options(assigns.options))

    ~H"""
    <label>
      <span><%= @label %></span>
      <select name={"security[" <> @name <> "]"} required={@required}>
        <option value=""><%= gettext("—") %></option>
        <%= for {opt_label, opt_value} <- @options do %>
          <option value={opt_value} selected={@value == opt_value}><%= opt_label %></option>
        <% end %>
      </select>
      <%= if msg = @errors[@name] do %>
        <span class="field-error"><%= msg %></span>
      <% end %>
    </label>
    """
  end

  defp normalize_options(options) do
    Enum.map(options, fn
      {label, value} -> {label, value}
      value -> {to_string(value), value}
    end)
  end

  defp dialog_title(:choose, _), do: gettext("Add new")
  defp dialog_title(:search, "crypto"), do: gettext("Search cryptocurrency")
  defp dialog_title(:search, _), do: gettext("Search security")
  defp dialog_title(:market, _), do: gettext("Choose market")
  defp dialog_title(:confirm, "edit"), do: gettext("Edit security")
  defp dialog_title(:confirm, "manual"), do: gettext("Enter security details")
  defp dialog_title(:confirm, _), do: gettext("Confirm details")

  defp provider_label(:portfolio_performance), do: "Portfolio Performance"
  defp provider_label(:coingecko), do: "CoinGecko"
  defp provider_label(:fake), do: "Fake"
  defp provider_label(other), do: to_string(other)

  defp conflict_description(security) do
    parts =
      [security.name, security.ticker_symbol, security.isin]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" · ")

    gettext("Matching existing entry: %{summary}", summary: parts)
  end

  # -- events ---------------------------------------------------------------

  @impl true
  def handle_event("close", _params, socket) do
    notify_parent(socket, :close)
    {:noreply, socket}
  end

  # Manual entry (#491): no provider round-trip — straight to the details
  # form with an empty, EUR-defaulted form.
  def handle_event("choose_mode", %{"mode" => "manual"}, socket) do
    {:noreply,
     socket
     |> assign(:mode, "manual")
     |> assign(:selected_result, nil)
     |> assign(:selected_market, nil)
     |> assign(:conflict, nil)
     |> assign(:errors, %{})
     |> assign(:form, manual_form())
     |> assign(:step, :confirm)}
  end

  def handle_event("choose_mode", %{"mode" => mode}, socket)
      when mode in ["security", "crypto"] do
    {:noreply,
     socket
     |> assign(:mode, mode)
     |> assign(:step, :search)
     |> assign(:results, [])
     |> assign(:query, "")}
  end

  def handle_event("search_change", %{"dialog_query" => query}, socket) do
    {:noreply, run_search(assign(socket, :query, LiveParam.string(query) || ""))}
  end

  def handle_event("search_submit", %{"dialog_query" => query}, socket) do
    {:noreply, run_search(assign(socket, :query, LiveParam.string(query) || ""))}
  end

  def handle_event("pick_result", %{"idx" => idx}, socket) do
    case pick(socket.assigns.results, idx) do
      nil ->
        {:noreply, socket}

      %SearchResult{markets: markets} = result when length(markets) > 1 ->
        {:noreply,
         socket
         |> assign(:selected_result, result)
         |> assign(:selected_market, nil)
         |> assign(:step, :market)}

      %SearchResult{markets: markets} = result ->
        market = List.first(markets)

        {:noreply,
         socket
         |> assign(:selected_result, result)
         |> assign(:selected_market, market)
         |> assign(:step, :confirm)
         |> assign(:form, build_form(result, market, socket.assigns.mode))
         |> assign(:conflict, nil)
         |> check_conflict()}
    end
  end

  def handle_event("pick_market", %{"idx" => idx}, socket) do
    with %SearchResult{} = result <- socket.assigns.selected_result,
         market when not is_nil(market) <- pick(result.markets, idx) do
      {:noreply,
       socket
       |> assign(:selected_market, market)
       |> assign(:step, :confirm)
       |> assign(:form, build_form(result, market, socket.assigns.mode))
       |> assign(:conflict, nil)
       |> check_conflict()}
    else
      _nothing_picked -> {:noreply, socket}
    end
  end

  def handle_event("back_to_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, :search)
     |> assign(:selected_market, nil)
     |> assign(:selected_result, nil)}
  end

  def handle_event("back_from_confirm", _params, socket) do
    cond do
      is_nil(socket.assigns.selected_result) ->
        # Manual entry has no search behind it — back returns to the choice.
        {:noreply, assign(socket, :step, :choose)}

      length(socket.assigns.selected_result.markets) > 1 ->
        {:noreply, assign(socket, :step, :market)}

      true ->
        {:noreply, assign(socket, :step, :search) |> assign(:selected_result, nil)}
    end
  end

  def handle_event("form_change", %{"security" => params}, socket) do
    {:noreply, assign(socket, :form, Map.merge(socket.assigns.form, LiveParam.form(params)))}
  end

  def handle_event("save", %{"security" => params}, socket) do
    params = LiveParam.form(params)

    case read_params(params, blank_mode(socket)) do
      {:ok, attrs} -> save(socket, attrs)
      {:error, refused, attrs} -> {:noreply, refuse(socket, refused, attrs)}
    end
  end

  # The merge and the open act on the conflict the dialog found; without one
  # a push of either changes nothing (E25 S4, F17).
  def handle_event(
        "merge_into_existing",
        _params,
        %{assigns: %{conflict: %Security{} = existing, selected_result: %SearchResult{} = result}} =
          socket
      ) do
    market = socket.assigns.selected_market

    with {:ok, form_overrides} <- read_params(socket.assigns.form, :drop),
         {:ok, security} <-
           Catalog.merge_search_result(Actor.owner_ui(), existing, result, market, form_overrides) do
      notify_parent(socket, {:updated, security})
      {:noreply, socket}
    else
      # #1072 (board 08.3): the match was deleted or merged away while the
      # dialog was open. The atom went into the errors assign, which the
      # render reads as a map, and the LiveView crashed; the page now runs
      # H8.6 for it, as for any row whose action finds it gone.
      {:error, :not_found} ->
        notify_parent(socket, {:conflict_vanished, existing})
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :errors, changeset_errors(changeset))}

      {:error, refused, attrs} ->
        {:noreply, refuse(socket, refused, attrs)}
    end
  end

  def handle_event("open_existing", %{"id" => _id}, %{assigns: %{conflict: %Security{}}} = socket) do
    notify_parent(socket, {:open_existing, socket.assigns.conflict})
    {:noreply, socket}
  end

  # An event this component does not know, or a payload it cannot read,
  # changes nothing (E25 S4, F17).
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp save(socket, attrs) do
    cond do
      socket.assigns.editing ->
        update_security(socket, socket.assigns.editing, attrs)

      socket.assigns.conflict ->
        update_security(socket, socket.assigns.conflict, attrs, :conflict)

      is_nil(socket.assigns.selected_result) ->
        # Manual entry (#491): create straight from the form, no provider
        # payload — the security carries the manual provider marker.
        attrs = Map.put_new(attrs, :provider, "manual")

        case Catalog.create_security(Actor.owner_ui(), attrs) do
          {:ok, security} ->
            notify_parent(socket, {:created, security})
            {:noreply, socket}

          {:error, changeset} ->
            {:noreply, assign(socket, :errors, changeset_errors(changeset))}
        end

      true ->
        result = socket.assigns.selected_result
        market = socket.assigns.selected_market

        case Catalog.create_from_search_result(Actor.owner_ui(), result, market, attrs) do
          {:ok, security} ->
            notify_parent(socket, {:created, security})
            {:noreply, socket}

          {:conflict, existing} ->
            {:noreply, assign(socket, :conflict, existing)}

          {:error, changeset} ->
            {:noreply, assign(socket, :errors, changeset_errors(changeset))}
        end
    end
  end

  # The entry a list index names, or nil for an index that is not one.
  defp pick(entries, idx) do
    case LiveParam.integer(idx, 0..(length(entries) - 1)//1) do
      nil -> nil
      index -> Enum.at(entries, index)
    end
  end

  defp run_search(socket) do
    query = String.trim(socket.assigns.query)

    if query == "" do
      assign(socket, :results, []) |> assign(:search_error, nil)
    else
      {:ok, all_results} = SecuritySearch.search(query)
      results = filter_by_mode(all_results, socket.assigns.mode)

      socket
      |> assign(:results, results)
      |> assign(:search_error, nil)
    end
  end

  defp filter_by_mode(results, "crypto") do
    Enum.filter(results, fn r -> r.asset_class == "crypto" or r.provider == :coingecko end)
  end

  defp filter_by_mode(results, "security") do
    Enum.reject(results, fn r -> r.asset_class == "crypto" end)
  end

  defp filter_by_mode(results, _), do: results

  defp build_form(%SearchResult{} = result, market, mode) do
    base = SearchResult.to_security_attrs(result, market)

    %{
      "name" => base[:name] || "",
      "ticker_symbol" => base[:ticker_symbol] || "",
      "isin" => base[:isin] || "",
      "wkn" => base[:wkn] || "",
      "currency_code" => default_currency(base[:currency_code], mode),
      "exchange_code" => base[:exchange_code] || "",
      "asset_class" => base[:asset_class] || "",
      "feed" => base[:feed] || "",
      "feed_url" => base[:feed_url] || "",
      "note" => ""
    }
  end

  defp default_currency(nil, "crypto"), do: "EUR"
  defp default_currency("", "crypto"), do: "EUR"
  defp default_currency(nil, _), do: ""
  defp default_currency(value, _), do: value

  # The empty form for manual entry (#491): EUR pre-picked so the required
  # currency select starts on the sensible local default.
  defp manual_form do
    %{
      "name" => "",
      "ticker_symbol" => "",
      "isin" => "",
      "wkn" => "",
      "currency_code" => "EUR",
      "exchange_code" => "",
      "asset_class" => "",
      "feed" => "",
      "feed_url" => "",
      "note" => ""
    }
  end

  defp check_conflict(socket) do
    case Catalog.find_matching_security(
           socket.assigns.selected_result,
           socket.assigns.selected_market
         ) do
      {:exists, existing} -> assign(socket, :conflict, existing)
      :not_found -> socket
    end
  end

  # The form's params as the write's attributes: the bond section's figures
  # read in the page's locale (a refused one is an error on its field, in
  # the page's language); every other field as `to_overrides/1` has always
  # read it.
  #
  # An emptied bond field clears its value only while editing (`:clear`),
  # where the section was filled from the security being saved. On every
  # other path (`:drop`), a create and above all the two conflict paths,
  # whose section starts blank over a security that may carry master data,
  # a blank field is no change. On every path the denomination's currency
  # is written only beside a denomination: its select only starts on the
  # security's currency, and a save that sets no face value must not store
  # that preset (#330, closing act on U7, findings 1 and 8).
  #
  # A refused figure answers `{:error, refused, attrs}`: the refusals, and
  # the attributes the rest of the form reads as, for `refuse/3`.
  defp read_params(params, blank) do
    {bond, rest} = Map.split(params, Map.keys(@bond_fields))
    attrs = &(rest |> to_overrides() |> Map.merge(bond_attrs(&1, blank)))

    case DecimalInput.cast(bond, @bond_decimals) do
      {:ok, bond} ->
        {:ok, attrs.(bond)}

      {:error, refused} ->
        {:ok, readable} = DecimalInput.cast(Map.drop(bond, Map.keys(refused)), @bond_decimals)
        {:error, refused, attrs.(readable)}
    end
  end

  # A figure the page cannot read stops the write, but the rest of the form
  # is checked in the same round (closing act on U7, finding 7): the
  # security's changeset runs over what was readable, writing nothing, and
  # its errors stand beside the refusals, a refusal keeping its own field.
  defp refuse(socket, refused, attrs) do
    checked =
      (socket.assigns.editing || socket.assigns.conflict || %Security{})
      |> Security.changeset(attrs)
      |> changeset_errors()

    assign(socket, :errors, Map.merge(checked, refused))
  end

  defp bond_attrs(bond, blank), do: bond |> read_bond(blank) |> currency_with_denomination()

  defp read_bond(bond, :clear),
    do: Map.new(bond, fn {key, value} -> {@bond_fields[key], blank_to_nil(value)} end)

  defp read_bond(bond, :drop) do
    bond
    |> Enum.flat_map(fn {key, value} ->
      case blank_to_nil(value) do
        nil -> []
        value -> [{@bond_fields[key], value}]
      end
    end)
    |> Map.new()
  end

  defp currency_with_denomination(%{face_value: %Decimal{}} = attrs), do: attrs

  defp currency_with_denomination(attrs),
    do: Map.delete(attrs, :face_value_currency_code)

  # Only an edit's section starts on the stored values, so only there does
  # a blank field mean "clear it".
  defp blank_mode(%{assigns: %{editing: %Security{}}}), do: :clear
  defp blank_mode(_socket), do: :drop

  defp blank_to_nil(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)

  defp blank_to_nil(value), do: value

  # Only the form's own fields (#942); any other key is dropped, where an
  # unknown one used to throw the whole form away.
  defp to_overrides(params) when is_map(params) do
    for {key, value} <- params,
        Map.has_key?(@form_fields, key),
        value not in [nil, ""],
        into: %{},
        do: {Map.fetch!(@form_fields, key), value}
  end

  # Editing a security, or "Update existing" on the match the search found:
  # the same write and the same answers, but one. A match gone meanwhile is
  # the page's H8.6 note, as for "Merge online fields" — neither conflict
  # button has anything left to act on (#1072, board 08.3).
  defp update_security(socket, security, attrs, mode \\ :edit) do
    case Catalog.update_security(Actor.owner_ui(), security, attrs) do
      {:ok, updated} ->
        notify_parent(socket, {:updated, updated})
        {:noreply, socket}

      {:error, :not_found} when mode == :conflict ->
        notify_parent(socket, {:conflict_vanished, security})
        {:noreply, socket}

      # Deleted in the meantime (E25 S6, F49): a form-level alert about the
      # record, never an error on a field (review round, R5).
      {:error, :not_found} ->
        {:noreply,
         assign(socket, :errors, %{
           @record_error =>
             gettext(
               "This security no longer exists: it was deleted after the dialog opened, so nothing was saved."
             )
         })}

      {:error, changeset} ->
        {:noreply, assign(socket, :errors, changeset_errors(changeset))}
    end
  end

  # #921, pick H8.3 (board 08-dialogs-copy): every field error in the page's
  # language. A plain changeset message goes through the `errors` domain, as
  # on the other surfaces; the currency freeze (ADR-0050 §11) is built in the
  # domain with English nouns for the API and MCP, so the dialog states it
  # with its own words and counts what freezes the security now.
  defp changeset_errors(%Ecto.Changeset{data: data} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_error(&1, data))
    |> Map.new(fn {field, msgs} -> {Atom.to_string(field), Enum.join(msgs, ", ")} end)
  end

  defp translate_error(error, data) do
    # #965: a refusal that names another security keeps the dialog's sentence.
    {msg, opts} = NamedRecordRefusal.screen(error)

    cond do
      opts[:validation] == :frozen and match?(%Security{id: id} when is_integer(id), data) ->
        data |> Freeze.freezing_references() |> ReferenceCounts.frozen()

      count = opts[:count] ->
        Gettext.dngettext(PortfolixirWeb.Gettext, "errors", msg, msg, count, opts)

      true ->
        Gettext.dgettext(PortfolixirWeb.Gettext, "errors", msg, opts)
    end
  end

  defp notify_parent(socket, message) do
    send(self(), {:dialog, socket.assigns.id, message})
  end
end
