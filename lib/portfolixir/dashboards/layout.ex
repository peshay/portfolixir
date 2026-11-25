defmodule Portfolixir.Dashboards.Layout do
  @moduledoc """
  A dashboard's layout and its validation (ADR-0062 §2, §4, §11).

  A layout is an ordered list of at most `max_items/0` items. An item names
  a registered `kind` (`Portfolixir.Dashboards.Widgets`), a `size` the kind
  supports on the grid (`full` is a page, never placed), its `col` (1 to 12)
  and `row` (1 to `max_row/0`) on the 12-column wide grid, and optional
  `settings`: `view_id` (a view that exists, on a kind that takes a view)
  and `period` (a pin, one of the dashboard periods the kind answers).

  `validate/2` refuses the **first** bad item, naming its index (0-based,
  the item's place in the list sent), the field and the reason; nothing is
  repaired, moved or dropped, save the exceptions below. A layout of more than `max_items/0` items is
  refused as a whole, before any item is read, with the index of the first
  item past the cap (40): no item there is bad in itself.

  **One exception, a stale view** (ADR-0062 §2: "A deleted view leaves an
  item's `view_id` dangling … the next save drops the stale id"): a
  `view_id` that names no view is dropped from its item's settings, not
  refused, when the same id is already stored in the dashboard's current
  layout (`stored:`), since it went stale when its view was deleted. Any
  other `view_id` that names no view is refused, and a create, which has
  no stored layout, refuses every one.

  **The second, a retired kind** (Sprint 31 closing act, C4): an item
  whose `kind` is not registered is dropped from the layout, not refused,
  when the dashboard's current layout (`stored:`) already holds an item of
  that kind, since a later release retired it after it was stored; a
  pin, a catalogue add or a save that resends the stored layout then goes
  through instead of being refused for an item the operator cannot change.
  Any other unregistered kind is refused, and a create refuses every one.

  **The third, a deleted own period** (Sprint 32 T5): a pin
  `saved:<id>` whose period was deleted is dropped from its item's
  settings, not refused, when the stored layout already pins it, as a
  stale view is; any other pin naming no stored period is refused
  (`:unknown_period`).
  The dropped item meets no overlap and keeps no place. It is strict: a key the item or its settings
  do not take is refused too, so a layout carries nothing the server does
  not read. Keys are strings (an atom key written in code is read as its
  string; no atom is ever made from a key), values are matched as strings
  and whole numbers, and every bound is checked before anything reaches the
  database: a `view_id` outside PostgreSQL's `bigint` is refused unread.

  The accepted layout comes back normalized, in the order sent: each item
  with exactly `"kind"`, `"size"`, `"col"`, `"row"` and `"settings"` (the
  settings sent, or an empty map). That is what a dashboard stores.
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  import Ecto.Query, only: [from: 2]

  alias Portfolixir.Buckets.View
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Periods
  alias Portfolixir.Periods.SavedPeriod
  alias Portfolixir.Repo

  @max_items 40
  @columns 12
  # 40 items at most, none taller than 4 rows: 160 rows hold any layout the
  # item cap admits stacked one below the other; 200 leaves room for gaps.
  @max_row 200
  @max_bigint 9_223_372_036_854_775_807

  @item_keys ~w(kind size col row settings)
  @setting_keys ~w(view_id period)

  @type item :: %{String.t() => term()}

  @type reason ::
          :not_a_list
          | :too_many_items
          | :not_an_object
          | :unknown_key
          | :missing
          | :unknown_kind
          | :unsupported_size
          | :not_an_integer
          | :off_grid
          | :overlap
          | :unknown_setting
          | :unknown_view
          | :no_view
          | :no_period
          | :unsupported_period
          | :no_room
          | :unknown_period

  @typedoc """
  A refusal: the item's 0-based `index` (`nil` when the layout itself is
  refused), the `field` (an item key, `"settings.<key>"`, or `nil` when no
  string names it), the `reason`, an English `message` and, for an
  overlap, the index of the earlier item it meets (`other`).
  """
  @type refusal :: %{
          required(:index) => non_neg_integer() | nil,
          required(:field) => String.t() | nil,
          required(:reason) => reason(),
          required(:message) => String.t(),
          optional(:other) => non_neg_integer()
        }

  @doc "The most items a layout holds (ADR-0062 §2)."
  @spec max_items() :: pos_integer()
  def max_items, do: @max_items

  @doc "The grid's column count (ADR-0062 §4)."
  @spec columns() :: pos_integer()
  def columns, do: @columns

  @doc "The highest row an item may start on."
  @spec max_row() :: pos_integer()
  def max_row, do: @max_row

  @doc """
  The first place on the grid where a widget of `size` fits beside the
  items of `layout` (a validated layout): scanning row by row from the top,
  each row left to right, the first `col` and `row` whose cells no item
  holds (Sprint 31 D7, „hinzufügen“ in „Alle Widgets“). Reads nothing.

  `{:error, :too_many_items}` when the layout already holds `max_items/0`;
  `{:error, :unsupported_size}` for `full` or any value that is no grid
  size; `{:error, :no_room}` when no row up to `max_row/0` has the place.
  """
  @spec first_free([item()], term()) ::
          {:ok, %{String.t() => pos_integer()}}
          | {:error, :too_many_items | :unsupported_size | :no_room}
  def first_free(layout, size) when is_list(layout) do
    case Widgets.dimensions(size) do
      :error ->
        {:error, :unsupported_size}

      {:ok, _dimensions} when length(layout) >= @max_items ->
        {:error, :too_many_items}

      {:ok, {width, height}} ->
        taken = layout |> Enum.flat_map(&cells/1) |> MapSet.new()
        places = for row <- 1..@max_row, col <- 1..(@columns - width + 1), do: {col, row}

        Enum.find_value(places, {:error, :no_room}, fn {col, row} ->
          if Enum.all?(area(col, row, width, height), &(not MapSet.member?(taken, &1))),
            do: {:ok, %{"col" => col, "row" => row}}
        end)
    end
  end

  defp cells(%{"size" => size, "col" => col, "row" => row}) do
    case Widgets.dimensions(size) do
      {:ok, {width, height}} -> area(col, row, width, height)
      :error -> []
    end
  end

  defp area(col, row, width, height),
    do: for(c <- col..(col + width - 1), r <- row..(row + height - 1), do: {c, r})

  @doc """
  Validates `layout`: `{:ok, normalized}` or `{:error, refusal}` naming the
  first bad item. Reads the views table once, for the view ids the layout
  names, and the stored periods once, for the own periods its pins name,
  and nothing else.

  Option `stored:` is the dashboard's layout as stored, when the write
  replaces one: a view id it already holds that names no view any more is
  dropped from the item that sends it, and an item of a kind it already
  holds that is no longer registered is dropped (see the moduledoc).

  Option `overlaps: :allow` reads every item but does not refuse two that
  overlap: the check the arrangement runs before it moves the others
  (`Portfolixir.Dashboards.Arrange`; ADR-0062's amendment of 2026-11-25,
  point 2), whose answer is validated again in full.
  """
  @spec validate(term(), keyword()) :: {:ok, [item()]} | {:error, refusal()}
  def validate(layout, opts \\ [])

  def validate(layout, opts) when is_list(layout) and is_list(opts) do
    if length(layout) > @max_items do
      refuse(@max_items, nil, :too_many_items)
    else
      stored = Keyword.get(opts, :stored, [])

      views = %{
        existing: existing_views(layout),
        stored: stored_views(stored),
        retired: retired_kinds(stored),
        overlaps: Keyword.get(opts, :overlaps, :refuse),
        periods: existing_periods(layout),
        stored_periods: stored_periods(stored)
      }

      layout
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {raw, index}, {:ok, placed} ->
        case validate_item(raw, index, views, placed) do
          {:ok, item} -> {:cont, {:ok, [{item, index} | placed]}}
          :retired -> {:cont, {:ok, placed}}
          {:error, _refusal} = refused -> {:halt, refused}
        end
      end)
      |> case do
        {:ok, placed} -> {:ok, placed |> Enum.reverse() |> Enum.map(&elem(&1, 0))}
        refused -> refused
      end
    end
  end

  def validate(_layout, _opts), do: refuse(nil, nil, :not_a_list)

  @doc """
  The English message of a refusal's reason, an `errors` msgid the screen
  translates as it translates a changeset's.
  """
  @spec message(reason()) :: String.t()
  def message(:not_a_list), do: dgettext_noop("errors", "must be a list of widgets")
  def message(:too_many_items), do: dgettext_noop("errors", "must hold at most 40 widgets")
  def message(:not_an_object), do: dgettext_noop("errors", "must be an object")
  def message(:unknown_key), do: dgettext_noop("errors", "is not a key a widget takes")
  def message(:missing), do: dgettext_noop("errors", "can't be blank")
  def message(:unknown_kind), do: dgettext_noop("errors", "is not a registered widget kind")

  def message(:unsupported_size),
    do:
      dgettext_noop(
        "errors",
        "is not a size this widget kind takes: the sizes are the families S, M, L and XL"
      )

  def message(:not_an_integer), do: dgettext_noop("errors", "must be a whole number")
  def message(:off_grid), do: dgettext_noop("errors", "is off the grid")
  def message(:overlap), do: dgettext_noop("errors", "overlaps another widget")
  def message(:unknown_setting), do: dgettext_noop("errors", "is not a setting a widget takes")
  def message(:unknown_view), do: dgettext_noop("errors", "names no view")
  def message(:no_period), do: dgettext_noop("errors", "this widget kind takes no period")
  def message(:no_view), do: dgettext_noop("errors", "this widget kind takes no view")

  def message(:unsupported_period),
    do: dgettext_noop("errors", "is not a period this widget kind takes")

  def message(:no_room),
    do:
      dgettext_noop(
        "errors",
        "leaves no place up to row 200 for the widgets it would move"
      )

  def message(:unknown_period), do: dgettext_noop("errors", "names no own period")

  # --- one item ---------------------------------------------------------

  defp validate_item(raw, index, views, placed) when is_map(raw) do
    with {:ok, fields} <- string_keys(raw, @item_keys, index, &item_key_refusal/2),
         {:ok, kind} <- kind(fields, views.retired, index),
         {:ok, {width, height}} <- size(fields, kind, index),
         {:ok, col} <- whole(fields, "col", index),
         {:ok, row} <- whole(fields, "row", index),
         :ok <- on_grid(col, row, width, index),
         {:ok, settings} <- settings(fields, kind, views, index),
         :ok <- no_overlap({col, row, width, height}, placed, index, views.overlaps) do
      {:ok,
       %{
         "kind" => kind.key,
         "size" => Map.fetch!(fields, "size"),
         "col" => col,
         "row" => row,
         "settings" => settings
       }}
    end
  end

  defp validate_item(_raw, index, _views, _placed), do: refuse(index, nil, :not_an_object)

  # Every key read as a string (an atom key written in code as its name; any
  # other key refused), and checked against `allowed` before any value is.
  defp string_keys(map, allowed, index, on_unknown) do
    Enum.reduce_while(map, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case key_string(key) do
        {:ok, name} ->
          if name in allowed,
            do: {:cont, {:ok, Map.put(acc, name, value)}},
            else: {:halt, on_unknown.(index, name)}

        :error ->
          {:halt, on_unknown.(index, nil)}
      end
    end)
  end

  defp key_string(key) when is_binary(key), do: {:ok, key}

  defp key_string(key) when is_atom(key) and not is_nil(key) and not is_boolean(key),
    do: {:ok, Atom.to_string(key)}

  defp key_string(_key), do: :error

  defp item_key_refusal(index, name), do: refuse(index, name, :unknown_key)

  defp setting_key_refusal(index, nil), do: refuse(index, "settings", :unknown_setting)
  defp setting_key_refusal(index, name), do: refuse(index, "settings." <> name, :unknown_setting)

  defp kind(%{"kind" => key}, retired, index) do
    case Widgets.fetch(key) do
      {:ok, kind} ->
        {:ok, kind}

      # Retired: stored before a release dropped its kind; the save drops it.
      :error ->
        if MapSet.member?(retired, key), do: :retired, else: refuse(index, "kind", :unknown_kind)
    end
  end

  defp kind(_fields, _retired, index), do: refuse(index, "kind", :missing)

  defp size(%{"size" => size}, kind, index) do
    with true <- is_binary(size) and size in kind.sizes,
         {:ok, dimensions} <- Widgets.dimensions(size) do
      {:ok, dimensions}
    else
      _not_placeable -> refuse(index, "size", :unsupported_size)
    end
  end

  defp size(_fields, _kind, index), do: refuse(index, "size", :missing)

  defp whole(fields, field, index) do
    case Map.fetch(fields, field) do
      {:ok, value} when is_integer(value) -> {:ok, value}
      {:ok, _value} -> refuse(index, field, :not_an_integer)
      :error -> refuse(index, field, :missing)
    end
  end

  defp on_grid(col, row, width, index) do
    cond do
      col < 1 or col + width - 1 > @columns -> refuse(index, "col", :off_grid)
      row < 1 or row > @max_row -> refuse(index, "row", :off_grid)
      true -> :ok
    end
  end

  # --- settings -----------------------------------------------------------

  defp settings(fields, kind, views, index) do
    case Map.get(fields, "settings", %{}) do
      nil ->
        {:ok, %{}}

      raw when is_map(raw) ->
        with {:ok, settings} <- string_keys(raw, @setting_keys, index, &setting_key_refusal/2),
             {:ok, settings} <- view_setting(settings, kind, views, index),
             {:ok, settings} <- period_setting(settings, kind, views, index) do
          {:ok, settings}
        end

      _other ->
        refuse(index, "settings", :not_an_object)
    end
  end

  defp view_setting(%{"view_id" => _id}, %{scope: :none}, _views, index),
    do: refuse(index, "settings.view_id", :no_view)

  defp view_setting(%{"view_id" => id} = settings, _kind, views, index) do
    cond do
      not view_id?(id) -> refuse(index, "settings.view_id", :unknown_view)
      MapSet.member?(views.existing, id) -> {:ok, settings}
      # Stale: stored before its view was deleted; the save drops it (§2).
      MapSet.member?(views.stored, id) -> {:ok, Map.delete(settings, "view_id")}
      true -> refuse(index, "settings.view_id", :unknown_view)
    end
  end

  defp view_setting(settings, _kind, _views, _index), do: {:ok, settings}

  defp period_setting(%{"period" => period} = settings, kind, views, index) do
    cond do
      kind.period == :none ->
        refuse(index, "settings.period", :no_period)

      not Widgets.takes_period?(kind.key, period) ->
        refuse(index, "settings.period", :unsupported_period)

      true ->
        own_period(settings, period, views, index)
    end
  end

  defp period_setting(settings, _kind, _views, _index), do: {:ok, settings}

  # An own period by reference (`saved:<id>`, Sprint 32 T5) must be stored;
  # one the stored layout already pins and whose period was deleted since
  # is dropped, as a stale view is (ADR-0062's amendment of 2026-11-25,
  # point 6). Any other key needs no row.
  defp own_period(settings, period, views, index) do
    case Periods.saved_id(period) do
      :error -> {:ok, settings}
      {:ok, id} -> own_period_id(settings, id, views, index)
    end
  end

  defp own_period_id(settings, id, views, index) do
    cond do
      MapSet.member?(views.periods, id) -> {:ok, settings}
      MapSet.member?(views.stored_periods, id) -> {:ok, Map.delete(settings, "period")}
      true -> refuse(index, "settings.period", :unknown_period)
    end
  end

  defp view_id?(id), do: is_integer(id) and id >= 1 and id <= @max_bigint

  # The views the layout names, read once: only ids that can be a view's.
  defp existing_views(layout) do
    ids =
      for item <- layout,
          is_map(item),
          settings = Map.get(item, "settings") || Map.get(item, :settings),
          is_map(settings),
          id = Map.get(settings, "view_id") || Map.get(settings, :view_id),
          view_id?(id),
          uniq: true,
          do: id

    case ids do
      [] -> MapSet.new()
      ids -> MapSet.new(Repo.all(from(v in View, where: v.id in ^ids, select: v.id)))
    end
  end

  # The own periods the layout's pins name that are stored, read once.
  defp existing_periods(layout) do
    ids =
      for item <- layout,
          is_map(item),
          settings = Map.get(item, "settings") || Map.get(item, :settings),
          is_map(settings),
          period = Map.get(settings, "period") || Map.get(settings, :period),
          {:ok, id} <- [Periods.saved_id(period)],
          uniq: true,
          do: id

    case ids do
      [] -> MapSet.new()
      ids -> MapSet.new(Repo.all(from(p in SavedPeriod, where: p.id in ^ids, select: p.id)))
    end
  end

  # The own periods a stored (normalized) layout pins.
  defp stored_periods(stored) when is_list(stored) do
    for %{"settings" => %{"period" => period}} <- stored,
        {:ok, id} <- [Periods.saved_id(period)],
        into: MapSet.new(),
        do: id
  end

  defp stored_periods(_stored), do: MapSet.new()

  # The view ids a stored (normalized) layout holds.
  defp stored_views(stored) when is_list(stored) do
    for %{"settings" => %{"view_id" => id}} <- stored, view_id?(id), into: MapSet.new(), do: id
  end

  defp stored_views(_stored), do: MapSet.new()

  # The kinds a stored (normalized) layout holds that are registered no more.
  defp retired_kinds(stored) when is_list(stored) do
    for %{"kind" => kind} <- stored, Widgets.fetch(kind) == :error, into: MapSet.new(), do: kind
  end

  defp retired_kinds(_stored), do: MapSet.new()

  # --- the grid -------------------------------------------------------------

  defp no_overlap(_rect, _placed, _index, :allow), do: :ok

  defp no_overlap(rect, placed, index, :refuse) do
    case Enum.find(placed, fn {item, _index} -> overlap?(rect, rect_of(item)) end) do
      nil ->
        :ok

      {_item, other} ->
        {:error, Map.put(refusal(index, "col", :overlap), :other, other)}
    end
  end

  defp rect_of(%{"size" => size, "col" => col, "row" => row}) do
    {:ok, {width, height}} = Widgets.dimensions(size)
    {col, row, width, height}
  end

  defp overlap?({c1, r1, w1, h1}, {c2, r2, w2, h2}),
    do: c1 < c2 + w2 and c2 < c1 + w1 and r1 < r2 + h2 and r2 < r1 + h1

  defp refuse(index, field, reason), do: {:error, refusal(index, field, reason)}

  defp refusal(index, field, reason),
    do: %{index: index, field: field, reason: reason, message: message(reason)}
end
