defmodule PortfolixirWeb.ControlBar do
  @moduledoc """
  The one bar of labelled controls (issue 1435, Sprint 29 L1; DESIGN.md,
  amendment of 2026-11-08 "Labelled controls start on one edge", and the
  anatomy of the control bar; board
  `ux-design-2026-11-12-sprint29/06-control-bar`, inventory §2).

  A *labelled* control is a segmented control, a select, a chip family or a
  field with a visible label beside it. Every bar of them is this component,
  never a wrapping row of label and control pairs, which puts each control
  right after its own label, so controls under one another sit offset by
  the difference of their labels. The bar has three layouts, switched by a
  container query on the bar, so the sidebar's width never decides:

    * **one line** while every group fits: each label, then its control;
    * **A, the label column**, once the bar is at most its `fold` wide: a
      two-column grid, the labels in a column as wide as the longest one,
      every control from the second column's edge at its own width;
    * **B, labels above**, the floor, once the bar is at most its `floor`
      wide: every label above its control, all at the bar's left edge.
      Where the fold and the floor both apply, B wins.

  `fold` and `floor` are named widths, each a class with its own container
  query in `app.css` (a container query cannot read a variable): `fold`
  560, 760 (the default, the stacked chart's) or 960 px, or `:always` for a
  bar whose groups never fit one line (the chip rows); `floor` 330 (the
  default) or 560 px, or `:always` for a bar whose labels always stand
  above. A new width is one more class and one more rule there.

  Each `:group` is a label and **one** control element, the slot's content
  (a field with its button, or a chip family, is one element around them;
  a chip family's chips wrap inside the control column, never under the
  label). The label is the control's label: with `for` it is a
  `<label for>`, for a select or a field; without, a `span` whose
  `label_id` the control names in its `aria-labelledby` (a segmented
  control, a chip family). `form` makes the group a form with those
  attributes (an id, `phx-change`), so a select's change reaches the
  LiveView with its label inside the form. A group without `label` keeps its
  control in the control column (a checkbox that carries its own label).

  The `:head` is a line above the controls, outside them (the stacked
  chart's breadcrumb); its element takes the line itself.
  """
  use Phoenix.Component

  @folds [560, 760, 960, :always]
  @floors [330, 560, :always]

  attr(:fold, :any, default: 760, doc: "560, 760, 960 or :always: where the label column starts")
  attr(:floor, :any, default: 330, doc: "330, 560 or :always: where every label moves above")
  attr(:class, :any, default: nil)
  attr(:rest, :global)

  slot(:head, doc: "a line above the controls, such as a breadcrumb")

  slot :group, doc: "a label and one control element" do
    attr(:label, :string, doc: "the visible label; none keeps the control in the control column")
    attr(:label_id, :string, doc: "the label's id, named by the control's aria-labelledby")
    attr(:for, :string, doc: "the id of the select or field the label is for")
    attr(:form, :list, doc: "the group as a form with these attributes (id, phx-change)")
  end

  def bar(assigns) do
    fold = width!(assigns.fold, @folds, :fold)
    floor = width!(assigns.floor, @floors, :floor)

    assigns =
      assign(assigns, :classes, [
        "control-bar",
        "control-bar--fold-#{fold}",
        "control-bar--floor-#{floor}",
        assigns.class
      ])

    ~H"""
    <div class={@classes} {@rest}>
      <%= render_slot(@head) %>
      <div class="control-bar__controls">
        <.group :for={group <- @group} group={group} />
      </div>
    </div>
    """
  end

  attr(:group, :map, required: true)

  defp group(%{group: %{form: form}} = assigns) when is_list(form) do
    assigns = assign(assigns, :form, form)

    ~H"""
    <form class={["control-bar__group", bare?(@group) && "control-bar__group--bare"]} {@form}>
      <.label group={@group} /><%= render_slot(@group) %>
    </form>
    """
  end

  defp group(assigns) do
    ~H"""
    <span class={["control-bar__group", bare?(@group) && "control-bar__group--bare"]}>
      <.label group={@group} /><%= render_slot(@group) %>
    </span>
    """
  end

  attr(:group, :map, required: true)

  defp label(%{group: %{label: label}} = assigns) when is_binary(label) do
    assigns = assign(assigns, label: label, id: assigns.group[:label_id])

    ~H"""
    <%= if @group[:for] do %>
      <label class="control-bar__label" for={@group[:for]} id={@id}><%= @label %></label>
    <% else %>
      <span class="control-bar__label" id={@id}><%= @label %></span>
    <% end %>
    """
  end

  defp label(assigns), do: ~H""

  defp bare?(group), do: not is_binary(group[:label])

  defp width!(width, widths, name) do
    if width in widths do
      width
    else
      raise ArgumentError,
            "ControlBar.bar/1: #{name} must be one of #{inspect(widths)}, got: #{inspect(width)}"
    end
  end
end
