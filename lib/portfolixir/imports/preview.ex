defmodule Portfolixir.Imports.Preview do
  @moduledoc """
  Outcome of parsing a Portfolio Performance export — a flat list of
  normalised `Portfolixir.Imports.Entry` rows plus aggregate summary
  data the UI uses to drive the preview screen.

  The preview is read-only: it does not touch the database. Persistence
  happens later in `Portfolixir.Imports.Applier` (Story 5).
  """

  alias Portfolixir.Imports.Entry

  @type t :: %__MODULE__{
          format: :json | :csv,
          source_filename: String.t() | nil,
          entries: [Entry.t()],
          errors: [%{row: pos_integer() | nil, message: String.t()}]
        }

  defstruct format: nil,
            source_filename: nil,
            entries: [],
            errors: []

  @doc """
  Counts per kind across all entries in the preview.

  Returns a map of `%{"purchase" => 12, "dividend" => 4, ...}`.
  """
  def counts_by_kind(%__MODULE__{entries: entries}) do
    Enum.reduce(entries, %{}, fn entry, acc ->
      Map.update(acc, entry.kind, 1, &(&1 + 1))
    end)
  end

  @doc """
  Unique securities referenced by entries — keyed by ISIN where
  available, otherwise by `{name, currency}`. Used by the UI to render
  the "would create N new securities" panel.
  """
  def unique_securities(%__MODULE__{entries: entries}) do
    entries
    |> Enum.map(& &1.security)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&security_key/1)
  end

  defp security_key(%{isin: isin}) when is_binary(isin) and isin != "", do: {:isin, isin}

  defp security_key(%{name: name, currency: currency}) when is_binary(name),
    do: {:name, name, currency}

  defp security_key(%{name: name}) when is_binary(name), do: {:name, name, nil}

  @doc """
  Unique `(pp_portfolio_name, pp_account_name)` combinations across
  entries — used by the UI to drive the account-mapping form.
  """
  def unique_pp_account_pairs(%__MODULE__{entries: entries}) do
    entries
    |> Enum.map(&{&1.pp_portfolio_name, &1.pp_account_name})
    |> Enum.reject(&match?({nil, nil}, &1))
    |> Enum.uniq()
  end
end
