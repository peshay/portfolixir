defmodule PortfolixirWeb.PredictionsLive do
  @moduledoc """
  The Wealth area's **Predictions** tab (`/predictions`; Sprint 26 V2, idea
  F1; ADR-0055 §§4-5; board `ux-design-2026-11-06-sprint26-f1`, part 2,
  pick A): how well the recorded predictions have scored, across every
  security and independent of the active view, which the subtitle says.

  Top to bottom:

    * **the author and model chips** (`author`, `model` in the URL, the
      calibration read's own filters); they narrow the report and the list;
    * **Calibration** with its counts: the Brier score ± its standard error
      beside the 0.25 reference, the sharpness, the hit rate ± its standard
      error beside the mean stated probability, and the resolved count with
      what is counted in no score;
    * **By probability**: while no band has the read's minimum count, one
      sentence why and the count per band; from it, the band table, a band
      below the minimum reading "too few · n of 20";
    * **By author and model**: the same block per author and per model;
    * **All predictions** across securities, newest first, with the status
      chips (`status` in the URL) and the due query (`due_before` today).

  The report is `Portfolixir.Predictions.calibration_report/2` and the list
  `Portfolixir.Predictions.list_with_resolution/2`, the reads
  `GET /api/v1/predictions/calibration` and `GET /api/v1/predictions`
  answer from, so the page and the agent read the same figures. The page
  writes nothing (ADR-0055 §2) and proposes nothing (§6): it scores calls
  and makes none.
  """

  use PortfolixirWeb, :live_view

  alias Portfolixir.Clock
  alias Portfolixir.Input.Text
  alias Portfolixir.Predictions
  alias Portfolixir.Predictions.Prediction
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.PredictionLabel
  alias PortfolixirWeb.StoredText

  # Every figure on this page is a ratio (a Brier score, its error and
  # reference, a sharpness, a band's bounds), a percentage or a count, so
  # each stays in the privacy mode (P1): `Format.plain_decimal/2`, never
  # the masked `Format.decimal/2`.
  @authors ~w(operator agent)
  @statuses ~w(open due resolved unresolved)
  # A model is stored at up to 100 characters (Prediction.model_max/0).
  @model_max 100

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :current_path, "/predictions")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      author: closed(params["author"], @authors),
      model: model(params["model"]),
      status: closed(params["status"], @statuses)
    }

    {:noreply, socket |> assign(:filters, filters) |> load()}
  end

  # Values from the URL are matched as text and handed on as text; the
  # context turns a known author into its atom, so no atom is made here.
  defp closed(value, allowed) when is_binary(value),
    do: if(value in allowed, do: value)

  defp closed(_value, _allowed), do: nil

  # A model filter is a text a stored model can be (`Input.Text`'s rule,
  # which the model was stored under): valid UTF-8, no control or invisible
  # character, at most the stored length. Anything else, such as `%00`,
  # which the database refuses in a query, filters nothing.
  defp model(value) when is_binary(value) and value != "" do
    if Text.check(value, max: @model_max) == :ok, do: value
  end

  defp model(_value), do: nil

  defp load(socket) do
    today = Clock.today()
    %{author: author, model: model, status: status} = socket.assigns.filters
    filters = Enum.reject([author: author, model: model], fn {_key, value} -> is_nil(value) end)

    if Predictions.list_predictions(limit: 1) == [] do
      assign(socket, empty?: true, today: today)
    else
      report = Predictions.calibration_report(filters)

      assign(socket,
        empty?: false,
        today: today,
        models: Predictions.list_models(),
        report: report,
        basis: report.computation_basis,
        entries: Predictions.list_with_resolution(filters ++ status_filter(status, today)),
        due: length(Predictions.list_with_resolution(filters ++ [due_before: today]))
      )
    end
  end

  # "Due" is the API's due query: open, with resolves_on on or before today.
  defp status_filter(nil, _today), do: []
  defp status_filter("due", today), do: [due_before: today]
  defp status_filter(status, _today), do: [status: status]

  @impl true
  def handle_event("filter_author", params, socket),
    do: patch(socket, author: closed(params["author"], @authors))

  # A click on the pressed model chip clears it.
  def handle_event("filter_model", params, socket) do
    model = model(params["model"])
    patch(socket, model: if(model == socket.assigns.filters.model, do: nil, else: model))
  end

  def handle_event("filter_status", params, socket),
    do: patch(socket, status: closed(params["status"], @statuses))

  # An event this page does not know, or a payload it cannot read, changes
  # nothing (E25 S4, F17).
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp patch(socket, changes) do
    filters = Map.merge(socket.assigns.filters, Map.new(changes))

    query =
      [author: filters.author, model: filters.model, status: filters.status]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    path = if query == [], do: "/predictions", else: "/predictions?" <> URI.encode_query(query)
    {:noreply, push_patch(socket, to: path)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell page_address={@page_address}
      current_path={@current_path}
      page_title={gettext("Predictions")}
      page_subtitle={
        gettext(
          "How well the recorded predictions have scored · across all securities, independent of the view"
        )
      }
    >
      <div class="workspace-page">
        <AppShell.area_tabs tabs={AppShell.wealth_tabs(:predictions)} />

        <%= if @empty? do %>
          <section class="workspace-section">
            <p class="empty-state" data-role="predictions-empty">
              <%= gettext("No prediction is recorded yet.") %>
              <%= gettext("Predictions are recorded over the API or MCP.") %>
            </p>
          </section>
        <% else %>
          <.filters filters={@filters} models={@models} />
          <.calibration report={@report} basis={@basis} />
          <.list entries={@entries} report={@report} due={@due} filters={@filters} today={@today} />
        <% end %>
      </div>
    </AppShell.shell>
    """
  end

  attr(:filters, :map, required: true)
  attr(:models, :list, required: true)

  # Board 02 ②: the author and model chips. Chips are toggles, so they
  # carry aria-pressed (UX-DR7). They sit in Wealth's control band, as the
  # other Wealth tabs' view switcher does, which gives them the section's
  # inline gutter (closing act, design critic V2).
  defp filters(assigns) do
    ~H"""
    <div class="workspace-section workspace-section--controls">
      <div
        id="prediction-filters"
        class="filter-chips prediction-filters"
        role="group"
        aria-label={gettext("Filter the predictions")}
      >
        <span class="filter-chips__family"><%= gettext("Author") %></span>
        <button
          :for={{value, label} <- [{nil, gettext("All")}, {"operator", gettext("Operator")}, {"agent", gettext("Agent")}]}
          type="button"
          id={"prediction-chip-author-#{value || "all"}"}
          class={["filter-chip", @filters.author == value && "is-active"]}
          aria-pressed={to_string(@filters.author == value)}
          phx-click="filter_author"
          phx-value-author={value || ""}
        >
          <%= label %>
        </button>
        <%= if @models != [] do %>
          <span class="filter-chips__family"><%= gettext("Model") %></span>
          <button
            :for={{model, index} <- Enum.with_index(@models)}
            type="button"
            id={"prediction-chip-model-#{chip_id(model, index)}"}
            class={["filter-chip", @filters.model == model && "is-active"]}
            aria-pressed={to_string(@filters.model == model)}
            phx-click="filter_model"
            phx-value-model={model}
          >
            <bdi><%= model %></bdi>
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  # A model is the agent's free text; an id carries it only when it is
  # plain, otherwise its position.
  defp chip_id(model, index) do
    if Regex.match?(~r/\A[A-Za-z0-9._-]{1,64}\z/, model), do: model, else: "n#{index}"
  end

  attr(:report, :map, required: true)
  attr(:basis, :map, required: true)

  defp calibration(assigns) do
    assigns =
      assign(assigns, :unresolved, unresolved(assigns.report.counts))

    ~H"""
    <section
      class="workspace-section kpi-band prediction-calibration"
      id="prediction-calibration"
      aria-labelledby="prediction-calibration-title"
    >
      <header class="section-head">
        <div class="section-title">
          <h2 id="prediction-calibration-title">
            <%= gettext("Calibration") %>
            <span class="section-head__meta">
              <%= gettext("· %{resolved} resolved · %{open} open · %{unresolved} not resolved",
                resolved: @report.counts.resolved,
                open: @report.counts.open,
                unresolved: @unresolved
              ) %>
            </span>
          </h2>
          <AppShell.section_info>
            <:line>
              <%= gettext(
                "Brier score: the mean of (p − o)² over the resolved predictions, p the stated probability, o 1 for a hit and 0 otherwise. The reference %{reference} is the score of “always 50 %”.",
                reference: Format.plain_decimal(@report.brier.reference, 2)
              ) %>
            </:line>
            <:line>
              <%= gettext(
                "Standard error: the sample standard deviation of the squared errors, divided by √n; for the hit rate, that of the hits."
              ) %>
            </:line>
            <:line>
              <%= gettext(
                "Sharpness: the mean of p − 0.50. Whoever always says 50 % is perfectly calibrated and says nothing."
              ) %>
            </:line>
            <:line>
              <%= gettext(
                "Hit rate: hits divided by n, beside the mean stated probability, which a calibrated hit rate matches."
              ) %>
            </:line>
            <:line>
              <%= gettext("Open and unresolved predictions count in no score; they are counted.") %>
            </:line>
            <:line>
              <%= gettext(
                "Resolved as on a security's Predictions tab; price return only, closes at most %{days} days old.",
                days: @basis.staleness_days
              ) %>
            </:line>
          </AppShell.section_info>
        </div>
      </header>

      <div class="kpi-band__support prediction-kpis">
        <article class="stat stat--compact" data-role="prediction-brier">
          <span><%= gettext("Brier score") %></span>
          <strong>
            <%= Format.plain_decimal(@report.brier.score, 3) %><small class="value-suffix"> ± <%= Format.plain_decimal(@report.brier.standard_error, 3) %></small>
          </strong>
          <small class="stat__sub">
            <%= gettext("± standard error · reference %{reference} = always 50 % · lower is better",
              reference: Format.plain_decimal(@report.brier.reference, 2)
            ) %>
          </small>
        </article>
        <article class="stat stat--compact" data-role="prediction-sharpness">
          <span><%= gettext("Sharpness") %></span>
          <strong><%= Format.plain_decimal(@report.sharpness, 2) %></strong>
          <small class="stat__sub">
            <%= gettext("mean distance of the probability from 0.50 · 0 = always 50 %") %>
          </small>
        </article>
        <article class="stat stat--compact" data-role="prediction-hit-rate">
          <span><%= gettext("Hit rate") %></span>
          <strong>
            <%= Format.percent(@report.hit_rate.rate) %><small :if={@report.hit_rate.rate} class="value-suffix">%</small>
          </strong>
          <small class="stat__sub">
            <%= gettext("± %{se} pp standard error · mean stated %{mean}",
              se: Format.percent(@report.hit_rate.standard_error),
              mean: percent(@report.hit_rate.mean_probability)
            ) %>
          </small>
        </article>
        <article class="stat stat--compact" data-role="prediction-counts">
          <span><%= pgettext("prediction status", "Resolved") %></span>
          <strong><%= @report.counts.resolved %></strong>
          <small class="stat__sub">
            <%= gettext("%{open} open and %{unresolved} not resolved count in no score",
              open: @report.counts.open,
              unresolved: @unresolved
            ) %>
          </small>
        </article>
      </div>
      <p class="summary-basis" data-role="prediction-basis">
        <%= gettext(
          "Basis: every resolved prediction once, its probability and outcome as on the security's Predictions tab."
        ) %>
      </p>

      <.bands bands={@report.bands} minimum={@basis.minimum_band_count} />
      <.groups groups={@report.groups} />
    </section>
    """
  end

  attr(:bands, :list, required: true)
  attr(:minimum, :integer, required: true)

  # Board 02 ⑤ and judgment call 7: one sentence and a count line while no
  # band has the minimum; the table from the first band at it.
  defp bands(assigns) do
    assigns = assign(assigns, :table?, Enum.any?(assigns.bands, &(&1.count >= assigns.minimum)))

    ~H"""
    <div class="prediction-bands" data-role="prediction-bands" data-state={if @table?, do: "table", else: "too_few"}>
      <div class="section-title"><h3><%= gettext("By probability") %></h3></div>
      <%= if @table? do %>
        <div class="data-table-wrapper">
          <table class="data-table prediction-bands-table">
            <thead>
              <tr>
                <th><%= gettext("Band") %></th>
                <th class="num"><%= pgettext("prediction status", "Resolved") %></th>
                <th class="num"><%= gettext("Mean stated") %></th>
                <th class="num"><%= gettext("Hit rate") %></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={band <- @bands}>
                <td><%= band_label(band) %></td>
                <td class="num"><%= band.count %></td>
                <td class="num"><%= percent(band.mean_probability) %></td>
                <td class="num">
                  <%= if band.hit_rate == :too_few do %>
                    <span class="prediction-too-few">
                      <%= ngettext(
                        "too few · %{count} of %{minimum}",
                        "too few · %{count} of %{minimum}",
                        band.count,
                        minimum: @minimum
                      ) %>
                    </span>
                  <% else %>
                    <%= percent(band.hit_rate) %>
                  <% end %>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% else %>
        <p class="prediction-bands__why">
          <%= gettext(
            "A hit rate per band shows from %{minimum} resolved predictions in the band; none has reached %{minimum} yet. Until then the Brier score with its standard error carries the finding.",
            minimum: @minimum
          ) %>
        </p>
        <p class="summary-basis prediction-bands__counts">
          <%= gettext("Resolved per band:") %>
          <%= Enum.map_join(@bands, " · ", &"#{band_label(&1)}: #{&1.count}") %>
        </p>
      <% end %>
    </div>
    """
  end

  attr(:groups, :map, required: true)

  # Board 02 ⑥: the operator, the agent over all its models, then each
  # model, indented; on a phone the same as two-line rows.
  defp groups(assigns) do
    assigns = assign(assigns, :rows, group_rows(assigns.groups))

    ~H"""
    <div class="prediction-groups" data-role="prediction-groups">
      <div class="section-title"><h3><%= gettext("By author and model") %></h3></div>
      <div class="data-table-wrapper" id="prediction-groups-table-wrap">
        <table class="data-table prediction-groups-table" id="prediction-groups-table">
          <thead>
            <tr>
              <th><%= gettext("Author") %></th>
              <th><%= gettext("Model") %></th>
              <th class="num"><%= pgettext("prediction status", "Resolved") %></th>
              <th class="num"><%= gettext("Brier score") %></th>
              <th class="num"><%= gettext("Sharpness") %></th>
              <th class="num"><%= gettext("Hit rate") %></th>
              <th class="num"><%= gettext("Mean stated") %></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows} class={row.model? && "prediction-groups__model"}>
              <td><%= row.author %></td>
              <td><%= row.model %></td>
              <td class="num"><%= row.block.counts.resolved %></td>
              <td class="num"><%= brier(row.block) %></td>
              <td class="num"><%= Format.plain_decimal(row.block.sharpness, 2) %></td>
              <td class="num"><%= hit_rate(row.block) %></td>
              <td class="num"><%= percent(row.block.hit_rate.mean_probability) %></td>
            </tr>
          </tbody>
        </table>
      </div>
      <ul class="phone-rows" id="prediction-groups-phone-rows">
        <li :for={row <- @rows} class="phone-row">
          <span class="phone-row__body">
            <span class="phone-row__name"><%= row.author %><%= if row.model? do %> · <%= row.model %><% end %></span>
            <span class="phone-row__ids">
              <%= ngettext(
                "%{count} resolved · sharpness %{sharpness} · mean stated %{mean}",
                "%{count} resolved · sharpness %{sharpness} · mean stated %{mean}",
                row.block.counts.resolved,
                sharpness: Format.plain_decimal(row.block.sharpness, 2),
                mean: percent(row.block.hit_rate.mean_probability)
              ) %>
            </span>
          </span>
          <span class="phone-row__figures">
            <span class="phone-row__figure"><%= brier(row.block) %></span>
            <span class="phone-row__figure2"><%= gettext("Hit rate") %> <%= hit_rate(row.block) %></span>
          </span>
        </li>
      </ul>
    </div>
    """
  end

  defp group_rows(groups) do
    operator =
      for group <- groups.author,
          group.author == :operator,
          do: %{author: gettext("Operator"), model: "—", model?: false, block: group}

    agent =
      for group <- groups.author,
          group.author == :agent,
          do: %{
            author: gettext("Agent"),
            model: gettext("all models"),
            model?: false,
            block: group
          }

    models =
      for group <- groups.model,
          is_binary(group.model),
          do: %{
            author: gettext("Agent"),
            model: StoredText.bdi(group.model),
            model?: true,
            block: group
          }

    operator ++ agent ++ models
  end

  attr(:entries, :list, required: true)
  attr(:report, :map, required: true)
  attr(:due, :integer, required: true)
  attr(:filters, :map, required: true)
  attr(:today, Date, required: true)

  # Board 02 ⑦: every prediction across securities, newest first, with the
  # status chips; "Due" is the API's due query.
  defp list(assigns) do
    counts = assigns.report.counts

    assigns =
      assign(assigns, :chips, [
        {nil, gettext("All"), counts.total},
        {"open", pgettext("prediction status", "Open"), counts.open},
        {"due", gettext("Due"), assigns.due},
        {"resolved", pgettext("prediction status", "Resolved"), counts.resolved},
        {"unresolved", gettext("Not resolved"), unresolved(counts)}
      ])

    ~H"""
    <section class="workspace-section prediction-list" id="prediction-list" aria-labelledby="prediction-list-title">
      <header class="section-head">
        <div class="section-title">
          <h2 id="prediction-list-title"><%= gettext("All predictions") %></h2>
        </div>
      </header>
      <div
        id="prediction-status-chips"
        class="filter-chips"
        role="group"
        aria-label={gettext("Filter by status")}
      >
        <button
          :for={{value, label, count} <- @chips}
          type="button"
          id={"prediction-chip-status-#{value || "all"}"}
          class={["filter-chip", @filters.status == value && "is-active"]}
          aria-pressed={to_string(@filters.status == value)}
          phx-click="filter_status"
          phx-value-status={value || ""}
        >
          <%= label %><span class="filter-chip__count"><%= count %></span>
        </button>
      </div>

      <%= if @entries == [] do %>
        <p class="empty-state"><%= gettext("No prediction matches this filter.") %></p>
      <% else %>
        <div class="data-table-wrapper" id="prediction-list-table-wrap">
          <table class="data-table prediction-list-table" id="prediction-list-table">
            <thead>
              <tr>
                <th><%= gettext("Made · author") %></th>
                <th class="cell-name"><%= gettext("Security · claim") %></th>
                <th class="num"><%= gettext("Prob.") %></th>
                <th><%= gettext("State") %></th>
                <th class="num"><%= gettext("Excess") %></th>
              </tr>
            </thead>
            <tbody>
              <.row
                :for={entry <- @entries}
                prediction={entry.prediction}
                resolution={entry.resolution}
                state={PredictionLabel.state(entry.prediction, entry.resolution, @today)}
                today={@today}
              />
            </tbody>
          </table>
        </div>
        <ul class="phone-rows" id="prediction-list-phone-rows">
          <.phone_row
            :for={entry <- @entries}
            prediction={entry.prediction}
            resolution={entry.resolution}
            state={PredictionLabel.state(entry.prediction, entry.resolution, @today)}
            today={@today}
          />
        </ul>
      <% end %>
    </section>
    """
  end

  attr(:prediction, :map, required: true)
  attr(:resolution, :map, required: true)
  attr(:state, :atom, required: true)
  attr(:today, Date, required: true)

  defp row(assigns) do
    ~H"""
    <tr data-role="prediction-row" data-prediction-id={@prediction.id} data-state={@state}>
      <td>
        <%= Format.date(made_on(@prediction)) %>
        <span class="policy-rule__words"><%= PredictionLabel.author(@prediction) %></span>
      </td>
      <td class="cell-name">
        <a href={"/securities/#{@prediction.security_id}?tab=predictions"}><bdi><%= @prediction.security.name %></bdi></a>
        <span class="policy-rule__words"><%= PredictionLabel.claim(@prediction) %></span>
      </td>
      <td class="num"><%= PredictionLabel.probability(@prediction) %></td>
      <td>
        <span class={PredictionLabel.badge_class(@state)} data-role="prediction-status">
          <%= PredictionLabel.status(@state, @prediction, @today) %>
        </span>
        <span :if={@state == :unresolved} class="policy-rule__reason">
          <%= PredictionLabel.reason(@resolution.reason) %>
        </span>
      </td>
      <td class="num">
        <%= if @state in [:hit, :miss] do %>
          <span class={PredictionLabel.sign_class(@resolution.excess)}><%= PredictionLabel.excess(@resolution.excess) %></span>
        <% else %>
          —
        <% end %>
      </td>
    </tr>
    """
  end

  # Under 560 px (UX-DR27): the security over the claim and the made line;
  # the figure is the excess once resolved, else the days left; its second
  # line names the status.
  defp phone_row(assigns) do
    ~H"""
    <li class="phone-row" data-prediction-id={@prediction.id} data-state={@state}>
      <span class="phone-row__body">
        <a class="phone-row__name phone-row__target" href={"/securities/#{@prediction.security_id}?tab=predictions"}>
          <bdi><%= @prediction.security.name %></bdi>
        </a>
        <span class="phone-row__ids">
          <span><%= PredictionLabel.claim(@prediction) %> · <%= PredictionLabel.probability(@prediction) %></span>
        </span>
        <span class="phone-row__ids">
          <%= Format.date(made_on(@prediction)) %> · <%= PredictionLabel.author(@prediction) %>
        </span>
      </span>
      <span class="phone-row__figures">
        <span class="phone-row__figure">
          <%= cond do %>
            <% @state in [:hit, :miss] -> %>
              <span class={PredictionLabel.sign_class(@resolution.excess)}><%= PredictionLabel.excess(@resolution.excess) %></span>
            <% @state == :open -> %>
              <%= ngettext("%{count} day left", "%{count} days left", Date.diff(@prediction.resolves_on, @today)) %>
            <% true -> %>
              —
          <% end %>
        </span>
        <span class="phone-row__figure2"><%= phone_status(@state, @resolution) %></span>
      </span>
    </li>
    """
  end

  defp phone_status(:hit, _resolution), do: gettext("Hit")
  defp phone_status(:miss, _resolution), do: gettext("missed")
  defp phone_status(:unresolved, resolution), do: PredictionLabel.reason(resolution.reason)
  defp phone_status(:waiting, _resolution), do: gettext("waiting for the close")
  defp phone_status(:open, _resolution), do: pgettext("prediction status", "open")

  defp made_on(prediction), do: Prediction.made_on(prediction)

  defp unresolved(counts), do: counts.unresolved |> Map.values() |> Enum.sum()

  defp band_label(band),
    do: "#{Format.plain_decimal(band.from, 2)}–#{Format.plain_decimal(band.to, 2)}"

  defp brier(block),
    do:
      "#{Format.plain_decimal(block.brier.score, 3)} ± #{Format.plain_decimal(block.brier.standard_error, 3)}"

  defp hit_rate(block),
    do: "#{percent(block.hit_rate.rate)} ± #{Format.percent(block.hit_rate.standard_error)}"

  defp percent(nil), do: "—"
  defp percent(%Decimal{} = value), do: Format.percent(value) <> " %"
end
