defmodule Portfolixir.Portfolios.Portfolio do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Input.BoundedDecimal
  alias Portfolixir.Input.Text
  alias Portfolixir.Portfolios.Target

  schema "portfolios" do
    field(:name, :string)
    field(:base_currency_code, :string)
    field(:notes, :string)
    # Since ADR-0020 the cash target lives on the Gesamt target plan, not on the
    # portfolio. This stays as a **virtual** field so the existing API/UI contract
    # (validate a `[0, 1]` fraction, echo it back) is unchanged; the Portfolios
    # context reads/write-through it to the portfolio-wide Gesamt cash plan.
    field(:cash_target_weight, :decimal, virtual: true)

    timestamps()
  end

  def changeset(portfolio, attrs) do
    portfolio
    |> cast(attrs, [:name, :base_currency_code, :notes, :cash_target_weight])
    |> normalize_currency_code()
    |> validate_required([:name, :base_currency_code])
    |> Text.validate([:name, :base_currency_code], max: 255)
    |> Text.validate(:notes, multiline: true, max: Text.free_text_max())
    |> check_constraint(:notes, name: :portfolios_notes_length_check)
    |> validate_length(:base_currency_code, is: 3)
    |> validate_cash_target_weight()
  end

  # The cash target is the SOLL share of the portfolio's counting cash inside
  # the allocation's 100% basis (securities + counting cash). It mirrors the
  # per-category target weights: a fraction in `[0, 1]`, or `nil` when the
  # maintainer does not steer a cash quote. See ADR-0009 and issue #335.
  defp validate_cash_target_weight(changeset) do
    changeset
    |> validate_number(:cash_target_weight,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1
    )
    # The plan's scale (E25 S4, G14), refused before the portfolio is written.
    |> BoundedDecimal.validate_scale(:cash_target_weight, Target.weight_scale())
  end

  defp normalize_currency_code(changeset) do
    update_change(changeset, :base_currency_code, fn
      value when is_binary(value) -> value |> String.trim() |> String.upcase()
      value -> value
    end)
  end
end
