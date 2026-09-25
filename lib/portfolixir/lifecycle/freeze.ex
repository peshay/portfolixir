defmodule Portfolixir.Lifecycle.Freeze do
  @moduledoc """
  The identity-field freezes of ADR-0050 §11 (§16 invariant 15): once history
  hangs on a row, the fields that give that history its meaning stop
  changing.

    * a cash account's `currency_code` and `portfolio_id` freeze once a
      transaction references it through either leg or a depot links to it;
    * a depot's `portfolio_id` freezes once a transaction references it
      through either leg;
    * a security's `currency_code` freezes once it has a transaction or a
      quote.

  "Referenced" is the reference check of the hardened delete
  (`Portfolixir.Lifecycle.Delete.referenced_by/1`): every `:restrict` foreign
  key of the disposition map onto the table, a transaction counted once
  whichever leg references the row. A security narrows it to transactions and
  quotes, the two families stated in its currency.

  `validate/1` is piped into each schema's `changeset/2`, so every writer that
  builds its update there is covered — the contexts, the API and MCP over
  them, the LiveView forms, the search dialog's "merge into existing" — and a
  refusal is a field error (`validation: :frozen`), which the API answers as
  422. The check itself runs when the row is **written**, inside the write's
  transaction and under the row's `FOR UPDATE` lock (`prepare_changes`): a
  booking or a quote that lands after the changeset was built still freezes
  the write, and one that is being inserted concurrently is waited for, not
  missed. A resent value equal to the stored one is no change and is never
  checked.
  """

  alias Ecto.Changeset
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Lifecycle.Delete
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount

  import Ecto.Query, only: [from: 2]

  @frozen_fields %{
    CashAccount => [:currency_code, :portfolio_id],
    SecuritiesAccount => [:portfolio_id],
    Security => [:currency_code]
  }

  # The referencing tables that freeze a row; `:referenced` is §11's whole
  # reference check.
  @freezing %{
    CashAccount => :referenced,
    SecuritiesAccount => :referenced,
    Security => ["transactions", "security_quotes"]
  }

  @labels %{
    "transactions" => {"transaction", "transactions"},
    "securities_accounts" => {"securities account", "securities accounts"},
    "security_quotes" => {"quote", "quotes"}
  }

  @doc "The fields that freeze on each of the three schemas."
  @spec frozen_fields() :: %{module() => [atom()]}
  def frozen_fields, do: @frozen_fields

  @doc """
  Attaches the freeze to `changeset` when it changes a frozen field of a
  stored row; a new row, or a changeset that leaves the frozen fields alone,
  is returned untouched.
  """
  @spec validate(Changeset.t()) :: Changeset.t()
  def validate(%Changeset{data: %schema{} = data} = changeset)
      when is_map_key(@frozen_fields, schema) do
    changing =
      Enum.filter(Map.fetch!(@frozen_fields, schema), &Map.has_key?(changeset.changes, &1))

    if changing != [] and Ecto.get_meta(data, :state) == :loaded do
      Changeset.prepare_changes(changeset, &refuse_when_referenced(&1, changing))
    else
      changeset
    end
  end

  @doc """
  What freezes `record`, counted per referencing table (only the tables that
  do); empty when nothing does.
  """
  @spec freezing_references(Delete.record()) :: Delete.referenced_by()
  def freezing_references(%schema{} = record) when is_map_key(@freezing, schema) do
    case Map.fetch!(@freezing, schema) do
      :referenced -> Delete.referenced_by(record)
      tables -> record |> Delete.referenced_by() |> Map.take(tables)
    end
  end

  # Runs inside the write's transaction, before the UPDATE.
  defp refuse_when_referenced(%Changeset{data: %schema{id: id} = data} = changeset, fields) do
    changeset.repo.one(from(r in schema, where: r.id == ^id, lock: "FOR UPDATE", select: r.id))

    case freezing_references(data) do
      references when map_size(references) == 0 ->
        changeset

      references ->
        message = "is frozen once referenced (#{counts(references)})"

        Enum.reduce(fields, changeset, fn field, acc ->
          Changeset.add_error(acc, field, message, validation: :frozen)
        end)
    end
  end

  defp counts(references) do
    references
    |> Enum.map(fn {table, count} -> {label(table, count), count} end)
    |> Enum.sort()
    |> Enum.map_join(", ", fn {label, count} -> "#{count} #{label}" end)
  end

  defp label(table, count) do
    {one, many} = Map.get(@labels, table, {table, table})
    if count == 1, do: one, else: many
  end
end
