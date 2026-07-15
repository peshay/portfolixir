defmodule PortfolixirWeb.ImportsLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Buckets
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Mapping
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Imports.PreviewStore
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.AppShell

  @max_upload_bytes 20_000_000

  @impl true
  def mount(_params, session, socket) do
    # Restore in-progress preview across locale-driven remounts.
    # Locale switches change the session's "locale" key and trigger a LiveView
    # remount via live_session :browser / LiveLocale on_mount.  Storing the
    # parsed preview in PreviewStore (keyed by the CSRF token, which is stable
    # across locale changes within the same browser session) lets us jump
    # straight back to the :preview step so the user does not have to re-upload.
    session_token = Map.get(session, "_csrf_token", "")

    {stage, preview, mapping} =
      case PreviewStore.get(session_token) do
        {stored_preview, stored_mapping} -> {:preview, stored_preview, stored_mapping}
        nil -> {:idle, nil, blank_mapping()}
      end

    socket =
      socket
      |> assign(:session_token, session_token)
      |> assign(:stage, stage)
      |> assign(:preview, preview)
      |> assign(:applying, false)
      |> assign(:result, nil)
      |> assign(:error, nil)
      |> reload_lookups()
      |> assign(:mapping, mapping)
      |> maybe_assign_preview_pp_names(preview)
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
    <AppShell.shell
      current_path="/imports"
      page_title={gettext("Imports")}
      page_subtitle={gettext("Bulk-import Portfolio Performance CSV or JSON exports.")}
    >
      <div id="imports-workspace" class="workspace-page">
        <AppShell.area_tabs tabs={AppShell.transactions_tabs(:import)} />

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
      </div>
    </AppShell.shell>
    """
  end

  defp render_idle(assigns) do
    ~H"""
    <div id="pp-import-drop" class="stack" phx-hook="PPImportDrop" phx-drop-target={@uploads.pp_file.ref}>
      <form
        id="pp-import-form"
        class="workspace-section import-drop-zone"
        phx-submit="parse"
        phx-change="validate"
      >
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
    <section class="workspace-section">
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
          <li class="kind-chip">
            <span class="name"><%= kind_label(kind) %></span>
            <span class="count"><%= count %></span>
          </li>
        <% end %>
      </ul>

      <%= if @preview.errors != [] do %>
        <section class="import-warning-box" id="parser-warnings-box" aria-label={gettext("Parser warnings")}>
          <div class="import-warning-box__head">
            <h3><%= gettext("Parser warnings") %></h3>
            <button
              type="button"
              id="copy-parser-warnings"
              class="icon-button"
              phx-click="copy_parser_warnings"
              aria-label={gettext("Copy parser warnings")}
              title={gettext("Copy parser warnings")}
            >
              <AppShell.icon name={:copy} />
            </button>
          </div>
          <pre><%= parser_warning_text(@preview.errors) %></pre>
        </section>
      <% end %>

      <form id="pp-import-apply" phx-change="mapping_changed" phx-submit="apply">
        <section class="panel inner" id="import-bucket-tag">
          <h3><%= gettext("Bucket tag for new accounts") %></h3>
          <p class="muted">
            <%= gettext("The accounts created by this import get the bucket tag:") %>
          </p>
          <label>
            <span><%= gettext("Bucket tag") %></span>
            <input
              type="text"
              name="bucket_tag"
              value={@mapping.bucket_tag}
              disabled={@mapping.bucket_skip}
              maxlength="100"
              placeholder={gettext("e.g. PP Import")}
            />
          </label>
          <label>
            <input type="hidden" name="bucket_skip" value="false" />
            <input
              type="checkbox"
              name="bucket_skip"
              value="true"
              checked={@mapping.bucket_skip}
            />
            <span><%= gettext("No tag — leave the new accounts untagged") %></span>
          </label>
          <p class="muted">
            <%= gettext(
              "An existing bucket with this name is reused. Accounts mapped to existing records keep their current tags."
            ) %>
          </p>
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
          <%= gettext("Missing securities will be created automatically.") %>
        </p>

        <% missing = missing_mappings(assigns) %>
        <%= if not @applying and missing != [] do %>
          <p id="import-missing-hint" class="form-help" role="status">
            <%= gettext("Still to map before import:") %>
            <%= Enum.join(missing, ", ") %>
          </p>
        <% end %>

        <div class="actions">
          <button
            type="submit"
            id="pp-import-confirm"
            class="button-primary"
            phx-disable-with={gettext("Importing…")}
            disabled={not mapping_complete?(assigns) or @applying}
            aria-describedby={if missing != [], do: "import-missing-hint", else: nil}
          >
            <%= if @applying do %>
              <span class="import-spinner" aria-hidden="true"></span>
              <%= gettext("Importing…") %>
            <% else %>
              <%= gettext("Confirm import") %>
            <% end %>
          </button>
          <button type="button" phx-click="reset"><%= gettext("Discard") %></button>
        </div>
      </form>
    </section>
    """
  end

  defp render_done(assigns) do
    ~H"""
    <section class="workspace-section import-done">
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

      <%= if @result.skipped_entries != [] do %>
        <div class="import-skipped" data-role="skipped-entries">
          <p class="muted">
            <%= gettext("Skipped %{n} unimportable record(s):",
              n: length(@result.skipped_entries)
            ) %>
          </p>
          <ul>
            <%= for skip <- @result.skipped_entries do %>
              <li><%= gettext("Row %{row}: %{reason}", row: skip.row, reason: skip.reason) %></li>
            <% end %>
          </ul>
        </div>
      <% end %>

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

  defp kind_label(kind) do
    case kind do
      "buy" -> gettext("Buy")
      "sell" -> gettext("Sell")
      "dividend" -> gettext("Dividend")
      "interest" -> gettext("Interest")
      "deposit" -> gettext("Deposit")
      "removal" -> gettext("Removal")
      "fee" -> gettext("Fee")
      "tax" -> gettext("Tax")
      "tax_refund" -> gettext("Tax refund")
      "cash_transfer" -> gettext("Cash transfer")
      "inbound_delivery" -> gettext("Inbound delivery")
      "outbound_delivery" -> gettext("Outbound delivery")
      "security_transfer" -> gettext("Security transfer")
      other -> other
    end
  end

  # --- upload + parse + mapping events ---

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("parse", _params, socket), do: {:noreply, socket}

  def handle_event("mapping_changed", params, socket) do
    mapping = mapping_from_params(params, socket.assigns.mapping)
    PreviewStore.put(socket.assigns.session_token, socket.assigns.preview, mapping)
    {:noreply, assign(socket, :mapping, mapping)}
  end

  def handle_event("apply", _params, socket) when socket.assigns.applying do
    {:noreply, socket}
  end

  def handle_event("apply", params, socket) do
    mapping = mapping_from_params(params, socket.assigns.mapping)
    socket = assign(socket, :mapping, mapping)

    case build_apply_params(mapping, socket.assigns) do
      {:ok, applier_params} ->
        preview = socket.assigns.preview

        {:noreply,
         socket
         |> assign(:applying, true)
         |> assign(:error, nil)
         |> start_async(:apply_import, fn -> Imports.apply(preview, applier_params) end)}

      {:error, message} ->
        {:noreply, assign(socket, :error, message)}
    end
  end

  def handle_event("reset", _params, socket) do
    PreviewStore.delete(socket.assigns.session_token)

    {:noreply,
     socket
     |> assign(:stage, :idle)
     |> assign(:preview, nil)
     |> assign(:applying, false)
     |> assign(:result, nil)
     |> assign(:error, nil)
     |> assign(:mapping, blank_mapping())
     |> reload_lookups()}
  end

  def handle_event("copy_parser_warnings", _params, socket) do
    text =
      socket.assigns.preview
      |> case do
        %Preview{errors: errors} -> parser_warning_text(errors)
        _ -> ""
      end

    {:noreply, push_event(socket, "copy-to-clipboard", %{text: text})}
  end

  @impl true
  def handle_async(:apply_import, {:ok, {:ok, result}}, socket) do
    PreviewStore.delete(socket.assigns.session_token)

    {:noreply,
     socket
     |> assign(:applying, false)
     |> assign(:stage, :done)
     |> assign(:result, result)
     |> assign(:error, nil)
     |> reload_lookups()}
  end

  def handle_async(:apply_import, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:applying, false)
     |> assign(:error, apply_error_message(reason))}
  end

  def handle_async(:apply_import, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:applying, false)
     |> assign(:error, gettext("Import failed unexpectedly. Please try again."))}
  end

  # The path comes from LiveView's own managed upload temp file, not from
  # user input, so there is no traversal surface here.
  # sobelow_skip ["Traversal.FileModule"]
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

          PreviewStore.put(socket.assigns.session_token, preview, socket.assigns.mapping)

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
    existing_cash = Portfolios.list_cash_accounts()
    existing_depots = Portfolios.list_securities_accounts()

    socket
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

  defp maybe_assign_preview_pp_names(socket, nil), do: socket

  defp maybe_assign_preview_pp_names(socket, preview),
    do: assign_preview_pp_names(socket, preview)

  defp blank_mapping do
    %{
      bucket_tag: default_bucket_tag(),
      bucket_skip: false,
      cash: %{},
      depot: %{}
    }
  end

  # The date-stamped default bucket name is data (a bucket name), not UI
  # copy — deliberately not translated.
  defp default_bucket_tag do
    "PP Import #{Date.to_iso8601(Date.utc_today())}"
  end

  # Auto-prefill: existing-name match → existing; otherwise create-new.
  defp initial_mapping_for(%Preview{} = preview, socket) do
    existing_cash_by_name = Map.new(socket.assigns.existing_cash, &{&1.name, &1.id})
    existing_depot_by_name = Map.new(socket.assigns.existing_depots, &{&1.name, &1.id})

    cash_pp_names = Mapping.unique_cash_pp_names(preview)
    depot_pp_names = Mapping.unique_depot_pp_names(preview)

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
          if default_cash_pp && default_cash_pp in cash_pp_names,
            do: "pp:#{default_cash_pp}",
            else: ""

        {pp_name, %{"target" => target, "cash" => cash_value}}
      end)

    %{blank_mapping() | cash: cash, depot: depot}
  end

  defp mapping_from_params(params, current) do
    %{
      bucket_tag: Map.get(params, "bucket_tag", current.bucket_tag),
      bucket_skip: parse_bucket_skip(Map.get(params, "bucket_skip"), current.bucket_skip),
      cash: Map.merge(current.cash, Map.get(params, "cash", %{})),
      depot: Map.merge(current.depot, Map.get(params, "depot", %{}))
    }
  end

  defp parse_bucket_skip(nil, current), do: current
  defp parse_bucket_skip(value, _current), do: value == "true"

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

  # True iff every dropdown is filled: every depot row needs a `target` and
  # a `cash`. The bucket tag never blocks — blank behaves like skip.
  defp mapping_complete?(%{mapping: m, cash_pp_names: cashes, depot_pp_names: depots}) do
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

    cash_ok? and depot_ok?
  end

  # The human-readable list of still-missing mappings, derived from the SAME
  # data `mapping_complete?/1` inspects, so the Confirm hint can never disagree
  # with the button's disabled state (#475).
  defp missing_mappings(%{mapping: m, cash_pp_names: cashes, depot_pp_names: depots}) do
    cash_missing(m, cashes) ++ depot_missing(m, depots)
  end

  defp cash_missing(m, cashes) do
    for pp <- cashes, not is_binary(Map.get(m.cash, pp)) do
      gettext("cash account: %{name}", name: pp)
    end
  end

  defp depot_missing(m, depots) do
    Enum.flat_map(depots, fn pp ->
      mapped = Map.get(m.depot, pp) || %{}
      target_ok? = is_binary(mapped["target"]) and mapped["target"] != ""
      cash_ok? = is_binary(mapped["cash"]) and mapped["cash"] != ""

      cond do
        not target_ok? and not cash_ok? ->
          [gettext("depot and its cash account: %{name}", name: pp)]

        not target_ok? ->
          [gettext("target depot: %{name}", name: pp)]

        not cash_ok? ->
          [gettext("cash account for depot: %{name}", name: pp)]

        true ->
          []
      end
    end)
  end

  # The portfolio binding is internal (ADR-0024): the applier resolves
  # `Portfolios.default_portfolio/1` itself — no portfolio param here.
  defp build_apply_params(mapping, assigns) do
    with {:ok, cash_params} <- cash_params(mapping, assigns.cash_pp_names),
         {:ok, depot_params} <- depot_params(mapping, assigns.depot_pp_names),
         bucket_tag = effective_bucket_tag(mapping),
         :ok <- validate_bucket_tag(bucket_tag) do
      {:ok,
       %{
         cash_accounts: cash_params,
         depots: depot_params,
         bucket_tag: bucket_tag
       }}
    end
  end

  # Pre-validates the tag BEFORE the apply starts (fix round): a too-long or
  # scope-colliding tag fails here with a clear message instead of aborting
  # the whole import at the very end.
  defp validate_bucket_tag(nil), do: :ok

  defp validate_bucket_tag(tag) do
    case Buckets.validate_tag_bucket_name(tag) do
      :ok -> :ok
      {:error, reason} -> {:error, bucket_tag_error_message(reason)}
    end
  end

  defp bucket_tag_error_message(:name_too_long) do
    gettext("The bucket tag is too long — bucket names carry at most 100 characters.")
  end

  defp bucket_tag_error_message(:name_taken_by_scope_bucket) do
    gettext(
      "The bucket tag names an existing scope bucket. Scope buckets are exclusive and cannot be used as import tags — pick a different tag name."
    )
  end

  # Skip checked or a blank field → no tag (nil); the applier treats nil as
  # "leave the new accounts untagged".
  defp effective_bucket_tag(%{bucket_skip: true}), do: nil

  defp effective_bucket_tag(%{bucket_tag: tag}) when is_binary(tag) do
    case String.trim(tag) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp effective_bucket_tag(_mapping), do: nil

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

  # A per-row insert rejection (e.g. a currency that does not match the
  # resolved cash account, issue #343) carries the rejecting changeset.
  # Surface its validation messages instead of an opaque struct dump so the
  # preview tells the user exactly which row and rule failed.
  defp apply_error_message(%{row: row, reason: {:insert_failed, %Ecto.Changeset{} = changeset}}) do
    gettext("Row %{row}: %{errors}", row: row || "?", errors: changeset_error_text(changeset))
  end

  # The tag write failed inside the apply (fix round belt-and-braces for the
  # race where the colliding scope bucket appears after the pre-validation):
  # surface the same clear message, never an `inspect` dump.
  defp apply_error_message({:bucket_tag_failed, :name_taken_by_scope_bucket}) do
    bucket_tag_error_message(:name_taken_by_scope_bucket)
  end

  defp apply_error_message({:bucket_tag_failed, %Ecto.Changeset{} = changeset}) do
    gettext("Bucket tag: %{errors}", errors: changeset_error_text(changeset))
  end

  defp apply_error_message(reason), do: inspect(reason)

  defp changeset_error_text(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, messages} ->
      "#{field} #{Enum.join(messages, ", ")}"
    end)
  end

  defp parser_warning_text(errors) do
    errors
    |> Enum.map(fn err -> "Row #{err.row || "?"}: #{err.message}" end)
    |> Enum.join("\n")
  end
end
