defmodule Portfolixir.Portfolios.Portfolio do
  use Ecto.Schema
  import Ecto.Changeset

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
    |> validate_length(:base_currency_code, is: 3)
    |> validate_cash_target_weight()
  end

  # The cash target is the SOLL share of the portfolio's counting cash inside
  # the allocation's 100% basis (securities + counting cash). It mirrors the
  # per-category target weights: a fraction in `[0, 1]`, or `nil` when the
  # maintainer does not steer a cash quote. See ADR-0009 and issue #335.
  defp validate_cash_target_weight(changeset) do
    validate_number(changeset, :cash_target_weight,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1
    )
  end

  defp normalize_currency_code(changeset) do
    update_change(changeset, :base_currency_code, fn
      value when is_binary(value) -> value |> String.trim() |> String.upcase()
      value -> value
    end)
  end
end
