defmodule Portfolixir.Imports.ImportHash do
  @moduledoc """
  The content hash of an import row (#533, ADR-0029, ADR-0050 §3): the
  re-import contract's first check, computed from file-side fields plus the
  portfolio before anything resolves.

  The fields are the row's kind, date and time, its security (ISIN, else
  name), quantity, price, gross amount, fees and taxes, its four Portfolio
  Performance account and depot names, and the portfolio id.

  **Injective, and every stored hash stays valid** (E25 S5, F36; risk-tier:
  idempotency, ADR-0036). Up to Sprint 15 the fields were joined with `|`
  and hashed, so two rows whose fields joined to one string (a separator
  moved from one name into its neighbour) shared one hash, and the second
  was skipped as already imported. Now:

    * a row with no `|` in any field hashes exactly as before — such a join
      has exactly one reading, so it is injective, and every hash stored for
      such a row stays valid;
    * a row with `|` in a field is hashed over its length-prefixed fields
      behind a leading NUL byte, which no joined form begins with, so it can
      share a hash with no other row. `legacy/2` names the hash the joined
      formula gave it, for the applier to recognise a row stored before this
      change.

  The legacy hash of a separator-bearing row is ambiguous by construction:
  a different row whose fields joined to the same string would be taken for
  the stored one. That is the closed direction for idempotency (nothing books
  twice), it only matches rows stored before this change, and the applier
  lists such a row among those already booked.
  """

  alias Portfolixir.Imports.Entry

  @separator "|"

  @doc "The content hash of `entry` imported into `portfolio_id`."
  @spec compute(Entry.t(), integer()) :: String.t()
  def compute(%Entry{} = entry, portfolio_id) when is_integer(portfolio_id) do
    parts = parts(entry, portfolio_id)

    if separator_bearing?(parts),
      do: digest(["\0" | length_prefixed(parts)]),
      else: joined(parts)
  end

  @doc """
  The hash the Sprint 15 formula gave `entry` when it differs from
  `compute/2` — the row carries the separator in a field — or `nil`.
  """
  @spec legacy(Entry.t(), integer()) :: String.t() | nil
  def legacy(%Entry{} = entry, portfolio_id) when is_integer(portfolio_id) do
    parts = parts(entry, portfolio_id)
    if separator_bearing?(parts), do: joined(parts)
  end

  defp parts(%Entry{} = entry, portfolio_id) do
    [
      entry.kind,
      date_str(entry.date),
      time_str(entry.time),
      security_key(entry.security),
      decimal_str(entry.quantity),
      decimal_str(entry.price),
      decimal_str(entry.gross_amount),
      decimal_str(entry.fees),
      decimal_str(entry.taxes),
      entry.pp_portfolio_name || "",
      entry.pp_account_name || "",
      entry.pp_counter_portfolio_name || "",
      entry.pp_counter_account_name || "",
      Integer.to_string(portfolio_id)
    ]
  end

  defp separator_bearing?(parts), do: Enum.any?(parts, &String.contains?(&1, @separator))

  # The Sprint 15 formula, byte for byte.
  defp joined(parts), do: parts |> Enum.join(@separator) |> digest()

  defp length_prefixed(parts),
    do: Enum.map(parts, &[Integer.to_string(byte_size(&1)), ":", &1])

  defp digest(iodata), do: :sha256 |> :crypto.hash(iodata) |> Base.encode16(case: :lower)

  defp date_str(nil), do: ""
  defp date_str(%Date{} = d), do: Date.to_iso8601(d)

  defp time_str(nil), do: ""
  defp time_str(%Time{} = t), do: Time.to_iso8601(t)

  defp decimal_str(nil), do: ""
  defp decimal_str(%Decimal{} = d), do: Decimal.to_string(d, :normal)

  defp security_key(nil), do: ""
  defp security_key(%{isin: isin}) when is_binary(isin) and isin != "", do: "isin:" <> isin
  defp security_key(%{name: name}) when is_binary(name), do: "name:" <> name
  defp security_key(_), do: ""
end
