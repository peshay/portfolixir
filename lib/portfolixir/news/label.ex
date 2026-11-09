defmodule Portfolixir.News.Label do
  @moduledoc """
  What an outside model says about one story (ADR-0056 §7): its event type,
  materiality, tone and confidence, optionally the clause of a thesis it
  touches and a security it suggests, under the model and prompt version
  that produced it. Written through `Portfolixir.News.Labels.put/2` only.

  **The fields** (§7): `cluster_id`, `model`, `prompt_version`,
  `event_type` (`earnings`, `guidance`, `capital_measure`, `legal`,
  `m_and_a`, `product`, `regulatory`, `macro`, `noise`), `materiality` 0 to
  3, `tone` -1, 0 or +1, optional `thesis_note_id` and `clause_idx`,
  `confidence` (a decimal from 0 to 1, at most four places), optional
  `suggested_security_id`, `machine_generated` (always true: a label is a
  proposal, NFR-10), and the server's `created_at` and `updated_at`.

  **Identifiers:** `model` and `prompt_version` are 1 to 64 characters of
  letters, digits and `. _ : / @ + -`, starting with a letter or a digit,
  and pass `Portfolixir.Input.Text`'s rule first, so an invisible character
  is refused naming its code point (ADR-0054 §4).

  The changeset reads values whose JSON types the write has checked
  (`Portfolixir.News.Labels`); the event type is looked up in a fixed map,
  never made into an atom from input. Each rule mirrors a CHECK of the
  `create_news_labels` migration.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Input.Text

  @event_types ~w(earnings guidance capital_measure legal m_and_a product regulatory macro noise)a
  @event_type_by_name Map.new(@event_types, &{Atom.to_string(&1), &1})

  @identifier_max 64
  @identifier ~r/\A[A-Za-z0-9][A-Za-z0-9._:\/@+-]{0,63}\z/
  @confidence ~r/\A[0-9]+(\.[0-9]+)?\z/
  @confidence_places 4
  @clause_max 10_000
  @int8_max 9_223_372_036_854_775_807

  @fields ~w(cluster_id model prompt_version event_type materiality tone thesis_note_id
             clause_idx confidence suggested_security_id machine_generated)

  @cast ~w(cluster_id model prompt_version materiality tone thesis_note_id clause_idx
           suggested_security_id machine_generated)a

  @type t :: %__MODULE__{}

  schema "news_labels" do
    field(:cluster_id, :integer)
    field(:model, :string)
    field(:prompt_version, :string)
    field(:event_type, Ecto.Enum, values: @event_types)
    field(:materiality, :integer)
    field(:tone, :integer)
    field(:thesis_note_id, :integer)
    field(:clause_idx, :integer)
    field(:confidence, :decimal)
    field(:suggested_security_id, :integer)
    field(:machine_generated, :boolean, default: true)

    timestamps(inserted_at: :created_at, type: :utc_datetime_usec)
  end

  @doc "The fields a label write takes, as the JSON names them (§7: exactly these)."
  @spec fields() :: [String.t()]
  def fields, do: @fields

  @doc "The nine event types of §7, as strings."
  @spec event_types() :: [String.t()]
  def event_types, do: Enum.map(@event_types, &Atom.to_string/1)

  @doc "Whether `value` is a model or prompt version identifier (see the moduledoc)."
  @spec identifier?(term()) :: boolean()
  def identifier?(value) when is_binary(value), do: Regex.match?(@identifier, value)
  def identifier?(_value), do: false

  @doc """
  Casts and checks a label from string-keyed `attrs` whose JSON types the
  write has already checked. A put replaces the whole label: a field
  `attrs` leaves out is cleared (`machine_generated` excepted, always true).
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(label, attrs) when is_map(attrs) do
    cleared = Map.new(@cast -- [:machine_generated], &{Atom.to_string(&1), nil})

    label
    |> cast(Map.merge(cleared, Map.take(attrs, Enum.map(@cast, &Atom.to_string/1))), @cast)
    |> put_event_type(Map.get(attrs, "event_type"))
    |> put_confidence(Map.get(attrs, "confidence"))
    |> validate_required([
      :cluster_id,
      :model,
      :prompt_version,
      :event_type,
      :materiality,
      :tone,
      :confidence,
      :machine_generated
    ])
    |> Text.validate([:model, :prompt_version], max: @identifier_max)
    |> validate_identifier(:model)
    |> validate_identifier(:prompt_version)
    |> validate_number(:cluster_id, greater_than: 0, less_than_or_equal_to: @int8_max)
    |> validate_number(:materiality, greater_than_or_equal_to: 0, less_than_or_equal_to: 3)
    |> validate_inclusion(:tone, [-1, 0, 1], message: "must be -1, 0 or 1")
    |> validate_number(:thesis_note_id, greater_than: 0, less_than_or_equal_to: @int8_max)
    |> validate_number(:suggested_security_id,
      greater_than: 0,
      less_than_or_equal_to: @int8_max
    )
    |> validate_number(:clause_idx,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: @clause_max
    )
    |> validate_clause()
    |> validate_inclusion(:machine_generated, [true],
      message: "is always true: a label is a machine's proposal (NFR-10)"
    )
    |> unique_constraint([:cluster_id, :model, :prompt_version],
      name: :news_labels_cluster_model_version_index
    )
    |> foreign_key_constraint(:thesis_note_id, name: :news_labels_thesis_note_id_fkey)
    |> check_constraint(:cluster_id, name: :news_labels_cluster_id_check, message: "is invalid")
    |> check_constraint(:event_type, name: :news_labels_event_type_check, message: "is invalid")
    |> check_constraint(:materiality, name: :news_labels_materiality_check, message: "is invalid")
    |> check_constraint(:tone, name: :news_labels_tone_check, message: "is invalid")
    |> check_constraint(:confidence, name: :news_labels_confidence_check, message: "is invalid")
    |> check_constraint(:machine_generated,
      name: :news_labels_machine_generated_check,
      message: "is invalid"
    )
    |> check_constraint(:model, name: :news_labels_model_check, message: "is invalid")
    |> check_constraint(:prompt_version,
      name: :news_labels_prompt_version_check,
      message: "is invalid"
    )
    |> check_constraint(:clause_idx, name: :news_labels_clause_check, message: "is invalid")
    |> check_constraint(:suggested_security_id,
      name: :news_labels_suggested_security_id_check,
      message: "is invalid"
    )
  end

  # The event type is looked up in a fixed map: a value outside the nine is
  # a field error naming them, and no atom is ever made from input.
  defp put_event_type(changeset, nil), do: put_change(changeset, :event_type, nil)

  defp put_event_type(changeset, name) do
    case Map.fetch(@event_type_by_name, name) do
      {:ok, type} ->
        put_change(changeset, :event_type, type)

      :error ->
        add_error(changeset, :event_type, "must be one of %{types}",
          types: Enum.join(event_types(), ", "),
          validation: :inclusion
        )
    end
  end

  # A plain decimal string (no sign, exponent or space), from 0 to 1, with at
  # most four places: the database's `trunc(confidence, 4)` check, refused
  # here with a field error rather than rounded.
  defp put_confidence(changeset, nil), do: put_change(changeset, :confidence, nil)

  defp put_confidence(changeset, text) when is_binary(text) do
    with true <- byte_size(text) <= 32 and Regex.match?(@confidence, text),
         {:ok, value} <- Decimal.cast(text),
         true <- in_unit_range?(value) and places(value) <= @confidence_places do
      put_change(changeset, :confidence, Decimal.normalize(value))
    else
      _refused ->
        add_error(
          changeset,
          :confidence,
          "must be a decimal string from 0 to 1 with at most %{places} places",
          places: @confidence_places,
          validation: :format
        )
    end
  end

  defp in_unit_range?(value),
    do: Decimal.compare(value, 0) != :lt and Decimal.compare(value, 1) != :gt

  defp places(%Decimal{} = value),
    do: value |> Decimal.normalize() |> Map.fetch!(:exp) |> min(0) |> abs()

  # Text's refusal first, naming an invisible character by its code point;
  # the shape only of a value that passed it.
  defp validate_identifier(changeset, field) do
    if Keyword.has_key?(changeset.errors, field),
      do: changeset,
      else: identifier_format(changeset, field)
  end

  defp identifier_format(changeset, field) do
    validate_format(changeset, field, @identifier,
      message:
        "must be 1 to 64 letters, digits or . _ : / @ + -, starting with a letter or a digit"
    )
  end

  defp validate_clause(changeset) do
    if get_field(changeset, :clause_idx) && is_nil(get_field(changeset, :thesis_note_id)),
      do:
        add_error(changeset, :clause_idx, "needs thesis_note_id: a clause is one of a thesis's"),
      else: changeset
  end
end
