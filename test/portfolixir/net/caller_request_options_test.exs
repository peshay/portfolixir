defmodule Portfolixir.Net.CallerRequestOptionsTest do
  # #1356 (Sprint 27's SEC1 fixer on #1422): the Yahoo, ECB and logo adapters
  # merged whatever `req:` options their caller handed them into the bounded
  # request -- another base URL, headers, a plug. Each stayed host-bound by
  # its allow-list, so nothing escaped, but the news fetcher had already
  # stopped taking any. Now they take one option from a caller, a test's
  # `plug:`, and only where the configuration allows it
  # (`config :portfolixir, Portfolixir.Net.TestPlug, allow: true`, the test
  # configuration's); anything else is refused before a request is built.
  #
  # async: false -- one case turns the configuration's allowance off.
  # Every name and answer is synthetic.
  use ExUnit.Case, async: false

  alias Portfolixir.Catalog.LogoLookup.CompaniesLogo
  alias Portfolixir.Catalog.LogoLookup.Wikipedia
  alias Portfolixir.Catalog.LogoStore
  alias Portfolixir.Catalog.QuoteSync.Yahoo
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecuritySearch.CoinGecko
  alias Portfolixir.Catalog.SecuritySearch.PortfolioPerformance
  alias Portfolixir.Fx.RateSync.Ecb

  defp calls do
    [
      {"Yahoo quotes",
       &Yahoo.fetch(%Security{ticker_symbol: "SYN", provider: "portfolio_performance"}, req: &1)},
      {"ECB daily rates", &Ecb.fetch(req: &1)},
      {"ECB rate history", &Ecb.fetch_history(req: &1)},
      {"CoinGecko image (the logo lookup's crypto path)",
       &CoinGecko.fetch_image_url("synthetic-coin", req: &1)},
      # The security search was left out of #1356 (Sprint 30 closing act,
      # security lens, finding 3).
      {"Portfolio Performance search", &PortfolioPerformance.search("synthetic", req: &1)},
      {"Wikipedia summary", &Wikipedia.lookup("Synthetic", req: &1)},
      {"Wikipedia search", &Wikipedia.search_logo("Synthetic", req: &1)},
      {"companieslogo page", &CompaniesLogo.fetch_image_url("Synthetic Corp", req: &1)},
      {"logo download",
       &LogoStore.download_and_store(
         %Security{id: 1, name: "Synthetic Corp"},
         "https://upload.wikimedia.org/synthetic.png",
         :wikipedia,
         req: &1,
         storage_dir: System.tmp_dir!()
       )}
    ]
  end

  # A stub that reports every request it answers to the test process.
  defp stub do
    test_pid = self()

    fn conn ->
      send(test_pid, {:stub_request, conn.host, Plug.Conn.get_req_header(conn, "x-caller")})
      Plug.Conn.send_resp(conn, 404, "")
    end
  end

  # The call is refused: it raises ArgumentError naming the option, or an
  # adapter that turns its own exceptions into a value answers an error.
  defp assert_refused(name, call, options) do
    result =
      try do
        call.(options)
      rescue
        error in ArgumentError ->
          assert Exception.message(error) =~ "takes no request option from its caller", name
          :raised
      end

    assert result == :raised or match?({:error, _}, result), "#{name}: #{inspect(result)}"
    refute_received {:stub_request, _host, _header}, "#{name} sent a request"
  end

  # User story (#1356):
  # As the operator whose instance asks Yahoo, the ECB, Wikipedia,
  # companieslogo.com, CoinGecko and the Portfolio Performance search,
  # I want each adapter to send only the request it builds itself,
  # so that no caller can add a host, a header or a transport to it.
  #
  # Acceptance criteria:
  # - A caller's base URL, header or any option beside a plug is refused,
  #   plug included, and no request is made.
  # - Without the configuration's allowance a caller's plug alone is
  #   refused too, and no request is made.
  # - With it, a test's plug alone still answers the adapter's request.
  test "every adapter refuses a caller's request options and sends no request" do
    for {name, call} <- calls() do
      assert_refused(name, call,
        plug: stub(),
        base_url: "https://elsewhere.test",
        headers: [{"x-caller", "synthetic"}]
      )

      assert_refused(name, call, headers: [{"x-caller", "synthetic"}])
    end
  end

  test "a caller's plug is refused unless the configuration allows a test's" do
    previous = Application.get_env(:portfolixir, Portfolixir.Net.TestPlug)
    Application.put_env(:portfolixir, Portfolixir.Net.TestPlug, allow: false)

    try do
      for {name, call} <- calls(), do: assert_refused(name, call, plug: stub())
    after
      if previous,
        do: Application.put_env(:portfolixir, Portfolixir.Net.TestPlug, previous),
        else: Application.delete_env(:portfolixir, Portfolixir.Net.TestPlug)
    end

    # Allowed, as the test configuration has it: the plug answers.
    assert {:error, _} = Ecb.fetch(req: [plug: stub()])
    assert_received {:stub_request, "www.ecb.europa.eu", []}
  end
end
