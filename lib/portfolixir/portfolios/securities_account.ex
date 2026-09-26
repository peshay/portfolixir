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
  The lifecycle merge's re-point of a depot's linked cash account (ADR-0050
  §7 step 5): `cash_account_id` alone, for a cash-account merge that moves
  the source's linked depots onto the target. Name, portfolio and former
  names are not cast, so the name guard and the identity freeze have no
  input here; the merge's same-portfolio guard keeps the composite key
  satisfied, and the key is declared, so a refusal is a changeset error.
  """
  def reassign_changeset(securities_account, attrs) when is_map(attrs) do
    securities_account
    |> cast(attrs, [:cash_account_id])
    |> validate_required([:cash_account_id])
    |> assoc_constraint(:cash_account)
    |> foreign_key_constraint(:cash_account_id,
      name: :securities_accounts_cash_account_portfolio_fkey
    )
  end

  @doc """
  The write of `former_names` alone (ADR-0050 §4), for the writers that hold
  the account-identity lock and have run the name guard: the remembered remap
  and the removal (`Portfolixir.Lifecycle.AccountNames`), and a merge's
  append of the source's names (`Portfolixir.Lifecycle.MergeWriter`, §7
  step 7).
  """
  def former_names_changeset(securities_account, former_names) when is_list(former_names) do
    change(securities_account, former_names: former_names)
  end
end
