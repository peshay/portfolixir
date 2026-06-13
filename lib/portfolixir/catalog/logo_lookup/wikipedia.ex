defmodule Portfolixir.Catalog.LogoLookup.Wikipedia do
  @moduledoc """
  Looks up a logo image URL from the Wikipedia REST API.

  The endpoint is `https://en.wikipedia.org/api/rest_v1/page/summary/{title}`.
  Wikipedia returns an `originalimage` object on most company pages — that
  is used as a last-resort image source. When the summary exposes a
  Wikidata item with a logo image claim, the rendered Commons logo is
  preferred.

  Returns:
    * `{:ok, url}` when a usable image URL was found.
    * `:not_found` when the page exists but has no `originalimage`, or
      when Wikipedia returns 404 for a deterministic fallback title.
    * `{:error, reason}` for other HTTP and transport failures.

  The `:req` option accepts the same shape `Req.merge/2` accepts (e.g. a
  `plug:` stub) so tests never reach the public internet.
  """

  @endpoint "https://en.wikipedia.org/api/rest_v1/page/summary"
  @search_endpoint "https://en.wikipedia.org/w/rest.php/v1/search/page"
  @wikidata_endpoint "https://www.wikidata.org/wiki/Special:EntityData"
  @commons_file_redirect "https://commons.wikimedia.org/wiki/Special:Redirect/file/"

  # A candidate is only accepted when its description/excerpt looks like a
  # company or fund and does NOT look like an unrelated topic (a fruit, a
  # genus, a film, …). This keeps the search from making false matches such
  # as "Apple" -> the fruit worse than the deterministic title lookup.
  @company_signal ~r/\b(compan(y|ies)|corporation|corporate|multinational|conglomerate|manufacturer|holding|bank|insurer|insurance|technolog|software|retailer|automaker|automotive|pharmaceutic|biotechnolog|enterprise|brand|airline|fund|asset management|investment|exchange[- ]traded|etf|brewer|producer|energy|telecommunication|semiconductor)\b/i
  @non_company_signal ~r/\b(genus|species|fruit|plant|tree|flower|river|mountain|volcano|village|municipality|film|movie|song|album|novel|video game|given name|surname|family name|disambiguation|deity|mytholog|footballer|actress|actor|singer|painter|island|lake)\b/i
  @stop_tokens ~w(the of and for inc corp corporation ltd limited ag se plc co company group holding nv sa class shares)

  @spec lookup(String.t(), keyword()) ::
          {:ok, String.t()} | :not_found | {:error, term()}
  def lookup(title, opts \\ []) when is_binary(title) do
    url = @endpoint <> "/" <> URI.encode(title, &URI.char_unreserved?/1)
    req = build_req(opts)

    case Req.get(req, url: url) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        image_from_summary(body, opts)

      {:ok, %Req.Response{status: 404}} ->
        :not_found

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Searches Wikipedia for a company/fund by name and returns the image of the
  first candidate that passes conservative validation.

  Returns `{:ok, url}`, `:not_found` (no usable candidate), or
  `{:error, reason}` for HTTP/transport failures on the search request.
  """
  @spec search_logo(String.t(), keyword()) ::
          {:ok, String.t()} | :not_found | {:error, term()}
  def search_logo(query, opts \\ []) when is_binary(query) do
    req = build_req(opts)

    case Req.get(req, url: @search_endpoint, params: [q: query, limit: 5]) do
      {:ok, %Req.Response{status: 200, body: %{"pages" => pages}}} when is_list(pages) ->
        pages
        |> Enum.filter(&plausible_match?(&1, query))
        |> first_candidate_image(opts)

      {:ok, %Req.Response{status: status}} when status in [200, 404] ->
        :not_found

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp first_candidate_image([], _opts), do: :not_found

  defp first_candidate_image([page | rest], opts) do
    case lookup(page["key"] || page["title"], opts) do
      {:ok, url} -> {:ok, url}
      _ -> first_candidate_image(rest, opts)
    end
  end

  defp plausible_match?(%{"title" => title} = page, query) when is_binary(title) do
    text = "#{page["description"] || ""} #{page["excerpt"] || ""}"
    similar_title?(title, query) and looks_like_company?(text)
  end

  defp plausible_match?(_page, _query), do: false

  defp looks_like_company?(text) do
    Regex.match?(@company_signal, text) and not Regex.match?(@non_company_signal, text)
  end

  defp similar_title?(title, query) do
    title_tokens = MapSet.new(tokenize(title))
    query_tokens = tokenize(query)
    query_set = MapSet.new(query_tokens)

    if MapSet.size(title_tokens) == 0 or MapSet.size(query_set) == 0 do
      false
    else
      common = MapSet.size(MapSet.intersection(title_tokens, query_set))
      common > 0 and common / MapSet.size(query_set) >= 0.34
    end
  end

  defp tokenize(string) do
    string
    |> String.downcase()
    |> String.replace(~r/\(.*?\)/, " ")
    |> String.replace(~r/[^a-z0-9 ]/u, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(&1 in @stop_tokens))
  end

  defp build_req(opts) do
    base =
      Req.new(
        headers: [{"user-agent", "portfolixir/0.1 (logo-lookup)"}],
        receive_timeout: 5_000,
        retry: false
      )

    case opts[:req] do
      nil -> base
      overrides when is_list(overrides) -> Req.merge(base, overrides)
    end
  end

  defp image_from_summary(%{} = body, opts) do
    case wikidata_logo_from_summary(body, opts) do
      {:ok, url} ->
        {:ok, url}

      :not_found ->
        summary_image(body)

      {:error, reason} ->
        case summary_image(body) do
          :not_found -> {:error, reason}
          fallback -> fallback
        end
    end
  end

  defp image_from_summary(_body, _opts), do: :not_found

  defp wikidata_logo_from_summary(%{"wikibase_item" => id}, opts)
       when is_binary(id) and id != "" do
    lookup_wikidata_logo(id, opts)
  end

  defp wikidata_logo_from_summary(_body, _opts), do: :not_found

  defp lookup_wikidata_logo(id, opts) do
    url = @wikidata_endpoint <> "/" <> URI.encode(id, &URI.char_unreserved?/1) <> ".json"
    req = build_req(opts)

    case Req.get(req, url: url) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        logo_url_from_entity(body, id)

      {:ok, %Req.Response{status: 404}} ->
        :not_found

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp logo_url_from_entity(body, id) do
    with %{"entities" => entities} <- body,
         %{} = entity <- Map.get(entities, id),
         claims when is_list(claims) <- get_in(entity, ["claims", "P154"]),
         filename when is_binary(filename) and filename != "" <- first_logo_filename(claims) do
      {:ok, commons_logo_redirect(filename)}
    else
      _ -> :not_found
    end
  end

  defp first_logo_filename(claims) do
    Enum.find_value(claims, fn claim ->
      get_in(claim, ["mainsnak", "datavalue", "value"])
    end)
  end

  defp commons_logo_redirect(filename) do
    @commons_file_redirect <> URI.encode(filename, &URI.char_unreserved?/1) <> "?width=256"
  end

  defp summary_image(%{"thumbnail" => %{"source" => source}}) when is_binary(source),
    do: {:ok, source}

  defp summary_image(%{"originalimage" => %{"source" => source}}) when is_binary(source),
    do: {:ok, source}

  defp summary_image(_body), do: :not_found
end
