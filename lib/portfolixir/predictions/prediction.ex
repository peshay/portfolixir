defmodule Portfolixir.Predictions.Prediction do
  @moduledoc """
  One prediction (ADR-0055 §1): a permanent record of one call on one
  security — it `outperform`s or `underperform`s a benchmark by
  `resolves_on`, with a stated `probability`.

  Rows are **append-only** (§2): never updated, never deleted, never
  withdrawn. The schema has no timestamps but `made_at`, and the database
  refuses UPDATE, DELETE and TRUNCATE (the `create_predictions` migration).

  The fields the caller states are cast here; the three the system states
  are not:

    * `made_at` — the server's clock at the write, UTC; a caller's
      `made_at` is refused, because a prediction dated in the past is one
      made with its outcome in view (§1);
    * `author` — `:operator` or `:agent`, derived from the credential
      (`Portfolixir.Actor.author/1`, ADR-0054 §1); a caller's `author` is
      refused;
    * `actor` — the name of the token that wrote it (the journal's actor
      label), `nil` for the operator's pages and an unnamed token; a
      caller's `actor` is refused.

  The benchmark is ADR-0046's two kinds, spelled in the input as
  `benchmark=` spells them — `"security:<id>"` or `"rate:<decimal>"` — and
  stored as `benchmark_kind` with exactly one of `benchmark_security_id`
  (a foreign key, so a benchmark security restricts its delete as the
  security does) and `benchmark_rate`. `benchmark/1` spells it back.

  `probability` and `benchmark_rate` are `Decimal`s, never floats; a float
  given for the probability is refused rather than converted.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Input.BoundedDate
  alias Portfolixir.Input.BoundedDecimal
  alias Portfolixir.Input.Text
  alias Portfolixir.Knowledge.SecurityNote
  alias Portfolixir.Portfolios.Performance.Benchmark

  @directions ~w(outperform underperform)a
  @authors ~w(operator agent)a
  @benchmark_kinds ~w(security rate)a

  @min_probability Decimal.new("0.50")
  @max_probability Decimal.new("0.99")
  @min_days 7
  @max_days 1830
  @model_max 100
  @rationale_max 4000
  # The width of `predictions.actor` (character varying(255)).
  @actor_max 255

  # The keys the system states and a caller may not (§1; ADR-0054 §1).
  @system_keys ~w(made_at author actor)a

  @type direction :: :outperform | :underperform
  @type author :: :operator | :agent

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          security_id: pos_integer() | nil,
          direction: direction() | nil,
          probability: Decimal.t() | nil,
          benchmark_kind: :security | :rate | nil,
          benchmark_security_id: pos_integer() | nil,
          benchmark_rate: Decimal.t() | nil,
          resolves_on: Date.t() | nil,
          made_at: DateTime.t() | nil,
          author: author() | nil,
          actor: String.t() | nil,
          model: String.t() | nil,
          note_id: pos_integer() | nil,
          rationale: String.t() | nil
        }

  schema "predictions" do
    field(:direction, Ecto.Enum, values: @directions)
    field(:probability, :decimal)
    field(:benchmark_kind, Ecto.Enum, values: @benchmark_kinds)
    field(:benchmark_rate, :decimal)
    field(:resolves_on, :date)
    field(:made_at, :utc_datetime_usec)
    field(:author, Ecto.Enum, values: @authors)
    field(:actor, :string)
    field(:model, :string)
    field(:rationale, :string)

    belongs_to(:security, Security)
    belongs_to(:benchmark_security, Security)
    belongs_to(:note, SecurityNote)
  end

  @doc "The closed direction set, as strings (API/MCP schema mirror)."
  @spec directions() :: [String.t()]
  def directions, do: Enum.map(@directions, &Atom.to_string/1)

  @doc "The closed author set, as strings."
  @spec authors() :: [String.t()]
  def authors, do: Enum.map(@authors, &Atom.to_string/1)

  @doc "The smallest probability a call states: `0.50`."
  @spec min_probability() :: Decimal.t()
  def min_probability, do: @min_probability

  @doc "The largest probability a call states: `0.99`."
  @spec max_probability() :: Decimal.t()
  def max_probability, do: @max_probability

  @doc "The fewest days `resolves_on` lies after the UTC day of `made_at`: 7."
  @spec min_days() :: pos_integer()
  def min_days, do: @min_days

  @doc "The most days `resolves_on` lies after the UTC day of `made_at`: 1,830."
  @spec max_days() :: pos_integer()
  def max_days, do: @max_days

  @doc "The longest `model` in characters: 100."
  @spec model_max() :: pos_integer()
  def model_max, do: @model_max

  @doc "The longest `rationale` in characters: 4,000."
  @spec rationale_max() :: pos_integer()
  def rationale_max, do: @rationale_max

  @doc """
  The benchmark as `benchmark=` spells it (ADR-0046 §4):
  `"security:<id>"` or `"rate:<decimal>"`.
  """
  @spec benchmark(t()) :: String.t()
  def benchmark(%__MODULE__{benchmark_kind: :security, benchmark_security_id: id})
      when is_integer(id),
      do: "security:#{id}"

  def benchmark(%__MODULE__{benchmark_kind: :rate, benchmark_rate: %Decimal{} = rate}),
    do: "rate:" <> Decimal.to_string(rate, :normal)

  @doc """
  The UTC day a prediction was made on, from which `resolves_on` is
  bounded (§1) and before which its start close lies (§3).
  """
  @spec made_on(t() | DateTime.t()) :: Date.t()
  def made_on(%__MODULE__{made_at: %DateTime{} = made_at}), do: made_on(made_at)

  def made_on(%DateTime{} = made_at),
    do: made_at |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_date()

  @castable ~w(security_id resolves_on note_id model rationale)a

  @doc """
  Builds a new prediction's changeset from the caller's `attrs` and the
  three values the system states: `made_at` (a UTC `DateTime`, the
  server's clock), `author` and `actor` (from the credential). A caller's
  `made_at`, `author` or `actor` in `attrs` is refused by name, so a caller
  learns that the server states them.

  The references are checked here only for their shape; that the security
  exists, that a benchmark security exists and is flagged `is_benchmark`,
  and that a linked note is an entry of the same security is the
  context's to read (`Portfolixir.Predictions.create_prediction/3`), with
  the database's foreign keys behind it.
  """
  @spec changeset(t(), map(), %{made_at: DateTime.t(), author: author(), actor: String.t() | nil}) ::
          Ecto.Changeset.t()
  def changeset(%__MODULE__{} = prediction, attrs, %{made_at: %DateTime{} = made_at} = system)
      when is_map(attrs) do
    prediction
    |> cast(attrs, @castable)
    |> refuse_system_keys(attrs)
    |> put_change(:made_at, to_usec(made_at))
    |> put_change(:author, Map.fetch!(system, :author))
    |> put_change(:actor, Map.get(system, :actor))
    |> cast_direction(attrs)
    |> cast_probability(attrs)
    |> cast_benchmark(attrs)
    |> update_change(:model, &blank_to_nil/1)
    |> update_change(:rationale, &blank_to_nil/1)
    |> validate_required([:security_id, :direction, :probability, :resolves_on])
    |> BoundedDate.validate([:resolves_on])
    |> validate_probability()
    |> validate_resolves_on(made_at)
    |> validate_model()
    |> validate_benchmark_differs()
    |> Text.validate(:model, max: @model_max)
    |> Text.validate(:rationale, multiline: true, max: @rationale_max)
    |> Text.validate(:actor, max: @actor_max)
    |> foreign_key_constraint(:security_id, name: :predictions_security_id_fkey)
    |> foreign_key_constraint(:benchmark,
      name: :predictions_benchmark_security_id_fkey,
      message: "is not a benchmark security"
    )
    |> foreign_key_constraint(:note_id,
      name: :predictions_note_id_fkey,
      message: "must reference a research-log entry of the same security"
    )
    |> check_constraint(:direction, name: :predictions_direction_check)
    |> check_constraint(:probability, name: :predictions_probability_check)
    |> check_constraint(:benchmark, name: :predictions_benchmark_check)
    |> check_constraint(:benchmark, name: :predictions_benchmark_rate_check)
    |> check_constraint(:benchmark, name: :predictions_benchmark_security_check)
    |> check_constraint(:resolves_on, name: :predictions_resolves_on_check)
    |> check_constraint(:author, name: :predictions_author_check)
    |> check_constraint(:model, name: :predictions_model_check)
    |> check_constraint(:rationale, name: :predictions_rationale_length_check)
  end

  defp refuse_system_keys(changeset, attrs) do
    Enum.reduce(@system_keys, changeset, fn key, acc ->
      if Map.has_key?(attrs, key) or Map.has_key?(attrs, Atom.to_string(key)),
        do: add_error(acc, key, system_key_message(key), validation: :system_stated),
        else: acc
    end)
  end

  defp system_key_message(:made_at),
    do:
      "is the server's clock at the write and cannot be given: a prediction is never " <>
        "dated in the past"

  defp system_key_message(:author),
    do: "is derived from the credential that writes the prediction and cannot be given"

  defp system_key_message(:actor),
    do: "is the name of the token that writes the prediction and cannot be given"

  # A closed-set value is accepted as the atom itself or as its string form;
  # a string becomes an atom only when it is already in the declared list,
  # so an unknown string is a plain "is invalid" and never a new atom.
  defp cast_direction(changeset, attrs) do
    case fetch_attr(attrs, :direction) do
      {:ok, value} when value in [nil, ""] -> changeset
      {:ok, value} when value in @directions -> put_change(changeset, :direction, value)
      {:ok, value} when is_binary(value) -> put_direction_string(changeset, value)
      {:ok, _other} -> add_error(changeset, :direction, "is invalid")
      :absent -> changeset
    end
  end

  defp put_direction_string(changeset, value) do
    if value in directions(),
      do: put_change(changeset, :direction, String.to_existing_atom(value)),
      else: add_error(changeset, :direction, "must be outperform or underperform")
  end

  # A decimal string ("0.70") or a Decimal; a float or an integer is refused
  # rather than converted, so no binary float ever becomes a stated belief.
  defp cast_probability(changeset, attrs) do
    case fetch_attr(attrs, :probability) do
      {:ok, value} when value in [nil, ""] ->
        changeset

      {:ok, %Decimal{} = value} ->
        if BoundedDecimal.finite?(value),
          do: put_change(changeset, :probability, value),
          else: add_error(changeset, :probability, probability_shape_message())

      {:ok, value} when is_binary(value) ->
        case BoundedDecimal.parse(String.trim(value)) do
          {:ok, decimal} -> put_change(changeset, :probability, decimal)
          :error -> add_error(changeset, :probability, probability_shape_message())
        end

      {:ok, _other} ->
        add_error(changeset, :probability, probability_shape_message())

      :absent ->
        changeset
    end
  end

  defp probability_shape_message,
    do: ~s(must be a decimal string from "0.50" to "0.99", such as "0.70")

  # §1: from 0.50 to 0.99 in steps of 0.01. Below 0.50 is the opposite call
  # above it, so the refusal names the other direction and its probability.
  defp validate_probability(changeset) do
    validate_change(changeset, :probability, fn :probability, value ->
      cond do
        Decimal.compare(value, @min_probability) == :lt ->
          [probability: {below_minimum_message(changeset, value), validation: :probability}]

        Decimal.compare(value, @max_probability) == :gt ->
          [
            probability:
              {"must be at most 0.99: a call stated as certain cannot be scored for " <>
                 "calibration", validation: :probability}
          ]

        BoundedDecimal.decimal_places(value) > 2 ->
          [
            probability:
              {"must be in steps of 0.01, such as 0.55 or 0.56", validation: :probability}
          ]

        true ->
          []
      end
    end)
    |> update_change(:probability, &normalize_probability/1)
  end

  defp normalize_probability(%Decimal{} = value) do
    if BoundedDecimal.decimal_places(value) <= 2, do: Decimal.round(value, 2), else: value
  end

  defp below_minimum_message(changeset, value) do
    complement = Decimal.sub(Decimal.new(1), value)

    other =
      case get_field(changeset, :direction) do
        :outperform -> "underperform"
        :underperform -> "outperform"
        _unknown -> "the other direction"
      end

    "must be at least 0.50: a call below 50 % is the opposite call, so record it as " <>
      "#{other} with probability #{Decimal.to_string(complement, :normal)}"
  end

  # The benchmark arrives as `benchmark=` spells it and is stored as its
  # kind with exactly one of the two columns.
  defp cast_benchmark(changeset, attrs) do
    case fetch_attr(attrs, :benchmark) do
      {:ok, value} when is_binary(value) and value != "" -> put_benchmark(changeset, value)
      {:ok, value} when value in [nil, ""] -> add_error(changeset, :benchmark, "can't be blank")
      {:ok, _other} -> add_error(changeset, :benchmark, benchmark_shape_message())
      :absent -> add_error(changeset, :benchmark, "can't be blank", validation: :required)
    end
  end

  defp put_benchmark(changeset, "security:" <> raw) do
    case parse_id(raw) do
      {:ok, id} ->
        changeset
        |> put_change(:benchmark_kind, :security)
        |> put_change(:benchmark_security_id, id)

      :error ->
        add_error(changeset, :benchmark, benchmark_shape_message())
    end
  end

  # The rule a remembered benchmark selector is read by (ADR-0046 §4): a
  # finite decimal inside the engine's bound and exact at its scale.
  defp put_benchmark(changeset, "rate:" <> raw) do
    with {:ok, rate} <- BoundedDecimal.parse(raw),
         {:ok, rate} <- Benchmark.exact_rate(rate) do
      changeset
      |> put_change(:benchmark_kind, :rate)
      |> put_change(:benchmark_rate, rate)
    else
      :error ->
        add_error(
          changeset,
          :benchmark,
          "rate must be a decimal annual rate from -0.999999 to 10, such as rate:0.02 for 2 % " <>
            "a year or rate:0 for an absolute call"
        )
    end
  end

  defp put_benchmark(changeset, _other),
    do: add_error(changeset, :benchmark, benchmark_shape_message())

  defp benchmark_shape_message,
    do: "must be security:<id> of a benchmark security or rate:<decimal>, such as rate:0"

  # A positive id inside the bigint range, as the API's id parser reads one.
  @max_int8 9_223_372_036_854_775_807
  defp parse_id(raw) do
    case Integer.parse(raw) do
      {id, ""} when id > 0 and id <= @max_int8 -> {:ok, id}
      _malformed -> :error
    end
  end

  defp validate_benchmark_differs(changeset) do
    security_id = get_field(changeset, :security_id)
    benchmark_id = get_field(changeset, :benchmark_security_id)

    if is_integer(security_id) and security_id == benchmark_id,
      do: add_error(changeset, :benchmark, "must differ from the security the call is about"),
      else: changeset
  end

  # §1: at least 7 and at most 1,830 days after the UTC day it is made.
  defp validate_resolves_on(changeset, made_at) do
    made_on = made_on(made_at)
    earliest = Date.add(made_on, @min_days)
    latest = Date.add(made_on, @max_days)

    validate_change(changeset, :resolves_on, fn :resolves_on, date ->
      cond do
        not match?(%Date{}, date) ->
          []

        Date.compare(date, earliest) == :lt ->
          [
            resolves_on:
              {"must be at least #{@min_days} days after the day the prediction is made " <>
                 "(#{Date.to_iso8601(made_on)}, UTC): #{Date.to_iso8601(earliest)} or later",
               validation: :resolves_on}
          ]

        Date.compare(date, latest) == :gt ->
          [
            resolves_on:
              {"must be at most #{@max_days} days after the day the prediction is made " <>
                 "(#{Date.to_iso8601(made_on)}, UTC): #{Date.to_iso8601(latest)} or earlier",
               validation: :resolves_on}
          ]

        true ->
          []
      end
    end)
  end

  # §1: the model an agent runs on is required, because models change under
  # one token; the operator runs on none.
  defp validate_model(changeset) do
    case {get_field(changeset, :author), get_field(changeset, :model)} do
      {:agent, nil} ->
        add_error(
          changeset,
          :model,
          "is required for an agent's prediction: name the model you run on",
          validation: :required
        )

      {:operator, model} when is_binary(model) ->
        add_error(
          changeset,
          :model,
          "is recorded only for an agent's prediction; the operator's carries none"
        )

      _fine ->
        changeset
    end
  end

  # The column is :utc_datetime_usec, which refuses a value of lower
  # precision rather than padding it: a clock reading on a whole second
  # (~U[... 15:00:00Z]) is the same instant at microsecond precision.
  defp to_usec(%DateTime{microsecond: {microsecond, _precision}} = made_at),
    do: %{made_at | microsecond: {microsecond, 6}}

  defp fetch_attr(attrs, field) do
    cond do
      Map.has_key?(attrs, field) -> {:ok, Map.get(attrs, field)}
      Map.has_key?(attrs, Atom.to_string(field)) -> {:ok, Map.get(attrs, Atom.to_string(field))}
      true -> :absent
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
