defmodule Portfolixir.Catalog.SecuritySearch do
  @moduledoc """
  Fans search queries out to the configured providers and merges their
  results. Each provider runs in its own Task and is isolated against errors
  — a single failing adapter never breaks the overall search.
  """

  require Logger

  alias Portfolixir.Catalog.SecuritySearch.SearchResult

  @doc """
  Runs the given query against every configured provider.

  Options:
    * `:providers` – list of adapter modules (overrides config)
    * `:timeout_ms` – per-provider timeout (default from config, 4000)
  """
  def search(query, opts \\ [])

  def search(query, _opts) when not is_binary(query), do: {:ok, []}

  def search(query, opts) do
    trimmed = String.trim(query)

    if trimmed == "" do
      {:ok, []}
    else
      providers = opts[:providers] || config(:providers, [])
      timeout = opts[:timeout_ms] || config(:timeout_ms, 4000)

      results =
        providers
        |> Task.async_stream(&run_provider(&1, trimmed, opts),
          timeout: timeout + 500,
          on_timeout: :kill_task
        )
        |> Enum.flat_map(fn
          {:ok, list} when is_list(list) -> list
          _ -> []
        end)
        |> dedupe()

      {:ok, results}
    end
  end

  defp run_provider(provider, query, opts) do
    case safe_call(provider, query, opts) do
      {:ok, results} when is_list(results) ->
        results

      {:error, reason} ->
        Logger.warning("security search provider #{inspect(provider)} failed: #{inspect(reason)}")

        []

      other ->
        Logger.warning(
          "security search provider #{inspect(provider)} returned unexpected #{inspect(other)}"
        )

        []
    end
  end

  defp safe_call(provider, query, opts) do
    provider.search(query, opts)
  rescue
    error ->
      {:error, error}
  catch
    kind, value ->
      {:error, {kind, value}}
  end

  defp dedupe(results) do
    {by_id, rest} =
      Enum.split_with(results, fn %SearchResult{} = r ->
        r.online_id != nil
      end)

    by_id =
      by_id
      |> Enum.uniq_by(fn r -> {r.provider, r.online_id} end)

    rest = Enum.uniq_by(rest, fn r -> {r.provider, r.isin, r.ticker_symbol, r.name} end)
    by_id ++ rest
  end

  defp config(key, default) do
    Application.get_env(:portfolixir, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
