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
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.Security

  @kinds ~w(thesis evidence invalidation_check event_result risk retraction decision)a
  @source_qualities ~w(primary secondary_multi awareness unverified)a
  @authors ~w(operator agent local_model)a
  @convictions ~w(low medium high)a

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

  @castable ~w(
    security_id machine_generated body source_url
    as_of supersedes_id valid_until invalidation_condition time_stop
  )a

  @closed_sets [
    author: @authors,
    kind: @kinds,
    source_quality: @source_qualities,
    conviction: @convictions
  ]

  @doc false
  def changeset(note, attrs) do
    note
    |> cast(attrs, @castable)
    |> cast_closed_sets(attrs)
    |> update_change(:body, &trim/1)
    |> update_change(:source_url, &blank_to_nil/1)
    |> update_change(:invalidation_condition, &blank_to_nil/1)
    |> validate_required([:security_id, :author, :kind, :body, :source_quality, :as_of])
    |> validate_length(:body, min: 1)
    |> validate_machine_generated_source()
    |> validate_retraction_supersedes()
    |> validate_thesis_fields()
    |> foreign_key_constraint(:security_id)
    |> foreign_key_constraint(:supersedes_id)
    |> check_constraint(:kind, name: :security_notes_kind_check)
    |> check_constraint(:source_quality, name: :security_notes_source_quality_check)
    |> check_constraint(:author, name: :security_notes_author_check)
    |> check_constraint(:conviction, name: :security_notes_conviction_check)
    |> check_constraint(:source_url, name: :security_notes_machine_generated_source_check)
    |> check_constraint(:supersedes_id, name: :security_notes_retraction_supersedes_check)
  end

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
