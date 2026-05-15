defmodule Portfolixir.Catalog.LogoLookup.Wikipedia do
  @moduledoc """
  Looks up a logo image URL from the Wikipedia REST API.

  The endpoint is `https://en.wikipedia.org/api/rest_v1/page/summary/{title}`.
  Wikipedia returns an `originalimage` object on most company pages — that
  is what we use as the logo source.

  Returns:
    * `{:ok, url}` when a usable image URL was found.
    * `:not_found` when the page exists but has no `originalimage`.
    * `{:error, reason}` for HTTP and transport failures.

  The `:req` option accepts the same shape `Req.merge/2` accepts (e.g. a
  `plug:` stub) so tests never reach the public internet.
  """

  @endpoint "https://en.wikipedia.org/api/rest_v1/page/summary"

  @spec lookup(String.t(), keyword()) ::
          {:ok, String.t()} | :not_found | {:error, term()}
  def lookup(title, opts \\ []) when is_binary(title) do
    url = @endpoint <> "/" <> URI.encode(title, &URI.char_unreserved?/1)
    req = build_req(opts)

    case Req.get(req, url: url) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        case body do
          %{"originalimage" => %{"source" => source}} when is_binary(source) ->
            {:ok, source}

          _ ->
            :not_found
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
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
end
