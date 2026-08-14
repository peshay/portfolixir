defmodule PortfolixirWeb.Securities.SecurityFormDialog do
  @moduledoc "Modal dialog for creating and editing a security."
  use Phoenix.LiveComponent
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Phoenix.LiveView.JS
  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.AssetClasses
  alias Portfolixir.Catalog.Currencies
  alias Portfolixir.Catalog.Feeds
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecuritySearch
  alias Portfolixir.Catalog.SecuritySearch.SearchResult
  alias PortfolixirWeb.AppShell

  @impl true
  def mount(socket) do
    {:ok,
     socket
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
      "note" => security.note || ""
    }
  end

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
    <p class="dialog-help"><%= gettext("Pick the market to import for") %> <strong><%= @selected_result.name %></strong>:</p>
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
    ~H"""
    <form id="security-dialog-form" phx-change="form_change" phx-submit="save" phx-target={@myself}>
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

  def handle_event("choose_mode", %{"mode" => mode}, socket) do
    {:noreply,
     socket
     |> assign(:mode, mode)
     |> assign(:step, :search)
     |> assign(:results, [])
     |> assign(:query, "")}
  end

  def handle_event("search_change", %{"dialog_query" => query}, socket) do
    {:noreply, run_search(assign(socket, :query, query))}
  end

  def handle_event("search_submit", %{"dialog_query" => query}, socket) do
    {:noreply, run_search(assign(socket, :query, query))}
  end

  def handle_event("pick_result", %{"idx" => idx}, socket) do
    case Enum.at(socket.assigns.results, String.to_integer(idx)) do
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
    result = socket.assigns.selected_result
    market = Enum.at(result.markets, String.to_integer(idx))

    {:noreply,
     socket
     |> assign(:selected_market, market)
     |> assign(:step, :confirm)
     |> assign(:form, build_form(result, market, socket.assigns.mode))
     |> assign(:conflict, nil)
     |> check_conflict()}
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
    {:noreply, assign(socket, :form, Map.merge(socket.assigns.form, params))}
  end

  def handle_event("save", %{"security" => params}, socket) do
    cond do
      socket.assigns.editing ->
        attrs = to_overrides(params)

        case Catalog.update_security(Actor.owner_ui(), socket.assigns.editing, attrs) do
          {:ok, security} ->
            notify_parent(socket, {:updated, security})
            {:noreply, socket}

          {:error, changeset} ->
            {:noreply, assign(socket, :errors, changeset_errors(changeset))}
        end

      socket.assigns.conflict ->
        existing = socket.assigns.conflict
        attrs = to_overrides(params)

        case Catalog.update_security(Actor.owner_ui(), existing, attrs) do
          {:ok, security} ->
            notify_parent(socket, {:updated, security})
            {:noreply, socket}

          {:error, changeset} ->
            {:noreply, assign(socket, :errors, changeset_errors(changeset))}
        end

      is_nil(socket.assigns.selected_result) ->
        # Manual entry (#491): create straight from the form, no provider
        # payload — the security carries the manual provider marker.
        attrs = params |> to_overrides() |> Map.put_new(:provider, "manual")

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
        overrides = to_overrides(params)

        case Catalog.create_from_search_result(Actor.owner_ui(), result, market, overrides) do
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

  def handle_event("merge_into_existing", _params, socket) do
    existing = socket.assigns.conflict
    result = socket.assigns.selected_result
    market = socket.assigns.selected_market
    form_overrides = to_overrides(socket.assigns.form)

    case Catalog.merge_search_result(Actor.owner_ui(), existing, result, market, form_overrides) do
      {:ok, security} ->
        notify_parent(socket, {:updated, security})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :errors, changeset_errors(changeset))}
    end
  end

  def handle_event("open_existing", %{"id" => _id}, socket) do
    notify_parent(socket, {:open_existing, socket.assigns.conflict})
    {:noreply, socket}
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

  defp to_overrides(params) when is_map(params) do
    params
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
    |> Map.new()
  rescue
    ArgumentError -> %{}
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
    |> Enum.map(fn {field, msgs} -> {Atom.to_string(field), Enum.join(msgs, ", ")} end)
    |> Map.new()
  end

  defp notify_parent(socket, message) do
    send(self(), {:dialog, socket.assigns.id, message})
  end
end
