defmodule PortfolixirWeb.ImportsLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Imports
  alias Portfolixir.Imports.Mapping
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.AppShell

  @max_upload_bytes 20_000_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:stage, :idle)
      |> assign(:preview, nil)
      |> assign(:result, nil)
      |> assign(:error, nil)
      |> reload_lookups()
      |> assign(:mapping, blank_mapping())
      |> allow_upload(:pp_file,
        accept: ~w(.csv .json application/json text/csv text/plain),
        max_entries: 1,
        max_file_size: @max_upload_bytes,
        auto_upload: true,
        progress: &handle_upload_progress/3
      )

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current_path="/imports">
      <header class="page-header">
        <h1><%= gettext("Imports") %></h1>
        <p><%= gettext("Bulk-import Portfolio Performance CSV or JSON exports.") %></p>
      </header>

      <%= if @error do %>
        <p class="alert-error" role="alert"><%= @error %></p>
      <% end %>

      <%= case @stage do %>
        <% :idle -> %>
          <%= render_idle(assigns) %>
        <% :preview -> %>
          <%= render_preview(assigns) %>
        <% :done -> %>
          <%= render_done(assigns) %>
      <% end %>
    </AppShell.shell>
    """
  end

  defp render_idle(assigns) do
    ~H"""
    <div id="pp-import-drop" class="stack" phx-hook="PPImportDrop" phx-drop-target={@uploads.pp_file.ref}>
      <form id="pp-import-form" class="panel import-drop-zone" phx-submit="parse" phx-change="validate">
        <svg class="import-drop-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M12 3v12" />
          <path d="M7 8l5-5 5 5" />
          <path d="M5 19h14" />
        </svg>
        <h2><%= gettext("Drop a Portfolio Performance export here") %></h2>
        <p class="muted">
          <%= gettext("CSV or JSON v1 · max 20 MB · nothing is saved before you confirm") %>
        </p>

        <.live_file_input upload={@uploads.pp_file} class="visually-hidden" />
        <button type="button" class="button-primary" data-import-file-button>
          <%= gettext("Choose file") %>
        </button>

        <%= for entry <- @uploads.pp_file.entries do %>
          <p class="muted upload-progress">
            <%= entry.client_name %> · <%= entry.progress %>%
          </p>
          <%= for err <- upload_errors(@uploads.pp_file, entry) do %>
            <p class="alert-error"><%= error_to_string(err) %></p>
          <% end %>
        <% end %>
      </form>
    </div>
    """
  end

  defp render_preview(assigns) do
    assigns =
      assign(assigns,
        kind_counts: Enum.sort(Preview.counts_by_kind(assigns.preview)),
        unique_securities_count: length(Preview.unique_securities(assigns.preview)),
        total_entries: total_entries(assigns.preview)
      )

    ~H"""
    <section class="panel">
      <h2><%= gettext("Preview") %></h2>
      <p class="muted">
        <%= gettext("Source format: %{format}",
          format: assigns.preview.format |> to_string() |> String.upcase()
        ) %>
      </p>

      <div class="import-stats">
        <div class="import-stat-card">
          <span class="label"><%= gettext("Entries") %></span>
          <span class="value"><%= @total_entries %></span>
        </div>
        <div class="import-stat-card">
          <span class="label"><%= gettext("Securities") %></span>
          <span class="value"><%= @unique_securities_count %></span>
        </div>
        <div class="import-stat-card">
          <span class="label"><%= gettext("Cash accounts") %></span>
          <span class="value"><%= length(@cash_pp_names) %></span>
        </div>
        <div class="import-stat-card">
          <span class="label"><%= gettext("Depots") %></span>
          <span class="value"><%= length(@depot_pp_names) %></span>
        </div>
        <%= if @preview.errors != [] do %>
          <div class="import-stat-card warning">
            <span class="label"><%= gettext("Warnings") %></span>
            <span class="value"><%= length(@preview.errors) %></span>
          </div>
        <% end %>
      </div>

      <h3><%= gettext("Counts by kind") %></h3>
      <ul class="kind-chips">
        <%= for {kind, count} <- @kind_counts do %>
          <li class="kind-chip" data-family={kind_family(kind)}>
            <span class="name"><%= kind %></span>
            <span class="count"><%= count %></span>
          </li>
        <% end %>
      </ul>

      <%= if @preview.errors != [] do %>
        <details>
          <summary><%= gettext("Parser warnings") %></summary>
          <ul>
            <%= for err <- @preview.errors do %>
              <li>Row <%= err.row %>: <%= err.message %></li>
            <% end %>
          </ul>
        </details>
      <% end %>

      <form id="pp-import-apply" phx-change="mapping_changed" phx-submit="apply">
        <section class="panel inner">
          <h3><%= gettext("Target portfolio") %></h3>
          <label>
            <span><%= gettext("Portfolio") %></span>
            <select name="portfolio_choice">
              <%= for p <- @portfolios do %>
                <option value={"existing:#{p.id}"} selected={@mapping.portfolio_choice == "existing:#{p.id}"}>
                  <%= p.name %> (<%= p.base_currency_code %>)
                </option>
              <% end %>
              <option value="create" selected={@mapping.portfolio_choice == "create"}>
                <%= gettext("+ Create new portfolio") %>
              </option>
            </select>
          </label>

          <%= if @mapping.portfolio_choice == "create" do %>
            <label>
              <span><%= gettext("New portfolio name") %></span>
              <input type="text" name="portfolio_name" value={@mapping.portfolio_name}
                     placeholder={gettext("e.g. PP Import")} />
            </label>
            <label>
              <span><%= gettext("Base currency") %></span>
              <input type="text" name="portfolio_currency" value={@mapping.portfolio_currency}
                     maxlength="3" />
            </label>
          <% end %>
        </section>

        <%= if @cash_pp_names != [] do %>
          <section class="panel inner">
            <h3><%= gettext("Cash accounts from the export") %></h3>
            <div class="mapping-grid">
              <%= for pp_name <- @cash_pp_names do %>
                <div class="mapping-row">
                  <div class="source">
                    <small><%= gettext("PP account") %></small>
                    <%= pp_name %>
                  </div>
                  <select name={"cash[#{pp_name}]"}>
                    <option value={"create:#{pp_name}"} selected={cash_value(@mapping, pp_name) == "create:#{pp_name}"}>
                      <%= gettext("+ Create new: %{name}", name: pp_name) %>
                    </option>
                    <%= for c <- @existing_cash do %>
                      <option value={"existing:#{c.id}"} selected={cash_value(@mapping, pp_name) == "existing:#{c.id}"}>
                        <%= c.name %>
                      </option>
                    <% end %>
                  </select>
                </div>
              <% end %>
            </div>
          </section>
        <% end %>

        <%= if @depot_pp_names != [] do %>
          <section class="panel inner">
            <h3><%= gettext("Depots from the export") %></h3>
            <div class="mapping-grid">
              <%= for pp_name <- @depot_pp_names do %>
                <div class="mapping-row depot">
                  <div class="source">
                    <small><%= gettext("PP depot") %></small>
                    <%= pp_name %>
                  </div>
                  <select name={"depot[#{pp_name}][target]"}>
                    <option value={"create:#{pp_name}"} selected={depot_target_value(@mapping, pp_name) == "create:#{pp_name}"}>
                      <%= gettext("+ Create new: %{name}", name: pp_name) %>
                    </option>
                    <%= for d <- @existing_depots do %>
                      <option value={"existing:#{d.id}"} selected={depot_target_value(@mapping, pp_name) == "existing:#{d.id}"}>
                        <%= d.name %>
                      </option>
                    <% end %>
                  </select>
                  <select name={"depot[#{pp_name}][cash]"}>
                    <option value="" selected={depot_cash_value(@mapping, pp_name) in [nil, ""]}>
                      <%= gettext("Pick a cash account…") %>
                    </option>
                    <%= for cash_pp <- @cash_pp_names do %>
                      <option value={"pp:#{cash_pp}"} selected={depot_cash_value(@mapping, pp_name) == "pp:#{cash_pp}"}>
                        <%= gettext("(import) %{name}", name: cash_pp) %>
                      </option>
                    <% end %>
                    <%= for c <- @existing_cash do %>
                      <option value={"existing:#{c.id}"} selected={depot_cash_value(@mapping, pp_name) == "existing:#{c.id}"}>
                        <%= c.name %>
                      </option>
                    <% end %>
                  </select>
                </div>
              <% end %>
            </div>
          </section>
        <% end %>

        <p class="muted">
          <%= gettext(
            "Missing securities will be created automatically inside the chosen portfolio."
          ) %>
        </p>

        <div class="actions">
          <button type="submit" id="pp-import-confirm" class="button-primary"
                  disabled={not mapping_complete?(assigns)}>
            <%= gettext("Confirm import") %>
          </button>
          <button type="button" phx-click="reset"><%= gettext("Discard") %></button>
        </div>
      </form>
    </section>
    """
  end

  defp render_done(assigns) do
    ~H"""
    <section class="panel import-done">
      <svg class="success-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor"
           stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="M5 12l5 5L20 7" />
      </svg>
      <h2><%= gettext("Import complete") %></h2>
      <p class="muted">
        <%= gettext("Created transactions: %{n}", n: @result.created_transactions) %>
        ·
        <%= gettext("Skipped duplicates: %{n}", n: @result.skipped_duplicates) %>
      </p>

      <div class="summary">
        <div class="import-stat-card">
          <span class="label"><%= gettext("Securities") %></span>
          <span class="value"><%= @result.created_securities %></span>
        </div>
        <div class="import-stat-card">
          <span class="label"><%= gettext("Cash accounts") %></span>
          <span class="value"><%= @result.created_cash_accounts %></span>
        </div>
        <div class="import-stat-card">
          <span class="label"><%= gettext("Depots") %></span>
          <span class="value"><%= @result.created_securities_accounts %></span>
        </div>
      </div>

      <div class="actions">
        <button type="button" class="button-primary" phx-click="reset">
          <%= gettext("Import another file") %>
        </button>
        <.link href="/transactions" class="button-secondary"><%= gettext("View transactions") %></.link>
      </div>
    </section>
    """
  end

  # Group transaction kinds for chip colour coding in the preview.
  defp kind_family(kind) do
    case kind do
      k when k in ["buy", "sell"] ->
        "trade"

      k when k in ["dividend", "interest", "tax_refund"] ->
        "income"

      k when k in ["fee", "tax", "removal"] ->
        "cost"

      k
      when k in ["cash_transfer", "security_transfer", "inbound_delivery", "outbound_delivery"] ->
        "transfer"

      "deposit" ->
        "cash"

      _ ->
        "cash"
    end
  end

  # --- upload + parse + mapping events ---

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("parse", _params, socket), do: {:noreply, socket}

  def handle_event("mapping_changed", params, socket) do
    {:noreply, assign(socket, :mapping, mapping_from_params(params, socket.assigns.mapping))}
  end

  def handle_event("apply", params, socket) do
    mapping = mapping_from_params(params, socket.assigns.mapping)
    socket = assign(socket, :mapping, mapping)

    case build_apply_params(mapping, socket.assigns) do
      {:ok, applier_params} ->
        case Imports.apply(socket.assigns.preview, applier_params) do
          {:ok, result} ->
            {:noreply,
             socket
             |> assign(:stage, :done)
             |> assign(:result, result)
             |> assign(:error, nil)
             |> reload_lookups()}

          {:error, reason} ->
            {:noreply, assign(socket, :error, apply_error_message(reason))}
        end

      {:error, message} ->
        {:noreply, assign(socket, :error, message)}
    end
  end

  def handle_event("reset", _params, socket) do
    {:noreply,
     socket
     |> assign(:stage, :idle)
     |> assign(:preview, nil)
     |> assign(:result, nil)
     |> assign(:error, nil)
     |> assign(:mapping, blank_mapping())
     |> reload_lookups()}
  end

  defp handle_upload_progress(:pp_file, entry, socket) do
    if entry.done? do
      [{body, filename}] =
        consume_uploaded_entries(socket, :pp_file, fn %{path: path}, e ->
          {:ok, {File.read!(path), e.client_name}}
        end)

      case Imports.parse_portfolio_performance(body, filename: filename) do
        {:ok, %Preview{} = preview} ->
          socket =
            socket
            |> assign(:stage, :preview)
            |> assign(:preview, preview)
            |> assign(:error, nil)
            |> reload_lookups()
            |> assign_preview_pp_names(preview)
            |> assign(:mapping, initial_mapping_for(preview, socket))

          {:noreply, socket}

        {:error, reason} ->
          {:noreply, assign(socket, :error, parse_error_message(reason))}
      end
    else
      {:noreply, socket}
    end
  end

  # --- helpers ---

  defp reload_lookups(socket) do
    portfolios = Portfolios.list_portfolios()
    existing_cash = Portfolios.list_cash_accounts()
    existing_depots = Portfolios.list_securities_accounts()

    socket
    |> assign(:portfolios, portfolios)
    |> assign(:existing_cash, existing_cash)
    |> assign(:existing_depots, existing_depots)
    |> assign_new(:cash_pp_names, fn -> [] end)
    |> assign_new(:depot_pp_names, fn -> [] end)
  end

  defp assign_preview_pp_names(socket, preview) do
    socket
    |> assign(:cash_pp_names, Mapping.unique_cash_pp_names(preview))
    |> assign(:depot_pp_names, Mapping.unique_depot_pp_names(preview))
  end

  defp blank_mapping do
    %{
      portfolio_choice: "create",
      portfolio_name: "PP Import",
      portfolio_currency: "EUR",
      cash: %{},
      depot: %{}
    }
  end

  # Auto-prefill: existing-name match → existing; otherwise create-new.
  defp initial_mapping_for(%Preview{} = preview, socket) do
    existing_cash_by_name = Map.new(socket.assigns.existing_cash, &{&1.name, &1.id})
    existing_depot_by_name = Map.new(socket.assigns.existing_depots, &{&1.name, &1.id})

    cash_pp_names = Mapping.unique_cash_pp_names(preview)
    depot_pp_names = Mapping.unique_depot_pp_names(preview)

    portfolio_choice =
      case socket.assigns.portfolios do
        [] -> "create"
        [first | _] -> "existing:#{first.id}"
      end

    cash =
      Map.new(cash_pp_names, fn pp_name ->
        case Map.fetch(existing_cash_by_name, pp_name) do
          {:ok, id} -> {pp_name, "existing:#{id}"}
          :error -> {pp_name, "create:#{pp_name}"}
        end
      end)

    depot =
      Map.new(depot_pp_names, fn pp_name ->
        target =
          case Map.fetch(existing_depot_by_name, pp_name) do
            {:ok, id} -> "existing:#{id}"
            :error -> "create:#{pp_name}"
          end

        default_cash_pp = Mapping.default_cash_for_depot(preview, pp_name)

        cash_value =
          cond do
            default_cash_pp && default_cash_pp in cash_pp_names -> "pp:#{default_cash_pp}"
            true -> ""
          end

        {pp_name, %{"target" => target, "cash" => cash_value}}
      end)

    %{
      blank_mapping()
      | portfolio_choice: portfolio_choice,
        cash: cash,
        depot: depot
    }
  end

  defp mapping_from_params(params, current) do
    %{
      portfolio_choice: Map.get(params, "portfolio_choice", current.portfolio_choice),
      portfolio_name: Map.get(params, "portfolio_name", current.portfolio_name),
      portfolio_currency: Map.get(params, "portfolio_currency", current.portfolio_currency),
      cash: Map.merge(current.cash, Map.get(params, "cash", %{})),
      depot: Map.merge(current.depot, Map.get(params, "depot", %{}))
    }
  end

  defp cash_value(mapping, pp_name), do: Map.get(mapping.cash, pp_name)

  defp depot_target_value(mapping, pp_name) do
    case Map.get(mapping.depot, pp_name) do
      %{"target" => t} -> t
      _ -> nil
    end
  end

  defp depot_cash_value(mapping, pp_name) do
    case Map.get(mapping.depot, pp_name) do
      %{"cash" => c} -> c
      _ -> nil
    end
  end

  defp total_entries(%Preview{entries: entries}) do
    Enum.reduce(entries, 0, fn e, acc -> acc + 1 + length(e.companion_entries || []) end)
  end

  # True iff every dropdown is filled. Portfolio create needs a name +
  # 3-letter currency; every depot row needs a `target` and a `cash`.
  defp mapping_complete?(%{mapping: m, cash_pp_names: cashes, depot_pp_names: depots}) do
    portfolio_ok? =
      case m.portfolio_choice do
        "create" ->
          is_binary(m.portfolio_name) and String.trim(m.portfolio_name) != "" and
            is_binary(m.portfolio_currency) and String.length(m.portfolio_currency) == 3

        "existing:" <> _ ->
          true

        _ ->
          false
      end

    cash_ok? = Enum.all?(cashes, fn pp -> is_binary(Map.get(m.cash, pp)) end)

    depot_ok? =
      Enum.all?(depots, fn pp ->
        case Map.get(m.depot, pp) do
          %{"target" => t, "cash" => c}
          when is_binary(t) and t != "" and is_binary(c) and c != "" ->
            true

          _ ->
            false
        end
      end)

    portfolio_ok? and cash_ok? and depot_ok?
  end

  defp build_apply_params(mapping, assigns) do
    with {:ok, portfolio} <- portfolio_param(mapping),
         {:ok, cash_params} <- cash_params(mapping, assigns.cash_pp_names),
         {:ok, depot_params} <- depot_params(mapping, assigns.depot_pp_names) do
      {:ok,
       %{
         portfolio: portfolio,
         cash_accounts: cash_params,
         depots: depot_params
       }}
    end
  end

  defp portfolio_param(%{portfolio_choice: "existing:" <> id_str}) do
    case Integer.parse(id_str) do
      {id, ""} -> {:ok, {:existing, id}}
      _ -> {:error, gettext("Invalid portfolio id.")}
    end
  end

  defp portfolio_param(%{
         portfolio_choice: "create",
         portfolio_name: name,
         portfolio_currency: ccy
       })
       when is_binary(name) and is_binary(ccy) do
    {:ok,
     {:create,
      %{name: String.trim(name), base_currency_code: ccy |> String.trim() |> String.upcase()}}}
  end

  defp portfolio_param(_), do: {:error, gettext("Please pick or define a portfolio.")}

  defp cash_params(mapping, pp_names) do
    Enum.reduce_while(pp_names, {:ok, %{}}, fn pp_name, {:ok, acc} ->
      case Map.get(mapping.cash, pp_name) do
        "existing:" <> id_str ->
          case Integer.parse(id_str) do
            {id, ""} -> {:cont, {:ok, Map.put(acc, pp_name, {:existing, id})}}
            _ -> {:halt, {:error, gettext("Invalid cash account id.")}}
          end

        "create:" <> name ->
          {:cont, {:ok, Map.put(acc, pp_name, {:create, name})}}

        _ ->
          {:halt, {:error, gettext("Pick a target for cash account %{n}.", n: pp_name)}}
      end
    end)
  end

  defp depot_params(mapping, pp_names) do
    Enum.reduce_while(pp_names, {:ok, %{}}, fn pp_name, {:ok, acc} ->
      with %{"target" => target_str, "cash" => cash_str} <- Map.get(mapping.depot, pp_name),
           {:ok, target} <- parse_depot_target(target_str),
           {:ok, cash} <- parse_depot_cash(cash_str) do
        {:cont, {:ok, Map.put(acc, pp_name, %{target: target, cash: cash})}}
      else
        _ ->
          {:halt, {:error, gettext("Pick a target and cash account for depot %{n}.", n: pp_name)}}
      end
    end)
  end

  defp parse_depot_target("existing:" <> id_str) do
    case Integer.parse(id_str) do
      {id, ""} -> {:ok, {:existing, id}}
      _ -> :error
    end
  end

  defp parse_depot_target("create:" <> name), do: {:ok, {:create, name}}
  defp parse_depot_target(_), do: :error

  defp parse_depot_cash("existing:" <> id_str) do
    case Integer.parse(id_str) do
      {id, ""} -> {:ok, {:existing, id}}
      _ -> :error
    end
  end

  defp parse_depot_cash("pp:" <> name), do: {:ok, name}
  defp parse_depot_cash(_), do: :error

  defp error_to_string(:too_large), do: gettext("File too large.")
  defp error_to_string(:not_accepted), do: gettext("File type not accepted.")
  defp error_to_string(:too_many_files), do: gettext("Only one file at a time.")
  defp error_to_string(other), do: to_string(other)

  defp parse_error_message(:unknown_format),
    do: gettext("Unknown file format — expected Portfolio Performance JSON or CSV.")

  defp parse_error_message({:unsupported_version, v}),
    do: gettext("Unsupported PP JSON version: %{v}", v: to_string(v))

  defp parse_error_message({:invalid_json, message}),
    do: gettext("Invalid JSON: %{message}", message: message)

  defp parse_error_message({:invalid_csv, message}),
    do: gettext("Invalid CSV: %{message}", message: message)

  defp parse_error_message({:missing_columns, missing}),
    do: gettext("CSV missing columns: %{cols}", cols: Enum.join(missing, ", "))

  defp parse_error_message(:empty_csv), do: gettext("The CSV file is empty.")

  defp parse_error_message(other), do: inspect(other)

  defp apply_error_message(reason), do: inspect(reason)
end
