defmodule Portfolixir.Knowledge.ThesisState do
  @moduledoc """
  The current thesis state of a security as a **projection over its research
  log** (ADR-0044 §1, the B4.1 fields; issue #749).

  Pure over a list of `SecurityNote` rows, so it is trivially rebuildable
  from the log alone (ADR-0039 would apply if it were ever materialised; it
  is computed per read today). The rule:

  1. The **current thesis** is the newest `thesis` entry that no other
     `thesis` entry supersedes (a newer thesis replaces the older one).
  2. Its **status** is `:retracted` when a `retraction` entry supersedes it,
     otherwise `:intact`; `:none` when the security has no thesis entry at all.
  3. **Last reviewed** is the newest entry of kind `thesis` or
     `invalidation_check` — the entries that state whether the thesis still
     holds — with its `as_of` and `author`.

  The state names the entry it derives from (`derived_from_entry_id`) and, when
  retracted, the retraction (`retracted_by_entry_id`), so a consumer can read
  the reason rather than trust a flag.
  """

  alias Portfolixir.Knowledge.SecurityNote

  @type status :: :none | :intact | :retracted

  @type t :: %{
          status: status(),
          thesis: String.t() | nil,
          conviction: atom() | nil,
          invalidation_condition: String.t() | nil,
          time_stop: Date.t() | nil,
          as_of: Date.t() | nil,
          derived_from_entry_id: integer() | nil,
          retracted_by_entry_id: integer() | nil,
          last_reviewed_at: Date.t() | nil,
          last_reviewed_by: atom() | nil,
          basis: String.t()
        }

  @basis "Derived from the security's research log, never stored: the newest thesis " <>
           "entry no other thesis supersedes is the current thesis; a retraction " <>
           "superseding it sets status retracted; last_reviewed is the newest thesis " <>
           "or invalidation_check entry (as_of, author). Entries never vanish."

  @doc "The state for an empty log."
  @spec none() :: t()
  def none do
    %{
      status: :none,
      thesis: nil,
      conviction: nil,
      invalidation_condition: nil,
      time_stop: nil,
      as_of: nil,
      derived_from_entry_id: nil,
      retracted_by_entry_id: nil,
      last_reviewed_at: nil,
      last_reviewed_by: nil,
      basis: @basis
    }
  end

  @doc """
  Projects the state from `notes` (any order; all entries of one security).
  """
  @spec project([SecurityNote.t()]) :: t()
  def project(notes) when is_list(notes) do
    sorted = Enum.sort_by(notes, &sort_key/1, :desc)
    superseders = Enum.group_by(sorted, & &1.supersedes_id)

    theses = Enum.filter(sorted, &(&1.kind == :thesis))

    current =
      Enum.find(theses, fn thesis ->
        superseders
        |> Map.get(thesis.id, [])
        |> Enum.all?(&(&1.kind != :thesis))
      end)

    case current do
      nil ->
        none() |> put_last_reviewed(sorted)

      thesis ->
        retraction =
          superseders |> Map.get(thesis.id, []) |> Enum.find(&(&1.kind == :retraction))

        %{
          status: if(retraction, do: :retracted, else: :intact),
          thesis: thesis.body,
          conviction: thesis.conviction,
          invalidation_condition: thesis.invalidation_condition,
          time_stop: thesis.time_stop,
          as_of: thesis.as_of,
          derived_from_entry_id: thesis.id,
          retracted_by_entry_id: retraction && retraction.id,
          last_reviewed_at: nil,
          last_reviewed_by: nil,
          basis: @basis
        }
        |> put_last_reviewed(sorted)
    end
  end

  defp put_last_reviewed(state, sorted) do
    case Enum.find(sorted, &(&1.kind in [:thesis, :invalidation_check])) do
      nil -> state
      review -> %{state | last_reviewed_at: review.as_of, last_reviewed_by: review.author}
    end
  end

  # Newest first: the statement date, then the write time, then the id — the
  # same order `Knowledge.list_notes/2` returns.
  def sort_key(%SecurityNote{} = note) do
    {Date.to_erl(note.as_of), NaiveDateTime.to_erl(note.inserted_at), note.id}
  end
end
