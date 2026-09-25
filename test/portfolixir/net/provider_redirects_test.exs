defmodule Portfolixir.Net.ProviderRedirectsTest do
  # E25 S3, F27 (#888): every provider adapter is built on the bounded client,
  # so every adapter inherits its redirect guard. This table walks each
  # adapter's every request with an upstream that answers with a redirect to a
  # target the policy refuses, and asserts that no second request is made.
  use ExUnit.Case, async: true

  alias Portfolixir.Catalog.LogoLookup.{CompaniesLogo, Wikipedia}
  alias Portfolixir.Catalog.QuoteSync.Yahoo
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecuritySearch.{CoinGecko, PortfolioPerformance}
  alias Portfolixir.Fx.RateSync.Ecb

  @landing "/redirect-landing"

  defp calls do
    [
      {"Yahoo quotes",
       &Yahoo.fetch(
         %Security{ticker_symbol: "SYN", provider: "portfolio_performance"},
         req: &1
       )},
      {"ECB daily rates", &Ecb.fetch(req: &1)},
      {"ECB rate history", &Ecb.fetch_history(req: &1)},
      {"CoinGecko search", &CoinGecko.search("syn", req: &1)},
      {"CoinGecko image", &CoinGecko.fetch_image_url("synthetic-coin", req: &1)},
      {"Portfolio Performance search", &PortfolioPerformance.search("syn", req: &1)},
      {"Wikipedia summary", &Wikipedia.lookup("Synthetic", req: &1)},
      {"Wikipedia search", &Wikipedia.search_logo("Synthetic", req: &1)},
      {"companieslogo page", &CompaniesLogo.fetch_image_url("Synthetic Corp", req: &1)}
    ]
  end

  # Every target the policy refuses: another host, a literal private address,
  # and a downgrade to plain http on the adapter's own host (the plug answers
  # any host, so a followed downgrade would be visible by its path).
  defp refused_targets(own_host) do
    [
      "https://elsewhere.test#{@landing}",
      "https://10.0.0.5#{@landing}",
      "http://#{own_host}#{@landing}"
    ]
  end

  defp redirecting_stub(test_pid, target_for) do
    [
      plug: fn conn ->
        send(test_pid, {:request, conn.host, conn.request_path})

        if conn.request_path == @landing do
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, "{}")
        else
          conn
          |> Plug.Conn.put_resp_header("location", target_for.(conn.host))
          |> Plug.Conn.send_resp(302, "")
        end
      end
    ]
  end

  # User story:
  # As an operator whose instance syncs quotes and rates and searches and
  # looks up logos at third parties,
  # I want no provider able to move a request of mine with a redirect,
  # so that an impersonated or hostile provider cannot turn my scheduled sync
  # into a request to my own network or to a host of its choosing.
  #
  # Acceptance criteria:
  # - For every adapter request, a redirect to another host, to a private
  #   address or to plain http is refused: the landing target is never
  #   requested and the adapter returns an error or not-found, never data.
  test "no adapter follows a redirect the URL policy refuses" do
    test_pid = self()

    for {label, call} <- calls(), index <- 0..2 do
      stub =
        redirecting_stub(test_pid, fn own_host -> Enum.at(refused_targets(own_host), index) end)

      result = call.(stub)

      refute match?({:ok, [_ | _]}, result), "#{label} returned data: #{inspect(result)}"
      refute match?({:ok, url} when is_binary(url), result), "#{label}: #{inspect(result)}"

      requests = collect_requests()
      assert requests != [], "#{label} made no request at all"

      refute Enum.any?(requests, fn {_host, path} -> path == @landing end),
             "#{label} followed a refused redirect (target #{index}): #{inspect(requests)}"
    end
  end

  defp collect_requests(acc \\ []) do
    receive do
      {:request, host, path} -> collect_requests([{host, path} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
