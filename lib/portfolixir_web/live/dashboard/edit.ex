defmodule PortfolixirWeb.Dashboard.Edit do
  @moduledoc """
  The dashboard's edit mode, held in the page (ADR-0062 §2, §7; idea board
  `ux-design-2026-11-21-idea-i56` 03, its edit-mode frame; Sprint 31 D6).

  An edit is the layout being edited, on the server, beside the stored
  dashboard it will replace (its name and the lock_version the page read)
  and the layout as read. Each step builds the next layout — a move, a
  drop, a resize and an add through the context's arrangement
  (`Portfolixir.Dashboards.arrange_layout/2`; ADR-0062's amendment of
  2026-11-25, point 1: the others make room, then the gaps close) — and
  validates it with `Portfolixir.Dashboards.validate_layout/2`; a step
  that is refused is not applied, and the step answers the sentence a
  screen reader says instead. Nothing here writes: the page saves the edit
  once, on „Fertig“, as one replace
  (`Portfolixir.Dashboards.replace_dashboard/3`), so a drag is not a
  journal entry.

  Each applied step keeps the edit before it (`previous`), so „Rückgängig“
  and Ctrl+Z take back that one step (`undo/1`), and the keys of the
  widgets it moved (`moved`), which the page marks until the next step
  (Sprint 32 E2; planning board `ux-design-2026-11-25-sprint32/01` ③).

  Every item carries a **key**, a whole number that stays with it for the
  whole edit, so the handle a keyboard is on keeps its id while its widget
  moves through the reading order, and an event names an item that a
  removal did not shift. The keys are the page's, never stored.

  The steps:

    * **move** one grid step (column ±1, row ±1; the arrow keys on the
      handle) and **place** at a column and row (a drag on the wide grid):
      the widget lands there and what it covers makes room; only a place
      off the grid is refused;
    * **resize** to a grid size its kind takes (`full` is a page, never a
      choice); a size that would leave the grid at the item's column moves
      it left as far as it needs, and what it covers makes room;
    * **remove**, after which the gaps close; **add** a kind from the
      catalogue in its first grid size (the registry lists a kind's sizes
      smallest first) at the first free place, row by row, column by
      column (`Portfolixir.Dashboards.Layout.first_free/2`, as „Alle
      Widgets“ adds one); the 41st widget and a grid with no place up to
      row 200 are refused;
    * **reorder** up or down in reading order (the compact class, ADR-0062
      §7: no placement on a grid the window does not show). The mapping
      back onto the grid is deterministic: the item **swaps places** with
      its neighbour in reading order (each takes the other's column and
      row), which keeps every other item where it is; where the two differ
      in size so that the swap would overlap or leave the grid, the whole
      layout is **laid out again in the new reading order**, each item at
      the first free place after the place of the item before it (row by
      row, column by column), which keeps the new order as the reading
      order.

  An edit begins from the stored layout with the items of kinds the
  registry no longer holds left out (the page draws none of them) and a
  view id that went stale dropped, as the next save would drop it (§2).
  """
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Widgets

  @columns 12

  alias Portfolixir.Dashboards.Arrange

  defstruct [:dashboard, :read, :layout, :keys, :next_key, stale: nil, previous: nil, moved: []]

  @type t :: %__MODULE__{
          dashboard: Dashboard.t(),
          read: [map()],
          layout: [map()],
          keys: [pos_integer()],
          next_key: pos_integer(),
          stale: Dashboard.t() | nil,
          previous:
            %{
              layout: [map()],
              keys: [pos_integer()],
              next_key: pos_integer(),
              key: pos_integer() | nil
            }
            | nil,
          moved: [pos_integer()]
        }

  @typedoc """
  A step's answer: the next edit with the sentence to announce and the key
  of the widget the step acted on, where its feedback stands and the focus
  goes (`nil`: none is left); or the sentence that says why the step was
  refused, with the key of the widget it was asked of (`nil` for an add,
  which has none yet); or `:error` for an item or a value the edit does
  not hold.
  """
  @type step ::
          {:ok, t(), String.t(), pos_integer() | nil}
          | {:refused, String.t(), pos_integer() | nil}
          | :error

  @doc "Begins an edit of the stored `dashboard`."
  @spec start(Dashboard.t()) :: t()
  def start(%Dashboard{} = dashboard) do
    layout = read_layout(dashboard)

    keys = Enum.to_list(1..length(layout)//1)

    %__MODULE__{
      dashboard: dashboard,
      read: layout,
      layout: layout,
      keys: keys,
      next_key: length(layout) + 1
    }
  end

  # The stored layout as an edit reads it: the kinds the registry holds,
  # normalised as the next save would store it.
  defp read_layout(%Dashboard{} = dashboard) do
    registered = Enum.filter(dashboard.layout, &match?({:ok, _}, Widgets.fetch(&1["kind"])))

    case Dashboards.validate_layout(registered, stored: dashboard.layout) do
      {:ok, normalized} -> normalized
      {:error, _refusal} -> registered
    end
  end

  @doc "The edited layout discarded: the layout as read, the edit still open."
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = edit) do
    %{
      edit
      | layout: edit.read,
        keys: Enum.to_list(1..length(edit.read)//1),
        stale: nil,
        previous: nil,
        moved: []
    }
    |> Map.put(:next_key, length(edit.read) + 1)
  end

  @doc """
  „Rückgängig“ (and Ctrl+Z): the edit as it was before the last step, that
  one step only; the widgets the undo moves back are marked. `:error` when
  no step is left to take back.
  """
  @spec undo(t()) :: {:ok, t(), String.t(), pos_integer() | nil} | :error
  def undo(
        %__MODULE__{previous: %{layout: layout, keys: keys, next_key: next_key} = previous} = edit
      ) do
    restored = %{
      edit
      | layout: layout,
        keys: keys,
        next_key: next_key,
        previous: nil,
        moved: List.delete(moved_keys(edit.layout, edit.keys, layout, keys), previous.key)
    }

    key = if previous.key in keys, do: previous.key

    {:ok, restored, gettext("Last step undone"), key}
  end

  def undo(%__MODULE__{}), do: :error

  @doc "Whether a step can be taken back."
  @spec undoable?(t()) :: boolean()
  def undoable?(%__MODULE__{previous: previous}), do: not is_nil(previous)

  @doc "Whether the edited layout differs from the layout as read."
  @spec changed?(t()) :: boolean()
  def changed?(%__MODULE__{layout: layout, read: read}), do: layout != read

  @doc """
  The save was refused as stale: `stored` is the dashboard as stored now,
  which the page shows beside the edit.
  """
  @spec stale(t(), Dashboard.t()) :: t()
  def stale(%__MODULE__{} = edit, %Dashboard{} = stored), do: %{edit | stale: stored}

  @doc """
  „Weiter bearbeiten“ after a stale save: the edit continues on the stored
  dashboard (its name and lock_version), so the next „Fertig“ replaces the
  stored version, which the operator has seen. Its layout becomes the
  layout as read, normalised as `start/1` reads one, so „Zurücksetzen“
  goes back to the stored version and „Fertig“ compares with it (Sprint
  31 closing act, order lens O1).
  """
  @spec rebase(t()) :: t()
  def rebase(%__MODULE__{stale: %Dashboard{} = stored} = edit),
    do: %{edit | dashboard: stored, read: read_layout(stored), stale: nil}

  def rebase(%__MODULE__{} = edit), do: edit

  @doc "The key of the item a page event names (a whole number or its digits), or `nil`."
  @spec key(t(), term()) :: pos_integer() | nil
  def key(%__MODULE__{keys: keys}, raw) do
    key = PortfolixirWeb.LiveParam.integer(raw, 1..max(Enum.max(keys, fn -> 1 end), 1))
    if key in keys, do: key
  end

  @doc "The key of the item at `index` in the edited layout."
  @spec key_at(t(), non_neg_integer()) :: pos_integer() | nil
  def key_at(%__MODULE__{keys: keys}, index), do: Enum.at(keys, index)

  # --- the steps -------------------------------------------------------------

  @doc "Moves the item `key` one grid step `:left`, `:right`, `:up` or `:down`."
  @spec move(t(), pos_integer(), :left | :right | :up | :down) :: step()
  def move(%__MODULE__{} = edit, key, direction) do
    with {:ok, index, item} <- fetch(edit, key) do
      {dc, dr} = step(direction)
      col = item["col"] + dc
      row = item["row"] + dr
      title = title(item)

      case arranged(edit, key, {:move, index, {col, row}}) do
        {:ok, next} ->
          {:ok, next,
           with_moved(
             gettext("%{widget} moved %{direction}, column %{col}, row %{row}",
               widget: title,
               direction: direction(direction),
               col: col,
               row: row
             ),
             next
           ), key}

        {:refused, reason} ->
          {:refused,
           gettext("%{widget} can't move %{direction}: %{reason}.",
             widget: title,
             direction: direction(direction),
             reason: reason
           ), key}
      end
    end
  end

  @doc "Places the item `key` at `col` and `row` (a drop on the wide grid)."
  @spec place(t(), pos_integer(), term(), term()) :: step()
  def place(%__MODULE__{} = edit, key, col, row) when is_integer(col) and is_integer(row) do
    with {:ok, index, item} <- fetch(edit, key) do
      title = title(item)

      case arranged(edit, key, {:move, index, {col, row}}) do
        {:ok, next} ->
          {:ok, next,
           with_moved(
             gettext("%{widget} placed at column %{col}, row %{row}",
               widget: title,
               col: col,
               row: row
             ),
             next
           ), key}

        {:refused, reason} ->
          {:refused,
           gettext("%{widget} can't go to column %{col}, row %{row}: %{reason}.",
             widget: title,
             col: col,
             row: row,
             reason: reason
           ), key}
      end
    end
  end

  def place(_edit, _key, _col, _row), do: :error

  @doc """
  Sizes the item `key` to `size`, one of its kind's grid sizes; where the
  size would leave the grid at its column, the item moves left as far as
  it needs; what it then covers makes room.
  """
  @spec resize(t(), pos_integer(), term()) :: step()
  def resize(%__MODULE__{} = edit, key, size) do
    with {:ok, index, item} <- fetch(edit, key),
         true <- is_binary(size) and size in grid_sizes(item["kind"]),
         {:ok, {width, _height}} <- Widgets.dimensions(size) do
      col = min(item["col"], @columns - width + 1)
      title = title(item)

      case arranged(edit, key, {:resize, index, size}) do
        {:ok, next} ->
          {:ok, next,
           with_moved(
             gettext("%{widget} set to size %{size}, column %{col}, row %{row}",
               widget: title,
               size: size,
               col: col,
               row: item["row"]
             ),
             next
           ), key}

        {:refused, reason} ->
          {:refused,
           gettext("%{widget} can't take size %{size}: %{reason}.",
             widget: title,
             size: size,
             reason: reason
           ), key}
      end
    else
      _not_a_size -> :error
    end
  end

  @doc """
  Removes the item `key`, then the gaps close; the feedback and the focus
  go to the next item in reading order, else the one before it, else
  nowhere (`nil`).
  """
  @spec remove(t(), pos_integer()) :: step()
  def remove(%__MODULE__{} = edit, key) do
    with {:ok, index, item} <- fetch(edit, key) do
      order = reading_keys(edit)
      at = Enum.find_index(order, &(&1 == key))
      focus = Enum.at(order, at + 1) || (at > 0 && Enum.at(order, at - 1)) || nil
      keys = List.delete_at(edit.keys, index)

      {:ok, layout} = Arrange.settle(List.delete_at(edit.layout, index))

      next =
        stepped(edit, key, %{edit | layout: layout, keys: keys})

      {:ok, next, with_moved(gettext("%{widget} removed", widget: title(item)), next), focus}
    end
  end

  @doc """
  Adds the kind `kind` in its first grid size at the first free place,
  row by row, column by column.
  """
  @spec add(t(), term()) :: step()
  def add(%__MODULE__{} = edit, kind) do
    with {:ok, registered} <- Widgets.fetch(kind),
         [size | _rest] <- grid_sizes(registered.key) do
      case Layout.first_free(edit.layout, size) do
        {:ok, %{"col" => col, "row" => row}} ->
          added(edit, registered.key, size, {col, row})

        {:error, :too_many_items} ->
          {:refused,
           gettext("%{widget} can't be added: a dashboard holds at most 40 widgets.",
             widget: Widgets.title(registered.key)
           ), nil}

        {:error, _no_room} ->
          {:refused,
           gettext("%{widget} can't be added: the grid has no free place.",
             widget: Widgets.title(registered.key)
           ), nil}
      end
    else
      _unknown -> :error
    end
  end

  @doc """
  Moves the item `key` one place `:up` or `:down` in reading order (the
  compact class's reorder; the moduledoc gives the mapping onto the grid).
  """
  @spec reorder(t(), pos_integer(), :up | :down) :: step()
  def reorder(%__MODULE__{} = edit, key, direction) when direction in [:up, :down] do
    with {:ok, _index, item} <- fetch(edit, key) do
      order = reading_keys(edit)
      at = Enum.find_index(order, &(&1 == key))
      to = if direction == :up, do: at - 1, else: at + 1
      title = title(item)

      cond do
        to < 0 ->
          {:refused, gettext("%{widget} is already first.", widget: title), key}

        to >= length(order) ->
          {:refused, gettext("%{widget} is already last.", widget: title), key}

        true ->
          other = Enum.at(order, to)
          new_order = order |> List.replace_at(at, other) |> List.replace_at(to, key)

          case swap(edit, key, other) || reflow(edit, new_order) do
            {:ok, reordered} ->
              next = stepped(edit, key, reordered)

              {:ok, next,
               gettext("%{widget} moved %{direction}, position %{position} of %{total}",
                 widget: title,
                 direction: direction(direction),
                 position: to + 1,
                 total: length(order)
               ), key}

            nil ->
              {:refused,
               gettext("%{widget} can't move %{direction}: %{reason}.",
                 widget: title,
                 direction: direction(direction),
                 reason: gettext("the grid has no free place")
               ), key}
          end
      end
    end
  end

  defp added(edit, kind, size, {col, row}) do
    item = %{"kind" => kind, "size" => size, "col" => col, "row" => row, "settings" => %{}}
    key = edit.next_key
    grown = %{edit | keys: edit.keys ++ [key], next_key: key + 1}

    case arranged(grown, key, {:add, item}, edit) do
      {:ok, next} ->
        {:ok, next,
         with_moved(
           gettext("%{widget} added at column %{col}, row %{row}, size %{size}",
             widget: Widgets.title(kind),
             col: col,
             row: row,
             size: size
           ),
           next
         ), key}

      {:refused, _reason} ->
        :error
    end
  end

  # --- the layout in reading order --------------------------------------------

  @doc "The keys in reading order (row, then column; ADR-0062 §4)."
  @spec reading_keys(t()) :: [pos_integer()]
  def reading_keys(%__MODULE__{layout: layout, keys: keys}) do
    layout
    |> Enum.zip(keys)
    |> Enum.sort_by(fn {item, _key} -> {item["row"], item["col"]} end)
    |> Enum.map(&elem(&1, 1))
  end

  @doc "A kind's grid sizes, in the registry's order (`full` is never one)."
  @spec grid_sizes(term()) :: [String.t()]
  def grid_sizes(kind) do
    case Widgets.fetch(kind) do
      {:ok, registered} ->
        Enum.filter(registered.sizes, &match?({:ok, _}, Widgets.dimensions(&1)))

      :error ->
        []
    end
  end

  # --- helpers ----------------------------------------------------------------

  defp fetch(edit, key) do
    case Enum.find_index(edit.keys, &(&1 == key)) do
      nil -> :error
      index -> {:ok, index, Enum.at(edit.layout, index)}
    end
  end

  defp step(:left), do: {-1, 0}
  defp step(:right), do: {1, 0}
  defp step(:up), do: {0, -1}
  defp step(:down), do: {0, 1}

  defp direction(:left), do: pgettext("move direction", "left")
  defp direction(:right), do: pgettext("move direction", "right")
  defp direction(:up), do: pgettext("move direction", "up")
  defp direction(:down), do: pgettext("move direction", "down")

  defp title(item), do: Widgets.title(item["kind"]) || item["kind"]

  # The layout arranged after `action` (the context's rule: the item acted
  # on keeps its place, the others make room, the gaps close), validated;
  # the step kept as `previous` (taken from `before`, the edit before an
  # add grew its keys) and the keys of the widgets it moved marked. A
  # refusal answers the reason in words.
  defp arranged(edit, key, action, before \\ nil) do
    with {:ok, layout} <- Dashboards.arrange_layout(edit.layout, action),
         {:ok, layout} <- validate(edit, layout) do
      {:ok, stepped(before || edit, key, %{edit | layout: layout})}
    else
      {:error, refusal} -> {:refused, reason(refusal)}
    end
  end

  # `next` with the step taken from `before` kept for „Rückgängig“ and the
  # widgets it moved, all but the one acted on (`key`), marked.
  defp stepped(before, key, next) do
    %{
      next
      | previous: %{layout: before.layout, keys: before.keys, next_key: before.next_key, key: key},
        moved: List.delete(moved_keys(before.layout, before.keys, next.layout, next.keys), key)
    }
  end

  # The keys whose place differs between two layouts (an item in one only
  # is not counted).
  defp moved_keys(layout_a, keys_a, layout_b, keys_b) do
    places = Map.new(Enum.zip(keys_a, layout_a), fn {k, i} -> {k, {i["col"], i["row"]}} end)

    for {k, item} <- Enum.zip(keys_b, layout_b),
        Map.has_key?(places, k),
        Map.fetch!(places, k) != {item["col"], item["row"]},
        do: k
  end

  # The step's sentence, and how many widgets made room for it.
  defp with_moved(say, %__MODULE__{moved: []}), do: say

  defp with_moved(say, %__MODULE__{moved: moved}) do
    say <>
      " · " <>
      ngettext("1 widget made room", "%{count} widgets made room", length(moved))
  end

  defp validate(edit, layout),
    do: Dashboards.validate_layout(layout, stored: edit.dashboard.layout)

  defp reason(:off_grid), do: gettext("it would leave the grid")
  defp reason(:no_room), do: gettext("the grid has no free place")

  defp reason(:too_many_items), do: gettext("a dashboard holds at most 40 widgets")
  defp reason(_refusal), do: gettext("the layout does not allow it")

  # The two items' places exchanged, or nil where the layout refuses it.
  defp swap(edit, key, other) do
    {:ok, a, item_a} = fetch(edit, key)
    {:ok, b, item_b} = fetch(edit, other)

    layout =
      edit.layout
      |> List.replace_at(a, %{item_a | "col" => item_b["col"], "row" => item_b["row"]})
      |> List.replace_at(b, %{item_b | "col" => item_a["col"], "row" => item_a["row"]})

    case validate(edit, layout) do
      {:ok, layout} -> {:ok, %{edit | layout: layout}}
      {:error, _refusal} -> nil
    end
  end

  # Every item laid out again in `order` (keys), each at the first free
  # place after the place of the one before it.
  defp reflow(edit, order) do
    by_key = Map.new(Enum.zip(edit.keys, edit.layout))

    placed =
      Enum.reduce_while(order, {%{}, [], {0, 0}}, fn key, {acc, rects, after_place} ->
        item = Map.fetch!(by_key, key)
        {:ok, {width, height}} = Widgets.dimensions(item["size"])

        case first_free_after(rects, width, height, after_place) do
          {col, row} ->
            {:cont,
             {Map.put(acc, key, %{item | "col" => col, "row" => row}),
              [{col, row, width, height} | rects], {row, col}}}

          nil ->
            {:halt, nil}
        end
      end)

    with {by_key, _rects, _last} <- placed,
         layout = Enum.map(edit.keys, &Map.fetch!(by_key, &1)),
         {:ok, layout} <- validate(edit, layout) do
      {:ok, %{edit | layout: layout}}
    else
      _none -> nil
    end
  end

  # The first place, row by row and column by column, strictly after
  # `{row, col}` `after_place`, where a `width` × `height` item stays on the
  # grid and overlaps none of `rects`.
  defp first_free_after(rects, width, height, {after_row, after_col}) do
    places =
      for row <- max(after_row, 1)..Layout.max_row(),
          col <- 1..(@columns - width + 1),
          {row, col} > {after_row, after_col},
          do: {col, row}

    Enum.find(places, fn {col, row} ->
      not Enum.any?(rects, &overlaps?(&1, {col, row, width, height}))
    end)
  end

  defp overlaps?({c1, r1, w1, h1}, {c2, r2, w2, h2}),
    do: c1 < c2 + w2 and c2 < c1 + w1 and r1 < r2 + h2 and r2 < r1 + h1
end
