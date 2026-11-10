defmodule PortfolixirWeb.Securities.StoriesTab do
  @moduledoc """
  The security page's tab **Nachrichten** (Sprint 28, N8; ADR-0056 §8,
  §10; board `ux-design-2026-11-08-sprint28/01`, "Am Wertpapier"; plan
  D-5): the security's stories, after Research.

  **No logic of its own.** The line on top is `securities.dossier`'s news
  block (`Portfolixir.News.dossier_block/2`); the rows are the page
  `news.list` answers for the security with `fields=std`
  (`Portfolixir.News.Reads.list/2`, the API's defaults and its newest
  prompt version), in its order: the title, the source's domain and tier,
  the time and the label, an outside model's reading marked „machine-made“
  with its event type in words (`PortfolixirWeb.EventTypeLabel`). A story
  already in the research log reads „kept“.

  **„Ins Research-Log“ is the agent's promotion as a form** (ADR-0056 §8,
  A2; NFR-10): it opens with what `notes.append` with a `cluster_id` would
  pre-fill (`Portfolixir.News.story_proposal/2`) and writes nothing; only
  its save writes, through `Portfolixir.News.append_note_from_story/3`,
  the function that call uses. The operator may change the kind, the
  headline, the event type and the tone, as the agent may; the date, the
  source link and the source quality are the story's and are shown, not
  offered. A field left as proposed is not sent, so the server pre-fills
  it as it would for the agent and keeps the label's id as provenance.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Input.Text
  alias Portfolixir.Knowledge.SecurityNote
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.EventTypeLabel
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.StoredText

  @kinds ~w(evidence event_result)

  attr(:rows, :list, required: true, doc: "news.list's story rows, fields=std")
  attr(:truncated, :boolean, default: false)
  attr(:block, :map, required: true, doc: "the dossier's news block")
  attr(:promotion, :map, default: nil, doc: "the open form: story, proposal, values, errors")

  @doc "The tab's panel."
  def panel(assigns) do
    ~H"""
    <section
      id="detail-tab-panel-news"
      role="tabpanel"
      aria-labelledby="detail-tab-news"
      class="detail-tab-panel detail-tab-panel--news"
    >
      <div class="detail-tab-hint" data-role="stories-basis">
        <%= gettext("The stories of this security the news layer keeps, newest first, as the agent reads them.") %>
        <AppShell.section_info>
          <:line>
            <%= gettext(
              "A label is an outside model's reading, marked „machine-made“; it moves and writes nothing."
            ) %>
          </:line>
          <:line>
            <%= gettext(
              "„To the research log“ opens the entry form pre-filled from the story, as the agent's notes.append with the story fills it: the headline from its title, the event type and the tone from its label, the date and the source from its best source. Only saving writes the entry."
            ) %>
          </:line>
          <:line>
            <%= gettext("Only an entry with a headline is drawn on the chart; a story never is.") %>
          </:line>
        </AppShell.section_info>
      </div>

      <div class="news-health" data-role="stories-week">
        <span class="badge badge--neutral" data-role="stories-week-count">
          <%= ngettext(
            "7 days: %{count} story · %{primary} primary",
            "7 days: %{count} stories · %{primary} primary",
            @block.count_7d,
            primary: @block.primary_7d
          ) %>
        </span>
        <span :if={@block.max_materiality} class="badge badge--neutral" data-role="stories-week-materiality">
          <%= gettext("highest materiality %{value}", value: @block.max_materiality) %>
        </span>
      </div>

      <.promotion_form :if={@promotion} promotion={@promotion} />

      <%= if @rows == [] do %>
        <p id="security-stories-empty" class="detail-tab-empty" role="status">
          <%= gettext("No story of this security has come in. Feeds are registered over the API or MCP.") %>
        </p>
      <% else %>
        <div id="security-stories-table-wrap" class="data-table-wrapper news-table-wrap">
          <table id="security-stories-table" class="data-table news-table">
            <thead>
              <tr>
                <th><%= gettext("Story") %></th>
                <th><%= gettext("Source") %></th>
                <th><%= gettext("Time") %></th>
                <th><%= gettext("Label") %></th>
                <th><span class="visually-hidden"><%= gettext("Research log") %></span></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @rows} data-story={row.id}>
                <td class="news-cell-title">
                  <span class="news-title" data-role="story-title"><%= foreign(row.title) %></span>
                  <span :if={row.count > 1} class="news-sub" data-role="story-count">
                    <%= ngettext("%{count} source to the same story", "%{count} sources to the same story", row.count) %>
                  </span>
                </td>
                <td data-role="story-source" class="news-cell-source">
                  <%= foreign(row.domain) %> <.tier tier={row.tier} />
                </td>
                <td data-role="story-time" class="news-cell-time"><%= time(row.at) %></td>
                <td data-role="story-label"><.label row={row} /></td>
                <td><.keep row={row} /></td>
              </tr>
            </tbody>
          </table>
        </div>
        <ul id="security-stories-phone-rows" class="phone-rows news-rows" aria-label={gettext("Stories")}>
          <li :for={row <- @rows} class="phone-row" data-story={row.id}>
            <div class="phone-row__body">
              <span class="phone-row__name"><%= foreign(row.title) %></span>
              <span class="phone-row__ids">
                <%= foreign(row.domain) %> <.tier tier={row.tier} /> · <%= time(row.at) %>
              </span>
              <span class="phone-row__ids"><.label row={row} /></span>
              <.keep row={row} id_prefix="phone-" />
            </div>
          </li>
        </ul>
        <p :if={@truncated} class="hint" data-role="stories-truncated">
          <%= gettext("The newest 20 stories; the agent reads the rest with the cursor.") %>
        </p>
      <% end %>
    </section>
    """
  end

  attr(:row, :map, required: true)
  attr(:id_prefix, :string, default: "")

  # A story in the log reads „kept“ (its notes, §8); else the form's button.
  defp keep(assigns) do
    ~H"""
    <%= if @row.note_ids != [] do %>
      <span class="badge badge--neutral story-keep" data-role="story-kept" title={notes_title(@row.note_ids)}>
        <%= pgettext("news story", "kept") %>
      </span>
    <% else %>
      <button
        type="button"
        class="button-ghost story-keep"
        phx-click="open_promotion"
        phx-value-story={@row.id}
        id={"#{@id_prefix}open-promotion-#{@row.id}"}
      >
        <%= gettext("To the research log") %>
      </button>
    <% end %>
    """
  end

  attr(:row, :map, required: true)

  # §7: the label's event type in words and its materiality, machine-made.
  defp label(assigns) do
    ~H"""
    <%= if @row.materiality do %>
      <span class="news-label">
        <%= if @row.event_type, do: EventTypeLabel.event_type(@row.event_type) %> · <%= gettext("materiality %{value}", value: @row.materiality) %>
        <span class="badge badge--neutral"><%= gettext("machine-made") %></span>
      </span>
    <% else %>
      <span class="news-label news-label--none"><%= gettext("no label") %></span>
    <% end %>
    """
  end

  attr(:tier, :atom, required: true)

  defp tier(assigns) do
    ~H"""
    <span class={["badge", @tier != :primary && "badge--neutral"]}><%= @tier %></span>
    """
  end

  attr(:promotion, :map, required: true)

  # The note form, pre-filled from the story (ADR-0056 §8, A2): kind,
  # headline, event type and tone the operator may change; the date, the
  # link and the quality the story's. Only its submit writes.
  defp promotion_form(assigns) do
    values = assigns.promotion.values
    errors = assigns.promotion.errors

    assigns =
      assign(assigns,
        proposal: assigns.promotion.proposal,
        values: values,
        errors: errors,
        kinds: @kinds,
        event_types: SecurityNote.event_types()
      )

    ~H"""
    <form
      id="story-promotion-form"
      class="research-entry-form story-promotion-form"
      phx-submit="save_promotion"
      aria-labelledby="story-promotion-title"
    >
      <h3 id="story-promotion-title" tabindex="-1">
        <%= gettext("To the research log") %>
      </h3>
      <p class="hint" data-role="promotion-story">
        <%= StoredText.isolate(
          gettext("From the story „%{title}“: nothing is written until the entry is saved.",
            title: StoredText.slot(:title)
          ),
          title: Text.escape_invisible(@promotion.title)
        ) %>
      </p>
      <div class="research-entry-form__grid">
        <label>
          <span><%= gettext("Kind") %></span>
          <select name="promotion[kind]">
            <option :for={kind <- @kinds} value={kind} selected={@values["kind"] == kind}>
              <%= kind_label(kind) %>
            </option>
          </select>
        </label>
        <label>
          <span><%= gettext("Event type") %></span>
          <select name="promotion[event_type]">
            <option value="" selected={@values["event_type"] in [nil, ""]}><%= gettext("— not stated —") %></option>
            <option :for={type <- @event_types} value={type} selected={@values["event_type"] == type}>
              <%= EventTypeLabel.event_type(type) %>
            </option>
          </select>
        </label>
        <label>
          <span><%= gettext("Tone") %></span>
          <select name="promotion[tone]">
            <option value="" selected={@values["tone"] in [nil, ""]}><%= gettext("— not stated —") %></option>
            <option :for={tone <- [1, 0, -1]} value={tone} selected={@values["tone"] == to_string(tone)}>
              <%= EventTypeLabel.tone(tone) %>
            </option>
          </select>
        </label>
        <label class="research-entry-form__full">
          <span><%= gettext("Headline") %></span>
          <input
            type="text"
            name="promotion[headline]"
            value={@values["headline"]}
            aria-invalid={if @errors["headline"], do: "true"}
            aria-describedby={if @errors["headline"], do: "promotion-error-headline"}
          />
        </label>
        <p
          :if={@errors["headline"]}
          id="promotion-error-headline"
          class="field-error research-entry-form__full"
          data-role="promotion-error-headline"
          role="alert"
        >
          <%= Enum.join(@errors["headline"], "; ") %>
        </p>
        <AppShell.invisible_text_note texts={[@values["headline"]]}>
          <%= gettext("The headline must be written anew: the entry refuses invisible characters.") %>
        </AppShell.invisible_text_note>
        <label class="research-entry-form__full">
          <span><%= gettext("Entry") %></span>
          <textarea name="promotion[body]" rows="3" required><%= @values["body"] %></textarea>
        </label>
        <p
          :if={@errors["body"]}
          class="field-error research-entry-form__full"
          data-role="promotion-error-body"
          role="alert"
        >
          <%= Enum.join(@errors["body"], "; ") %>
        </p>
      </div>
      <dl class="research-entry__facts story-promotion-form__facts">
        <div>
          <dt><%= gettext("As of") %></dt>
          <dd data-role="promotion-as-of"><%= Format.date(@proposal["as_of"]) %></dd>
        </div>
        <div>
          <dt><%= gettext("Source quality") %></dt>
          <dd data-role="promotion-quality"><%= @promotion.quality_label %></dd>
        </div>
        <div class="story-promotion-form__source">
          <dt><%= gettext("Source link") %></dt>
          <dd data-role="promotion-source">
            <a href={@proposal["source_url"]} rel="noopener noreferrer" target="_blank">
              <%= foreign(@proposal["source_url"]) %>
            </a>
          </dd>
        </div>
      </dl>
      <p class="hint"><%= gettext("The date, the source link and the source quality are the story's.") %></p>
      <ul :if={@errors["other"]} class="research-entry-form__errors" role="alert">
        <li :for={error <- @errors["other"]}><%= error %></li>
      </ul>
      <div class="story-promotion-form__actions">
        <button type="submit" class="button"><%= gettext("Save to the research log") %></button>
        <button type="button" id="story-promotion-cancel" class="button-ghost" phx-click="close_promotion">
          <%= gettext("Cancel") %>
        </button>
      </div>
    </form>
    """
  end

  defp kind_label("evidence"), do: gettext("Evidence")
  defp kind_label("event_result"), do: gettext("Event result")

  defp notes_title(ids), do: Enum.map_join(ids, ", ", &"##{&1}")

  # Foreign text as stored, its invisible characters spelled (ADR-0054 §4).
  defp foreign(nil), do: ""
  defp foreign(text), do: StoredText.bdi(Text.escape_invisible(text))

  # A time to the minute in UTC, its date in the page's notation, as the
  # news page writes it.
  defp time(nil), do: "—"

  defp time(%DateTime{} = at) do
    utc = DateTime.shift_zone!(at, "Etc/UTC")
    Format.date(DateTime.to_date(utc)) <> " " <> Calendar.strftime(utc, "%H:%M")
  end
end
