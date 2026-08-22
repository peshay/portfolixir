defmodule Portfolixir.Catalog.Security do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.AssetClasses
  alias Portfolixir.Catalog.Currencies
  alias Portfolixir.Catalog.Feeds

  @providers ~w(portfolio_performance coingecko manual)

  @type t :: %__MODULE__{}

  schema "securities" do
    field(:name, :string)
    field(:ticker_symbol, :string)
    field(:isin, :string)
    field(:wkn, :string)
    field(:currency_code, :string)
    field(:exchange_code, :string)
    field(:asset_class, :string)
    field(:note, :string)
    field(:feed, :string)
    field(:feed_url, :string)
    field(:latest_feed, :string)
    field(:latest_feed_url, :string)
    field(:is_retired, :boolean, default: false)
    # ADR-0028 §2 escape hatch: force the raw quote basis for this security's
    # provider-synced rows (providers that never back-adjust after a split).
    field(:treat_quotes_as_raw, :boolean, default: false)
    field(:online_id, :string)
    field(:provider, :string)
    field(:attributes, :map, default: %{})

    has_many(:identifier_aliases, Portfolixir.Catalog.IdentifierAlias)

    timestamps()
  end

  @castable ~w(
    name ticker_symbol isin wkn currency_code exchange_code asset_class
    note feed feed_url latest_feed latest_feed_url is_retired
    treat_quotes_as_raw online_id provider attributes
  )a

  def changeset(security, attrs) do
    security
    |> cast(attrs, @castable)
    |> normalize_text(:ticker_symbol, &String.upcase/1)
    |> normalize_text(:currency_code, &String.upcase/1)
    |> normalize_text(:exchange_code, &String.upcase/1)
    |> normalize_text(:wkn, &String.upcase/1)
    |> normalize_text(:isin, &String.upcase/1)
    |> empty_to_nil([
      :ticker_symbol,
      :isin,
      :wkn,
      :exchange_code,
      :asset_class,
      :note,
      :feed,
      :feed_url,
      :latest_feed,
      :latest_feed_url,
      :online_id,
      :provider
    ])
    |> default_attributes()
    |> infer_asset_class()
    |> validate_required([:name, :currency_code])
    |> validate_length(:currency_code, is: 3)
    |> validate_inclusion(:currency_code, Currencies.codes(), message: "is invalid")
    |> validate_inclusion(:asset_class, AssetClasses.codes(), message: "is invalid")
    |> validate_inclusion(:provider, @providers, message: "is invalid")
    |> validate_feed(:feed)
    |> validate_feed(:latest_feed)
    |> unique_constraint([:provider, :online_id],
      name: :securities_provider_online_id_unique_index
    )
    |> unique_constraint(:isin, name: :securities_isin_unique_index)
  end

  def delete_changeset(security) do
    security
    |> change()
    |> foreign_key_constraint(:id,
      name: :transactions_security_id_fkey,
      message: "is referenced by existing records"
    )
    |> foreign_key_constraint(:id,
      name: :security_quotes_security_id_fkey,
      message: "is referenced by existing records"
    )
  end

  def asset_classes, do: AssetClasses.codes()
  def providers, do: @providers

  def effective_asset_class(%__MODULE__{asset_class: asset_class}) when is_binary(asset_class),
    do: asset_class

  def effective_asset_class(%__MODULE__{} = security) do
    infer_asset_class_code(security.name, security.isin, security.ticker_symbol) ||
      inferred_from_logo(security)
  end

  def effective_asset_class(_), do: nil

  # A name-unresolved instrument that has an ISIN *and* a resolved company logo
  # is treated as equity: the logo pipeline already decided "this is a company",
  # and the ISIN marks it as a real listed instrument (not a bare crypto or
  # commodity). ISIN structure alone is not a reliable asset-class signal, so it
  # is only used together with the company-logo result (#408). A user-set class
  # always wins (handled by the binary-asset_class clause above).
  defp inferred_from_logo(%__MODULE__{isin: isin, attributes: attributes})
       when is_binary(isin) and isin != "" do
    if is_binary(get_in(attributes || %{}, ["logo_path"])), do: "equity"
  end

  defp inferred_from_logo(_security), do: nil

  defp validate_feed(changeset, field) do
    case get_field(changeset, field) do
      nil ->
        changeset

      "" ->
        changeset

      value ->
        if Feeds.supported?(value), do: changeset, else: add_error(changeset, field, "is invalid")
    end
  end

  defp default_attributes(changeset) do
    update_change(changeset, :attributes, fn
      nil -> %{}
      value when is_map(value) -> value
      _ -> %{}
    end)
  end

  defp infer_asset_class(changeset) do
    case get_field(changeset, :asset_class) do
      nil ->
        class =
          changeset
          |> get_field(:name)
          |> infer_asset_class_code(
            get_field(changeset, :isin),
            get_field(changeset, :ticker_symbol)
          )

        if class, do: put_change(changeset, :asset_class, class), else: changeset

      _asset_class ->
        changeset
    end
  end

  # Decided against a default "ISIN + ticker present → equity" rule:
  # funds without "ETF" in their name (e.g. "AIS-AM.MSCI EM A. EOC") share the
  # same ISIN+ticker structure as equities and are a frequent false-positive.
  # The fund_or_nil/1 fallback handles these without overfitting.
  defp infer_asset_class_code(name, _isin, ticker_symbol) do
    cond do
      government_bond_name?(name) -> "government_bond"
      etf_name?(name) -> "etf"
      crypto_name?(name) or crypto_ticker?(ticker_symbol) -> "crypto"
      commodity_name?(name) -> "commodity"
      # Certificate/leverage products are checked before equities because their
      # names often also carry an issuer suffix (e.g. "Aktienanleihe … AG").
      true -> derivative_class(name) || equity_or_nil(name) || fund_or_nil(name)
    end
  end

  # Physically-backed precious-metal products (e.g. EUWAX/Xetra Gold) and
  # bare precious-metal holdings (e.g. a "Gold" position on bitcoin.de). The
  # bare-name branch is exact-match only so "Barrick Gold Corp" stays equity.
  defp commodity_name?(name) when is_binary(name) do
    Regex.match?(
      ~r/EUWAX\s*Gold|Xetra[\s-]?Gold|Physical\s+(Gold|Silver|Platinum|Palladium)|\bGold\s+Bullion\b|^(Gold|Silber|Silver|Platin(?:um)?)$/i,
      name
    )
  end

  defp commodity_name?(_), do: false

  defp equity_or_nil(name) do
    if equity_name?(name) and not structured_product_name?(name), do: "equity", else: nil
  end

  defp fund_or_nil(name) do
    if fund_name?(name), do: "fund", else: nil
  end

  # Conservative mapping of structured/leverage products (DDV taxonomy) to a leaf
  # asset-class code. Only matches derivative-specific tokens so ordinary equities
  # (e.g. "American Express") are never misread as certificates.
  defp derivative_class(name) when is_binary(name) do
    cond do
      knockout_name?(name) -> "knock_out"
      Regex.match?(~r/\bDisc[CP]|Discount[\s-]?(Zertifikat|Cap)/i, name) -> "discount_certificate"
      Regex.match?(~r/\bOptionsschein\b|\bWarrant\b/i, name) -> "warrant"
      Regex.match?(~r/\bFaktor\b/i, name) -> "factor_certificate"
      Regex.match?(~r/Aktienanleihe|Reverse[\s-]?Convertible/i, name) -> "reverse_convertible"
      Regex.match?(~r/Bonus[\s-]?(Zertifikat|Cap)/i, name) -> "bonus_certificate"
      Regex.match?(~r/Express[\s-]?Zertifikat/i, name) -> "express_certificate"
      # Bare Call/Put is broker shorthand for a warrant; checked last so e.g.
      # "Turbo Call" is a knock-out and "DiscC" a discount certificate.
      Regex.match?(~r/\b(Call|Put)\b/i, name) -> "warrant"
      true -> nil
    end
  end

  defp derivative_class(_), do: nil

  defp knockout_name?(name) do
    Regex.match?(
      ~r/\bTurbo[A-Z]?\b|Knock[\s-]?Out|\bKO\b|Mini[\s-]?Future|\bO\.End\b|Open[\s-]?End[\s-]?Turbo|\bWAVE\b|Unlimited\s+Turbo/i,
      name
    )
  end

  defp government_bond_name?(name) when is_binary(name) do
    Regex.match?(
      ~r/(bundesrepublik|bundesanleihe|bundesobligation|bundesschatz|staatsanleihe|treasury\s+(note|bond|bill)|government\s+bond|sovereign\s+bond|republic\s+of|kingdom\s+of|^anleihe\s+(australien|belgien|deutschland|frankreich|italien|kanada|niederlande|norwegen|österreich|singapur|spanien|usa|vereinigte\s+staaten|united\s+states)\b)/i,
      name
    )
  end

  defp government_bond_name?(_), do: false

  defp etf_name?(name) when is_binary(name) do
    Regex.match?(~r/\b(U\.?ETF|UETF|UCITS\s+ETF|ETF|ETC|ETN|ETP)\b/i, name)
  end

  defp etf_name?(_), do: false

  defp crypto_name?(name) when is_binary(name) do
    Regex.match?(
      ~r/^\s*(bitcoin|ethereum|ether|solana|cardano|polkadot|litecoin|chainlink|ripple|xrp|dogecoin|avalanche|tron)\s*$/i,
      name
    )
  end

  defp crypto_name?(_), do: false

  defp crypto_ticker?(ticker) when is_binary(ticker) do
    Regex.match?(~r/^(BTC|ETH|SOL|ADA|DOT|LTC|LINK|XRP|DOGE|AVAX|TRX)([-.][A-Z]{3})?$/i, ticker)
  end

  defp crypto_ticker?(_), do: false

  defp structured_product_name?(name) when is_binary(name) do
    Regex.match?(
      ~r/(Turbo[A-Z]?|Disc[CP]?|Discount|Call|Put|Optionsschein|Zertifikat|O\.End|Em\.-u\.Handelsg\.mbH)/i,
      name
    )
  end

  defp equity_name?(name) when is_binary(name) do
    Regex.match?(
      ~r/(Registered\s+Shares?|Registered\s+Part\.?\s*Shares?|Reg\.?\s*Shares?|Inhaber-Aktien|Namens-Aktien|Vorzugsaktien|Actions|Aandelen|Common\s+Stock|\bInc\.?\b|\bCorp\.?\b|\bCorporation\b|\bCompany\b|\bCo\.|\bLtd\.?\b|\bAG\b|\bSE\b|\bPLC\b|S\.p\.A\.|S\.?A\.?|SA\/NV|\bAktiengesellschaft\b|\bA\/S\b|\bASA\b|\bKGaA\b|\bAzioni\b|\bAcciones\b|\bAktier\b|\b(?:Sp\.)?ADR(?:s)?\b|\bGDR(?:s)?\b|Depos\.?\s*Receipts?|\bINH\.ON\b)/i,
      name
    )
  end

  defp equity_name?(_), do: false

  # Known fund-issuer prefixes (kept in sync with LogoLookup's issuer list).
  # Only reached when no ETF token and no equity suffix was found, so false
  # positives for pure bank equities (UBS AG, BNP Paribas SA) are filtered
  # out by equity_or_nil first.
  defp fund_name?(name) when is_binary(name) do
    Regex.match?(
      ~r/\biShares\b|\bVanguard\b|\bLyxor\b|\b(?:AIS-?AM|Amundi)\b|\bXtrackers\b|\bSPDR\b|\bInvesco\b|\bWisdomTree\b|\bVanEck\b|\bFidelity\b|\bDeka\b/i,
      name
    )
  end

  defp fund_name?(_), do: false

  defp normalize_text(changeset, field, fun) do
    update_change(changeset, field, fn
      value when is_binary(value) -> value |> String.trim() |> fun.()
      value -> value
    end)
  end

  defp empty_to_nil(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, acc ->
      update_change(acc, field, fn
        value when is_binary(value) ->
          value = String.trim(value)
          if value == "", do: nil, else: value

        value ->
          value
      end)
    end)
  end
end
