defmodule Portfolixir.Catalog.LogoLookup.CompaniesLogo do
  @moduledoc """
  Looks up a company/issuer logo from companieslogo.com as a fallback when
  CoinGecko/Wikipedia yield nothing.

  The site exposes a logo page per company at `/{slug}/logo/` whose
  `og:image` meta tag points at the canonical logo bitmap. We derive a slug
  from the (cleaned) company name, fetch the page and return the `og:image`
  URL — the actual download + validation happens in `LogoStore`.

  Returns:
    * `{:ok, url}` when an `og:image` was found.
    * `:not_found` when no candidate slug resolved to a page with an image.
    * `{:error, reason}` for HTTP/transport failures.

  The `:req` option accepts the same shape `Req.merge/2` accepts (e.g. a
  `plug:` stub) so tests never reach the public internet.
  """

  alias Portfolixir.Net.Http

  @base_url "https://companieslogo.com"

  @og_image ~r/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i
  @og_image_rev ~r/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i

  # Dropped from the slug so "Apple Inc." and "Apple" hit the same page.
  @suffix_words ~w(inc incorporated corp corporation co company ag se plc sa nv ltd
                   limited holding holdings group the and class registered shares)

  @spec fetch_image_url(String.t(), keyword()) ::
          {:ok, String.t()} | :not_found | {:error, term()}
  def fetch_image_url(name, opts \\ []) when is_binary(name) do
    name
    |> slug_candidates()
    |> try_slugs(opts, :not_found)
  end

  defp try_slugs([], _opts, last), do: last

  defp try_slugs([slug | rest], opts, last) do
    case fetch_slug(slug, opts) do
      {:ok, url} -> {:ok, url}
      :not_found -> try_slugs(rest, opts, last)
      {:error, _} = err -> try_slugs(rest, opts, err)
    end
  end

  defp fetch_slug(slug, opts) do
    url = @base_url <> "/" <> slug <> "/logo/"

    case Http.get(build_req(opts), url: url) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        extract_og_image(body)

      {:ok, %Req.Response{status: 404}} ->
        :not_found

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_og_image(html) do
    case Regex.run(@og_image, html) || Regex.run(@og_image_rev, html) do
      [_, url] when is_binary(url) and url != "" -> {:ok, url}
      _ -> :not_found
    end
  end

  @doc false
  def slug_candidates(name) when is_binary(name) do
    cleaned =
      name
      |> String.downcase()
      |> String.replace(~r/\(.*?\)/, " ")
      |> String.split(~r/[^a-z0-9]+/, trim: true)
      |> Enum.reject(&(&1 in @suffix_words))

    full = Enum.join(cleaned, "-")
    first = List.first(cleaned)

    [full, first]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  defp build_req(opts) do
    base =
      Http.new(
        headers: [{"user-agent", "portfolixir/0.1 (logo-lookup)"}],
        receive_timeout: 5_000,
        decode_body: false,
        max_bytes: 2 * 1024 * 1024,
        deadline_ms: 15_000
      )

    case opts[:req] do
      nil -> base
      overrides when is_list(overrides) -> Req.merge(base, overrides)
    end
  end
end
