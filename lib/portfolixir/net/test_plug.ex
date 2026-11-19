defmodule Portfolixir.Net.TestPlug do
  @moduledoc """
  The one request option a provider adapter takes from its caller (#1356):
  a test's `plug:`, and only where the configuration allows one
  (`config :portfolixir, Portfolixir.Net.TestPlug, allow: true`, which only
  the test configuration sets).

  The Yahoo quotes, the ECB rates, the logo path (the logo store, the
  Wikipedia and companieslogo.com lookups, and CoinGecko's image read) and
  the Portfolio Performance security search used
  to merge whatever `req:` options their caller passed into the request
  `Portfolixir.Net.Http` built: another base URL, headers, a transport. Each
  stayed bound to its host allow-list, so nothing escaped, but nothing in
  the application passes one, and the news fetcher had stopped taking any
  (Sprint 27, SEC1). `merge/2` keeps that seam for a test's stub alone:
  any other option, or a plug where the configuration allows none, raises
  `ArgumentError` naming the options' keys (never their values) before a
  request exists.
  """

  @doc """
  `req` with the caller's `req: [plug: plug]` merged, where the
  configuration allows a test's plug; `req` as built when `opts` carries no
  `req:` (or an empty one). Raises `ArgumentError` for anything else.
  """
  # The request is the one `Portfolixir.Net.Http.new/1` built; this module
  # names no Req type, so the outbound chokepoint's scan reads only the
  # merge it registers.
  @spec merge(struct(), keyword()) :: struct()
  def merge(req, opts) when is_struct(req) and is_list(opts) do
    case Keyword.get(opts, :req) do
      nil -> req
      [] -> req
      [plug: plug] -> if allowed?(), do: Req.merge(req, plug: plug), else: refuse([:plug])
      other -> refuse(keys(other))
    end
  end

  defp allowed? do
    :portfolixir
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:allow, false)
  end

  defp keys(options) when is_list(options) do
    for option <- options, do: if(is_tuple(option), do: elem(option, 0), else: :invalid)
  end

  defp keys(_options), do: [:invalid]

  defp refuse(keys) do
    raise ArgumentError,
          "a provider adapter takes no request option from its caller but a test's plug " <>
            "(#1356); refused: #{inspect(keys)}"
  end
end
