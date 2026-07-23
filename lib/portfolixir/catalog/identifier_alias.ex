defmodule Portfolixir.Catalog.IdentifierAlias do
  @moduledoc """
  A recorded former ISIN of a security (ADR-0029 §3).

  Created by `Portfolixir.Catalog.record_isin_change/4`, which moves the
  security's current ISIN into a row like this and writes the new ISIN onto the
  security in one journaled transaction. The import ladder's ISIN tier resolves
  entries via these rows after the current-ISIN lookup misses. Aliases are
  correctable master data — journaled delete/reassign exists — not write-once.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.Security

  @type t :: %__MODULE__{}

  schema "security_identifier_aliases" do
    belongs_to(:security, Security)
    field(:former_isin, :string)
    field(:changed_on, :date)
    field(:note, :string)

    timestamps()
  end

  @doc false
  def changeset(alias_row, attrs) do
    alias_row
    |> cast(attrs, [:security_id, :former_isin, :changed_on, :note])
    |> update_change(:former_isin, &normalize_isin/1)
    |> update_change(:note, &normalize_note/1)
    |> validate_required([:security_id, :former_isin, :changed_on])
    |> foreign_key_constraint(:security_id)
    |> unique_constraint(:former_isin,
      name: :security_identifier_aliases_former_isin_unique_index,
      message: "is already recorded as a former ISIN"
    )
  end

  @doc """
  Catalog normal form for ISIN comparison and storage: trimmed and uppercased,
  matching `Portfolixir.Catalog.Security`'s changeset normalization. Blank
  input normalizes to `nil`.
  """
  @spec normalize_isin(String.t() | nil) :: String.t() | nil
  def normalize_isin(value) when is_binary(value) do
    case value |> String.trim() |> String.upcase() do
      "" -> nil
      normalized -> normalized
    end
  end

  def normalize_isin(_value), do: nil

  defp normalize_note(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_note(value), do: value
end
