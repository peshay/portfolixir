defmodule PortfolixirWeb.Journal.Change do
  @moduledoc """
  What one audit-journal entry changed, as the Audit journal page shows it
  (Sprint 23 V3, idea U2; board `ux-design-2026-11-02-sprint23/03-journal`
  ③): one line per changed field over a fold of the stored values, reduced
  to the fields that changed.

  The page reads the **operation**, not the diff of the two images:

  - an update (or an upsert that replaced a row) lists the fields whose
    stored before and after differ;
  - a create (or an upsert that inserted) folds every stored value, its
    before „—“;
  - a delete reads „deleted, with every value“ and folds every value of the
    before-image, its after „—“, whatever the entry's after-image holds
    (a row delete's after repeats the deleted row; found while drawing 7).

  Field names are the stored keys, as `GET /api/v1/journal` answers them, so
  the operator and the agent name a field alike. A value is shown as stored:
  text as text, a list or a map as JSON, none as „—“. A line cuts a value at
  80 characters and the fold at 300; the API carries the whole image.
  """

  alias Portfolixir.Journal.Entry

  # Bookkeeping columns every update moves; the fold keeps them, the lines
  # say what the write was for.
  @timestamps ~w(inserted_at updated_at)

  @line_cut 80
  @fold_cut 300

  @doc """
  `%{lines: lines, values: values}` for `entry`: `lines` is `[:deleted]` for
  a delete, else `{field, before, after}` per changed field without the
  timestamps; `values` is `{field, before, after}` per field the fold shows.
  """
  @spec build(Entry.t()) :: %{lines: list(), values: [{String.t(), String.t(), String.t()}]}
  def build(%Entry{operation: :delete, before: before}) do
    %{lines: [:deleted], values: every_value(before, :before)}
  end

  def build(%Entry{before: before, after: after_image}) when not is_map(before) do
    %{lines: [], values: every_value(after_image, :after)}
  end

  def build(%Entry{before: before, after: after_image}) do
    after_image = if is_map(after_image), do: after_image, else: %{}

    changed =
      (Map.keys(before) ++ Map.keys(after_image))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.filter(&(Map.get(before, &1) != Map.get(after_image, &1)))

    %{
      lines:
        for field <- changed, field not in @timestamps do
          {field, show(before[field], @line_cut), show(after_image[field], @line_cut)}
        end,
      values:
        for field <- changed do
          {field, show(before[field], @fold_cut), show(after_image[field], @fold_cut)}
        end
    }
  end

  defp every_value(image, side) when is_map(image) do
    for field <- image |> Map.keys() |> Enum.sort() do
      value = show(image[field], @fold_cut)
      if side == :before, do: {field, value, "—"}, else: {field, "—", value}
    end
  end

  defp every_value(_image, _side), do: []

  defp show(nil, _cut), do: "—"
  defp show(value, cut) when is_binary(value), do: cut(value, cut)

  defp show(value, cut) when is_number(value) or is_boolean(value),
    do: cut(to_string(value), cut)

  defp show(value, cut), do: cut(Jason.encode!(value), cut)

  defp cut(text, cut) do
    if String.length(text) > cut, do: String.slice(text, 0, cut - 1) <> "…", else: text
  end
end
