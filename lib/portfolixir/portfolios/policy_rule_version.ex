defmodule Portfolixir.Portfolios.PolicyRuleVersion do
  @moduledoc """
  One version of a policy rule (ADR-0049 §1, §2, §4): the predicate, and the
  period it is the standard, `[valid_from, valid_until]` inclusive.

  ## The predicate

  | Part | Values |
  |---|---|
  | `subject_type` | `basis` · `security` · `category` · `view` · `cash` |
  | `measure` | `weight` · `drift` · `hhi` · `volatility` · `max_drawdown` |
  | `kind` | `cap` (breached strictly above `threshold`) · `floor` (strictly below) · `band` (outside `[lower, upper]`) |
  | `window` | `30d` · `90d` · `365d`, exactly for `volatility` and `max_drawdown` |
  | `severity` | `warn` · `hard`, the risk lens's vocabulary |

  The subject references are `security_id` (a security), `classification_id`
  plus `category_id` (a category), and `subject_view_id` (a view). A
  **security read for drift** also names the `classification_id` whose plan
  carries its position target: a position target lives in one
  classification's plan (ADR-0030), so "the drift of this security" is only
  one figure once the plan is named.

  ## The measure matrix (§2) and the scales (§8)

  | Measure | Subjects | Scale of the thresholds |
  |---|---|---|
  | `weight` | security · category · cash · view | percent, `[0, 100]` |
  | `drift` | category · security | percentage points, `[−100, 100]` |
  | `hhi` | basis | `[0, 10000]` |
  | `volatility` | basis | percent, annualized, `≥ 0` |
  | `max_drawdown` | basis | percent in the metric's own sign, `[−100, 0]` |

  ADR-0049 §8 names the first four bounds; the drawdown's follows from the
  metric's sign (a drawdown is a decline, `≤ 0`) and is stated here so a
  floor of `+20` — a rule that can never be met — is refused at the write.

  The closed sets are `Ecto.Enum` fields resolved from input with
  `String.to_existing_atom/1` **only after** the string was found in the
  declared list, so an unknown string is a plain `"is invalid"` and never a
  new atom (the hard rule). The database mirrors every set, the matrix, the
  subject shape and the threshold shape as CHECK constraints.

  ## Immutability

  A version whose `valid_from` has been reached is the standard of a period
  that already happened: it is never updated and never deleted, except that
  its `valid_until` is set when an edit or a retirement closes it. That rule
  lives in `Portfolixir.Portfolios.PolicyRules` against the host's calendar
  day, and the database refuses a bypassing write through a trigger.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Input.BoundedDate
  alias Portfolixir.Input.Text
  alias Portfolixir.Portfolios.PolicyRule

  @subject_types ~w(basis security category view cash)a
  @measures ~w(weight drift hhi volatility max_drawdown)a
  @kinds ~w(cap floor band)a
  @severities ~w(warn hard)a
  @windows [:"30d", :"90d", :"365d"]

  @metric_measures [:volatility, :max_drawdown]

  @matrix %{
    weight: [:security, :category, :cash, :view],
    drift: [:category, :security],
    hhi: [:basis],
    volatility: [:basis],
    max_drawdown: [:basis]
  }

  @scales %{
    weight: {Decimal.new(0), Decimal.new(100)},
    drift: {Decimal.new(-100), Decimal.new(100)},
    hhi: {Decimal.new(0), Decimal.new(10_000)},
    volatility: {Decimal.new(0), nil},
    max_drawdown: {Decimal.new(-100), Decimal.new(0)}
  }

  @type t :: %__MODULE__{}

  schema "policy_rule_versions" do
    field(:subject_type, Ecto.Enum, values: @subject_types)
    field(:security_id, :integer)
    field(:classification_id, :integer)
    field(:category_id, :integer)
    field(:subject_view_id, :integer)
    field(:measure, Ecto.Enum, values: @measures)
    field(:kind, Ecto.Enum, values: @kinds)
    field(:threshold, :decimal)
    field(:lower, :decimal)
    field(:upper, :decimal)
    # `window` is an SQL keyword; the column is `metric_window`.
    field(:window, Ecto.Enum, values: @windows, source: :metric_window)
    field(:severity, Ecto.Enum, values: @severities)
    field(:note, :string)
    field(:valid_from, :date)
    field(:valid_until, :date)

    belongs_to(:policy_rule, PolicyRule)

    timestamps()
  end

  @doc """
  Every field of a version's predicate and period, as strings: what a rename
  of the rule refuses to carry (#872), because it belongs to a version.
  """
  def predicate_fields do
    (__schema__(:fields) -- [:id, :policy_rule_id, :inserted_at, :updated_at])
    |> Enum.map(&Atom.to_string/1)
  end

  @doc "The closed subject set, as strings (API/MCP schema mirror)."
  def subject_types, do: Enum.map(@subject_types, &Atom.to_string/1)

  @doc "The closed measure set, as strings."
  def measures, do: Enum.map(@measures, &Atom.to_string/1)

  @doc "The closed kind set, as strings."
  def kinds, do: Enum.map(@kinds, &Atom.to_string/1)

  @doc "The closed severity set, as strings."
  def severities, do: Enum.map(@severities, &Atom.to_string/1)

  @doc "The ADR-0047 windows a metric rule reads, as strings."
  def windows, do: Enum.map(@windows, &Atom.to_string/1)

  @doc "The subjects each measure is read for (§2)."
  @spec matrix() :: %{atom() => [atom()]}
  def matrix, do: @matrix

  @doc "The `{min, max}` bounds of a measure's thresholds (`nil` = unbounded)."
  @spec scale(atom()) :: {Decimal.t(), Decimal.t() | nil}
  def scale(measure), do: Map.fetch!(@scales, measure)

  @doc "Whether a measure reads an ADR-0047 portfolio metric (and so a window)."
  @spec metric_measure?(atom()) :: boolean()
  def metric_measure?(measure), do: measure in @metric_measures

  # The predicate: everything the version says about the standard. Excludes
  # `valid_until`, which the context sets when it closes a version, and the
  # rule reference, which the context sets from the rule itself.
  @predicate ~w(security_id classification_id category_id subject_view_id threshold lower
                upper note valid_from)a

  @closed_sets [
    subject_type: @subject_types,
    measure: @measures,
    kind: @kinds,
    severity: @severities,
    window: @windows
  ]

  @doc """
  The changeset of a new version's predicate. `policy_rule_id` is set by the
  context; `valid_until` only ever by the context closing a version.
  """
  def changeset(version, attrs) do
    version
    |> cast(attrs, [:policy_rule_id | @predicate])
    |> cast_closed_sets(attrs)
    |> update_change(:note, &trim_text/1)
    |> validate_required([
      :policy_rule_id,
      :subject_type,
      :measure,
      :kind,
      :severity,
      :valid_from
    ])
    # E25 S4, F70: the start a rule is checked against is the start stored.
    |> BoundedDate.validate([:valid_from])
    |> Text.validate(:note, multiline: true, max: Text.free_text_max())
    |> validate_matrix()
    |> validate_subject()
    |> validate_window()
    |> validate_thresholds()
    |> foreign_key_constraint(:policy_rule_id)
    |> foreign_key_constraint(:security_id)
    |> foreign_key_constraint(:classification_id)
    |> foreign_key_constraint(:category_id)
    |> foreign_key_constraint(:subject_view_id)
    |> check_constraint(:subject_type, name: :policy_rule_versions_subject_type_check)
    |> check_constraint(:measure, name: :policy_rule_versions_measure_check)
    |> check_constraint(:kind, name: :policy_rule_versions_kind_check)
    |> check_constraint(:severity, name: :policy_rule_versions_severity_check)
    |> check_constraint(:window, name: :policy_rule_versions_window_check)
    |> check_constraint(:subject_type, name: :policy_rule_versions_matrix_check)
    |> check_constraint(:subject_type, name: :policy_rule_versions_subject_check)
    |> check_constraint(:threshold, name: :policy_rule_versions_thresholds_check)
    |> check_constraint(:valid_until, name: :policy_rule_versions_period_check)
    |> check_constraint(:note, name: :policy_rule_versions_note_length_check)
    |> exclusion_constraint(:valid_from,
      name: :policy_rule_versions_no_overlap,
      message: "overlaps another version of this rule"
    )
  end

  @doc """
  The changeset that closes a version: only `valid_until` moves (§4).
  """
  def close_changeset(version, valid_until) do
    version
    |> change(valid_until: valid_until)
    |> check_constraint(:valid_until, name: :policy_rule_versions_period_check)
    |> exclusion_constraint(:valid_until,
      name: :policy_rule_versions_no_overlap,
      message: "overlaps another version of this rule"
    )
  end

  # §2: the subject must fit the measure.
  defp validate_matrix(changeset) do
    measure = get_field(changeset, :measure)
    subject = get_field(changeset, :subject_type)

    cond do
      is_nil(measure) or is_nil(subject) ->
        changeset

      subject in Map.fetch!(@matrix, measure) ->
        changeset

      true ->
        add_error(changeset, :subject_type, "does not fit the measure %{measure}",
          measure: measure
        )
    end
  end

  # §1: each subject carries exactly its own reference.
  defp validate_subject(changeset) do
    case get_field(changeset, :subject_type) do
      :security ->
        changeset
        |> validate_required([:security_id])
        |> validate_absent([:category_id, :subject_view_id])
        |> validate_drift_classification()

      :category ->
        changeset
        |> validate_required([:classification_id, :category_id])
        |> validate_absent([:security_id, :subject_view_id])

      :view ->
        changeset
        |> validate_required([:subject_view_id])
        |> validate_absent([:security_id, :classification_id, :category_id])

      subject when subject in [:basis, :cash] ->
        validate_absent(changeset, [
          :security_id,
          :classification_id,
          :category_id,
          :subject_view_id
        ])

      nil ->
        changeset
    end
  end

  # A security's drift is read from one classification's plan; any other
  # measure on a security does not name one.
  defp validate_drift_classification(changeset) do
    if get_field(changeset, :measure) == :drift do
      validate_required(changeset, [:classification_id],
        message: "is required for the drift of a security (the plan's classification)"
      )
    else
      validate_absent(changeset, [:classification_id])
    end
  end

  defp validate_absent(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, acc ->
      if is_nil(get_field(acc, field)),
        do: acc,
        else: add_error(acc, field, "is not recorded on this subject")
    end)
  end

  # §2: the window is present exactly for the metric measures.
  defp validate_window(changeset) do
    measure = get_field(changeset, :measure)
    window = get_field(changeset, :window)

    cond do
      is_nil(measure) ->
        changeset

      metric_measure?(measure) and is_nil(window) ->
        add_error(changeset, :window, "is required for %{measure}", measure: measure)

      not metric_measure?(measure) and not is_nil(window) ->
        add_error(changeset, :window, "is only recorded on volatility and max_drawdown")

      true ->
        changeset
    end
  end

  # §1, §8: a cap or floor carries one threshold, a band lower ≤ upper, and
  # every figure lies on the measure's scale.
  defp validate_thresholds(changeset) do
    case get_field(changeset, :kind) do
      kind when kind in [:cap, :floor] ->
        changeset
        |> validate_required([:threshold])
        |> validate_absent([:lower, :upper])
        |> validate_on_scale([:threshold])

      :band ->
        changeset
        |> validate_required([:lower, :upper])
        |> validate_absent([:threshold])
        |> validate_on_scale([:lower, :upper])
        |> validate_band_order()

      nil ->
        changeset
    end
  end

  defp validate_band_order(changeset) do
    lower = get_field(changeset, :lower)
    upper = get_field(changeset, :upper)

    if match?(%Decimal{}, lower) and match?(%Decimal{}, upper) and
         Decimal.compare(lower, upper) == :gt,
       do: add_error(changeset, :upper, "must be at least lower"),
       else: changeset
  end

  defp validate_on_scale(changeset, fields) do
    case get_field(changeset, :measure) do
      nil ->
        changeset

      measure ->
        {min, max} = scale(measure)
        Enum.reduce(fields, changeset, &validate_figure(&2, &1, min, max))
    end
  end

  defp validate_figure(changeset, field, min, max) do
    case get_field(changeset, field) do
      %Decimal{} = value ->
        cond do
          Decimal.nan?(value) or Decimal.inf?(value) ->
            add_error(changeset, field, "is invalid")

          Decimal.compare(value, min) == :lt ->
            add_error(changeset, field, "must be at least %{min}", min: min)

          max && Decimal.compare(value, max) == :gt ->
            add_error(changeset, field, "must be at most %{max}", max: max)

          true ->
            changeset
        end

      _absent ->
        changeset
    end
  end

  # A closed-set value is accepted as the atom itself or as its string form; a
  # string becomes an atom only when it is already in the declared list
  # (`String.to_existing_atom/1` after the membership check), and anything
  # else is a plain "is invalid".
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
    if value in Enum.map(allowed, &Atom.to_string/1),
      do: put_change(changeset, field, String.to_existing_atom(value)),
      else: add_error(changeset, field, "is invalid")
  end

  defp fetch_attr(attrs, field) do
    cond do
      Map.has_key?(attrs, field) -> {:ok, Map.get(attrs, field)}
      Map.has_key?(attrs, Atom.to_string(field)) -> {:ok, Map.get(attrs, Atom.to_string(field))}
      true -> :absent
    end
  end

  defp trim_text(value) when is_binary(value), do: String.trim(value)
  defp trim_text(value), do: value
end
