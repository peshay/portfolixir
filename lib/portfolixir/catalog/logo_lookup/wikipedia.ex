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

  alias Portfolixir.Net.Http
  alias Portfolixir.Net.PathSegment

  @endpoint "https://en.wikipedia.org/api/rest_v1/page/summary"
  @search_endpoint "https://en.wikipedia.org/w/rest.php/v1/search/page"
  @wikidata_endpoint "https://www.wikidata.org/wiki/Special:EntityData"
  # The only hosts a request or a redirect hop may reach (F27).
  @allowed_hosts ["en.wikipedia.org", "www.wikidata.org"]
  # Special:FilePath with a width renders SVG logos to PNG (Special:Redirect only
  # 301-redirects to the raw SVG, which the logo store then rejects — #483).
  @commons_file_path "https://commons.wikimedia.org/wiki/Special:FilePath/"
  # The page size the search asks for, and the most candidates one search may
  # turn into summary lookups, whatever the answer carries (F30).
  @search_limit 5

  # A candidate is accepted when its description/excerpt looks like a company
  # or fund and does NOT look like an unrelated topic (a fruit, a genus, a
  # film, …). We deliberately do NOT require the candidate title to share
  # words with the query: Wikipedia ranks the best match first, and many
  # companies live under a different title than their brokerage name (e.g.
  # "Bayerische Motoren Werke" -> "BMW", "Xinjiang Goldwind" -> "Goldwind").
  # The company/non-company guard is what keeps "Apple" -> the fruit out.
  @company_signal ~r/\b(compan(y|ies)|corporation|corporate|multinational|conglomerate|manufacturer|holding|bank|insurer|insurance|technolog|software|retailer|automaker|automotive|pharmaceutic|biotechnolog|enterprise|brand|airline|fund|asset management|investment|exchange[- ]traded|etf|brewer|producer|energy|telecommunication|semiconductor|maker|developer)\b/i
  @non_company_signal ~r/\b(genus|species|fruit|plant|tree|flower|river|mountain|volcano|village|municipality|film|movie|song|album|novel|video game|given name|surname|family name|disambiguation|deity|mytholog|footballer|actress|actor|singer|painter|island|lake)\b/i

  @spec lookup(String.t(), keyword()) ::
          {:ok, String.t()} | :not_found | {:error, term()}
  def lookup(title, opts \\ []) when is_binary(title) do
    # Every identifier placed in a path is one segment (F31).
    with {:ok, segment} <- PathSegment.encode(title) do
      case Http.get(build_req(opts), url: @endpoint <> "/" <> segment) do
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

    case Http.get(req, url: @search_endpoint, params: [q: query, limit: @search_limit]) do
      {:ok, %Req.Response{status: 200, body: %{"pages" => pages}}} when is_list(pages) ->
        pages
        |> Enum.take(@search_limit)
        |> Enum.filter(&company_like?/1)
        |> Enum.filter(&title_matches_query?(&1, query))
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
    with title when is_binary(title) <- candidate_title(page),
         {:ok, url} <- lookup(title, opts) do
      {:ok, url}
    else
      _ -> first_candidate_image(rest, opts)
    end
  end

  # Every field of an upstream candidate is type-matched before use (F30).
  defp candidate_title(%{"key" => key}) when is_binary(key) and key != "", do: key
  defp candidate_title(%{"title" => title}) when is_binary(title), do: title
  defp candidate_title(_page), do: nil

  defp company_like?(%{"title" => title} = page) when is_binary(title) do
    looks_like_company?(text_field(page, "description") <> " " <> text_field(page, "excerpt"))
  end

  defp company_like?(_page), do: false

  defp text_field(page, key) do
    case Map.get(page, key) do
      value when is_binary(value) -> value
      _ -> ""
    end
  end

  defp looks_like_company?(text) do
    Regex.match?(@company_signal, text) and not Regex.match?(@non_company_signal, text)
  end

  # Stop the fuzzy search from accepting an unrelated brand: the candidate's
  # title must relate to the query, so "Swarmer Inc" does not match "Docker
  # (container engine)" (#487). It relates when it shares a meaningful token
  # (Apple ~ "Apple Inc.") or is an acronym of the query (BMW ~ "Bayerische
  # Motoren Werke") — the common German AG-abbreviation case. A company under a
  # wholly unrelated title falls through to the companieslogo fallback or to no
  # logo; a missing logo is better than a wrong one.
  @name_stopwords ~w(inc incorporated corp corporation co company group holding holdings
                     the and of ag se plc sa nv ltd llc lp)
  defp title_matches_query?(page, query) when is_map(page) do
    title = if is_binary(page["title"]), do: page["title"], else: ""
    query_tokens = name_tokens(query)

    query_tokens != [] and
      (shares_token?(query_tokens, name_tokens(title)) or acronym_of?(title, query_tokens))
  end

  defp shares_token?(a, b), do: not MapSet.disjoint?(MapSet.new(a), MapSet.new(b))

  # "BMW" is the initials of "Bayerische Motoren Werke". Treat the title as a
  # match when its letters are a prefix of (or equal to) the query tokens'
  # initials, ignoring trailing share-class noise.
  defp acronym_of?(title, query_tokens) do
    letters = title |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")
    initials = query_tokens |> Enum.map_join(&String.first/1)

    String.length(letters) >= 2 and
      (letters == initials or String.starts_with?(initials, letters))
  end

  defp name_tokens(text) do
    text
    |> String.downcase()
    |> String.replace(~r/\(.*?\)/, " ")
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    |> Enum.reject(&(&1 in @name_stopwords or String.length(&1) < 2))
  end

  defp build_req(opts) do
    base =
      Http.new(
        headers: [{"user-agent", "portfolixir/0.1 (logo-lookup)"}],
        receive_timeout: 5_000,
        allowed_hosts: @allowed_hosts,
        max_bytes: 2 * 1024 * 1024,
        deadline_ms: 15_000
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
    with {:ok, segment} <- PathSegment.encode(id) do
      case Http.get(build_req(opts), url: @wikidata_endpoint <> "/" <> segment <> ".json") do
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
  end

  # Every level of the entity is type-matched before it is read (F30).
  defp logo_url_from_entity(body, id) do
    with %{"entities" => %{} = entities} <- body,
         %{"claims" => %{"P154" => claims}} when is_list(claims) <- Map.get(entities, id),
         filename when is_binary(filename) and filename != "" <- first_logo_filename(claims),
         {:ok, segment} <- PathSegment.encode(filename) do
      {:ok, commons_logo_redirect(segment)}
    else
      _ -> :not_found
    end
  end

  defp first_logo_filename(claims) do
    Enum.find_value(claims, fn
      %{"mainsnak" => %{"datavalue" => %{"value" => value}}} when is_binary(value) -> value
      _claim -> nil
    end)
  end

  defp commons_logo_redirect(segment), do: @commons_file_path <> segment <> "?width=256"

  defp summary_image(%{"thumbnail" => %{"source" => source}}) when is_binary(source),
    do: {:ok, source}

  defp summary_image(%{"originalimage" => %{"source" => source}}) when is_binary(source),
    do: {:ok, source}

  defp summary_image(_body), do: :not_found
end
