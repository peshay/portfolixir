defmodule Portfolixir.Portfolios.CashAccount do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Portfolios.Portfolio

  # FR5 (#389): a cash account's liquidity role decides whether (and how) its
  # balance is real, deployable cash. `free_cash` is genuine spendable cash;
  # `credit_line` is an overdraft/Lombard facility whose negative balance is a
  # liability and whose unused headroom is never liquidity; `reserve` is a
  # visible-but-excluded bucket (e.g. a business account). This replaces the
  # #317 boolean `counts_toward_cash_quote` with a single 3-way source of truth.
  @liquidity_roles ~w(free_cash credit_line reserve)

  schema "cash_accounts" do
    field(:name, :string)
    field(:currency_code, :string)
    field(:notes, :string)
    field(:liquidity_role, :string, default: "free_cash")

    belongs_to(:portfolio, Portfolio)

    timestamps()
  end

  @doc """
  The closed set of liquidity roles, mirroring the DB check constraint added in
  the `liquidity_role` migration. The schema validates against this list.
  """
  def liquidity_roles, do: @liquidity_roles

  def changeset(cash_account, attrs) do
    cash_account
    |> cast(attrs, [:portfolio_id, :name, :currency_code, :notes, :liquidity_role])
    |> normalize_currency_code()
    |> validate_required([:portfolio_id, :name, :currency_code, :liquidity_role])
    |> validate_length(:currency_code, is: 3)
    |> validate_inclusion(:liquidity_role, @liquidity_roles)
    |> assoc_constraint(:portfolio)
  end

  defp normalize_currency_code(changeset) do
    update_change(changeset, :currency_code, fn
      value when is_binary(value) -> value |> String.trim() |> String.upcase()
      value -> value
    end)
  end
end
