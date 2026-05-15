defmodule Portfolixir.Catalog.LogoLookup do
  @moduledoc """
  Dispatches a security to the right logo source based on its asset
  class / provider, downloads the image once via `LogoStore` and stores
  the relative path on the security's `attributes` map.

  Strategies:
    * `asset_class = "crypto"` with `provider = "coingecko"` and a
      non-empty `online_id` -> CoinGecko `/coins/{id}` -> `image.large`.
    * `asset_class in ~w(equity etf fund)` -> Wikipedia REST
      `page/summary/{name}` -> `originalimage.source`.
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

  def find_url(%Security{asset_class: class, name: name}, opts)
      when class in @equity_classes and is_binary(name) and name != "" do
    case lookup_wikipedia_variants(name, opts) do
      {:ok, url} -> {:ok, url, :wikipedia}
      :not_found -> :skip
      {:error, reason} -> {:error, reason}
    end
  end

  def find_url(%Security{}, _opts), do: :skip

  # Names like "Apple" resolve to the fruit page on Wikipedia and return a
  # photo of an apple, not the Apple Inc. logo. Equity names without a
  # corporate suffix get the "(company)" disambiguator first; the bare
  # name is only tried when the name already carries Inc./Corp./AG/...
  # (in which case "X (company)" usually doesn't exist).
  defp lookup_wikipedia_variants(name, opts) do
    variants =
      if has_company_suffix?(name) do
        [name]
      else
        ["#{name} (company)"]
      end

    Enum.reduce_while(variants, :not_found, fn title, _acc ->
      case Wikipedia.lookup(title, opts) do
        {:ok, url} -> {:halt, {:ok, url}}
        :not_found -> {:cont, :not_found}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

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
