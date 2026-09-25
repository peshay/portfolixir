defmodule Portfolixir.Input.BoundedDecimal do
  @moduledoc """
  The decimal bounds every writer and every query parser share (E25 S4).

    * `parse/1` and `finite?/1` — a decimal from outside is a clean, finite
      value or it is refused. `Decimal.parse/1` also accepts `NaN` and
      `Infinity`, which then raise inside a comparison or silently disable a
      threshold (G15).
    * `quantize/3` — a stored amount is rounded half up to its column's scale
      before it is validated (ADR-0016 §2), so the value checked for its sign
      is the value stored, answered and journaled (G16).
    * `validate_column/3` — a magnitude past the column's precision is a field
      error, never a failed write (G17).
    * `validate_scale/3` — a value carries at most a fixed number of decimal
      places (the target weights, G14).
  """

  import Ecto.Changeset

  @doc "Whether `value` is a finite `Decimal`."
  @spec finite?(term()) :: boolean()
  def finite?(%Decimal{} = value), do: not Decimal.nan?(value) and not Decimal.inf?(value)
  def finite?(_value), do: false

  @doc """
  Parses a decimal string from a query or a form: the whole string must be one
  finite decimal. Anything else is `:error`.
  """
  @spec parse(term()) :: {:ok, Decimal.t()} | :error
  def parse(value) when is_binary(value) do
    case Decimal.parse(value) do
      {%Decimal{} = decimal, ""} -> if finite?(decimal), do: {:ok, decimal}, else: :error
      _malformed -> :error
    end
  end

  def parse(_value), do: :error

  @doc """
  Rounds a change of `field` half up to `scale` decimal places when it carries
  more (ADR-0016 §2: persistence quantises to the column's scale). A value at
  or under the scale is left exactly as given.
  """
  @spec quantize(Ecto.Changeset.t(), atom(), non_neg_integer()) :: Ecto.Changeset.t()
  def quantize(changeset, field, scale) do
    update_change(changeset, field, fn
      %Decimal{} = value ->
        if finite?(value) and decimal_places(value) > scale,
          do: Decimal.round(value, scale, :half_up),
          else: value

      other ->
        other
    end)
  end

  @doc """
  Refuses a change of `field` whose magnitude does not fit a
  `numeric(precision, scale)` column: at most `precision - scale` digits
  before the decimal point.
  """
  @spec validate_column(Ecto.Changeset.t(), atom(), {pos_integer(), non_neg_integer()}) ::
          Ecto.Changeset.t()
  def validate_column(changeset, field, {precision, scale}) do
    integer_digits = precision - scale
    limit = Decimal.new(1, 1, integer_digits)

    validate_change(changeset, field, fn ^field, value ->
      if finite?(value) and Decimal.compare(Decimal.abs(value), limit) == :lt do
        []
      else
        [
          {field,
           {"must have at most %{digits} digits before the decimal point",
            digits: integer_digits, validation: :column_range}}
        ]
      end
    end)
  end

  @doc """
  Refuses a change of `field` with more than `max_scale` decimal places;
  trailing zeros do not count.
  """
  @spec validate_scale(Ecto.Changeset.t(), atom(), non_neg_integer()) :: Ecto.Changeset.t()
  def validate_scale(changeset, field, max_scale) do
    validate_change(changeset, field, fn ^field, value ->
      if finite?(value) and decimal_places(value) <= max_scale do
        []
      else
        [
          {field,
           {"must have at most %{count} decimal places",
            count: max_scale, validation: :decimal_scale}}
        ]
      end
    end)
  end

  @doc """
  The decimal places a finite decimal carries, trailing zeros not counted:
  `2.50` has one, `100` none.
  """
  @spec decimal_places(Decimal.t()) :: non_neg_integer()
  def decimal_places(%Decimal{} = value) do
    case Decimal.normalize(value) do
      %Decimal{exp: exp} when exp < 0 -> -exp
      _whole -> 0
    end
  end
end
