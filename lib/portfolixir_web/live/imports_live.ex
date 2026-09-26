defmodule PortfolixirWeb.ImportsLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Clock
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Mapping
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Imports.PreviewStore
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.LiveParam

  @max_upload_bytes 20_000_000

  # The fields a mapping row carries, as its form sends them.
  @depot_fields ~w(target cash)
  @security_fields ~w(choice ack record_isin_change)

  @impl true
  def mount(_params, session, socket) do
    # Restore in-progress preview across locale-driven remounts.
    # Locale switches change the session's "locale" key and trigger a LiveView
    # remount via live_session :browser / LiveLocale on_mount.  Storing the
    # parsed preview in PreviewStore (keyed by the CSRF token, which is stable
    # across locale changes within the same browser session) lets us jump
    # straight back to the :preview step so the user does not have to re-upload.
    # The store key is a hash of the session token (#768), never the token.
    session_token = PreviewStore.key_for(Map.get(session, "_csrf_token"))

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
      |> assign_security_resolutions(preview)
      |> assign_account_states(preview)
      |> assign_remember_outcomes()
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
          <%= gettext("CSV or JSON v1 · max 20 MB · nothing is saved before confirmation") %>
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
    resolutions = assigns.security_resolutions

    assigns =
      assign(assigns,
        kind_counts: Enum.sort(Preview.counts_by_kind(assigns.preview)),
        # The securities the mapping step lists (E25 S5, F33): one per
        # unique reference of the resolution plan, whatever it carries.
        unique_securities_count: length(resolutions),
        total_entries: total_entries(assigns.preview),
        # E25 S5 (F35): a depot row's cash choices, built once for every
        # depot row rather than once per depot.
        depot_cash_choices:
          depot_cash_choices(assigns.cash_pp_names, assigns.existing_cash, assigns.option_tags),
        matched_resolutions: Enum.filter(resolutions, &(&1.status == :matched)),
        plain_create_resolutions: Enum.filter(resolutions, &(&1.status == :create)),
        decision_resolutions:
          Enum.filter(resolutions, &(&1.status in [:needs_decision, :config_at_risk]))
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
                <% key = Mapping.row_key("cash", pp_name) %>
                <% chosen = cash_value(@mapping, pp_name) %>
                <div class="mapping-row" id={"mapping-cash-#{key}"}>
                  <div class="source">
                    <small><%= gettext("PP account") %></small>
                    <%= pp_name %>
                    <.mapping_count counts={row_counts(@account_states, "cash", pp_name)} />
                  </div>
                  <div class="mapping-target">
                    <select name={"cash[#{key}]"}>
                      <%!-- ADR-0050 §4: an ambiguous name is prefilled with
                           nothing, and the select says so rather than showing
                           its first option as if it were chosen. --%>
                      <option :if={chosen in [nil, ""]} value="" selected>
                        <%= gettext("Decide…") %>
                      </option>
                      <.create_option
                        name={pp_name}
                        chosen={chosen}
                        refusal={create_refusal(@account_states, "cash", pp_name, @account_names)}
                      />
                      <%= for c <- @existing_cash do %>
                        <option value={"existing:#{c.id}"} selected={chosen == "existing:#{c.id}"}>
                          <%= account_label(@option_tags, :cash, c) %>
                        </option>
                      <% end %>
                    </select>
                    <.mapping_notes group="cash" key={key} name={pp_name} chosen={chosen} {row_note_assigns(assigns, "cash", pp_name)} />
                  </div>
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
                <% key = Mapping.row_key("depot", pp_name) %>
                <% chosen = depot_target_value(@mapping, pp_name) %>
                <div class="mapping-row depot" id={"mapping-depot-#{key}"}>
                  <div class="source">
                    <small><%= gettext("PP depot") %></small>
                    <%= pp_name %>
                    <.mapping_count counts={row_counts(@account_states, "depot", pp_name)} />
                  </div>
                  <div class="mapping-target">
                    <select name={"depot[#{key}][target]"}>
                      <option :if={chosen in [nil, ""]} value="" selected>
                        <%= gettext("Decide…") %>
                      </option>
                      <.create_option
                        name={pp_name}
                        chosen={chosen}
                        refusal={create_refusal(@account_states, "depot", pp_name, @account_names)}
                      />
                      <%= for d <- @existing_depots do %>
                        <option value={"existing:#{d.id}"} selected={chosen == "existing:#{d.id}"}>
                          <%= account_label(@option_tags, :depot, d) %>
                        </option>
                      <% end %>
                    </select>
                    <.mapping_notes group="depot" key={key} name={pp_name} chosen={chosen} {row_note_assigns(assigns, "depot", pp_name)} />
                  </div>
                  <% chosen_cash = depot_cash_value(@mapping, pp_name) %>
                  <select name={"depot[#{key}][cash]"}>
                    <option value="" selected={chosen_cash in [nil, ""]}>
                      <%= gettext("Pick a cash account…") %>
                    </option>
                    <%= for {value, label} <- @depot_cash_choices do %>
                      <option value={value} selected={chosen_cash == value}><%= label %></option>
                    <% end %>
                  </select>
                </div>
              <% end %>
            </div>
          </section>
        <% end %>

        <section class="panel inner" id="import-security-mapping">
          <h3><%= gettext("Securities from the export") %></h3>

          <%= if @matched_resolutions == [] and @plain_create_resolutions == [] and @decision_resolutions == [] do %>
            <p class="muted"><%= gettext("This import references no securities.") %></p>
          <% end %>

          <%= if @matched_resolutions != [] do %>
            <details data-role="matched-securities">
              <summary>
                <%= ngettext(
                  "%{count} security matches existing records",
                  "%{count} securities match existing records",
                  length(@matched_resolutions)
                ) %>
              </summary>
              <ul>
                <%= for res <- @matched_resolutions do %>
                  <li>
                    <%= res.label %> → <%= res.security.name %>
                    <span class="muted">(<%= tier_label(res.matched.tier) %>)</span>
                    <%!-- Matching never renames stored master data (ADR-0029
                         §2), so a renamed export would otherwise match with no
                         trace of the new name (#609). --%>
                    <span :if={res.name_differs} class="muted">
                      — <%= gettext("file name: %{name}; stored name kept", name: res.name_differs) %>
                    </span>
                  </li>
                <% end %>
              </ul>
            </details>
          <% end %>

          <%= if @plain_create_resolutions != [] do %>
            <details data-role="plain-creates">
              <summary>
                <%= ngettext(
                  "%{count} new security will be created",
                  "%{count} new securities will be created",
                  length(@plain_create_resolutions)
                ) %>
              </summary>
              <div class="mapping-grid">
                <%= for res <- @plain_create_resolutions do %>
                  <div class="mapping-row">
                    <div class="source">
                      <small><%= gettext("PP security") %></small>
                      <%= res.label %>
                    </div>
                    <.security_choice_select mapping={@mapping} existing_securities={@existing_securities} res={res} />
                    <.isin_change_offer mapping={@mapping} existing_securities={@existing_securities} res={res} />
                  </div>
                <% end %>
              </div>
            </details>
          <% end %>

          <%= for res <- @decision_resolutions do %>
            <div class="mapping-row" data-role="security-decision">
              <div class="source">
                <small><%= gettext("PP security") %></small>
                <%= res.label %>
              </div>
              <div>
                <p class="muted"><%= decision_text(res) %></p>
                <%= if res.candidates != [] do %>
                  <ul>
                    <%= for candidate <- res.candidates do %>
                      <li><%= security_option_label(candidate) %></li>
                    <% end %>
                  </ul>
                <% end %>
                <.security_choice_select mapping={@mapping} existing_securities={@existing_securities} res={res} />
                <.isin_change_offer mapping={@mapping} existing_securities={@existing_securities} res={res} />
                <%= if res.status == :config_at_risk and security_choice(@mapping, res) == "create" do %>
                  <label>
                    <input type="hidden" name={"security[#{res.key}][ack]"} value="false" />
                    <input
                      type="checkbox"
                      name={"security[#{res.key}][ack]"}
                      value="true"
                      checked={security_ack?(@mapping, res)}
                    />
                    <span>
                      <%= gettext(
                        "Create anyway (existing configuration stays unchanged)"
                      ) %>
                    </span>
                  </label>
                <% end %>
              </div>
            </div>
          <% end %>
        </section>

        <%!-- Skipped on an incremental file (#607): the check lists every
             transacted, configured security the import does not touch, which on
             a small file is every other security in the portfolio. --%>
        <p
          :if={@unmatched_config == [] and @unmatched_config_scope == :incremental}
          id="import-unmatched-config-skipped"
          class="form-help"
          role="status"
        >
          <%= gettext(
            "Leftover-configuration check skipped: this file references only part of the transacted securities, so it reads as an incremental import rather than a full re-export. Re-run with a full export to check for renames."
          ) %>
        </p>

        <%= if @unmatched_config != [] do %>
          <section class="import-warning-box" id="import-unmatched-config">
            <h3><%= gettext("Configured securities this import does not touch") %></h3>
            <p class="muted">
              <%= gettext(
                "These securities carry strategy configuration (category assignments or position targets) but match no entry in this file — likely a rename or ISIN change in Portfolio Performance. Remedy: record the ISIN change on the security (or, without an ISIN, rename it in-app to match, or remap it below), then re-run the import."
              ) %>
            </p>
            <ul>
              <%= for row <- @unmatched_config do %>
                <li>
                  <%= row.security.name %><%= if row.security.isin do %> · <%= row.security.isin %><% end %>
                </li>
              <% end %>
            </ul>
          </section>
        <% end %>

        <%!-- ADR-0050 §2: a file already applied is a no-op; the preview says
             so once, above the confirm, instead of in every row (board 04,
             "Randfall"). The confirm stays: it writes nothing and reports
             every duplicate with its layer. --%>
        <% total = @account_states.counts.total %>
        <AppShell.data_note
          :if={total.new == 0 and nothing_new?(total)}
          severity={:note}
          data-role="nothing-to-import"
        ><%= nothing_to_import(total) %></AppShell.data_note>

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

      <%= if @result.alias_matches != [] do %>
        <p class="muted" data-role="alias-matches">
          <%= gettext("%{n} record(s) matched via former ISIN.", n: length(@result.alias_matches)) %>
        </p>
      <% end %>

      <%= if @result.security_overrides != [] do %>
        <p class="muted" data-role="security-overrides">
          <%= gettext("%{n} securities were mapped manually.", n: length(@result.security_overrides)) %>
        </p>
      <% end %>

      <%= if @result.collapsed_duplicates != [] do %>
        <p class="muted" data-role="collapsed-duplicates">
          <%= gettext("%{n} row(s) collapsed onto the same resolved booking within this file.",
            n: length(@result.collapsed_duplicates)
          ) %>
        </p>
      <% end %>

      <%= if @result.unresolved_entries != [] do %>
        <div class="import-skipped" data-role="unresolved-entries">
          <p class="muted">
            <%= gettext("%{n} record(s) could not be resolved to a security and were not imported:",
              n: length(@result.unresolved_entries)
            ) %>
          </p>
          <ul>
            <%= for unresolved <- @result.unresolved_entries do %>
              <li>
                <%= gettext("Row %{row}: %{reason}", row: unresolved.row, reason: unresolved.reason) %>
              </li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <%!-- ADR-0050 §4 (board 04, board 04b): what remembering each remapped
           file name did, so a remembered name never changes master data
           without a word. --%>
      <%= if @result.remembered_names != [] do %>
        <div class="import-skipped" data-role="remembered-names">
          <p class="muted"><%= gettext("Remembered for future imports:") %></p>
          <ul>
            <li :for={remembered <- @result.remembered_names}>
              <%= remembered_line(remembered, @existing_cash, @existing_depots) %>
            </li>
          </ul>
        </div>
      <% end %>

      <%!-- ADR-0050 §3 (board 04): the skipped duplicates grouped by the layer
           that caught them. The identical rows of a re-import are the
           expected mass and stay closed; a retired hash and the economic
           layer are worth a look and stand open. --%>
      <%= if @result.duplicate_entries != [] do %>
        <div class="import-skipped" data-role="duplicate-entries">
          <p class="muted">
            <%= ngettext(
              "Skipped one record already booked:",
              "Skipped %{count} records already booked:",
              length(@result.duplicate_entries)
            ) %>
          </p>
          <%= for {layer, entries} <- duplicate_groups(@result.duplicate_entries) do %>
            <details
              class="dup-group"
              data-role="duplicate-group"
              data-layer={layer}
              open={layer != :hash}
            >
              <summary class="disclosure-summary">
                <AppShell.icon name={:chevron_right} size={14} class="disclosure-chevron" />
                <span><b><%= length(entries) %></b> · <%= duplicate_reason(%{layer: layer}) %></span>
              </summary>
              <ul>
                <li :for={dup <- entries}>
                  <%= gettext("Row %{row}: %{description}",
                    row: dup.row,
                    description: row_description(@preview, dup.row)
                  ) %>
                </li>
              </ul>
            </details>
          <% end %>
        </div>
      <% end %>

      <%!-- ADR-0050 §2's third limit (board 04b): a row booked on or before a
           set balance a merge adjusted is inserted, and that balance absorbs
           its amount. Listed with the balance, never silent. --%>
      <%= if @result.behind_restated_anchor != [] do %>
        <div class="import-skipped" data-role="behind-restated-anchor">
          <p class="muted">
            <%= ngettext(
              "One booking lies on or before a set balance a merge adjusted; that balance absorbs its amount:",
              "%{count} bookings lie on or before a set balance a merge adjusted; that balance absorbs their amounts:",
              length(@result.behind_restated_anchor)
            ) %>
          </p>
          <ul>
            <li :for={behind <- @result.behind_restated_anchor}>
              <%= gettext("Row %{row}: %{description} — set balance of %{account} on %{date}",
                row: behind.row,
                description: row_description(@preview, behind.row),
                account: account_name(@existing_cash, behind.cash_account_id),
                date: Date.to_iso8601(behind.anchor_date)
              ) %>
            </li>
          </ul>
        </div>
      <% end %>

      <%!-- ADR-0050 §5: a transfer whose two sides lead to one account or
           depot is void, skipped and listed, never an abort. --%>
      <%= if @result.internal_transfers != [] do %>
        <div class="import-skipped" data-role="internal-transfers">
          <p class="muted">
            <%= ngettext(
              "Skipped one internal transfer: both sides lead to the same account or depot.",
              "Skipped %{count} internal transfers: both sides lead to the same account or depot.",
              length(@result.internal_transfers)
            ) %>
          </p>
          <ul>
            <%= for transfer <- @result.internal_transfers do %>
              <li>
                <%= gettext("Row %{row}: %{kind} %{date} · %{from} → %{to}",
                  row: transfer.row,
                  kind: kind_label(transfer.kind),
                  date: transfer.date && Date.to_iso8601(transfer.date),
                  from: transfer.pp_name,
                  to: transfer.pp_counter_name
                ) %>
              </li>
            <% end %>
          </ul>
        </div>
      <% end %>

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

  defp depot_cash_choices(cash_pp_names, existing_cash, option_tags) do
    Enum.map(cash_pp_names, &{"pp:#{&1}", gettext("(import) %{name}", name: &1)}) ++
      Enum.map(existing_cash, &{"existing:#{&1.id}", account_label(option_tags, :cash, &1)})
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
    mapping = mapping_from_params(params, socket.assigns)
    PreviewStore.put_mapping(socket.assigns.session_token, mapping)
    {:noreply, socket |> assign(:mapping, mapping) |> assign_remember_outcomes()}
  end

  def handle_event("apply", _params, socket) when socket.assigns.applying do
    {:noreply, socket}
  end

  def handle_event("apply", params, socket) do
    mapping = mapping_from_params(params, socket.assigns)
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
     |> assign_security_resolutions(nil)
     |> assign_account_states(nil)
     |> assign_remember_outcomes()
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

  # An event this page does not know, or a payload it cannot read, changes
  # nothing (E25 S4, F17).
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:park_preview, park}, socket) do
    # Only the preview this page still shows: a reset, an apply or another
    # upload in between has moved on, and parking it would bring it back.
    if socket.assigns.stage == :preview and Map.get(socket.assigns, :park) == park do
      PreviewStore.put(
        socket.assigns.session_token,
        socket.assigns.preview,
        socket.assigns.mapping
      )
    end

    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

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

  # ADR-0050 §10: an account the mapping names has been merged away (or
  # deleted) since the preview opened. Nothing was written; the account
  # mapping is recomputed from the current accounts, keeping the bucket tag
  # and the security choices, and the user reviews it before confirming.
  def handle_async(
        :apply_import,
        {:ok, {:error, {:resolution_diverged, %{kind: kind}}}},
        socket
      )
      when kind in [:cash_account, :securities_account] do
    socket = socket |> reload_lookups() |> assign_account_states(socket.assigns.preview)
    fresh = initial_mapping_for(socket.assigns.preview, socket.assigns.account_states)

    mapping =
      Map.merge(socket.assigns.mapping, %{
        cash: fresh.cash,
        depot: fresh.depot,
        prefill: fresh.prefill
      })

    PreviewStore.put_mapping(socket.assigns.session_token, mapping)

    {:noreply,
     socket
     |> assign(:applying, false)
     |> assign(:mapping, mapping)
     |> assign_remember_outcomes()
     |> assign(
       :error,
       gettext(
         "An account mapped in this preview was merged or deleted since it was opened. The account mapping was refreshed from the current accounts; review it before confirming again. Nothing was written."
       )
     )}
  end

  # Preview→apply revalidation abort (ADR-0029 §2): the data changed while
  # the preview was open. Re-run the ladder so the user reviews the CURRENT
  # resolutions before confirming again.
  def handle_async(:apply_import, {:ok, {:error, {:resolution_diverged, _key}}}, socket) do
    {:noreply,
     socket
     |> assign(:applying, false)
     |> assign_security_resolutions(socket.assigns.preview)
     |> assign(
       :error,
       gettext(
         "Security data changed while this preview was open — the re-checked matching differs from the approved set. The refreshed preview needs a fresh review before confirming."
       )
     )}
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
            |> assign_security_resolutions(preview)
            |> assign_account_states(preview)

          socket =
            socket
            |> assign(:mapping, initial_mapping_for(preview, socket.assigns.account_states))
            |> assign_remember_outcomes()

          # E25 S5 (F33): parked only once it has rendered. The message is
          # handled after this callback's render, so a preview whose first
          # render fails is never parked to fail again on every remount.
          park = make_ref()
          send(self(), {:park_preview, park})

          {:noreply, assign(socket, :park, park)}

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
    |> assign(:option_tags, option_tags(existing_cash, existing_depots))
    |> assign(:account_names, %{
      "cash" => Map.new(existing_cash, &{&1.id, &1.name}),
      "depot" => Map.new(existing_depots, &{&1.id, &1.name})
    })
    |> assign_new(:cash_pp_names, fn -> [] end)
    |> assign_new(:depot_pp_names, fn -> [] end)
    |> assign_new(:row_names, fn -> row_names([], []) end)
  end

  defp assign_preview_pp_names(socket, preview) do
    cash_pp_names = Mapping.unique_cash_pp_names(preview)
    depot_pp_names = Mapping.unique_depot_pp_names(preview)

    socket
    |> assign(:cash_pp_names, cash_pp_names)
    |> assign(:depot_pp_names, depot_pp_names)
    |> assign(:row_names, row_names(cash_pp_names, depot_pp_names))
  end

  # E25 S5 (F42): the server-side map from a row's opaque key, the only thing
  # a field name carries, back to the file's name. A key the preview did not
  # hand out addresses nothing.
  defp row_names(cash_pp_names, depot_pp_names) do
    %{
      "cash" => Map.new(cash_pp_names, &{Mapping.row_key("cash", &1), &1}),
      "depot" => Map.new(depot_pp_names, &{Mapping.row_key("depot", &1), &1})
    }
  end

  defp maybe_assign_preview_pp_names(socket, nil), do: socket

  defp maybe_assign_preview_pp_names(socket, preview),
    do: assign_preview_pp_names(socket, preview)

  # --- what each account row says (ADR-0050 §3, §4; boards 04 and 04b) ---

  @empty_counts %{
    hash: 0,
    retired: 0,
    unimportable: 0,
    economics: 0,
    internal_transfer: 0,
    new: 0
  }

  # How each file name resolves (the prefill's own resolution) and how many
  # of the file's bookings each name carries per first-check layer, read
  # once per preview: both are reads of the database as it is now, and the
  # apply re-checks both.
  defp assign_account_states(socket, nil) do
    assign(socket, :account_states, %{
      resolutions: %{"cash" => %{}, "depot" => %{}},
      counts: %{"cash" => %{}, "depot" => %{}, total: @empty_counts}
    })
  end

  defp assign_account_states(socket, %Preview{} = preview) do
    %{cash_accounts: cash, depots: depots} = Imports.resolve_accounts(preview)
    counts = Imports.reimport_counts(preview)

    assign(socket, :account_states, %{
      resolutions: %{"cash" => cash, "depot" => depots},
      counts: %{"cash" => counts.cash_accounts, "depot" => counts.depots, total: counts.total}
    })
  end

  defp row_counts(states, group, pp_name),
    do: states.counts |> Map.fetch!(group) |> Map.get(pp_name, @empty_counts)

  defp resolution(states, group, pp_name),
    do: states.resolutions |> Map.fetch!(group) |> Map.get(pp_name, :none)

  # ADR-0050 §4 (board 04b, G4b-A): "+ Create new: X" is impossible when the
  # name guard refuses X — another account's live or former name. That is
  # exactly what the prefill's resolution found, so the reason is read from
  # it: nil when X is free.
  defp create_refusal(states, group, pp_name, account_names) do
    case resolution(states, group, pp_name) do
      :none ->
        nil

      {:ok, _id, :live} ->
        gettext("an account already has this name")

      {:ok, id, :former} ->
        gettext("a former name of %{account}",
          account: Map.get(account_names[group], id, "##{id}")
        )

      {:ambiguous, :live, ids} ->
        ngettext("the name of %{count} account", "the name of %{count} accounts", length(ids))

      {:ambiguous, :former, ids} ->
        ngettext(
          "a former name of %{count} account",
          "a former name of %{count} accounts",
          length(ids)
        )
    end
  end

  # A row whose file name is ambiguous needs no decision when none of its
  # bookings is new: a hash hit resolves nothing (ADR-0050 §3; board 04,
  # note 4).
  defp decision_needed?(states, group, pp_name) do
    case resolution(states, group, pp_name) do
      {:ambiguous, _tier, _ids} -> row_counts(states, group, pp_name).new > 0
      _resolved -> true
    end
  end

  # What remembering each changed row would do, read when the mapping
  # changes (ADR-0050 §4): only a row whose prefill the operator changed onto
  # an existing, differently named account is a remap to remember.
  defp assign_remember_outcomes(socket) do
    %{mapping: mapping, account_names: names} = socket.assigns
    prefill = Map.get(mapping, :prefill, %{})

    choices = %{
      "cash" => mapping.cash,
      "depot" => Map.new(mapping.depot, fn {pp_name, row} -> {pp_name, row["target"]} end)
    }

    outcomes =
      for {group, rows} <- choices,
          {pp_name, "existing:" <> raw = choice} <- rows,
          choice != get_in(prefill, [group, pp_name]),
          {:ok, id} <- [LiveParam.fetch_id(raw)],
          Map.get(names[group], id) != pp_name,
          into: %{} do
        {{group, pp_name}, Imports.remember_outcome(remember_kind(group), pp_name, id)}
      end

    assign(socket, :remember_outcomes, outcomes)
  end

  defp remember_kind("cash"), do: :cash_account
  defp remember_kind("depot"), do: :securities_account

  defp row_note_assigns(assigns, group, pp_name) do
    %{
      counts: row_counts(assigns.account_states, group, pp_name),
      resolution: resolution(assigns.account_states, group, pp_name),
      prefill: get_in(assigns.mapping, [:prefill, group, pp_name]),
      remember_outcome: Map.get(assigns.remember_outcomes, {group, pp_name}),
      remember_on: get_in(assigns.mapping, [:remember, group, pp_name]) != "false",
      account_names: assigns.account_names[group],
      option_tags: assigns.option_tags
    }
  end

  # --- same-named accounts told apart (#884 F1, board 04b) ---

  # Per account whose name another account of its kind also carries, what
  # tells it apart: the first of its features whose values differ across the
  # accounts of that name. A cash account: its linked depots, its currency,
  # its creation date, its number; a depot: its cash account, its creation
  # date, its number. Accounts with a unique name carry none.
  defp option_tags(existing_cash, existing_depots) do
    depots_by_cash = Enum.group_by(existing_depots, & &1.cash_account_id, & &1.name)
    cash_names = Map.new(existing_cash, &{&1.id, &1.name})

    cash_features = [
      fn c ->
        case depots_by_cash |> Map.get(c.id, []) |> Enum.sort() do
          [] -> gettext("no depot")
          names -> gettext("at %{depots}", depots: Enum.join(names, ", "))
        end
      end,
      & &1.currency_code,
      &created_tag/1,
      &number_tag/1
    ]

    depot_features = [
      &gettext("with %{cash}", cash: Map.get(cash_names, &1.cash_account_id, "—")),
      &created_tag/1,
      &number_tag/1
    ]

    %{cash: tags(existing_cash, cash_features), depot: tags(existing_depots, depot_features)}
  end

  defp tags(accounts, features) do
    accounts
    |> Enum.group_by(& &1.name)
    |> Enum.flat_map(fn
      {_name, [_single]} ->
        []

      {_name, same} ->
        feature =
          Enum.find(features, List.last(features), fn feature ->
            values = Enum.map(same, feature)
            length(Enum.uniq(values)) == length(values)
          end)

        Enum.map(same, &{&1.id, feature.(&1)})
    end)
    |> Map.new()
  end

  defp created_tag(account),
    do:
      gettext("created %{date}",
        date: account.inserted_at |> NaiveDateTime.to_date() |> Date.to_iso8601()
      )

  defp number_tag(account), do: gettext("no. %{id}", id: account.id)

  defp account_label(option_tags, kind, account) do
    case Map.get(option_tags[kind], account.id) do
      nil -> account.name
      tag -> "#{account.name} · #{tag}"
    end
  end

  # --- the row's parts ---

  attr(:counts, :map, required: true)

  # Per row (board 04): how many of its bookings are already imported (by
  # content hash, a merge's retired hash, or an equal booking the apply finds
  # by its economics), how many internal transfers are dropped, and how many
  # are new — "nothing to create" when none is. A booking that names two
  # accounts counts in both rows.
  defp mapping_count(assigns) do
    counts = assigns.counts
    assigns = assign(assigns, hits: already_imported(counts), transfers: counts.internal_transfer)

    ~H"""
    <span class="mapping-count" data-role="mapping-count"><%= if @hits > 0 do %><%= ngettext(
          "%{count} booking already imported",
          "%{count} bookings already imported",
          @hits
        ) %> · <% end %><%= if @transfers > 0 do %><%= ngettext(
          "%{count} internal transfer dropped",
          "%{count} internal transfers dropped",
          @transfers
        ) %> · <% end %><b><%= cond do
          @counts.new == 0 -> gettext("nothing to create")
          @hits + @transfers > 0 -> ngettext("%{count} new", "%{count} new", @counts.new)
          true -> ngettext("%{count} booking new", "%{count} bookings new", @counts.new)
        end %></b></span>
    """
  end

  # Rows the apply skips as already booked, on any of its layers.
  defp already_imported(counts), do: counts.hash + counts.retired + counts.economics

  # Nothing new, but something the import recognises: a file already applied.
  defp nothing_new?(counts), do: already_imported(counts) + counts.internal_transfer > 0

  attr(:name, :string, required: true)
  attr(:chosen, :string, default: nil)
  attr(:refusal, :string, default: nil)

  # "+ Create new: X" — disabled, with its reason in its own label, when the
  # name guard would refuse X (board 04b, G4b-A).
  defp create_option(assigns) do
    ~H"""
    <%= if @refusal do %>
      <option value={"create:#{@name}"} disabled selected={@chosen == "create:#{@name}"}>
        <%= gettext("+ Create new: %{name} — not possible: %{reason}", name: @name, reason: @refusal) %>
      </option>
    <% else %>
      <option value={"create:#{@name}"} selected={@chosen == "create:#{@name}"}>
        <%= gettext("+ Create new: %{name}", name: @name) %>
      </option>
    <% end %>
    """
  end

  attr(:group, :string, required: true)
  attr(:key, :string, required: true)
  attr(:name, :string, required: true)
  attr(:chosen, :string, default: nil)
  attr(:counts, :map, required: true)
  attr(:resolution, :any, required: true)
  attr(:prefill, :string, default: nil)
  attr(:remember_outcome, :any, default: nil)
  attr(:remember_on, :boolean, default: true)
  attr(:account_names, :map, required: true)
  attr(:option_tags, :map, required: true)

  # Under the select, only what is not obvious (board 04): why the row is
  # prefilled when a former name did it, that "+ Create new" creates nothing
  # without a new booking, the "remember" box of a changed prefill (G4-A),
  # why remembering is not offered, and an ambiguous name's note.
  defp mapping_notes(assigns) do
    assigns = assign(assigns, basis: basis(assigns), remember: remember_mode(assigns))

    ~H"""
    <%= case @basis do %>
      <% {:former, account} -> %>
        <span class="mapping-basis" data-role="mapping-basis">
          <%= gettext("matched by a former name — %{account}, formerly “%{name}”",
            account: account,
            name: @name
          ) %>
        </span>
      <% :create_nothing -> %>
        <span class="mapping-basis" data-role="mapping-basis">
          <%= gettext("no account under this name; it is created only with its first new booking") %>
        </span>
      <% {:ambiguous, sentence} -> %>
        <AppShell.data_note severity={:attention} data-role="mapping-ambiguous">
          <%= sentence %>
          <%= gettext(
            "The choice holds for this import's new bookings and cannot be remembered while more than one account carries the name. Once only one does, the import maps the name to it: renaming or merging under"
          ) %>
          <.link href="/portfolios"><%= gettext("Accounts & depots") %></.link>.
        </AppShell.data_note>
      <% nil -> %>
    <% end %>
    <%= case @remember do %>
      <% :box -> %>
        <div class="mapping-remember" data-role="mapping-remember">
          <label>
            <input type="hidden" name={"remember[#{@group}][#{@key}]"} value="false" />
            <input
              type="checkbox"
              name={"remember[#{@group}][#{@key}]"}
              value="true"
              checked={@remember_on}
              aria-describedby={"remember-#{@group}-#{@key}"}
            />
            <span><%= gettext("Remember this mapping") %></span>
          </label>
          <small id={"remember-#{@group}-#{@key}"}><%= remember_sentence(assigns) %></small>
        </div>
      <% :not_offered -> %>
        <span class="mapping-basis" data-role="mapping-not-remembered">
          <%= gettext(
            "“%{name}” is already the name of another account; the choice holds for this import only. Merging or renaming that account changes this:",
            name: @name
          ) %>
          <.link href="/portfolios"><%= gettext("Accounts & depots") %></.link>.
        </span>
      <% nil -> %>
    <% end %>
    """
  end

  # Why the row is prefilled, said only where it is not obvious (board 04).
  defp basis(%{resolution: {:ok, id, :former}} = assigns) do
    if assigns.chosen == "existing:#{id}",
      do: {:former, Map.get(assigns.account_names, id, "##{id}")}
  end

  defp basis(%{resolution: :none, counts: counts} = assigns) do
    if assigns.chosen == "create:#{assigns.name}" and counts.new == 0 and nothing_new?(counts),
      do: :create_nothing
  end

  defp basis(%{resolution: {:ambiguous, tier, ids}, counts: %{new: new}} = assigns)
       when new > 0 do
    {:ambiguous,
     ambiguous_sentence(
       assigns.group,
       assigns.name,
       tier,
       ids,
       assigns.account_names,
       assigns.option_tags
     )}
  end

  defp basis(_assigns), do: nil

  # The "remember" box of a changed prefill (G4-A) where remembering appends
  # or moves the name; where the name is another account's live name, why it
  # is not offered — except on an ambiguous row, whose note already says so.
  defp remember_mode(%{remember_outcome: :append}), do: :box
  defp remember_mode(%{remember_outcome: {:move, _from}}), do: :box

  defp remember_mode(%{remember_outcome: {:not_offered, _live_on}, resolution: resolution}) do
    if match?({:ambiguous, _tier, _ids}, resolution), do: nil, else: :not_offered
  end

  defp remember_mode(_assigns), do: nil

  defp remember_sentence(%{remember_on: false} = assigns) do
    gettext("Holds for this import only. A future import suggests “%{prefill}” again.",
      prefill: prefill_label(assigns)
    )
  end

  defp remember_sentence(%{remember_outcome: {:move, from_id}} = assigns) do
    gettext(
      "“%{name}” becomes a former name of %{account} and is then no longer a former name of %{from}.",
      name: assigns.name,
      account: chosen_name(assigns),
      from: Map.get(assigns.account_names, from_id, "##{from_id}")
    )
  end

  defp remember_sentence(assigns) do
    gettext(
      "“%{name}” becomes a former name of %{account}; a future import maps the name by itself.",
      name: assigns.name,
      account: chosen_name(assigns)
    )
  end

  defp chosen_name(%{chosen: "existing:" <> raw, account_names: names}) do
    case LiveParam.fetch_id(raw) do
      {:ok, id} -> Map.get(names, id, "##{id}")
      :error -> "—"
    end
  end

  # The option the next import would prefill again, as the list names it.
  defp prefill_label(%{prefill: "create:" <> name}),
    do: gettext("+ Create new: %{name}", name: name)

  defp prefill_label(%{prefill: "existing:" <> _raw} = assigns),
    do: chosen_name(%{assigns | chosen: assigns.prefill})

  defp prefill_label(_assigns), do: gettext("Decide…")

  defp ambiguous_sentence(group, name, tier, ids, account_names, option_tags) do
    kind = if group == "cash", do: :cash, else: :depot

    labels =
      Enum.map_join(ids, "; ", fn id ->
        case tier do
          :live -> Map.get(option_tags[kind], id) || Map.get(account_names, id, "##{id}")
          :former -> Map.get(account_names, id, "##{id}")
        end
      end)

    case {group, tier} do
      {"cash", :live} ->
        ngettext(
          "%{count} cash account is named “%{name}” (%{labels}), so there is no prefill.",
          "%{count} cash accounts are named “%{name}” (%{labels}), so there is no prefill.",
          length(ids),
          name: name,
          labels: labels
        )

      {"cash", :former} ->
        ngettext(
          "%{count} cash account carries “%{name}” as a former name (%{labels}), so there is no prefill.",
          "%{count} cash accounts carry “%{name}” as a former name (%{labels}), so there is no prefill.",
          length(ids),
          name: name,
          labels: labels
        )

      {"depot", :live} ->
        ngettext(
          "%{count} depot is named “%{name}” (%{labels}), so there is no prefill.",
          "%{count} depots are named “%{name}” (%{labels}), so there is no prefill.",
          length(ids),
          name: name,
          labels: labels
        )

      {"depot", :former} ->
        ngettext(
          "%{count} depot carries “%{name}” as a former name (%{labels}), so there is no prefill.",
          "%{count} depots carry “%{name}” as a former name (%{labels}), so there is no prefill.",
          length(ids),
          name: name,
          labels: labels
        )
    end
  end

  # ADR-0050 §2: a file already applied is a no-op — said once, for the
  # whole file (board 04, "Randfall").
  defp nothing_to_import(total) do
    hits = already_imported(total)
    transfers = total.internal_transfer

    already =
      cond do
        hits == 0 ->
          []

        total.unimportable > 0 ->
          [
            ngettext(
              "%{count} entry is already imported; the others cannot be imported.",
              "%{count} entries are already imported; the others cannot be imported.",
              hits
            )
          ]

        transfers > 0 ->
          [
            ngettext(
              "%{count} entry is already imported.",
              "%{count} entries are already imported.",
              hits
            )
          ]

        true ->
          [
            ngettext(
              "The entry is already imported.",
              "All %{count} entries are already imported.",
              hits
            )
          ]
      end

    dropped =
      if transfers > 0,
        do: [
          ngettext(
            "%{count} internal transfer is dropped: both of its accounts are one account now.",
            "%{count} internal transfers are dropped: both accounts of each are one account now.",
            transfers
          )
        ],
        else: []

    Enum.join(
      already ++
        dropped ++
        [gettext("The import creates nothing: no booking, no account, no depot, no security.")],
      " "
    )
  end

  # --- the result's lists (boards 04 and 04b) ---

  defp remembered_line(%{kind: kind, name: name, account_id: id, outcome: outcome}, cash, depots) do
    accounts = if kind == :cash_account, do: cash, else: depots
    account = account_name(accounts, id)

    case outcome do
      :appended ->
        gettext("“%{name}” is now a former name of %{account}.", name: name, account: account)

      {:moved, from_id} ->
        gettext("“%{name}” is now a former name of %{account} and no longer of %{from}.",
          name: name,
          account: account,
          from: account_name(accounts, from_id)
        )

      {:not_offered, holder_id} ->
        gettext("“%{name}” was not remembered: it is the name of %{holder}.",
          name: name,
          holder: account_name(accounts, holder_id)
        )
    end
  end

  defp account_name(accounts, id) do
    case Enum.find(accounts, &(&1.id == id)) do
      nil -> "##{id}"
      account -> account.name
    end
  end

  @duplicate_layers [:hash, :retired, :economics]

  defp duplicate_groups(duplicates) do
    grouped = Enum.group_by(duplicates, & &1.layer)

    for layer <- @duplicate_layers,
        entries = Map.get(grouped, layer, []),
        entries != [],
        do: {layer, entries}
  end

  # What a file row books, in the page's words: its kind and date, the
  # security, the amount (or the quantity), and the file's account names.
  defp row_description(%Preview{entries: entries}, row) do
    case Enum.find(entries, &(&1.source_row == row)) do
      nil -> gettext("a row of the file")
      entry -> entry_description(entry)
    end
  end

  defp row_description(_preview, _row), do: gettext("a row of the file")

  defp entry_description(entry) do
    [
      "#{kind_label(entry.kind)} #{entry.date && Date.to_iso8601(entry.date)}",
      entry.security && entry.security[:name],
      entry_amount(entry),
      entry_names(entry)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp entry_amount(%{gross_amount: %Decimal{} = amount, currency_code: currency}),
    do: String.trim("#{Format.money(amount)} #{currency}")

  defp entry_amount(%{quantity: %Decimal{} = quantity}),
    do: gettext("%{quantity} shares", quantity: Format.exact(quantity))

  defp entry_amount(_entry), do: nil

  defp entry_names(%{kind: "security_transfer"} = entry),
    do: arrow(entry.pp_portfolio_name, entry.pp_counter_portfolio_name)

  defp entry_names(entry) do
    case entry.pp_account_name do
      nil -> arrow(entry.pp_portfolio_name, entry.pp_counter_portfolio_name)
      account -> arrow(account, entry.pp_counter_account_name)
    end
  end

  defp arrow(nil, nil), do: nil
  defp arrow(from, nil), do: from
  defp arrow(nil, to), do: to
  defp arrow(from, to), do: "#{from} → #{to}"

  # The ADR-0029 §2 security-mapping step: one classified resolution row per
  # unique security reference plus the pre-apply inverse check, recomputed on
  # every parse/remount (the ladder runs against the CURRENT database).
  defp assign_security_resolutions(socket, nil) do
    socket
    |> assign(:security_resolutions, [])
    |> assign(:unmatched_config, [])
    |> assign(:unmatched_config_scope, :full_export)
    |> assign(:existing_securities, [])
  end

  defp assign_security_resolutions(socket, %Preview{} = preview) do
    %{resolutions: resolutions, unmatched_config: unmatched, unmatched_config_scope: scope} =
      Imports.resolve_securities(preview)

    socket
    |> assign(:security_resolutions, resolutions)
    |> assign(:unmatched_config, unmatched)
    |> assign(:unmatched_config_scope, scope)
    # A benchmark is not an import target (ADR-0046 §1).
    |> assign(:existing_securities, Catalog.list_securities(is_benchmark: false))
  end

  defp blank_mapping do
    %{
      bucket_tag: default_bucket_tag(),
      bucket_skip: false,
      cash: %{},
      depot: %{},
      security: %{},
      # ADR-0050 §4: the per-name "remember" of a remap, on by default; only a
      # "false" is ever stored. Its control is the preview's board-04 work.
      remember: %{"cash" => %{}, "depot" => %{}},
      # The choice the preview prefilled per file name, as shown: only a
      # choice the operator changed from it is a remap to remember.
      prefill: %{"cash" => %{}, "depot" => %{}}
    }
  end

  # The date-stamped default bucket name is data (a bucket name), not UI
  # copy — deliberately not translated.
  defp default_bucket_tag do
    "PP Import #{Date.to_iso8601(Clock.today())}"
  end

  # Auto-prefill (ADR-0050 §4) through the resolution the apply uses: an
  # exact live name, then a former name → that account; a name found by
  # neither → create-new; an ambiguous name → nothing ("Decide…").
  defp initial_mapping_for(%Preview{} = preview, %{resolutions: resolutions}) do
    %{"cash" => cash_resolutions, "depot" => depot_resolutions} = resolutions

    cash_pp_names = Mapping.unique_cash_pp_names(preview)
    depot_pp_names = Mapping.unique_depot_pp_names(preview)
    # E25 S5 (F35): every depot's default cash account in one pass.
    default_cash = Mapping.default_cash_by_depot(preview)

    cash =
      Map.new(cash_pp_names, fn pp_name ->
        {pp_name, prefill(Map.fetch!(cash_resolutions, pp_name), pp_name)}
      end)

    depot =
      Map.new(depot_pp_names, fn pp_name ->
        target = prefill(Map.fetch!(depot_resolutions, pp_name), pp_name)

        default_cash_pp = Map.get(default_cash, pp_name)

        cash_value =
          if default_cash_pp && default_cash_pp in cash_pp_names,
            do: "pp:#{default_cash_pp}",
            else: ""

        {pp_name, %{"target" => target, "cash" => cash_value}}
      end)

    prefill = %{
      "cash" => cash,
      "depot" => Map.new(depot, fn {pp_name, %{"target" => target}} -> {pp_name, target} end)
    }

    %{blank_mapping() | cash: cash, depot: depot, prefill: prefill}
  end

  defp prefill({:ok, id, _tier}, _pp_name), do: "existing:#{id}"
  defp prefill(:none, pp_name), do: "create:#{pp_name}"
  defp prefill({:ambiguous, _tier, _ids}, _pp_name), do: ""

  # The mapping takes only the shapes its form sends (E25 S4, F17): a string
  # per cash name, a map of strings per depot and per security row, a string
  # tag. Anything else changes nothing — the mapping is parked in the preview
  # store, so a shape the page cannot render would crash every remount.
  #
  # Cash and depot rows are addressed by their opaque key (E25 S5, F42): a
  # file name never becomes part of a field name, where brackets in it would
  # nest into another row's parameters. A key the preview did not hand out is
  # ignored.
  defp mapping_from_params(params, %{mapping: current, row_names: row_names} = assigns) do
    params = LiveParam.map(params)

    %{
      bucket_tag: LiveParam.string(Map.get(params, "bucket_tag")) || current.bucket_tag,
      bucket_skip: parse_bucket_skip(Map.get(params, "bucket_skip"), current.bucket_skip),
      cash:
        Map.merge(
          current.cash,
          params |> Map.get("cash") |> by_name(row_names["cash"]) |> LiveParam.form()
        ),
      depot:
        merge_rows(
          current.depot,
          params |> Map.get("depot") |> by_name(row_names["depot"]),
          @depot_fields
        ),
      security:
        merge_rows(
          Map.get(current, :security, %{}),
          params |> Map.get("security") |> handed_out(assigns.security_resolutions),
          @security_fields
        ),
      remember:
        merge_remember(Map.get(current, :remember, blank_mapping().remember), params, row_names),
      prefill: Map.get(current, :prefill, blank_mapping().prefill)
    }
  end

  defp by_name(given, names) do
    for {key, value} <- LiveParam.map(given),
        is_binary(key),
        name = Map.get(names, key),
        name != nil,
        into: %{},
        do: {name, value}
  end

  # E25 S5 review round (F42): a security row is kept only under a key the
  # page's resolution plan handed out; any other key addresses nothing.
  defp handed_out(given, resolutions) do
    keys = MapSet.new(resolutions, & &1.key)
    for {key, row} <- LiveParam.map(given), MapSet.member?(keys, key), into: %{}, do: {key, row}
  end

  # "remember[cash][<key>]" / "remember[depot][<key>]" = "false" switches a
  # remap's remembering off; anything else leaves it on (the default).
  defp merge_remember(current, params, row_names) do
    case Map.get(params, "remember") do
      %{} = given ->
        Map.new(["cash", "depot"], fn group ->
          given_names = given |> Map.get(group) |> by_name(row_names[group]) |> LiveParam.form()
          {group, Map.merge(Map.get(current, group, %{}), given_names)}
        end)

      _absent ->
        current
    end
  end

  # Per-key deep merge so a change event carrying only some of a row's fields
  # (a depot's target / cash, a security's choice / ack / record_isin_change)
  # never drops the others; a row that is not a map, and a field that is not
  # a string or not the row's, is ignored.
  defp merge_rows(current, given, fields) do
    rows =
      for {key, row} <- LiveParam.map(given), is_binary(key) and is_map(row), into: %{} do
        {key, row |> LiveParam.form() |> Map.take(fields)}
      end

    Map.merge(current, rows, fn _key, old, new ->
      if is_map(old), do: Map.merge(old, new), else: new
    end)
  end

  defp parse_bucket_skip(nil, current), do: current
  defp parse_bucket_skip(value, _current), do: value == "true"

  # --- security mapping step helpers (ADR-0029 §2) ---

  defp security_choice(mapping, res) do
    case get_in(Map.get(mapping, :security, %{}), [res.key, "choice"]) do
      nil -> default_security_choice(res)
      value -> value
    end
  end

  # A surfaced decision starts undecided; creations (plain and config-at-risk)
  # default to "create" — the config-at-risk row additionally needs its
  # per-row acknowledgment before apply unblocks.
  defp default_security_choice(%{status: :needs_decision}), do: ""
  defp default_security_choice(_res), do: "create"

  defp security_ack?(mapping, res) do
    get_in(Map.get(mapping, :security, %{}), [res.key, "ack"]) == "true"
  end

  defp security_record_isin_change?(mapping, res) do
    get_in(Map.get(mapping, :security, %{}), [res.key, "record_isin_change"]) == "true"
  end

  defp chosen_existing_security(mapping, res, existing_securities) do
    case security_choice(mapping, res) do
      "existing:" <> id_str ->
        case LiveParam.id(id_str) do
          nil -> nil
          id -> Enum.find(existing_securities, &(&1.id == id))
        end

      _other ->
        nil
    end
  end

  # Override durability (§2): offer recording the remap as a §3 ISIN change
  # exactly when the entry carries an ISIN that differs from the chosen
  # security's current ISIN (an ISIN-less target has nothing to alias).
  defp isin_change_applicable?(res, target) do
    is_binary(res.ref.isin) and not is_nil(target) and is_binary(target.isin) and
      target.isin != res.ref.isin
  end

  attr(:mapping, :map, required: true)
  attr(:existing_securities, :list, required: true)
  attr(:res, :map, required: true)

  defp security_choice_select(assigns) do
    assigns = assign(assigns, :choice, security_choice(assigns.mapping, assigns.res))

    ~H"""
    <select name={"security[#{@res.key}][choice]"}>
      <%= if @res.status == :needs_decision do %>
        <option value="" selected={@choice == ""}><%= gettext("Decide…") %></option>
      <% end %>
      <option value="create" selected={@choice == "create"}>
        <%= gettext("+ Create new: %{name}", name: @res.label) %>
      </option>
      <%= for s <- @existing_securities do %>
        <option value={"existing:#{s.id}"} selected={@choice == "existing:#{s.id}"}>
          <%= security_option_label(s) %>
        </option>
      <% end %>
    </select>
    """
  end

  attr(:mapping, :map, required: true)
  attr(:existing_securities, :list, required: true)
  attr(:res, :map, required: true)

  defp isin_change_offer(assigns) do
    target = chosen_existing_security(assigns.mapping, assigns.res, assigns.existing_securities)
    assigns = assign(assigns, :target, target)

    ~H"""
    <%= if isin_change_applicable?(@res, @target) do %>
      <label>
        <input type="hidden" name={"security[#{@res.key}][record_isin_change]"} value="false" />
        <input
          type="checkbox"
          name={"security[#{@res.key}][record_isin_change]"}
          value="true"
          checked={security_record_isin_change?(@mapping, @res)}
        />
        <span>
          <%= gettext("Record %{isin} as an ISIN change (the current ISIN %{current} becomes a former-ISIN alias)",
            isin: @res.ref.isin,
            current: @target.isin
          ) %>
        </span>
      </label>
    <% end %>
    """
  end

  defp security_option_label(security) do
    [security.name, security.currency_code, security.isin]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp tier_label(:isin), do: gettext("matched via ISIN")
  defp tier_label(:former_isin), do: gettext("matched via former ISIN")
  defp tier_label(:wkn), do: gettext("matched via WKN")
  defp tier_label(:ticker), do: gettext("matched via ticker")
  defp tier_label(:name), do: gettext("matched via name")

  defp decision_text(%{status: :config_at_risk} = res) do
    names = Enum.map_join(res.at_risk, ", ", & &1.security.name)

    gettext(
      "Creating this security would leave strategy configuration (category assignments or position targets) stranded on: %{names}. Map it to the existing security, or explicitly confirm the creation.",
      names: names
    )
  end

  defp decision_text(%{conflict: %{type: :ambiguous}}) do
    gettext(
      "Several existing securities share this identifier — pick the right one or create a new security."
    )
  end

  defp decision_text(%{conflict: %{type: :identifier_veto}}) do
    gettext(
      "A likely match differs on a stronger identifier — possibly an ISIN change that has not been recorded yet. Map it explicitly (optionally recording the ISIN change) or create a new security."
    )
  end

  # E25 S5 (F36): one key standing for two references fails closed.
  defp decision_text(%{conflict: %{type: :key_collision}}) do
    gettext(
      "Two securities of this file cannot be told apart, so the import is refused. Correct them in Portfolio Performance and export again."
    )
  end

  defp decision_text(%{conflict: %{type: :cross_tier}}) do
    gettext(
      "Different identifiers point at different existing securities. Decide which one this entry belongs to."
    )
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

  # True iff every row that needs a decision has one the apply can carry out:
  # a cash row a choice, a depot row a target and a cash account. A choice of
  # "+ Create new" for a name the guard refuses is no choice (board 04b); an
  # ambiguous row with no new booking needs none (board 04, note 4). The
  # bucket tag never blocks — blank behaves like skip.
  defp mapping_complete?(%{cash_pp_names: cashes, depot_pp_names: depots} = assigns) do
    Enum.all?(cashes, &(cash_row_state(assigns, &1) in [:ok, :skip])) and
      Enum.all?(depots, &(depot_row_state(assigns, &1) in [:ok, :skip])) and
      security_decisions_complete?(assigns)
  end

  # :ok, :skip (undecided, and no decision needed) or :missing.
  defp cash_row_state(assigns, pp_name) do
    choice = Map.get(assigns.mapping.cash, pp_name)

    cond do
      not chosen?(choice) ->
        if decision_needed?(assigns.account_states, "cash", pp_name), do: :missing, else: :skip

      refused_create?(assigns, "cash", pp_name, choice) ->
        :missing

      true ->
        :ok
    end
  end

  # :ok, :skip, or {:missing, :both | :target | :cash}.
  defp depot_row_state(assigns, pp_name) do
    mapped = Map.get(assigns.mapping.depot, pp_name) || %{}
    target = mapped["target"]
    cash = mapped["cash"]

    if not chosen?(target) and not decision_needed?(assigns.account_states, "depot", pp_name) do
      :skip
    else
      target_ok? = chosen?(target) and not refused_create?(assigns, "depot", pp_name, target)
      cash_ok? = chosen?(cash) and depot_cash_ok?(assigns, target, cash)

      case {target_ok?, cash_ok?} do
        {true, true} -> :ok
        {false, false} -> {:missing, :both}
        {false, true} -> {:missing, :target}
        {true, false} -> {:missing, :cash}
      end
    end
  end

  # A depot's cash account named by a file cash name the mapping leaves
  # undecided (an ambiguous name with nothing new) links nothing; that is
  # fine for an existing depot, whose own cash account stays, and not for a
  # depot the import would create.
  defp depot_cash_ok?(assigns, target, "pp:" <> cash_name) do
    chosen?(Map.get(assigns.mapping.cash, cash_name)) or match?("existing:" <> _, target)
  end

  defp depot_cash_ok?(_assigns, _target, _cash), do: true

  # Only where the row has a new booking: without one nothing is created,
  # and the choice cannot fail the import.
  defp refused_create?(assigns, group, pp_name, "create:" <> _name) do
    row_counts(assigns.account_states, group, pp_name).new > 0 and
      create_refusal(assigns.account_states, group, pp_name, assigns.account_names) != nil
  end

  defp refused_create?(_assigns, _group, _pp_name, _choice), do: false

  # ADR-0029 §2: a surfaced decision requires an explicit choice; a
  # config-at-risk creation requires a remap or the per-row acknowledgment.
  defp security_decisions_complete?(%{security_resolutions: resolutions, mapping: m}) do
    Enum.all?(resolutions, &security_row_complete?(&1, m))
  end

  defp security_row_complete?(%{status: :needs_decision} = res, m) do
    security_choice(m, res) != ""
  end

  defp security_row_complete?(%{status: :config_at_risk} = res, m) do
    case security_choice(m, res) do
      "existing:" <> _id -> true
      "create" -> security_ack?(m, res)
      _other -> false
    end
  end

  defp security_row_complete?(_res, _m), do: true

  # The human-readable list of still-missing mappings, derived from the SAME
  # data `mapping_complete?/1` inspects, so the Confirm hint can never disagree
  # with the button's disabled state (#475).
  defp missing_mappings(%{cash_pp_names: cashes, depot_pp_names: depots} = assigns) do
    cash_missing(assigns, cashes) ++ depot_missing(assigns, depots) ++ security_missing(assigns)
  end

  defp security_missing(%{security_resolutions: resolutions, mapping: m}) do
    for res <- resolutions, not security_row_complete?(res, m) do
      gettext("security: %{name}", name: res.label)
    end
  end

  defp cash_missing(assigns, cashes) do
    for pp <- cashes, cash_row_state(assigns, pp) == :missing do
      gettext("cash account: %{name}", name: pp)
    end
  end

  defp chosen?(value), do: is_binary(value) and value != ""

  defp depot_missing(assigns, depots) do
    Enum.flat_map(depots, fn pp ->
      case depot_row_state(assigns, pp) do
        {:missing, :both} -> [gettext("depot and its cash account: %{name}", name: pp)]
        {:missing, :target} -> [gettext("target depot: %{name}", name: pp)]
        {:missing, :cash} -> [gettext("cash account for depot: %{name}", name: pp)]
        _complete -> []
      end
    end)
  end

  # The portfolio binding is internal (ADR-0024): the applier resolves
  # `Portfolios.default_portfolio/1` itself — no portfolio param here.
  defp build_apply_params(mapping, assigns) do
    assigns = %{assigns | mapping: mapping}

    with {:ok, cash_params} <- cash_params(assigns),
         {:ok, depot_params} <- depot_params(assigns, cash_params),
         {:ok, security_mappings, approved} <- security_params(mapping, assigns),
         bucket_tag = effective_bucket_tag(mapping),
         :ok <- validate_bucket_tag(bucket_tag) do
      {:ok,
       %{
         cash_accounts: cash_params,
         depots: depot_params,
         remember: remember_params(mapping),
         bucket_tag: bucket_tag,
         security_mappings: security_mappings,
         approved_resolutions: approved
       }}
    end
  end

  # ADR-0050 §4 and board 04 (G4-A): a remembered remap is a choice the
  # operator changed from the prefill onto an existing account, remembered
  # unless switched off. Every name mapped onto an existing account is passed
  # explicitly, because the applier remembers an absent name by default:
  #
  #   * an unchanged prefill is not remembered — it is the preview's choice,
  #     and a former name removed since the preview opened must not be
  #     written back;
  #   * an append is remembered, and so is a move of another account's
  #     former name, which the row states before the import is applied; a
  #     live name of another account is never remembered (the row says why).
  defp remember_params(mapping) do
    remember = Map.get(mapping, :remember, %{})
    prefill = Map.get(mapping, :prefill, %{})
    depot_targets = Map.new(mapping.depot, fn {pp_name, m} -> {pp_name, m["target"]} end)

    %{
      cash_accounts: remembered(:cash_account, mapping.cash, prefill["cash"], remember["cash"]),
      depots: remembered(:securities_account, depot_targets, prefill["depot"], remember["depot"])
    }
  end

  defp remembered(kind, choices, prefill, switches) do
    for {pp_name, "existing:" <> raw_id = choice} <- choices, into: %{} do
      remember? =
        Map.get(switches || %{}, pp_name) != "false" and
          Map.get(prefill || %{}, pp_name) != choice and remembers?(kind, pp_name, raw_id)

      {pp_name, remember?}
    end
  end

  defp remembers?(kind, pp_name, raw_id) do
    case LiveParam.fetch_id(raw_id) do
      {:ok, id} ->
        case Imports.remember_outcome(kind, pp_name, id) do
          :append -> true
          {:move, _from_id} -> true
          _nothing_to_remember -> false
        end

      :error ->
        false
    end
  end

  # Splits the reviewed security resolutions into the applier's explicit
  # `security_mappings` (user decisions: remaps, acknowledged creations) and
  # the `approved_resolutions` baseline the apply revalidates in-transaction
  # (ADR-0029 §2). Every resolution lands in exactly one of the two maps.
  defp security_params(mapping, %{security_resolutions: resolutions}) do
    Enum.reduce_while(resolutions, {:ok, %{}, %{}}, fn res, {:ok, mappings, approved} ->
      case security_apply_decision(res, mapping) do
        {:mapping, value} ->
          {:cont, {:ok, Map.put(mappings, res.key, value), approved}}

        {:approved, digest} ->
          {:cont, {:ok, mappings, Map.put(approved, res.key, digest)}}

        {:error, _message} = error ->
          {:halt, error}
      end
    end)
  end

  defp security_apply_decision(%{status: :matched} = res, _mapping) do
    {:approved, {:matched, res.matched.security_id}}
  end

  defp security_apply_decision(res, mapping) do
    case {res.status, security_choice(mapping, res)} do
      {_status, "existing:" <> id_str} ->
        case LiveParam.fetch_id(id_str) do
          {:ok, id} -> {:mapping, existing_security_mapping(res, mapping, id)}
          :error -> {:error, gettext("Invalid security id.")}
        end

      {:create, "create"} ->
        {:approved, :create}

      {:needs_decision, "create"} ->
        {:mapping, :create}

      {:config_at_risk, "create"} ->
        if security_ack?(mapping, res) do
          {:mapping, :create}
        else
          {:error, gettext("Confirm the flagged creation of security %{name}.", name: res.label)}
        end

      _other ->
        {:error, gettext("Decide how to import security %{name}.", name: res.label)}
    end
  end

  defp existing_security_mapping(res, mapping, id) do
    if security_record_isin_change?(mapping, res) do
      {:existing, id, :record_isin_change}
    else
      {:existing, id}
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

  defp cash_params(%{mapping: mapping, cash_pp_names: pp_names} = assigns) do
    Enum.reduce_while(pp_names, {:ok, %{}}, fn pp_name, {:ok, acc} ->
      case {cash_row_state(assigns, pp_name), Map.get(mapping.cash, pp_name)} do
        # Undecided and nothing new to book: the applier resolves the name
        # itself and holds it (ADR-0050 §3, §4).
        {:skip, _choice} ->
          {:cont, {:ok, acc}}

        {:ok, "existing:" <> id_str} ->
          case LiveParam.fetch_id(id_str) do
            {:ok, id} -> {:cont, {:ok, Map.put(acc, pp_name, {:existing, id})}}
            :error -> {:halt, {:error, gettext("Invalid cash account id.")}}
          end

        {:ok, "create:" <> name} ->
          {:cont, {:ok, Map.put(acc, pp_name, {:create, name})}}

        _missing ->
          {:halt, {:error, gettext("Pick a target for cash account %{n}.", n: pp_name)}}
      end
    end)
  end

  defp depot_params(%{mapping: mapping, depot_pp_names: pp_names} = assigns, cash_params) do
    Enum.reduce_while(pp_names, {:ok, %{}}, fn pp_name, {:ok, acc} ->
      with :ok <- depot_row_state(assigns, pp_name),
           %{"target" => target_str, "cash" => cash_str} <- Map.get(mapping.depot, pp_name),
           {:ok, target} <- parse_depot_target(target_str),
           {:ok, cash} <- parse_depot_cash(cash_str, target, cash_params, assigns) do
        {:cont, {:ok, Map.put(acc, pp_name, %{target: target, cash: cash})}}
      else
        :skip ->
          {:cont, {:ok, acc}}

        _ ->
          {:halt, {:error, gettext("Pick a target and cash account for depot %{n}.", n: pp_name)}}
      end
    end)
  end

  defp parse_depot_target("existing:" <> id_str) do
    with {:ok, id} <- LiveParam.fetch_id(id_str), do: {:ok, {:existing, id}}
  end

  defp parse_depot_target("create:" <> name), do: {:ok, {:create, name}}
  defp parse_depot_target(_), do: :error

  defp parse_depot_cash("existing:" <> id_str, _target, _cash_params, _assigns) do
    with {:ok, id} <- LiveParam.fetch_id(id_str), do: {:ok, {:existing, id}}
  end

  # A file cash name the mapping leaves undecided links nothing: an existing
  # depot keeps its own cash account (`depot_cash_ok?/3`).
  defp parse_depot_cash("pp:" <> name, {:existing, depot_id}, cash_params, assigns) do
    if Map.has_key?(cash_params, name) do
      {:ok, name}
    else
      case Enum.find(assigns.existing_depots, &(&1.id == depot_id)) do
        %{cash_account_id: cash_id} -> {:ok, {:existing, cash_id}}
        nil -> :error
      end
    end
  end

  defp parse_depot_cash("pp:" <> name, _target, _cash_params, _assigns), do: {:ok, name}
  defp parse_depot_cash(_cash, _target, _cash_params, _assigns), do: :error

  # The applier names the layer that caught the duplicate; the words are the
  # page's (#769), so the German page is German here too.
  defp duplicate_reason(%{layer: :hash}),
    do: gettext("an identical row was imported before (stored content hash)")

  # ADR-0050 §3: the row's content hash was retired when a merge removed the
  # booking that held it.
  defp duplicate_reason(%{layer: :retired}),
    do: gettext("a row with this content was removed by a merge (retired content hash)")

  defp duplicate_reason(%{layer: :economics}),
    do: gettext("an existing booking has the same date, security, quantity and amount")

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

  # E25 S5 (F34, board 11): the finding and the remedy, in the error band.
  defp parse_error_message(:invalid_encoding),
    do:
      gettext(
        "The file is not UTF-8 encoded. Remedy: export it again from Portfolio Performance and drop the file without saving it in a spreadsheet first."
      )

  defp parse_error_message(:malformed_payload),
    do: gettext("The file could not be read as a Portfolio Performance export.")

  # E25 S5 (F35, board 11): what is too much and what a file that fits looks
  # like; the cap itself is named nowhere on the page.
  defp parse_error_message(:too_many_names),
    do:
      gettext(
        "The file names too many different accounts, depots or securities for one preview. Remedy: create smaller exports in Portfolio Performance, for example one per account or depot, and import them one after another."
      )

  defp parse_error_message({:too_many_rows, n}),
    do:
      gettext("The file has %{n} rows; the import is sized for at most %{max}.",
        n: n,
        max: PortfolioPerformance.max_rows()
      )

  # E25 S5 (F38): the cap counts the entries a file expands into.
  defp parse_error_message({:too_many_entries, n}),
    do:
      gettext(
        "The file expands to %{n} entries (its rows and the tax refunds they split off); the import is sized for at most %{max}.",
        n: n,
        max: PortfolioPerformance.max_rows()
      )

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

  # A selected override target vanished between preview and apply.
  defp apply_error_message({:invalid_security_mapping, _key}) do
    gettext(
      "A selected security no longer exists — review the security mapping and confirm again."
    )
  end

  defp apply_error_message({:record_isin_change_failed, _key, %Ecto.Changeset{} = changeset}) do
    gettext("Recording the ISIN change failed: %{errors}",
      errors: changeset_error_text(changeset)
    )
  end

  # A forced :create override collided with an existing security (e.g. a
  # live-ISIN unique constraint): surface the rejecting changeset's field
  # messages instead of an opaque tuple dump.
  defp apply_error_message({:security_create_failed, %Ecto.Changeset{} = changeset}) do
    gettext("Creating the security failed: %{errors}", errors: changeset_error_text(changeset))
  end

  defp apply_error_message({failed, name, %Ecto.Changeset{} = changeset})
       when failed in [:cash_create_failed, :depot_create_failed] do
    gettext("Creating the account %{name} failed: %{errors}",
      name: name,
      errors: changeset_error_text(changeset)
    )
  end

  defp apply_error_message({:portfolio_create_failed, %Ecto.Changeset{} = changeset}) do
    gettext("Creating the portfolio failed: %{errors}", errors: changeset_error_text(changeset))
  end

  # ADR-0050 §4: an account name two accounts carry is never guessed.
  defp apply_error_message({:ambiguous_account_name, _kind, name, _ids}) do
    gettext(
      "Several accounts are named %{name}. Pick the one this export's %{name} books to, then confirm again. Nothing was written.",
      name: name
    )
  end

  defp apply_error_message({:security_key_collision, _key}) do
    gettext(
      "Two securities of this file cannot be told apart, so the import is refused. Correct them in Portfolio Performance and export again."
    )
  end

  # Named messages only (#769): no reason is shown as an inspected term.
  defp apply_error_message(_reason), do: gettext("Import failed. Nothing was written.")

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
    |> Enum.map(fn err ->
      gettext("Row %{row}: %{message}", row: err.row || "?", message: err.message)
    end)
    |> Enum.join("\n")
  end
end
