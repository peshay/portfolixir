defmodule Portfolixir.Portfolios.CashAccount do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Input.Text
  alias Portfolixir.Lifecycle.AccountNames
  alias Portfolixir.Lifecycle.Freeze
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
    # ADR-0050 §4: the names this account was known by, which the importer
    # resolves after the live name. Never cast from a request; written by the
    # rename rule, the remembered remap, the removal and the merge.
    field(:former_names, {:array, :string}, default: [])

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
    # E25 S4 (G17, G24): the column's width in code points, no control
    # characters; after L1's identity freezes, which stay as they are.
    |> Text.validate([:name, :currency_code], max: 255)
    |> Text.validate(:notes, multiline: true, max: Text.free_text_max())
    |> check_constraint(:notes, name: :cash_accounts_notes_length_check)
    |> validate_length(:currency_code, is: 3)
    |> validate_inclusion(:liquidity_role, @liquidity_roles)
    |> assoc_constraint(:portfolio)
    # ADR-0050 §4: the name guard, and on a rename the rename rule, under the
    # account-identity lock (taken before the freeze's row lock).
    |> AccountNames.validate()
    # ADR-0050 §11: `currency_code` and `portfolio_id` freeze once a
    # transaction (either leg) or a linked depot references the account.
    |> Freeze.validate()
  end

  @doc """
  The write of `former_names` alone (ADR-0050 §4), for the writers in
  `Portfolixir.Lifecycle.AccountNames` that hold the account-identity lock and
  have run the name guard: the remembered remap and the removal.
  """
  def former_names_changeset(cash_account, former_names) when is_list(former_names) do
    change(cash_account, former_names: former_names)
  end

  defp normalize_currency_code(changeset) do
    update_change(changeset, :currency_code, fn
      value when is_binary(value) -> value |> String.trim() |> String.upcase()
      value -> value
    end)
  end
end
