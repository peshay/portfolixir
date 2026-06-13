defmodule Portfolixir.Catalog.LogoLookup do
  @moduledoc """
  Dispatches a security to the right logo source based on its asset
  class / provider, downloads the image once via `LogoStore` and stores
  the relative path on the security's `attributes` map.

  Strategies:
    * `asset_class = "crypto"` -> CoinGecko. `provider = "coingecko"` uses the
      stored `online_id`; PP-imported cryptos resolve a coin id from their
      ticker/name via `CryptoMap`.
    * `asset_class in ~w(equity etf fund)` -> Wikipedia REST (deterministic
      titles + a validated name search), then companieslogo.com as a fallback.
      ETFs/funds try known issuer titles (iShares, Vanguard, Lyxor, …) first.
    * structured/leverage products (warrant, knock-out, certificates) have no
      own logo, but get their *issuer's* logo (BNP Paribas, Morgan Stanley, …)
      when the issuer is recognizable in the name.
    * anything else -> `:skip`.

  The `:req` option is forwarded to both the lookup adapters and the
  store so a single Req plug-stub can be used end-to-end in tests.
  """

  require Logger

  alias Portfolixir.Catalog.LogoLookup.CompaniesLogo
  alias Portfolixir.Catalog.LogoLookup.CryptoMap
  alias Portfolixir.Catalog.LogoLookup.Wikipedia
  alias Portfolixir.Catalog.LogoStore
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecuritySearch.CoinGecko

  @equity_classes ~w(equity etf fund)
  # Structured/leverage products: no own logo, but they carry an issuer
  # (BNP Paribas, Morgan Stanley, …) whose logo is shown instead.
  @derivative_classes ~w(
    warrant knock_out factor_certificate discount_certificate
    bonus_certificate express_certificate reverse_convertible
  )

  # Issuer detection for ETF/fund providers AND structured-product issuers.
  # `titles` feed the Wikipedia/Wikidata logo lookup; `slug` is the
  # companieslogo.com fallback slug; `name` is the display issuer.
  @issuers [
    {~r/\biShares\b/i, %{name: "iShares", titles: ["iShares"], slug: "ishares"}},
    {~r/\bVanguard\b/i, %{name: "Vanguard", titles: ["The Vanguard Group"], slug: "vanguard"}},
    {~r/\bLyxor\b/i,
     %{name: "Lyxor", titles: ["Lyxor Asset Management", "Lyxor"], slug: "lyxor"}},
    {~r/\b(AIS-?AM|Amundi)\b/i, %{name: "Amundi", titles: ["Amundi"], slug: "amundi"}},
    {~r/\b(Xtrackers|DWS)\b/i,
     %{name: "Xtrackers", titles: ["DWS Group", "Xtrackers"], slug: "dws"}},
    {~r/\b(SPDR|State\s+Street)\b/i,
     %{name: "State Street", titles: ["State Street Global Advisors"], slug: "state-street"}},
    {~r/\bInvesco\b/i, %{name: "Invesco", titles: ["Invesco"], slug: "invesco"}},
    {~r/\bWisdomTree\b/i,
     %{name: "WisdomTree", titles: ["WisdomTree Investments"], slug: "wisdomtree"}},
    {~r/\bVanEck\b/i, %{name: "VanEck", titles: ["VanEck"], slug: "vaneck"}},
    {~r/\bFranklin\b/i,
     %{
       name: "Franklin Templeton",
       titles: ["Franklin Templeton Investments"],
       slug: "franklin-templeton"
     }},
    {~r/\bFidelity\b/i, %{name: "Fidelity", titles: ["Fidelity Investments"], slug: "fidelity"}},
    {~r/\bDeka\b/i, %{name: "Deka", titles: ["DekaBank"], slug: "dekabank"}},
    {~r/\bBNP\s+Paribas\b|\bBNPP?\b/i,
     %{name: "BNP Paribas", titles: ["BNP Paribas"], slug: "bnp-paribas"}},
    {~r/\bMorgan\s+Stanley\b/i,
     %{name: "Morgan Stanley", titles: ["Morgan Stanley"], slug: "morgan-stanley"}},
    {~r/\bGoldman\s+Sachs\b/i,
     %{name: "Goldman Sachs", titles: ["Goldman Sachs"], slug: "goldman-sachs"}},
    {~r/\bSoci[ée]t[ée]\s+G[ée]n[ée]rale\b|\bSocGen\b/i,
     %{name: "Société Générale", titles: ["Société Générale"], slug: "societe-generale"}},
    {~r/\bDeutsche\s+Bank\b/i,
     %{name: "Deutsche Bank", titles: ["Deutsche Bank"], slug: "deutsche-bank"}},
    {~r/\bCommerzbank\b/i, %{name: "Commerzbank", titles: ["Commerzbank"], slug: "commerzbank"}},
    {~r/\bUBS\b/i, %{name: "UBS", titles: ["UBS"], slug: "ubs"}},
    {~r/\bHSBC\b/i, %{name: "HSBC", titles: ["HSBC"], slug: "hsbc"}},
    {~r/\bJ\.?P\.?\s*Morgan\b|\bJPM\b/i,
     %{name: "JPMorgan", titles: ["JPMorgan Chase"], slug: "jpmorgan-chase"}},
    {~r/\bCitigroup\b|\bCitibank\b|\bCiti\b/i,
     %{name: "Citigroup", titles: ["Citigroup"], slug: "citigroup"}},
    {~r/\bBarclays\b/i, %{name: "Barclays", titles: ["Barclays"], slug: "barclays"}},
    {~r/\bVontobel\b/i, %{name: "Vontobel", titles: ["Vontobel"], slug: "vontobel"}},
    {~r/\bDZ\s*BANK\b/i, %{name: "DZ Bank", titles: ["DZ Bank"], slug: "dz-bank"}}
  ]

  @spec find_url(Security.t(), keyword()) ::
          {:ok, String.t(), atom()} | :skip | {:error, term()}
  def find_url(
        %Security{asset_class: "crypto", provider: "coingecko", online_id: id} = _sec,
        opts
      )
      when is_binary(id) and id != "" do
    coingecko_by_id(id, opts)
  end

  # Cryptos imported from Portfolio Performance carry no CoinGecko `online_id`,
  # so the ticker/name is mapped to a coin id and the logo is fetched from
  # CoinGecko anyway. Unknown coins yield `:skip` without a network call.
  def find_url(%Security{asset_class: "crypto"} = security, opts) do
    crypto_by_mapping(security, opts)
  end

  def find_url(%Security{asset_class: class, name: name} = security, opts)
      when class in @equity_classes and is_binary(name) and name != "" do
    company_logo(security, opts)
  end

  def find_url(%Security{asset_class: class, name: name} = security, opts)
      when class in @derivative_classes and is_binary(name) and name != "" do
    issuer_logo(security, opts)
  end

  def find_url(%Security{provider: "portfolio_performance", name: name} = security, opts)
      when is_binary(name) and name != "" do
    case Security.effective_asset_class(security) do
      "crypto" -> crypto_by_mapping(security, opts)
      class when class in @derivative_classes -> issuer_logo(security, opts)
      class when class in @equity_classes -> company_logo(security, opts)
      # PP names without a recognizable legal form (e.g. "Amazon", "Microsoft",
      # "Zalando", "XINJIANG GOLDWIND") infer no asset class but are still
      # companies — try a company logo. Commodities/bonds/indices keep their
      # flag/initials fallback.
      nil -> company_logo(security, opts)
      _ -> :skip
    end
  end

  def find_url(%Security{}, _opts), do: :skip

  @doc """
  Whether the background discovery should try to fetch a logo for this
  security. Mirrors what `find_url/2` will actually attempt: equities/ETFs/
  funds/crypto always; structured/leverage products only when their issuer
  (BNP Paribas, Morgan Stanley, …) is recognizable; and imported (Portfolio
  Performance) securities whose name infers no asset class — these are plain
  equities the broker export did not tag (e.g. "Amazon", "Zalando"), which
  previously were silently skipped by the background queue while the manual
  "Update logo" action found them. Commodities, bonds and indices keep their
  flag/initials fallback.
  """
  @spec candidate?(Security.t()) :: boolean()
  def candidate?(%Security{} = security) do
    case Security.effective_asset_class(security) do
      class when class in @equity_classes -> true
      "crypto" -> true
      class when class in @derivative_classes -> detect_issuer(security.name) != nil
      nil -> unclassified_company?(security)
      _ -> false
    end
  end

  def candidate?(_), do: false

  defp unclassified_company?(%Security{provider: "portfolio_performance", name: name})
       when is_binary(name) and name != "",
       do: true

  defp unclassified_company?(_), do: false

  defp crypto_by_mapping(%Security{} = security, opts) do
    case CryptoMap.coin_id(security) do
      nil -> :skip
      id -> coingecko_by_id(id, opts)
    end
  end

  defp coingecko_by_id(id, opts) do
    case CoinGecko.fetch_image_url(id, opts) do
      {:ok, url} -> {:ok, url, :coingecko}
      :not_found -> :skip
      {:error, reason} -> {:error, reason}
    end
  end

  # Equity/ETF/fund: Wikipedia (deterministic titles + search) first, then
  # companieslogo.com as a fallback (by issuer for ETFs, else by company name).
  defp company_logo(%Security{} = security, opts) do
    case wikipedia_by_security(security, opts) do
      {:ok, _url, _source} = ok -> ok
      :skip -> companies_logo_fallback(security, opts)
      {:error, reason} -> companies_logo_or_error(security, opts, reason)
    end
  end

  # Structured/leverage products themselves have no logo; show the issuer's.
  defp issuer_logo(%Security{name: name} = _security, opts) do
    case detect_issuer(name) do
      nil ->
        :skip

      issuer ->
        case lookup_wikipedia_variants(issuer.titles, opts) do
          {:ok, url} -> {:ok, url, :wikipedia}
          :not_found -> companies_logo_by_slug(issuer.slug, opts)
          {:error, reason} -> companies_logo_slug_or_error(issuer.slug, opts, reason)
        end
    end
  end

  defp companies_logo_fallback(%Security{name: name}, opts) do
    case detect_issuer(name) do
      %{slug: slug} -> companies_logo_by_slug(slug, opts)
      nil -> companies_logo_by_slug(name, opts)
    end
  end

  defp companies_logo_by_slug(name_or_slug, opts) do
    case CompaniesLogo.fetch_image_url(name_or_slug, opts) do
      {:ok, url} -> {:ok, url, :companieslogo}
      _ -> :skip
    end
  end

  defp companies_logo_or_error(%Security{} = security, opts, reason) do
    case companies_logo_fallback(security, opts) do
      :skip -> {:error, reason}
      other -> other
    end
  end

  defp companies_logo_slug_or_error(slug, opts, reason) do
    case companies_logo_by_slug(slug, opts) do
      :skip -> {:error, reason}
      other -> other
    end
  end

  defp detect_issuer(name) when is_binary(name) do
    Enum.find_value(@issuers, fn {regex, issuer} ->
      if Regex.match?(regex, name), do: issuer
    end)
  end

  defp detect_issuer(_name), do: nil

  defp wikipedia_by_security(%Security{} = security, opts) do
    case lookup_wikipedia_variants(wikipedia_title_candidates(security), opts) do
      {:ok, url} -> {:ok, url, :wikipedia}
      :not_found -> wikipedia_by_search(security, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  # Last resort when none of the deterministic title variants resolved: search
  # Wikipedia for the cleaned-up company/fund name. The search adapter only
  # returns an image when a candidate passes conservative validation (entity
  # looks like a company/fund and the title is similar to the query), so this
  # does not make false matches like "Apple" -> fruit worse than today.
  defp wikipedia_by_search(%Security{} = security, opts) do
    case search_name(security) do
      query when byte_size(query) >= 3 ->
        case Wikipedia.search_logo(query, opts) do
          {:ok, url} -> {:ok, url, :wikipedia}
          :not_found -> :skip
          {:error, reason} -> {:error, reason}
        end

      _ ->
        :skip
    end
  end

  # Names like "Apple" resolve to the fruit page on Wikipedia and return a
  # photo of an apple, not the Apple Inc. logo. Equity names without a
  # corporate suffix get the "(company)" disambiguator first. Imported names
  # can be all-caps or omit suffix punctuation, so suffix-bearing names also
  # get a normalized Wikipedia title fallback after the stored value.
  defp lookup_wikipedia_variants(titles, opts) when is_list(titles) do
    titles
    |> Enum.reduce_while(:not_found, fn title, _acc ->
      case Wikipedia.lookup(title, opts) do
        {:ok, url} -> {:halt, {:ok, url}}
        :not_found -> {:cont, :not_found}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp wikipedia_title_candidates(%Security{asset_class: class, name: name})
       when class in ["etf", "fund"] do
    name
    |> issuer_logo_titles()
    |> Kernel.++(wikipedia_title_variants(name))
    |> Enum.uniq()
  end

  defp wikipedia_title_candidates(%Security{name: name} = security) do
    case Security.effective_asset_class(security) do
      class when class in ["etf", "fund"] ->
        name
        |> issuer_logo_titles()
        |> Kernel.++(wikipedia_title_variants(name))
        |> Enum.uniq()

      _ ->
        wikipedia_title_variants(name)
    end
  end

  defp issuer_logo_titles(name) do
    case detect_issuer(name) do
      %{titles: titles} -> titles
      nil -> []
    end
  end

  defp wikipedia_title_variants(name) do
    trimmed = String.trim(name)
    normalized = normalize_wikipedia_company_title(trimmed)

    variants =
      if has_company_suffix?(trimmed) do
        [trimmed, normalized]
      else
        ["#{trimmed} (company)", trimmed, normalized]
      end

    # Broker-mangled names ("VESTAS WIND SYS. DK -,20") get a cleaned title as a
    # low-priority extra shot, appended last so it never reorders the existing
    # deterministic variants.
    (variants ++ [broker_clean_title(trimmed)])
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  defp broker_clean_title(trimmed) do
    stripped = strip_broker_artifacts(trimmed)

    if stripped != "" and String.downcase(stripped) != String.downcase(trimmed) do
      normalize_wikipedia_company_title(stripped)
    end
  end

  defp normalize_wikipedia_company_title(name) do
    name
    |> String.downcase()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
    |> normalize_company_suffix()
  end

  defp normalize_company_suffix(title) do
    title
    |> replace_suffix(~r/\bInc\.?\z/i, "Inc.")
    |> replace_suffix(~r/\bCorp\.?\z/i, "Corp.")
    |> replace_suffix(~r/\bLtd\.?\z/i, "Ltd.")
    |> replace_suffix(~r/\bLLC\z/i, "LLC")
    |> replace_suffix(~r/\bGmbh\z/i, "GmbH")
    |> replace_suffix(~r/\bAg\z/i, "AG")
    |> replace_suffix(~r/\bSe\z/i, "SE")
    |> replace_suffix(~r/\bS\.?A\.?\z/i, "S.A.")
    |> replace_suffix(~r/\bN\.?V\.?\z/i, "N.V.")
    |> replace_suffix(~r/\bPlc\z/i, "plc")
  end

  defp replace_suffix(title, regex, replacement), do: Regex.replace(regex, title, replacement)

  defp has_company_suffix?(name) do
    Regex.match?(
      ~r/\b(Inc\.?|Corp(\.|oration)?|Ltd\.?|LLC|GmbH|AG|SE|S\.?A\.?|N\.?V\.?|plc|Holding|Group)\b/i,
      name
    )
  end

  # Strips broker-export noise so the company/fund name can be matched or
  # searched: parentheticals and depositary-receipt/ratio markers
  # ("(Spons.ADRs)/4"), trailing nominal-value tokens ("DK -,20", "DL -,01",
  # "LS-,025"), "o.N."/"o.St.", share-class words and class-letter suffixes,
  # "HLDGS", and hyphen runs from spellings like "NOVO-NORDISK".
  defp strip_broker_artifacts(name) do
    name
    |> String.replace(~r/\([^)]*\)/, " ")
    |> String.replace(~r{/\s*\d+}, " ")
    |> String.replace(~r/\b(Spons\.?|Sponsored)?\s*(ADRs?|GDRs?)\b/i, "")
    |> String.replace(
      ~r/\s+(EO|DL|DM|DK|SK|NK|HK|SF|YE|US|CT|LS|GBP|EUR|USD|CHF|JPY|SEK|NOK|DKK|HKD)\s*-?\s*[,.]?\s*\d[\d.,\s]*$/i,
      ""
    )
    |> String.replace(~r/\bo\.?\s*N\.?\s*$/i, "")
    |> String.replace(~r/\bo\.?\s*St\.?\b/i, "")
    |> String.replace(~r/\b(Inhaber|Namens|Vorzugs|Stamm)[- ]?Akt(ien|\.)?\b/i, "")
    |> String.replace(~r/\bVorz\.?\b/i, "")
    |> String.replace(~r/\bRegistered\s+(Part\.?\s*)?Shares?\b/i, "")
    |> String.replace(~r/\bReg\.?\s*Sh(s|ares?)?\b/i, "")
    |> String.replace(~r/\bHldgs?\.?\b/i, "")
    |> String.replace(~r/\bNew\s*$/i, "")
    |> String.replace(~r/\s+(?:Cl\.?\s*|Class\s*|Ser\.?\s*|Series\s*)?[A-H]\s*$/, "")
    |> String.replace(~r/-+/, " ")
    |> String.replace(~r/\s{2,}/, " ")
    |> String.trim()
    |> String.replace(~r/[\s.]+$/, "")
    |> String.trim()
  end

  defp search_name(%Security{name: name}) when is_binary(name) do
    trimmed = String.trim(name)

    case strip_broker_artifacts(trimmed) do
      "" -> trimmed
      stripped -> stripped
    end
  end

  @doc """
  Runs the full pipeline: discovery + download + persist.

  Returns the updated `%Security{}` on success, `:skip` when no strategy
  matches or the source has no image, or `{:error, reason}` on failure.
  Caller is expected to log failures — this function does so itself when
  invoked from a supervised task.
  """
  @spec run(Security.t(), keyword()) ::
          {:ok, Security.t()} | :skip | {:error, term()}
  def run(%Security{} = security, opts \\ []) do
    case find_url(security, opts) do
      {:ok, url, source} ->
        case LogoStore.download_and_store(security, url, source, opts) do
          {:ok, updated} ->
            {:ok, updated}

          {:error, reason} ->
            Logger.warning(
              "logo download failed for security ##{security.id}: #{inspect(reason)}"
            )

            {:error, reason}
        end

      :skip ->
        :skip

      {:error, reason} ->
        Logger.warning("logo lookup failed for security ##{security.id}: #{inspect(reason)}")

        {:error, reason}
    end
  end
end
