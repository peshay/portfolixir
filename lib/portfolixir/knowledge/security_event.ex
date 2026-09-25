defmodule Portfolixir.Knowledge.SecurityEvent do
  @moduledoc """
  One dated calendar fact about a security (ADR-0048 §1).

  An event is **not** a corporate action. [ADR-0028](../../docs/decisions/0028-corporate-actions-as-ledger-events.html)
  made corporate actions ledger events because a split *changes a position*;
  an earnings date changes nothing until a price moves, and a price move is
  already a quote. `Ledger.Projection.effects/1` never sees one of these rows,
  and when the dividend is actually paid the booking goes through the ledger
  as it always did — the event is marked `confirmed`, not converted.

  Rows are **mutable and journaled**, deliberately not append-only like the
  research log (§4): a research entry is an argument whose history *is* its
  meaning, while an event is a fact about the world, and a rescheduled call
  does not make the old date a second fact — it makes it wrong. Two rows for
  one reporting date is a calendar an operator cannot read. The change history
  lives in the append-only audit journal (ADR-0017), and the table is
  guard-armed in the migration that created it.

  The closed sets (`kind`, `timing`, `source_quality`) are `Ecto.Enum` fields
  resolved from input with `String.to_existing_atom/1` **only after** the
  string was found in the declared list, so an unknown string is a plain
  `"is invalid"` changeset error and never a new atom.

  `source_quality` reuses ADR-0044's four-value vocabulary exactly rather than
  inventing a second scale — one answer to "how well do we know this" across
  both knowledge families, so the two stay comparable.

  `checked_at` is a **date**, not a timestamp: the day the fact was last
  re-read against its source. It answers a different question from `date` —
  a confirmed future date nobody has re-read in three months is a different
  risk from a past date nobody resolved, which is why §5 gives each its own
  read.

  No `Decimal` anywhere: an event carries no money (§6).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Input.BoundedDate
  alias Portfolixir.Input.Text

  @kinds ~w(earnings ex_dividend dividend_payment lockup_expiry index_review
            shareholder_meeting regulatory_decision guidance_update)a
  @timings ~w(exact estimated window month)a
  @source_qualities ~w(primary secondary_multi awareness unverified)a

  @type t :: %__MODULE__{}

  schema "security_events" do
    field(:kind, Ecto.Enum, values: @kinds)
    field(:date, :date)
    field(:date_end, :date)
    field(:timing, Ecto.Enum, values: @timings)
    field(:confirmed, :boolean, default: false)
    field(:source_url, :string)
    field(:source_quality, Ecto.Enum, values: @source_qualities)
    field(:checked_at, :date)
    field(:note, :string)
    field(:machine_generated, :boolean, default: false)

    # Read-side annotation of the staleness read (§5.4); virtual, so it never
    # reaches the DB or the journal snapshot.
    field(:days_since_checked, :integer, virtual: true)

    belongs_to(:security, Security)

    timestamps()
  end

  @doc "The closed kind set, as strings (API/MCP schema mirror)."
  def kinds, do: Enum.map(@kinds, &Atom.to_string/1)

  @doc "The closed timing-qualifier set, as strings."
  def timings, do: Enum.map(@timings, &Atom.to_string/1)

  @doc "The closed source-quality set, as strings (ADR-0044's, reused)."
  def source_qualities, do: Enum.map(@source_qualities, &Atom.to_string/1)

  @doc """
  The span of days an event could fall on (§3) — the conservative resolution
  the due-date read uses, because the failure being prevented is a missed date
  rather than an early warning.

    * `exact` and `estimated` — the single day;
    * `window` — `date` through `date_end`, inclusive;
    * `month` — the whole calendar month of `date`, because the day is not
      known.
  """
  @spec span(t()) :: {Date.t(), Date.t()}
  def span(%__MODULE__{timing: :window, date: date, date_end: date_end})
      when not is_nil(date_end),
      do: {date, date_end}

  def span(%__MODULE__{timing: :month, date: date}),
    do: {Date.beginning_of_month(date), Date.end_of_month(date)}

  def span(%__MODULE__{date: date}), do: {date, date}

  # Mirrors `security_events.source_url`'s column width.
  @max_source_url 255

  @castable ~w(security_id date date_end confirmed source_url checked_at note machine_generated)a

  @closed_sets [kind: @kinds, timing: @timings, source_quality: @source_qualities]

  @doc """
  Builds an event's changeset. `today` is injected by the context shell (the
  clock stays out of schemas, AR-2): a `checked_at` later than `today` plus
  one day of zone slack is refused (E25 S6, G09) — it is the day the source
  was re-read, and a future one hid the event from the stale-calendar read.
  """
  def changeset(event, attrs, %Date{} = today) do
    event
    |> cast(attrs, @castable)
    |> cast_closed_sets(attrs)
    |> update_change(:source_url, &trim_text/1)
    |> update_change(:note, &trim_text/1)
    |> validate_required([:security_id, :kind, :date, :timing, :source_quality])
    |> BoundedDate.validate([:date, :date_end, :checked_at])
    |> validate_checked_by(today)
    # The link is rendered as an anchor and handed to an agent as a source:
    # only http(s) — never javascript:, data: or a bare path.
    |> validate_format(:source_url, ~r{\Ahttps?://\S+\z}i, message: "must be an http(s) URL")
    # The column is varchar(255); without this a tracking-laden link is a
    # Postgrex 22001 and a 500 instead of a field error the caller can read.
    |> Text.validate(:source_url, max: @max_source_url)
    |> Text.validate(:note, multiline: true, max: Text.free_text_max())
    |> validate_window()
    |> validate_machine_generated_source()
    |> foreign_key_constraint(:security_id)
    |> check_constraint(:kind, name: :security_events_kind_check)
    |> check_constraint(:timing, name: :security_events_timing_check)
    |> check_constraint(:source_quality, name: :security_events_source_quality_check)
    |> check_constraint(:date_end, name: :security_events_window_end_check)
    |> check_constraint(:source_url, name: :security_events_machine_generated_source_check)
    |> check_constraint(:note, name: :security_events_note_length_check)
  end

  defp validate_checked_by(changeset, today) do
    latest = Date.add(today, 1)

    validate_change(changeset, :checked_at, fn :checked_at, checked_at ->
      if Date.compare(checked_at, latest) == :gt,
        do: [checked_at: {"must not be later than tomorrow", validation: :not_future}],
        else: []
    end)
  end

  # §3: only a window carries a range, and it never runs backwards. Stating it
  # on the other three timings matters as much as requiring it on the window —
  # a `date_end` beside an `exact` date is a range nobody would read.
  defp validate_window(changeset) do
    timing = get_field(changeset, :timing)
    date = get_field(changeset, :date)
    date_end = get_field(changeset, :date_end)

    cond do
      timing == :window and is_nil(date_end) ->
        add_error(changeset, :date_end, "is required for a window event")

      timing == :window and not is_nil(date) and Date.compare(date_end, date) == :lt ->
        add_error(changeset, :date_end, "must be on or after date")

      timing != :window and not is_nil(date_end) ->
        add_error(changeset, :date_end, "is only recorded on a window event")

      true ->
        changeset
    end
  end

  # §6 / NFR-10: an extracted event is a proposal carrying its source link.
  defp validate_machine_generated_source(changeset) do
    if get_field(changeset, :machine_generated) == true and
         is_nil(get_field(changeset, :source_url)) do
      add_error(changeset, :source_url, "is required for a machine-generated event")
    else
      changeset
    end
  end

  # A closed-set value is accepted as the atom itself or as its string form; a
  # string becomes an atom only when it is already in the declared list
  # (`String.to_existing_atom/1` after the membership check), and anything else
  # is a plain "is invalid" — the Ecto.Enum cast error would otherwise carry a
  # type tuple the API error renderer cannot interpolate.
  defp cast_closed_sets(changeset, attrs) do
    Enum.reduce(@closed_sets, changeset, fn {field, allowed}, acc ->
      case fetch_attr(attrs, field) do
        :absent -> acc
        {:ok, nil} -> acc
        {:ok, ""} -> acc
        {:ok, value} when is_atom(value) -> put_closed_set_atom(acc, field, value, allowed)
        {:ok, value} when is_binary(value) -> put_closed_set_string(acc, field, value, allowed)
        {:ok, _other} -> add_error(acc, field, "is invalid")
      end
    end)
  end

  defp put_closed_set_atom(changeset, field, value, allowed) do
    if value in allowed,
      do: put_change(changeset, field, value),
      else: add_error(changeset, field, "is invalid")
  end

  defp put_closed_set_string(changeset, field, value, allowed) do
    allowed_strings = Enum.map(allowed, &Atom.to_string/1)

    if value in allowed_strings do
      put_change(changeset, field, String.to_existing_atom(value))
    else
      add_error(changeset, field, "is invalid")
    end
  end

  defp fetch_attr(attrs, field) do
    cond do
      Map.has_key?(attrs, field) -> {:ok, Map.get(attrs, field)}
      Map.has_key?(attrs, Atom.to_string(field)) -> {:ok, Map.get(attrs, Atom.to_string(field))}
      true -> :absent
    end
  end

  # `cast/3` already maps a whitespace-only string to the field's default
  # (`nil` here) through Ecto's `:empty_values`, so "a link made of spaces"
  # never reaches this function as a change. What is left is the padding
  # around a value that does carry text, and a cleared field passing through
  # as `nil`.
  defp trim_text(value) when is_binary(value), do: String.trim(value)
  defp trim_text(value), do: value
end
