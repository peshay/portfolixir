defmodule PortfolixirWeb.Api.V1.SplitController do
  @moduledoc """
  The dedicated split booking flow over the JSON API (ADR-0028 §1, AR-11).

  `POST /api/v1/splits/preview` shows the per-portfolio fan-out (quantities
  before/after the effective date, resulting current position, warnings)
  without writing anything; `POST /api/v1/splits` books one `split` row per
  positioned portfolio atomically. The generic transaction endpoint rejects
  the `split` kind — this controller is the only write path for it.
  Financial decimals serialize as strings; the ratio parts stay integers.
  """

  use PortfolixirWeb, :controller

  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Ledger.Transaction
  alias PortfolixirWeb.Api.V1.JSON

  def preview(conn, params) do
    case Splits.preview_split(split_attrs(params)) do
      {:ok, preview} -> json(conn, %{data: JSON.split_preview(preview)})
      {:error, reason} -> error_response(conn, reason)
    end
  end

  def create(conn, params) do
    case Splits.book_split(conn.assigns.actor, split_attrs(params)) do
      {:ok, transactions} ->
        conn
        |> put_status(:created)
        |> json(%{data: %{transactions: Enum.map(transactions, &JSON.transaction/1)}})

      {:error, reason} ->
        error_response(conn, reason)
    end
  end

  defp split_attrs(params) do
    Map.take(params, ["security_id", "date", "ratio_numerator", "ratio_denominator"])
  end

  defp error_response(conn, :security_not_found), do: not_found(conn)

  defp error_response(conn, reason) when is_atom(reason),
    do: unprocessable(conn, error_shape(reason))

  defp error_response(conn, {:existing_split, %Transaction{} = existing}),
    do: unprocessable(conn, %{date: [existing_split_message(existing)]})

  # A same-day split with a different normalized ratio would corrupt every
  # quote consumer that dedupes rows into one security-level event (E17
  # review, finding 2).
  defp error_response(conn, {:conflicting_split_ratio, %Transaction{} = existing}),
    do: unprocessable(conn, %{ratio: [conflicting_ratio_message(existing)]})

  defp error_response(conn, %Ecto.Changeset{} = changeset),
    do: unprocessable(conn, JSON.errors(changeset))

  defp error_shape(:invalid_date), do: %{date: ["is invalid"]}
  defp error_shape(:future_effective_date), do: %{date: ["must not be in the future"]}
  defp error_shape(:invalid_ratio), do: %{ratio: ["must be a pair of positive integers"]}

  defp error_shape(:identity_ratio),
    do: %{ratio: ["must change the share count (a 1:1 split is meaningless)"]}

  defp error_shape(:no_position),
    do: %{security_id: ["no portfolio holds a position in this security at the effective date"]}

  # Write idempotency (ADR-0028 §1): the rejection names the existing event.
  defp existing_split_message(%Transaction{} = existing) do
    "a split for this security is already booked on #{Date.to_iso8601(existing.date)}: " <>
      "transaction ##{existing.id} records ratio " <>
      "#{existing.split_ratio_numerator}:#{existing.split_ratio_denominator}" <>
      existing_portfolio_suffix(existing)
  end

  defp existing_portfolio_suffix(%Transaction{portfolio: %{name: name}}) when is_binary(name),
    do: " for portfolio \"#{name}\""

  defp existing_portfolio_suffix(_existing), do: ""

  defp conflicting_ratio_message(%Transaction{} = existing) do
    "a split with a different ratio is already booked for this security on " <>
      "#{Date.to_iso8601(existing.date)}: transaction ##{existing.id} records ratio " <>
      "#{existing.split_ratio_numerator}:#{existing.split_ratio_denominator}. " <>
      "Delete that event first if it is wrong."
  end

  defp unprocessable(conn, errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end
end
