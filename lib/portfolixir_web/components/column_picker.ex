defmodule PortfolixirWeb.ColumnPicker do
  @moduledoc """
  The one column picker (#850; DESIGN.md → Inventory → Overlays, pick E3 of
  board `ux-design-2026-09-20/03-column-picker`): a `.popover.column-picker`
  with `role="dialog"`, a `.popover-head` heading and the columns grouped in
  `<fieldset>`/`<legend>` — at fourteen columns a flat list is a search task,
  and the grouping is the difference that matters.

  It began as the securities list's own component; the transaction history
  and Wealth Positions built theirs on a `<details>` with a flat list, which
  the spec recorded as drift. All three render this one now.

  Stateless: the owning LiveView holds whether it is open, renders the toggle
  (`toggle/1`) and receives the form's `on_change` event with the raw
  `columns[]` strings, which it validates against its own registry — no atom
  is minted from them here. The close button and Escape send `on_close` and
  return the focus to the toggle named by `toggle_id`.
  """

  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Phoenix.LiveView.JS

  alias PortfolixirWeb.AppShell

  attr(:id, :string, required: true)
  attr(:form_id, :string, required: true)
  attr(:on_change, :string, required: true)
  attr(:on_close, :string, required: true)

  attr(:toggle_id, :string,
    required: true,
    doc: "the toggle that opened the picker; closing hands the focus back to it"
  )

  attr(:groups, :list,
    required: true,
    doc: "`[{legend, [{value, label}]}]` in display order; an empty group is skipped"
  )

  attr(:selected, :list, required: true, doc: "the checked values, as strings")

  def picker(assigns) do
    ~H"""
    <div
      id={@id}
      class="popover column-picker"
      role="dialog"
      aria-label={gettext("Choose columns")}
      phx-window-keydown={close(@on_close, @toggle_id)}
      phx-key="Escape"
    >
      <div class="popover-head">
        <h3><%= gettext("Columns") %></h3>
        <button
          type="button"
          class="icon-button"
          data-role="column-picker-close"
          phx-click={close(@on_close, @toggle_id)}
          aria-label={gettext("Close")}
        >
          <AppShell.icon name={:x} size={14} />
        </button>
      </div>
      <form id={@form_id} phx-change={@on_change}>
        <fieldset :for={{legend, options} <- @groups} :if={options != []} class="column-group">
          <legend><%= legend %></legend>
          <label :for={{value, label} <- options} class="checkbox-row">
            <input type="checkbox" name="columns[]" value={value} checked={value in @selected} />
            <span><%= label %></span>
          </label>
        </fieldset>
        <%!-- Hidden sentinel: the form always sends a (possibly empty) list
             for "columns[]", even when every box is unchecked. --%>
        <input type="hidden" name="columns[]" value="" />
      </form>
    </div>
    """
  end

  # Closing removes the focused control with the popover; without a target the
  # focus falls to the page body (closing act, F31), so it goes back to the
  # toggle that opened it.
  defp close(event, toggle_id), do: event |> JS.push() |> JS.focus(to: "#" <> toggle_id)

  @doc """
  The labelled toggle for a picker at the head of a section or a table: the
  icon and the word, `aria-expanded` reporting the popover's state.
  """
  attr(:id, :string, required: true)
  attr(:open, :boolean, required: true)
  attr(:on_toggle, :string, required: true)

  def toggle(assigns) do
    ~H"""
    <button
      type="button"
      id={@id}
      class={["button-ghost", "column-picker-toggle", @open && "is-active"]}
      phx-click={@on_toggle}
      aria-haspopup="dialog"
      aria-expanded={to_string(@open)}
    >
      <AppShell.icon name={:columns} size={14} />
      <%= gettext("Columns") %>
    </button>
    """
  end
end
