defmodule Portfolixir.Catalog.LogoLookup do
  @moduledoc """
  Dispatches a security to the right logo source based on its asset
  class / provider, downloads the image once via `LogoStore` and stores
  the relative path on the security's `attributes` map.

  Strategies:
    * `asset_class = "crypto"` with `provider = "coingecko"` and a
      non-empty `online_id` -> CoinGecko `/coins/{id}` -> `image.large`.
    * `asset_class in ~w(equity etf fund)` -> Wikipedia REST. ETFs/funds
      try known issuer titles (iShares, Vanguard, Lyxor, …) before the
      individual fund name.
    * anything else -> `:skip`.

  The `:req` option is forwarded to both the lookup adapters and the
  store so a single Req plug-stub can be used end-to-end in tests.
  """

  require Logger

  alias Portfolixir.Catalog.LogoLookup.Wikipedia
  alias Portfolixir.Catalog.LogoStore
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecuritySearch.CoinGecko

  @equity_classes ~w(equity etf fund)
  @issuer_logo_titles [
    {~r/\biShares\b/i, ["iShares"]},
    {~r/\bVanguard\b/i, ["The Vanguard Group"]},
    {~r/\bLyxor\b/i, ["Lyxor Asset Management", "Lyxor"]},
    {~r/\b(AIS-?AM|Amundi)\b/i, ["Amundi"]},
    {~r/\b(Xtrackers|DWS)\b/i, ["DWS Group", "Xtrackers"]},
    {~r/\b(SPDR|State Street)\b/i, ["State Street Global Advisors"]},
    {~r/\bInvesco\b/i, ["Invesco"]},
    {~r/\bWisdomTree\b/i, ["WisdomTree Investments"]},
    {~r/\bVanEck\b/i, ["VanEck"]},
    {~r/\bUBS\b/i, ["UBS"]},
    {~r/\bBNP\s+Paribas\b|\bBNPP\b/i, ["BNP Paribas"]},
    {~r/\bHSBC\b/i, ["HSBC"]},
    {~r/\bFranklin\b/i, ["Franklin Templeton Investments"]},
    {~r/\bJPMorgan\b|\bJPM\b/i, ["JPMorgan Chase"]},
    {~r/\bFidelity\b/i, ["Fidelity Investments"]},
    {~r/\bDeka\b/i, ["DekaBank"]}
  ]

  @spec find_url(Security.t(), keyword()) ::
          {:ok, String.t(), atom()} | :skip | {:error, term()}
  def find_url(
        %Security{asset_class: "crypto", provider: "coingecko", online_id: id} = _sec,
        opts
      )
      when is_binary(id) and id != "" do
    case CoinGecko.fetch_image_url(id, opts) do
      {:ok, url} -> {:ok, url, :coingecko}
      :not_found -> :skip
      {:error, reason} -> {:error, reason}
    end
  end

  def find_url(%Security{asset_class: class, name: name} = security, opts)
      when class in @equity_classes and is_binary(name) and name != "" do
    wikipedia_by_security(security, opts)
  end

  def find_url(%Security{provider: "portfolio_performance", name: name} = security, opts)
      when is_binary(name) and name != "" do
    wikipedia_by_security(security, opts)
  end

  def find_url(%Security{}, _opts), do: :skip

  defp wikipedia_by_security(%Security{} = security, opts) do
    case lookup_wikipedia_variants(wikipedia_title_candidates(security), opts) do
      {:ok, url} -> {:ok, url, :wikipedia}
      :not_found -> :skip
      {:error, reason} -> {:error, reason}
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
    Enum.find_value(@issuer_logo_titles, [], fn {regex, titles} ->
      if Regex.match?(regex, name), do: titles
    end)
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

    variants
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
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
