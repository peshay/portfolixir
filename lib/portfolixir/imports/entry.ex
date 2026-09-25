defmodule Portfolixir.Imports.Entry do
  @moduledoc """
  Normalised representation of one row from a Portfolio Performance
  export, independent of source format (JSON or CSV).

  An entry is parser-side only — it carries the strings/decimals as
  they appeared in the export plus a `kind` mapped to one of
  `Portfolixir.Ledger.Transaction.kinds/0`. Turning an entry into a
  ledger transaction is the job of `Portfolixir.Imports.Applier`
  (Story 5), which resolves PP account/portfolio names to real
  Portfolixir IDs and computes the idempotency hash.

  All financial fields are `Decimal` — never floats — to satisfy the
  AGENTS.md money-precision rule.
  """

  @type security_ref :: %{
          optional(:isin) => String.t() | nil,
          optional(:wkn) => String.t() | nil,
          optional(:ticker) => String.t() | nil,
          optional(:name) => String.t() | nil,
          optional(:currency) => String.t() | nil
        }

  @type t :: %__MODULE__{
          source_row: pos_integer() | String.t() | nil,
          kind: String.t(),
          date: Date.t() | nil,
          time: Time.t() | nil,
          currency_code: String.t() | nil,
          gross_amount: Decimal.t() | nil,
          fees: Decimal.t() | nil,
          taxes: Decimal.t() | nil,
          quantity: Decimal.t() | nil,
          price: Decimal.t() | nil,
          security: security_ref() | nil,
          pp_portfolio_name: String.t() | nil,
          pp_account_name: String.t() | nil,
          pp_counter_portfolio_name: String.t() | nil,
          pp_counter_account_name: String.t() | nil,
          note: String.t() | nil,
          warnings: [String.t()],
          companion_entries: [t()],
          companion_index: pos_integer() | nil
        }

  defstruct source_row: nil,
            kind: nil,
            date: nil,
            time: nil,
            currency_code: nil,
            gross_amount: nil,
            fees: nil,
            taxes: nil,
            quantity: nil,
            price: nil,
            security: nil,
            pp_portfolio_name: nil,
            pp_account_name: nil,
            pp_counter_portfolio_name: nil,
            pp_counter_account_name: nil,
            note: nil,
            warnings: [],
            companion_entries: [],
            # Set by `flatten/1` on a split-off companion: its 1-based
            # position among its parent's companions (E25 S5, F37).
            companion_index: nil

  @doc """
  Flattens an entry list so each parent's `companion_entries` becomes
  a top-level entry of its own, ordered right after the parent and marked
  with its `companion_index` (1-based), so the applier can hash it with its
  parent and book or skip it together with it (E25 S5, F37).
  """
  @spec flatten([t()]) :: [t()]
  def flatten(entries) do
    Enum.flat_map(entries, fn entry ->
      companions =
        entry.companion_entries
        |> Enum.with_index(1)
        |> Enum.map(fn {companion, index} -> %{companion | companion_index: index} end)

      [%{entry | companion_entries: []} | companions]
    end)
  end
end
