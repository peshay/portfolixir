defmodule Portfolixir.Portfolios.SecuritiesAccount do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Input.Text
  alias Portfolixir.Lifecycle.AccountNames
  alias Portfolixir.Lifecycle.Freeze
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.Portfolio

  schema "securities_accounts" do
    field(:name, :string)
    field(:notes, :string)
    # ADR-0050 §4: the names this depot was known by, which the importer
    # resolves after the live name. Never cast from a request; written by the
    # rename rule, the remembered remap, the removal and the merge.
    field(:former_names, {:array, :string}, default: [])

    belongs_to(:portfolio, Portfolio)
    belongs_to(:cash_account, CashAccount)

    timestamps()
  end

  def changeset(securities_account, attrs) do
    securities_account
    |> cast(attrs, [:portfolio_id, :cash_account_id, :name, :notes])
    |> validate_required([:portfolio_id, :cash_account_id, :name])
    # E25 S4 (G17, G24): the column's width in code points, no control
    # characters; after L1's identity freezes, which stay as they are.
    |> Text.validate(:name, max: 255)
    |> Text.validate(:notes, multiline: true, max: Text.free_text_max())
    |> check_constraint(:notes, name: :securities_accounts_notes_length_check)
    |> assoc_constraint(:portfolio)
    |> assoc_constraint(:cash_account)
    |> foreign_key_constraint(:cash_account_id,
      name: :securities_accounts_cash_account_portfolio_fkey
    )
    # ADR-0050 §4: the name guard, and on a rename the rename rule, under the
    # account-identity lock (taken before the freeze's row lock).
    |> AccountNames.validate()
    # ADR-0050 §11: `portfolio_id` freezes once a transaction references the
    # depot through either leg.
    |> Freeze.validate()
  end

  @doc """
  The write of `former_names` alone (ADR-0050 §4), for the writers in
  `Portfolixir.Lifecycle.AccountNames` that hold the account-identity lock and
  have run the name guard: the remembered remap and the removal.
  """
  def former_names_changeset(securities_account, former_names) when is_list(former_names) do
    change(securities_account, former_names: former_names)
  end
end
