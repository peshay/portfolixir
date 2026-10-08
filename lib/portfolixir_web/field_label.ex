defmodule PortfolixirWeb.FieldLabel do
  @moduledoc """
  The word a page names a changeset field by, and the refusal it reads, in the
  page's language (the booking drawer's fix round; board
  `ux-design-2026-10-04/09-import-correction`, found while drawing): a
  refusal reads "ISIN has already been taken", never "isin has already been
  taken".

  One map for the booking drawer, the Imports page and Buckets. It covers
  every field the schemas an import's apply or the drawer write can be
  refused on — the booking, the security, the cash account, the depot, the
  portfolio, the bucket and the ISIN change (`field_label_test.exs` derives
  the list from the schemas, so a field added without a label fails there).
  The labels are the ones the form inputs and the history carry. An unknown
  field falls back to its key.

  `changeset_message/1` is the one way these pages state a refused changeset:
  "<label> <message>" per field, the messages of one field joined by ", ",
  the fields by "; ", each message through the `errors` domain.
  """
  use Gettext, backend: PortfolixirWeb.Gettext

  alias PortfolixirWeb.NamedRecordRefusal

  @spec label(atom() | String.t()) :: String.t()
  # The booking.
  def label(:type), do: gettext("Type")
  def label(:date), do: gettext("Date")
  def label(:quantity), do: gettext("Quantity")
  def label(:price), do: gettext("Price")
  def label(:fees), do: gettext("Fees")
  def label(:taxes), do: gettext("Taxes")
  def label(:gross_amount), do: gettext("Amount")
  def label(:currency_code), do: gettext("Currency")
  def label(:security_amount), do: gettext("Amount in the security's currency")
  def label(:settlement_amount), do: gettext("Settlement amount")
  def label(:settlement_fx_rate), do: gettext("Exchange rate")
  def label(:split_ratio_numerator), do: gettext("New shares")
  def label(:split_ratio_denominator), do: gettext("Old shares")
  def label(:import_hash), do: gettext("Content hash")
  def label(:notes), do: gettext("Notes")
  def label(:note), do: gettext("Note")

  # The accounts, depots, portfolio and security a record names.
  def label(:security_id), do: gettext("Security")
  def label(:securities_account_id), do: gettext("Depot")
  def label(:counter_securities_account_id), do: gettext("Counter depot")
  def label(:cash_account_id), do: gettext("Cash account")
  def label(:counter_cash_account_id), do: gettext("Counter account")
  def label(:portfolio_id), do: gettext("Portfolio")
  def label(:source_portfolio_id), do: gettext("Portfolio")

  # A security the import creates, with the security dialog's labels.
  def label(:name), do: gettext("Name")
  def label(:isin), do: gettext("ISIN")
  def label(:wkn), do: gettext("WKN")
  def label(:ticker_symbol), do: gettext("Ticker")
  def label(:exchange_code), do: gettext("Exchange")
  def label(:asset_class), do: gettext("Asset class")
  def label(:feed), do: gettext("Quote feed")
  def label(:feed_url), do: gettext("Quote feed URL")
  def label(:latest_feed), do: gettext("Latest quote feed")
  def label(:latest_feed_url), do: gettext("Latest quote feed URL")
  def label(:is_retired), do: gettext("Retired")
  def label(:is_benchmark), do: gettext("Benchmark")
  def label(:treat_quotes_as_raw), do: gettext("Treat synced quotes as raw")
  def label(:online_id), do: gettext("Online ID")
  def label(:provider), do: gettext("Provider")
  def label(:attributes), do: gettext("Attributes")
  def label(:coupon_rate), do: gettext("Coupon p. a. (%)")
  def label(:coupon_frequency), do: gettext("Interest payment")
  def label(:maturity_date), do: gettext("Maturity")
  def label(:issue_date), do: gettext("Issue date")
  def label(:face_value), do: gettext("Denomination (face value)")
  def label(:face_value_currency_code), do: gettext("Face value currency")

  # A cash account, a depot, a portfolio or a bucket the import creates.
  def label(:base_currency_code), do: gettext("Base currency")
  def label(:liquidity_role), do: gettext("Liquidity role")
  def label(:former_names), do: gettext("Former names")
  def label(:dimension), do: gettext("Dimension")
  def label(:color), do: gettext("Color")

  # The ISIN change an import's mapping can record.
  def label(:new_isin), do: gettext("New ISIN")
  def label(:former_isin), do: gettext("Former ISIN")
  def label(:changed_on), do: gettext("ISIN change date")

  def label(other), do: to_string(other)

  @doc """
  A refused changeset as one sentence in the page's language: "<label>
  <message>" per field, the messages of one field joined by ", ", the fields
  by "; ".
  """
  @spec changeset_message(Ecto.Changeset.t()) :: String.t()
  def changeset_message(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_error/1)
    |> Enum.map_join("; ", fn {field, messages} ->
      "#{label(field)} #{Enum.join(messages, ", ")}"
    end)
  end

  @doc """
  One changeset message through the `errors` domain, its bindings filled. A
  message that names another field (`%{field}`, e.g. "must differ from
  %{field}") names it by its label. A refusal that names another record
  reads the sentence the screen keeps for it (#965,
  `PortfolixirWeb.NamedRecordRefusal`).
  """
  @spec translate_error({String.t(), keyword()}) :: String.t()
  def translate_error(error) do
    {message, opts} = NamedRecordRefusal.screen(error)

    opts =
      case opts[:field] do
        field when is_atom(field) and not is_nil(field) ->
          Keyword.put(opts, :field, label(field))

        _other ->
          opts
      end

    case opts[:count] do
      nil -> Gettext.dgettext(PortfolixirWeb.Gettext, "errors", message, opts)
      count -> Gettext.dngettext(PortfolixirWeb.Gettext, "errors", message, message, count, opts)
    end
  end
end
