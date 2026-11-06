defmodule PortfolixirWeb.Securities.PredictionsTab do
  @moduledoc """
  The security page's tab **Predictions** (Sprint 26 V1; F1, ADR-0055 §5;
  board `ux-design-2026-11-06-sprint26-f1`, part 1): the calls recorded on
  one security, newest first, in the research timeline's anatomy
  (`.research-timeline`, `.research-entry`, its head, meta, facts and
  body), because a prediction is another permanent record of the
  security's and carries a sentence and a rationale.

  Each entry is headed by its status badge and "#id · day made · author",
  then the claim in one sentence beside its probability. A resolved call
  adds its figures — the return, the benchmark return, the excess in
  percentage points and the dates of the closes used — and nothing else
  does: an open or unresolved call's claim line says all there is. A miss
  is muted, never red; the excess keeps its sign colour beside it.

  The entries come from `Portfolixir.Predictions.list_with_resolution/2`,
  the read `GET /api/v1/predictions?security_id=` answers from, so the tab
  and the API cannot disagree. The tab writes nothing: a prediction is
  recorded over the API or MCP, and never changed (ADR-0055 §2).
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Predictions.Calibration
  alias Portfolixir.Predictions.Prediction
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.PredictionLabel

  attr(:security, :map, required: true)
  attr(:entries, :list, required: true, doc: "`%{prediction:, resolution:}`, newest first")
  attr(:note_kinds, :map, default: %{}, doc: "research-entry id => kind, for the entry's link")
  attr(:today, Date, required: true)

  @doc "The tab's panel."
  def panel(assigns) do
    assigns = assign(assigns, :days, Calibration.computation_basis().staleness_days)

    ~H"""
    <section
      id="detail-tab-panel-predictions"
      role="tabpanel"
      aria-labelledby="detail-tab-predictions"
      class="detail-tab-panel detail-tab-panel--predictions"
    >
      <%!-- Board 02 ②: the tab has no heading, so its line keeps the set
           and ends in the ⓘ with the rule, as Research and Dates do. --%>
      <div class="detail-tab-hint" data-role="predictions-basis">
        <%= gettext("Recorded predictions on this security, newest first. None is ever changed or deleted.") %>
        <AppShell.section_info>
          <:line>
            <%= gettext(
              "A prediction stays as it was made: it is never changed, withdrawn or deleted. A corrected prediction is a new one, and both count."
            ) %>
          </:line>
          <:line>
            <%= gettext(
              "It is scored at read from stored closes, both sides in EUR at the stored exchange rate of their day; no result is ever stored."
            ) %>
          </:line>
          <:line>
            <%= gettext(
              "Start: the last close on or before the day it was made. End: the last on or before the resolution day. It is scored once a close from the resolution day on is in, at the latest %{days} days after it.",
              days: @days
            ) %>
          </:line>
          <:line>
            <%= gettext(
              "A close more than %{days} days before its date does not count; the prediction then stays unresolved, with its reason, and is never estimated.",
              days: @days
            ) %>
          </:line>
          <:line>
            <%= gettext(
              "Excess = return − the benchmark's return. “Outperforms” hits above 0, “underperforms” below 0; exactly 0 misses both. A fixed rate compounds daily; 0 % is the absolute call (rises, falls)."
            ) %>
          </:line>
          <:line><%= gettext("Price return only: distributions count on neither side.") %></:line>
          <:line><%= gettext("Predictions are recorded over the API or MCP.") %></:line>
        </AppShell.section_info>
      </div>

      <%= if @entries == [] do %>
        <p class="empty-state">
          <%= gettext("No prediction is recorded for this security.") %>
          <%= gettext("Predictions are recorded over the API or MCP.") %>
        </p>
      <% else %>
        <ol
          class="research-timeline prediction-timeline"
          data-role="prediction-timeline"
          aria-label={gettext("Predictions")}
        >
          <.entry
            :for={entry <- @entries}
            prediction={entry.prediction}
            resolution={entry.resolution}
            state={PredictionLabel.state(entry.prediction, entry.resolution, @today)}
            security={@security}
            note_kinds={@note_kinds}
            today={@today}
            days={@days}
          />
        </ol>
      <% end %>
    </section>
    """
  end

  attr(:prediction, :map, required: true)
  attr(:resolution, :map, required: true)
  attr(:state, :atom, required: true)
  attr(:security, :map, required: true)
  attr(:note_kinds, :map, required: true)
  attr(:today, Date, required: true)
  attr(:days, :integer, required: true)

  defp entry(assigns) do
    ~H"""
    <li
      id={"prediction-#{@prediction.id}"}
      class={["research-entry", "prediction-entry", "prediction-entry--#{@state}"]}
      data-role="prediction-entry"
      data-state={@state}
    >
      <div class="research-entry__head">
        <span class={PredictionLabel.badge_class(@state)} data-role="prediction-status">
          <%= PredictionLabel.status(@state, @prediction, @today) %>
        </span>
        <span class="research-entry__meta">
          #<%= @prediction.id %> · <%= Format.date(Prediction.made_on(@prediction)) %> · <%= PredictionLabel.author(@prediction) %>
        </span>
      </div>
      <p class="prediction-entry__claim">
        <strong><%= PredictionLabel.claim(@prediction) %></strong>
        <span class="prediction-entry__p">
          <span class="prediction-entry__p-label"><%= gettext("Probability") %></span>
          <%= PredictionLabel.probability(@prediction) %>
        </span>
      </p>
      <p :if={@state == :waiting} class="prediction-entry__reason">
        <%= gettext(
          "The resolution day has passed; it is scored once a close from %{date} on is in, at the latest on %{last}.",
          date: Format.date(@prediction.resolves_on),
          last: Format.date(Date.add(@prediction.resolves_on, @days))
        ) %>
      </p>
      <p :if={@state == :unresolved} class="prediction-entry__reason">
        <b><%= PredictionLabel.reason(@resolution.reason) %>:</b>
        <%= PredictionLabel.reason_sentence(@resolution, @days) %>
      </p>
      <dl :if={@state in [:hit, :miss]} class="research-entry__facts prediction-entry__facts">
        <div>
          <dt><%= gettext("Return") %></dt>
          <dd class="num">
            <span class={PredictionLabel.sign_class(@resolution.security.return)}><%= PredictionLabel.return(@resolution.security.return) %></span>
          </dd>
        </div>
        <div>
          <dt><%= gettext("Benchmark return") %></dt>
          <dd class="num"><%= PredictionLabel.return(@resolution.benchmark.return) %></dd>
        </div>
        <div>
          <dt><%= gettext("Excess") %></dt>
          <dd class="num">
            <span class={PredictionLabel.sign_class(@resolution.excess)}><%= PredictionLabel.excess(@resolution.excess) %></span>
          </dd>
        </div>
        <div>
          <dt><%= gettext("Closes") %></dt>
          <dd>
            <%= Format.date(@resolution.security.start.date) %> → <%= Format.date(@resolution.security.end.date) %>
          </dd>
        </div>
      </dl>
      <p :if={@prediction.rationale} class="research-entry__body"><%= @prediction.rationale %></p>
      <p :if={@prediction.note_id} class="research-entry__meta">
        <a href={"/securities/#{@security.id}?tab=research#research-entry-#{@prediction.note_id}"}>
          <%= note_link(@prediction.note_id, Map.get(@note_kinds, @prediction.note_id)) %>
        </a>
      </p>
    </li>
    """
  end

  defp note_link(id, nil), do: gettext("Research #%{id}", id: id)

  defp note_link(id, kind),
    do: gettext("Research #%{id} · %{kind}", id: id, kind: kind_label(kind))

  # The research log's own kind words (the Research tab's `kind_label/1`).
  defp kind_label(:thesis), do: gettext("Thesis")
  defp kind_label(:evidence), do: gettext("Evidence")
  defp kind_label(:invalidation_check), do: gettext("Invalidation check")
  defp kind_label(:event_result), do: gettext("Event result")
  defp kind_label(:risk), do: gettext("Risk")
  defp kind_label(:retraction), do: gettext("Retraction")
  defp kind_label(:decision), do: gettext("Decision")
end
