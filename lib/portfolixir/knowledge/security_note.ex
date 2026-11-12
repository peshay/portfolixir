defmodule Portfolixir.Knowledge.SecurityNote do
  @moduledoc """
  One entry of a security's research log (ADR-0044 §2).

  Rows are **append-only**: never updated, never deleted — the schema carries
  `inserted_at` only and the database refuses UPDATE/DELETE/TRUNCATE (see the
  `create_security_notes` migration). A refuted finding is withdrawn by a
  `retraction` entry that supersedes it (§3); the superseded entry stays
  visible.

  The closed sets (`kind`, `source_quality`, `author`, `conviction`) are
  `Ecto.Enum` fields resolved from input with `String.to_existing_atom/1`
  **only after** the string was found in the declared list, so an unknown
  string is a plain `"is invalid"` changeset error and never a new atom
  (`String.to_atom/1` is forbidden).

  `as_of` is the statement's cut-off date, distinct from `inserted_at` — an
  entry written today about last quarter is not fresh information, and only
  that separation makes the review-hygiene reads mean anything.

  **A headline, an event type and a tone** (ADR-0044's amendment of
  2026-11-06; Sprint 28, N5): an `evidence` or `event_result` entry may
  carry `headline` (plain text, at most 80 code points, one line, no
  invisible character: ADR-0054 §4), `event_type` (the eight types of
  `event_types/0`, ADR-0056 §7's set without `noise`) and `tone` (-1, 0 or
  +1, the writer's reading, never a computed figure, a filter or a sort
  key). On any other kind each is refused naming the field. Like every
  field they are set once: the log is append-only. `news_label_id` is
  provenance only, never cast from input: the id of the news label an entry
  written from a story took its event type or tone from
  (`Portfolixir.News.Promotion`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Input.BoundedDate
  alias Portfolixir.Input.Text

  @kinds ~w(thesis evidence invalidation_check event_result risk retraction decision)a
  @source_qualities ~w(primary secondary_multi awareness unverified)a
  @authors ~w(operator agent local_model)a
  @convictions ~w(low medium high)a
  # S28 N5 (ADR-0044's amendment of 2026-11-06): the event types an entry
  # may carry, ADR-0056 §7's without `noise`, and the kinds that carry them.
  @event_types ~w(earnings guidance capital_measure legal m_and_a product regulatory macro)a
  @marker_kinds [:evidence, :event_result]
  @marker_fields [:headline, :event_type, :tone]
  @headline_max 80

  # The width of `security_notes.source_url` (character varying(2048)): the
  # news parser's cap, so a story's link fits an entry (ADR-0056 E2).
  @max_source_url 2048

  @type t :: %__MODULE__{}

  schema "security_notes" do
    field(:author, Ecto.Enum, values: @authors)
    field(:machine_generated, :boolean, default: false)
    field(:kind, Ecto.Enum, values: @kinds)
    field(:body, :string)
    field(:source_url, :string)
    field(:source_quality, Ecto.Enum, values: @source_qualities)
    field(:as_of, :date)
    field(:valid_until, :date)

    # Fields of the `thesis` kind (ADR-0044 ask list: the conviction tier is a
    # field of the thesis kind; invalidation condition and time stop are the
    # B4.1 state inputs the projection reads).
    field(:conviction, Ecto.Enum, values: @convictions)
    field(:invalidation_condition, :string)
    field(:time_stop, :date)

    # A headline, an event type and a tone (S28 N5), and the news label an
    # entry written from a story took them from (provenance, never cast).
    field(:headline, :string)
    field(:event_type, Ecto.Enum, values: @event_types)
    field(:tone, :integer)
    field(:news_label_id, :integer)

    # Read-side annotation: the ids of the entries superseding this one
    # (newest first). Populated by `Portfolixir.Knowledge.list_notes/2`;
    # virtual, so it never reaches the DB or the journal snapshot.
    field(:superseded_by_ids, {:array, :integer}, virtual: true, default: [])

    belongs_to(:security, Security)
    belongs_to(:supersedes, __MODULE__)

    timestamps(updated_at: false)
  end

  @doc "The closed kind set, as strings (API/MCP schema mirror)."
  def kinds, do: Enum.map(@kinds, &Atom.to_string/1)

  @doc "The closed source-quality set, as strings."
  def source_qualities, do: Enum.map(@source_qualities, &Atom.to_string/1)

  @doc "The closed author set, as strings."
  def authors, do: Enum.map(@authors, &Atom.to_string/1)

  @doc "The closed conviction-tier set, as strings."
  def convictions, do: Enum.map(@convictions, &Atom.to_string/1)

  @doc "The event types an entry may carry, as strings (S28 N5)."
  def event_types, do: Enum.map(@event_types, &Atom.to_string/1)

  @doc "The kinds that carry a headline, an event type and a tone, as strings."
  def marker_kinds, do: Enum.map(@marker_kinds, &Atom.to_string/1)

  @doc "The longest headline an entry stores, in code points."
  def headline_max, do: @headline_max

  @castable ~w(
    security_id machine_generated body source_url
    as_of supersedes_id valid_until invalidation_condition time_stop headline tone
  )a

  @closed_sets [
    author: @authors,
    kind: @kinds,
    source_quality: @source_qualities,
    conviction: @convictions,
    event_type: @event_types
  ]

  @doc """
  Builds an entry's changeset. `today` is injected by the context shell (the
  clock stays out of schemas, AR-2): an `as_of` after it is refused (E25 S6,
  F44) — an entry states what held on its day, and on a log that is never
  edited a mistyped future year could never be taken back. `valid_until` and
  `time_stop` may lie in the future; that is what they are for.
  """
  def changeset(note, attrs, %Date{} = today) do
    note
    |> cast(attrs, @castable)
    |> cast_closed_sets(attrs)
    |> update_change(:body, &trim/1)
    |> update_change(:source_url, &blank_to_nil/1)
    |> update_change(:invalidation_condition, &blank_to_nil/1)
    |> update_change(:headline, &blank_to_nil/1)
    |> validate_required([:security_id, :author, :kind, :body, :source_quality, :as_of])
    |> BoundedDate.validate([:as_of, :valid_until, :time_stop])
    |> validate_not_future(today)
    |> validate_length(:body, min: 1)
    # The link is rendered as an anchor on the timeline and handed to an agent
    # as a source: only http(s) — never javascript:, data: or a bare path.
    # No backslash (closing act of Sprint 29, F2): a browser reads it as `/`
    # where RFC 3986 does not, so the host shown and the host opened differ.
    |> validate_format(:source_url, ~r{\Ahttps?://[^\s\\]+\z}i, message: "must be an http(s) URL")
    # The column is varchar(2048); without this a longer link is a Postgrex
    # 22001 and a 500 instead of a field error the caller can read.
    |> Text.validate(:source_url, max: @max_source_url)
    # Code-point caps on append-only storage (E25 S6, G01), with a CHECK of
    # the same number behind each.
    |> Text.validate(:body, multiline: true, max: Text.entry_body_max())
    |> Text.validate(:invalidation_condition, multiline: true, max: Text.free_text_max())
    |> Text.validate(:headline, max: @headline_max)
    |> validate_inclusion(:tone, [-1, 0, 1], message: "must be -1, 0 or 1")
    |> validate_machine_generated_source()
    |> validate_retraction_supersedes()
    |> validate_thesis_fields()
    |> validate_marker_fields()
    |> foreign_key_constraint(:security_id)
    |> foreign_key_constraint(:supersedes_id)
    |> check_constraint(:kind, name: :security_notes_kind_check)
    |> check_constraint(:source_quality, name: :security_notes_source_quality_check)
    |> check_constraint(:author, name: :security_notes_author_check)
    |> check_constraint(:conviction, name: :security_notes_conviction_check)
    |> check_constraint(:source_url, name: :security_notes_machine_generated_source_check)
    |> check_constraint(:supersedes_id, name: :security_notes_retraction_supersedes_check)
    |> check_constraint(:body, name: :security_notes_body_length_check)
    |> check_constraint(:invalidation_condition,
      name: :security_notes_invalidation_condition_length_check
    )
    |> check_constraint(:headline, name: :security_notes_headline_length_check)
    |> check_constraint(:headline, name: :security_notes_marker_kind_check)
    |> check_constraint(:event_type, name: :security_notes_event_type_check)
    |> check_constraint(:tone, name: :security_notes_tone_check)
  end

  @doc """
  Puts the provenance id of the news label an entry written from a story
  took its event type or tone from (S28 N5); `nil` leaves it absent. Never
  cast from input: the server states where a proposal came from.
  """
  @spec put_news_label(Ecto.Changeset.t(), pos_integer() | nil) :: Ecto.Changeset.t()
  def put_news_label(changeset, nil), do: changeset

  def put_news_label(changeset, id) when is_integer(id),
    do: put_change(changeset, :news_label_id, id)

  # A closed-set value is accepted as the atom itself or as its string form;
  # a string becomes an atom only when it is already in the declared list
  # (`String.to_existing_atom/1` after the membership check), and anything
  # else is a plain "is invalid" — the Ecto.Enum cast error would otherwise
  # carry a type tuple that the API error renderer cannot interpolate.
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

  defp validate_not_future(changeset, today) do
    validate_change(changeset, :as_of, fn :as_of, as_of ->
      if Date.compare(as_of, today) == :gt,
        do: [as_of: {"must not be in the future", validation: :not_future}],
        else: []
    end)
  end

  @doc """
  The day an entry counts as a review on (E25 S6, F44): its `as_of`, but no
  later than the day it was written. An entry stored with a future `as_of`
  before the refusal existed would otherwise keep its position off the
  review-hygiene read until that date. `inserted_at` is UTC and `as_of` the
  instance's day, so the written day carries one day of slack for a host
  east of UTC — no entry the refusal accepts is ever moved.
  """
  @spec review_date(t()) :: Date.t()
  def review_date(%__MODULE__{as_of: as_of, inserted_at: %NaiveDateTime{} = inserted_at}) do
    written = inserted_at |> NaiveDateTime.to_date() |> Date.add(1)
    if Date.compare(as_of, written) == :gt, do: written, else: as_of
  end

  def review_date(%__MODULE__{as_of: as_of}), do: as_of

  # ADR-0044 §4: an extracted entry is a proposal carrying its source link.
  defp validate_machine_generated_source(changeset) do
    if get_field(changeset, :machine_generated) == true and
         is_nil(get_field(changeset, :source_url)) do
      add_error(changeset, :source_url, "is required for a machine-generated entry")
    else
      changeset
    end
  end

  # ADR-0044 §3: a retraction withdraws something — it always supersedes.
  defp validate_retraction_supersedes(changeset) do
    if get_field(changeset, :kind) == :retraction and
         is_nil(get_field(changeset, :supersedes_id)) do
      add_error(changeset, :supersedes_id, "a retraction must supersede an entry")
    else
      changeset
    end
  end

  # The thesis-only fields carry no meaning on another kind; rejecting them
  # keeps the projection's inputs unambiguous.
  defp validate_thesis_fields(changeset) do
    if get_field(changeset, :kind) == :thesis do
      changeset
    else
      Enum.reduce([:conviction, :invalidation_condition, :time_stop], changeset, fn field, acc ->
        if is_nil(get_field(acc, field)),
          do: acc,
          else: add_error(acc, field, "is only recorded on a thesis entry")
      end)
    end
  end

  # S28 N5: a headline, an event type and a tone say what a kept finding or
  # result was; on a thesis, a risk or a decision they would draw a marker
  # for something that is not an event.
  defp validate_marker_fields(changeset) do
    if get_field(changeset, :kind) in [nil | @marker_kinds] do
      changeset
    else
      Enum.reduce(@marker_fields, changeset, fn field, acc ->
        if is_nil(get_field(acc, field)),
          do: acc,
          else: add_error(acc, field, "is only recorded on an evidence or event_result entry")
      end)
    end
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
