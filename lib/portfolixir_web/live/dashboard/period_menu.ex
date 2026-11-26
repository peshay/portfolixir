defmodule PortfolixirWeb.Dashboard.PeriodMenu do
  @moduledoc """
  The dashboard's top bar for the period and its menu (ADR-0062's amendment
  of 2026-11-25, point 6; board `ux-design-2026-11-25-sprint32/04` ① and
  ②; plan D-5; Sprint 32 T4).

    * **The bar** (`bar/1`): the operator's quick choice as chips
      (`Portfolixir.Periods.quick_choice/0`), then one button that opens the
      menu. It names the active period where the quick choice does not hold
      it („3M ▾“) and an own period always („Seit Umschichtung ▾“), else
      „Zeitraum ▾“; beside an own period's name stand its dates, from its
      first day to its last or to today, so it
      is never unclear what a name spans. The chips keep the compact class's
      strip that scrolls sideways (Sprint 31).
    * **The menu**: four groups, each a group named by its heading —
      rolling (1T to Max), calendar (lfd. Monat to Vorjahr; a quarter not
      yet begun is drawn and cannot be chosen), own (the stored periods,
      each with its dates and ⋯ to change or delete it, and „Eigenen
      Zeitraum anlegen …“), year (this year and the five before). Each
      option has ★ beside it, pressed while the quick choice holds it, that
      adds it or takes it out; a footnote under the groups says so (the S32
      closing act). Escape, a pick and a click elsewhere close it; in the
      compact class it is a sheet from the bottom edge, standing on the tab
      bar.
    * **A widget's pin** (Sprint 32 T5; board 04 ③): its ⋯ „Zeitraum
      festpinnen …“ opens the same menu for that widget, said in its first
      line; a pick there is the widget's pin, an own period by reference
      (`saved:<id>`). It lies over the page, not under the bar.
    * **The dialog** (`dialog/1`): a native dialog element (the
      ModalDialog hook) with Name, Von, Bis „heute“ or a date, „in der Schnellwahl
      zeigen“; „Speichern und anwenden“ stores and applies it.

  The page (`PortfolixirWeb.DashboardLive`) owns the events; this module only
  draws.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Clock
  alias Portfolixir.Periods
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.DateInput
  alias PortfolixirWeb.FieldLabel
  alias PortfolixirWeb.Format

  # The years the menu offers: this one and the five before.
  @years 6

  attr(:period, :string, required: true, doc: "the active period's key")
  attr(:quick, :map, required: true, doc: "`Portfolixir.Periods.quick_choice/0`")
  attr(:saved, :list, required: true, doc: "the stored periods")
  attr(:open, :boolean, default: false)
  attr(:say, :string, default: nil)

  attr(:pin, :map,
    default: nil,
    doc: "the widget the menu pins for (Sprint 32 T5): %{index, kind, title, period}, or nil"
  )

  @doc "The quick choice, the menu's button with its dates, the menu and the status line."
  def bar(assigns) do
    today = Clock.today()
    quick = Enum.filter(assigns.quick.keys, &resolves?(&1, today, assigns.saved))
    in_quick? = assigns.period in quick
    own? = Periods.saved_id(assigns.period) != :error

    assigns =
      assign(assigns,
        today: today,
        chips: quick,
        in_quick?: in_quick? and not own?,
        button_label:
          if(in_quick? and not own?,
            do: gettext("Period"),
            else: Widget.period_label(assigns.period, assigns.saved)
          ),
        dates: own_dates(assigns.period, assigns.saved, today)
      )

    ~H"""
    <%!-- The compact strip scrolls a chip the keyboard focuses whole
         into view (Sprint 31 closing act, Y4). --%>
    <div
      id="dashboard-period-strip"
      class="dashboard-period"
      data-role="dashboard-period-strip"
      phx-hook="ScrollFocused"
    >
      <div
        class="segmented-control dashboard-period__control"
        data-role="dashboard-period"
        role="group"
        aria-label={gettext("Quick choice")}
      >
        <button
          :for={key <- @chips}
          type="button"
          class={["segmented-control__option", @period == key && "is-active"]}
          phx-click="set_period"
          phx-value-period={key}
          aria-pressed={to_string(@period == key)}
          data-period={key}
        >
          <%= Widget.period_label(key, @saved) %>
        </button>
      </div>
    </div>
    <div class="dashboard-period-menu" data-role="period-menu-root" data-active-period={@period}>
      <button
        id="dashboard-period-menu-toggle"
        type="button"
        class={["dashboard-period-menu__toggle", not @in_quick? && "is-active"]}
        phx-click="period_menu"
        phx-value-open={to_string(not @open)}
        aria-expanded={to_string(@open)}
        aria-controls="dashboard-period-menu"
        aria-haspopup="true"
        aria-label={gettext("Period: %{period}", period: Widget.period_label(@period, @saved))}
        data-role="period-menu-toggle"
      >
        <span data-role="period-menu-label"><%= @button_label %></span>
        <span aria-hidden="true">▾</span>
      </button>
      <span :if={@dates} class="dashboard-period-menu__dates" data-role="period-dates"><%= @dates %></span>
      <.panel
        :if={@open}
        period={if @pin, do: @pin.period, else: @period}
        quick={@quick}
        saved={@saved}
        today={@today}
        pin={@pin}
      />
      <%!-- What a star, a save or a delete did, heard where it was
           done; no whitespace inside, so `:empty` holds. --%>
      <p
        id="dashboard-period-status"
        class="dashboard-period-menu__say"
        role="status"
        aria-live="polite"
        data-role="period-say"
      ><%= @say %></p>
    </div>
    """
  end

  attr(:period, :string, default: nil)
  attr(:quick, :map, required: true)
  attr(:saved, :list, required: true)
  attr(:today, Date, required: true)
  attr(:pin, :map, default: nil)

  defp panel(assigns) do
    year = assigns.today.year

    assigns =
      assign(assigns,
        years: Enum.map(0..(@years - 1), &"year:#{year - &1}"),
        this_quarter: "q#{div(assigns.today.month - 1, 3) + 1}",
        dropped: length(assigns.quick.dropped)
      )

    ~H"""
    <div
      id="dashboard-period-menu"
      class={["dashboard-period-menu__panel", @pin && "is-pin"]}
      data-role="period-menu"
      data-pin-kind={@pin && @pin.kind}
      tabindex="-1"
      aria-label={@pin && gettext("Pin a period for “%{widget}”", widget: @pin.title)}
      phx-click-away="period_menu"
      phx-value-open="false"
      phx-window-keydown="period_menu_key"
      phx-key="Escape"
    >
      <%!-- Sprint 32 T5 (board 04 ③): opened from a widget's ⋯, a pick
           is that widget's pin. --%>
      <p :if={@pin} class="dashboard-period-menu__pin" data-role="period-pin-head">
        <%= gettext("Pin a period for “%{widget}”", widget: @pin.title) %>
      </p>
      <p :if={@dropped > 0} class="dashboard-period-menu__note" data-role="period-quick-dropped">
        <%= ngettext(
          "An own period of the quick choice was deleted; it is no longer in the bar.",
          "%{count} own periods of the quick choice were deleted; they are no longer in the bar.",
          @dropped
        ) %>
      </p>
      <.group id="period-group-rolling" title={pgettext("period menu", "Rolling · to today")}>
        <.option
          :for={key <- Periods.rolling()}
          pin={@pin}
          key={key}
          active={@period == key}
          begun={begun?(key, @today, @saved)}
          quick={@quick}
          saved={@saved}
        />
      </.group>
      <.group id="period-group-calendar" title={pgettext("period menu", "Calendar")}>
        <.option
          :for={key <- Periods.calendar()}
          pin={@pin}
          key={key}
          active={@period == key}
          begun={begun?(key, @today, @saved)}
          quick={@quick}
          saved={@saved}
        />
      </.group>
      <.group id="period-group-own" title={pgettext("period menu", "Own · stored")} list>
        <div :for={own <- @saved} class="dashboard-period-menu__own" data-role="period-own">
          <.star key={"saved:#{own.id}"} label={own.name} quick={@quick} />
          <button
            type="button"
            class={["dashboard-period-menu__own-name", @period == "saved:#{own.id}" && "is-active"]}
            phx-click={if @pin, do: "pin_period", else: "set_period"}
            phx-value-index={@pin && @pin.index}
            phx-value-period={"saved:#{own.id}"}
            aria-pressed={to_string(@period == "saved:#{own.id}")}
            data-role="period-option"
            data-period={"saved:#{own.id}"}
          ><%= own.name %></button>
          <span class="dashboard-period-menu__own-dates"><%= own_span(own) %></span>
          <button
            type="button"
            class="dashboard-period-menu__edit"
            phx-click="period_dialog"
            phx-value-id={own.id}
            aria-label={gettext("Change or delete “%{name}”", name: own.name)}
            title={gettext("Change or delete “%{name}”", name: own.name)}
            data-role="period-edit"
            data-period={"saved:#{own.id}"}
          ><span aria-hidden="true">⋯</span></button>
        </div>
        <button
          :if={length(@saved) < Periods.max_saved()}
          type="button"
          id="dashboard-period-add"
          class="dashboard-period-menu__add"
          phx-click="period_dialog"
          phx-value-id=""
          data-role="period-add"
        >＋ <%= gettext("Create own period …") %></button>
      </.group>
      <.group id="period-group-year" title={pgettext("period menu", "Year")}>
        <.option
          :for={key <- @years}
          pin={@pin}
          key={key}
          active={@period == key}
          begun={begun?(key, @today, @saved)}
          quick={@quick}
          saved={@saved}
        />
      </.group>
      <%!-- The S32 closing act (board 04 ②): what ★ means, why a
           quarter is dashed, why this quarter stands twice. --%>
      <p class="dashboard-period-menu__foot" data-role="period-menu-note">
        <%= gettext(
          "★ = in the bar as a quick choice; a click on the star puts a period in or takes it out. A quarter not yet begun is drawn dashed and cannot be chosen. “%{current}” and “%{quarter}” are the same quarter today; both stand here because the one moves on and the other stays.",
          current: Widget.period_label("qtd", @saved),
          quarter: Widget.period_label(@this_quarter, @saved)
        ) %>
      </p>
    </div>
    """
  end

  # Whether a key resolves today: a quarter or a year not yet begun is
  # drawn and cannot be chosen.
  defp begun?(key, today, saved), do: match?({:ok, _term}, Periods.resolve(key, today, saved))

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:list, :boolean, default: false)
  slot(:inner_block, required: true)

  defp group(assigns) do
    ~H"""
    <section class="dashboard-period-menu__group">
      <h3 id={@id} class="dashboard-period-menu__head"><%= @title %></h3>
      <div
        class={[
          if(@list, do: "dashboard-period-menu__list", else: "dashboard-period-menu__options")
        ]}
        role="group"
        aria-labelledby={@id}
      >
        <%= render_slot(@inner_block) %>
      </div>
    </section>
    """
  end

  attr(:key, :string, required: true)
  attr(:active, :boolean, required: true)
  attr(:begun, :boolean, required: true)
  attr(:quick, :map, required: true)
  attr(:saved, :list, required: true)
  attr(:pin, :map, default: nil)

  defp option(assigns) do
    assigns = assign(assigns, :label, Widget.period_label(assigns.key, assigns.saved))

    ~H"""
    <span class={["dashboard-period-menu__option", not @begun && "is-off"]}>
      <button
        type="button"
        class={["dashboard-period-menu__pick", @active && "is-active"]}
        phx-click={if @pin, do: "pin_period", else: "set_period"}
        phx-value-index={@pin && @pin.index}
        phx-value-period={@key}
        aria-pressed={to_string(@active)}
        disabled={not @begun}
        title={if not @begun, do: gettext("Not yet begun")}
        data-role="period-option"
        data-period={@key}
      ><%= @label %></button>
      <.star :if={@begun} key={@key} label={@label} quick={@quick} />
    </span>
    """
  end

  attr(:key, :string, required: true)
  attr(:label, :string, required: true)
  attr(:quick, :map, required: true)

  defp star(assigns) do
    assigns = assign(assigns, :on, assigns.key in assigns.quick.keys)

    ~H"""
    <button
      type="button"
      class={["dashboard-period-menu__star", @on && "is-on"]}
      phx-click="quick_toggle"
      phx-value-period={@key}
      aria-pressed={to_string(@on)}
      aria-label={gettext("Quick choice: %{period}", period: @label)}
      title={gettext("Quick choice: %{period}", period: @label)}
      data-role="period-star"
      data-period={@key}
    ><span aria-hidden="true"><%= if @on, do: "★", else: "☆" %></span></button>
    """
  end

  attr(:dialog, :map, required: true, doc: "%{id, name, from, to_mode, to, quick, errors}")

  @doc """
  „Eigener Zeitraum“: a native dialog opened by the ModalDialog hook, to
  make an own period or change or delete one (board 04 ②).
  """
  def dialog(assigns) do
    ~H"""
    <dialog
      id="period-dialog"
      class="modal period-dialog"
      phx-hook="ModalDialog"
      data-close-event="period_dialog_close"
      aria-labelledby="period-dialog-title"
    >
      <header class="modal-head">
        <h2 id="period-dialog-title"><%= gettext("Own period") %></h2>
        <button
          type="button"
          class="icon-button"
          aria-label={gettext("Close")}
          phx-click="period_dialog_close"
        >
          <span aria-hidden="true">×</span>
        </button>
      </header>
      <form id="period-form" phx-submit="period_save">
        <div class="modal-body">
          <div class="form-grid">
            <label>
              <span><%= gettext("Name") %></span>
              <input
                type="text"
                name="period[name]"
                value={@dialog.name}
                maxlength={Periods.name_max()}
                autocomplete="off"
                required
              />
              <.field_error dialog={@dialog} field={:name} />
            </label>
            <label>
              <span><%= gettext("From") %></span>
              <input
                type="text"
                name="period[from]"
                value={@dialog.from}
                placeholder={DateInput.placeholder()}
                pattern={DateInput.pattern()}
                maxlength="10"
                autocomplete="off"
                required
              />
              <.field_error dialog={@dialog} field={:from} />
            </label>
            <fieldset class="period-dialog__to">
              <legend><%= gettext("To") %></legend>
              <label class="period-dialog__choice">
                <input type="radio" name="period[to_mode]" value="today" checked={@dialog.to_mode != "date"} />
                <%= gettext("today") %>
              </label>
              <label class="period-dialog__choice">
                <input type="radio" name="period[to_mode]" value="date" checked={@dialog.to_mode == "date"} />
                <%= gettext("Date") %>
              </label>
              <input
                type="text"
                name="period[to]"
                value={@dialog.to}
                placeholder={DateInput.placeholder()}
                pattern={DateInput.pattern()}
                maxlength="10"
                autocomplete="off"
                aria-label={gettext("Last day")}
              />
              <.field_error dialog={@dialog} field={:to} />
            </fieldset>
            <label class="period-dialog__choice">
              <input type="hidden" name="period[quick]" value="false" />
              <input type="checkbox" name="period[quick]" value="true" checked={@dialog.quick} />
              <%= gettext("Show in the quick choice") %>
            </label>
          </div>
          <p class="hint">
            <%= gettext("“until today” grows by a day every day; a fixed end stays. Stored for every device and recorded in the audit journal.") %>
          </p>
          <p :if={@dialog.alert} class="alert-error" role="alert"><%= @dialog.alert %></p>
        </div>
        <div class="modal-footer">
          <button
            :if={@dialog.id}
            type="button"
            class="button-ghost"
            phx-click="period_delete"
            phx-value-id={@dialog.id}
            data-confirm={gettext("Delete this own period? Widgets pinned to it then follow the dashboard's period.")}
            data-role="period-delete"
          >
            <%= gettext("Delete") %>
          </button>
          <span class="modal-footer__spacer"></span>
          <button type="button" class="button-ghost" phx-click="period_dialog_close">
            <%= gettext("Cancel") %>
          </button>
          <button type="submit" class="button-primary" data-role="period-save">
            <%= gettext("Save and apply") %>
          </button>
        </div>
      </form>
    </dialog>
    """
  end

  attr(:dialog, :map, required: true)
  attr(:field, :atom, required: true)

  defp field_error(assigns) do
    assigns = assign(assigns, :message, Map.get(assigns.dialog.errors, assigns.field))

    ~H"""
    <span :if={@message} class="field-error" data-role="period-field-error" data-field={@field}><%= @message %></span>
    """
  end

  @doc "The field errors of a refused write, each in the page's language."
  @spec errors(Ecto.Changeset.t()) :: %{atom() => String.t()}
  def errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&FieldLabel.translate_error/1)
    |> Map.new(fn {field, [message | _]} -> {field, message} end)
  end

  # An own period's span as the menu lists it: its first day to its last,
  # or to „heute“.
  defp own_span(%{from: from, to: nil}), do: Format.date(from) <> " – " <> gettext("today")
  defp own_span(%{from: from, to: to}), do: Format.date(from) <> " – " <> Format.date(to)

  # The dates beside the button while an own period is active: its first
  # day to its last, or to today's date.
  defp own_dates(period, saved, today) do
    with {:ok, id} <- Periods.saved_id(period),
         %{from: from, to: to} <- Enum.find(saved, &(&1.id == id)) do
      Format.date(from) <> " – " <> Format.date(to || today)
    else
      _none -> nil
    end
  end

  defp resolves?(key, today, saved), do: begun?(key, today, saved)
end
