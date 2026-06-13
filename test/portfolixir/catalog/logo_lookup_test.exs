defmodule Portfolixir.Catalog.LogoLookupTest do
  # User story:
  # As a local portfolio maintainer,
  # I want Portfolixir to find a logo for each new security on its own
  # (crypto via CoinGecko, equities/ETFs via Wikipedia), so I don't have to
  # download images manually like I did in Portfolio Performance.
  #
  # Acceptance criteria for the dispatcher:
  # - Crypto with `provider="coingecko"` and an `online_id` consults the
  #   CoinGecko detail API and yields `{:ok, url, :coingecko}`.
  # - Equity/ETF/Fund consults Wikipedia REST `page/summary/{title}` and
  #   yields `{:ok, url, :wikipedia}` when the page returns an
  #   `originalimage`.
  # - Anything else (index, commodity, bond, crypto without online_id,
  #   …) returns `:skip` without touching the network.
  # - Transport-level errors are surfaced as `{:error, reason}` so the
  #   caller can log them; the security is left unchanged.
  use ExUnit.Case, async: true

  alias Portfolixir.Catalog.LogoLookup
  alias Portfolixir.Catalog.Security

  defp plug_stub(fun), do: [plug: fun]

  defp json_response(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  describe "find_url/2" do
    test "crypto -> CoinGecko detail endpoint -> image.large" do
      stub =
        plug_stub(fn conn ->
          assert conn.request_path =~ "/coins/bitcoin"

          json_response(conn, 200, %{
            "image" => %{
              "thumb" => "thumb.png",
              "small" => "small.png",
              "large" => "https://coingecko/large.png"
            }
          })
        end)

      security = %Security{
        provider: "coingecko",
        online_id: "bitcoin",
        asset_class: "crypto",
        name: "Bitcoin"
      }

      assert {:ok, "https://coingecko/large.png", :coingecko} =
               LogoLookup.find_url(security, req: stub)
    end

    test "equity -> Wikipedia REST page summary -> originalimage.source" do
      stub =
        plug_stub(fn conn ->
          assert conn.request_path =~ "/api/rest_v1/page/summary/"

          json_response(conn, 200, %{
            "originalimage" => %{"source" => "https://wikipedia/Apple_Inc..png"}
          })
        end)

      security = %Security{
        provider: "manual",
        asset_class: "equity",
        name: "Apple Inc.",
        ticker_symbol: "AAPL"
      }

      assert {:ok, "https://wikipedia/Apple_Inc..png", :wikipedia} =
               LogoLookup.find_url(security, req: stub)
    end

    # User story:
    # As a local portfolio maintainer importing Portfolio Performance securities,
    # I want logo lookup to use the security name even when PP did not provide an asset class,
    # so that import-created securities can be enriched without inventing classifications.
    #
    # Acceptance criteria:
    # - `provider="portfolio_performance"` with a name uses Wikipedia lookup.
    # - No asset class is required for that path.
    # - The lookup still uses the normal stubbed request path in tests.
    test "Portfolio Performance securities can use name-based Wikipedia lookup without asset class" do
      stub =
        plug_stub(fn conn ->
          assert conn.request_path =~ "/api/rest_v1/page/summary/"

          json_response(conn, 200, %{
            "originalimage" => %{"source" => "https://wikipedia/Imported.png"}
          })
        end)

      security = %Security{
        provider: "portfolio_performance",
        asset_class: nil,
        name: "Imported Fund"
      }

      assert {:ok, "https://wikipedia/Imported.png", :wikipedia} =
               LogoLookup.find_url(security, req: stub)
    end

    test "Wikipedia page without originalimage -> :skip" do
      stub =
        plug_stub(fn conn ->
          # No originalimage in the body
          json_response(conn, 200, %{"title" => "Whatever"})
        end)

      security = %Security{provider: "manual", asset_class: "equity", name: "Whatever Inc."}

      assert :skip = LogoLookup.find_url(security, req: stub)
    end

    test "ambiguous bare names get the (company) disambiguator on Wikipedia" do
      # "Apple" alone resolves to the fruit; "Apple (company)" redirects to
      # Apple Inc. The dispatcher must prefer the (company) variant for
      # names without a corporate suffix to avoid picking up the wrong page.
      stub =
        plug_stub(fn conn ->
          assert conn.request_path =~ "Apple%20%28company%29"

          json_response(conn, 200, %{
            "originalimage" => %{"source" => "https://wikipedia/Apple_logo.png"}
          })
        end)

      security = %Security{
        provider: "manual",
        asset_class: "equity",
        name: "Apple"
      }

      assert {:ok, "https://wikipedia/Apple_logo.png", :wikipedia} =
               LogoLookup.find_url(security, req: stub)
    end

    test "falls back to the normal name when the special Wikipedia variant has no image" do
      {:ok, calls} = Agent.start_link(fn -> [] end)

      stub =
        plug_stub(fn conn ->
          title =
            conn.request_path
            |> String.replace_prefix("/api/rest_v1/page/summary/", "")
            |> URI.decode()

          Agent.update(calls, &(&1 ++ [title]))

          case title do
            "Example (company)" ->
              json_response(conn, 200, %{"title" => "Example"})

            "Example" ->
              json_response(conn, 200, %{
                "originalimage" => %{"source" => "https://wikipedia/Example.png"}
              })
          end
        end)

      security = %Security{
        provider: "manual",
        asset_class: "equity",
        name: "Example"
      }

      assert {:ok, "https://wikipedia/Example.png", :wikipedia} =
               LogoLookup.find_url(security, req: stub)

      assert Agent.get(calls, & &1) == ["Example (company)", "Example"]
    end

    # User story:
    # As a local portfolio maintainer with imported securities,
    # I want logo lookup to recover from all-caps names like "ALPHABET INC",
    # so that updating a logo does not fail just because the Wikipedia title
    # uses normal company punctuation.
    #
    # Acceptance criteria:
    # - A suffix-bearing all-caps company name is tried as stored first.
    # - A normalized Wikipedia title variant is tried after a 404.
    # - The lookup succeeds without adding a "(company)" disambiguator.
    test "falls back from all-caps imported company names to normalized Wikipedia titles" do
      {:ok, calls} = Agent.start_link(fn -> [] end)

      stub =
        plug_stub(fn conn ->
          title =
            conn.request_path
            |> String.replace_prefix("/api/rest_v1/page/summary/", "")
            |> URI.decode()

          Agent.update(calls, &(&1 ++ [title]))

          case title do
            "ALPHABET INC" ->
              Plug.Conn.send_resp(conn, 404, "not found")

            "Alphabet Inc." ->
              json_response(conn, 200, %{
                "originalimage" => %{"source" => "https://wikipedia/Alphabet_Inc..png"}
              })
          end
        end)

      security = %Security{
        provider: "manual",
        asset_class: "equity",
        name: "ALPHABET INC"
      }

      assert {:ok, "https://wikipedia/Alphabet_Inc..png", :wikipedia} =
               LogoLookup.find_url(security, req: stub)

      assert Agent.get(calls, & &1) == ["ALPHABET INC", "Alphabet Inc."]
    end

    # User story:
    # As a local portfolio maintainer adding ETFs,
    # I want Portfolixir to use the ETF issuer logo (iShares, Vanguard,
    # Lyxor, Amundi, …) before trying the individual fund name,
    # so that ETF rows get a recognizable provider logo automatically.
    #
    # Acceptance criteria:
    # - ETF names with a known issuer try the issuer Wikipedia title first.
    # - The individual ETF name remains a fallback when the issuer has no image.
    # - The behavior is deterministic and tested with a local Req plug.
    test "ETF lookup prefers issuer logo titles before the full fund name" do
      {:ok, calls} = Agent.start_link(fn -> [] end)

      stub =
        plug_stub(fn conn ->
          title =
            conn.request_path
            |> String.replace_prefix("/api/rest_v1/page/summary/", "")
            |> URI.decode()

          Agent.update(calls, &(&1 ++ [title]))

          case title do
            "iShares" ->
              json_response(conn, 200, %{
                "originalimage" => %{"source" => "https://wikipedia/iShares.png"}
              })
          end
        end)

      security = %Security{
        provider: "manual",
        asset_class: "etf",
        name: "iShares Core MSCI World UCITS ETF"
      }

      assert {:ok, "https://wikipedia/iShares.png", :wikipedia} =
               LogoLookup.find_url(security, req: stub)

      assert Agent.get(calls, & &1) == ["iShares"]
    end

    test "ETF issuer lookup falls back to the fund name when the issuer has no image" do
      {:ok, calls} = Agent.start_link(fn -> [] end)

      stub =
        plug_stub(fn conn ->
          title =
            conn.request_path
            |> String.replace_prefix("/api/rest_v1/page/summary/", "")
            |> URI.decode()

          Agent.update(calls, &(&1 ++ [title]))

          case title do
            "The Vanguard Group" ->
              json_response(conn, 200, %{"title" => "The Vanguard Group"})

            "Vanguard FTSE All-World UCITS ETF (company)" ->
              json_response(conn, 200, %{"title" => "Vanguard FTSE All-World UCITS ETF"})

            "Vanguard FTSE All-World UCITS ETF" ->
              json_response(conn, 200, %{
                "originalimage" => %{"source" => "https://wikipedia/VanguardFund.png"}
              })
          end
        end)

      security = %Security{
        provider: "manual",
        asset_class: "etf",
        name: "Vanguard FTSE All-World UCITS ETF"
      }

      assert {:ok, "https://wikipedia/VanguardFund.png", :wikipedia} =
               LogoLookup.find_url(security, req: stub)

      assert Agent.get(calls, & &1) == [
               "The Vanguard Group",
               "Vanguard FTSE All-World UCITS ETF (company)",
               "Vanguard FTSE All-World UCITS ETF"
             ]
    end

    # User story:
    # As a local portfolio maintainer importing Portfolio Performance data,
    # I want imported ETF names to use issuer-logo lookup even when the export
    # did not carry an asset class,
    # so that import-created ETFs don't require manual type cleanup first.
    #
    # Acceptance criteria:
    # - `provider="portfolio_performance"` and a PP-style ETF name infer the
    #   ETF logo strategy from the name.
    # - iShares/AIS-Amundi/Vanguard U.ETF spellings from imports hit issuer
    #   titles before full fund titles.
    test "Portfolio Performance ETF names infer issuer logo lookup without asset_class" do
      {:ok, calls} = Agent.start_link(fn -> [] end)

      stub =
        plug_stub(fn conn ->
          title =
            conn.request_path
            |> String.replace_prefix("/api/rest_v1/page/summary/", "")
            |> URI.decode()

          Agent.update(calls, &(&1 ++ [title]))

          case title do
            "iShares" ->
              json_response(conn, 200, %{
                "originalimage" => %{"source" => "https://wikipedia/iShares.png"}
              })
          end
        end)

      security = %Security{
        provider: "portfolio_performance",
        asset_class: nil,
        name: "iShares Core MSCI Emerging Markets IMI UCITS ETF"
      }

      assert {:ok, "https://wikipedia/iShares.png", :wikipedia} =
               LogoLookup.find_url(security, req: stub)

      assert Agent.get(calls, & &1) == ["iShares"]
    end

    test "names that already carry a corporate suffix go straight to the bare lookup" do
      stub =
        plug_stub(fn conn ->
          # No (company) suffix appended for names like "SAP SE" or "Apple Inc."
          refute conn.request_path =~ "company"

          json_response(conn, 200, %{
            "originalimage" => %{"source" => "https://wikipedia/SAP.png"}
          })
        end)

      for name <- ["SAP SE", "Apple Inc.", "Tesla, Inc", "Siemens AG"] do
        security = %Security{provider: "manual", asset_class: "equity", name: name}
        assert {:ok, _url, :wikipedia} = LogoLookup.find_url(security, req: stub)
      end
    end

    test "asset classes outside the heuristic return :skip without HTTP" do
      stub =
        plug_stub(fn _conn ->
          flunk("must not hit the network for skipped asset classes")
        end)

      for {asset_class, online_id} <- [
            {"index", nil},
            {"commodity", nil},
            {"bond", nil},
            {"crypto", nil}
          ] do
        security = %Security{
          provider: "manual",
          asset_class: asset_class,
          online_id: online_id,
          name: "X"
        }

        assert :skip = LogoLookup.find_url(security, req: stub)
      end
    end

    test "transport errors propagate as {:error, reason}" do
      stub =
        plug_stub(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("text/plain")
          |> Plug.Conn.send_resp(500, "boom")
        end)

      security = %Security{
        provider: "coingecko",
        online_id: "bitcoin",
        asset_class: "crypto",
        name: "Bitcoin"
      }

      assert {:error, _} = LogoLookup.find_url(security, req: stub)
    end
  end

  describe "find_url/2 crypto mapping" do
    # User story:
    # As a maintainer importing cryptos from Portfolio Performance (provider
    # "portfolio_performance", no CoinGecko online_id), I want their ticker
    # mapped to a CoinGecko coin id so the logo is fetched anyway.
    test "PP-imported crypto resolves its CoinGecko id from the ticker" do
      stub =
        plug_stub(fn conn ->
          assert conn.request_path =~ "/coins/bitcoin"

          json_response(conn, 200, %{"image" => %{"large" => "https://coingecko/btc.png"}})
        end)

      security = %Security{
        provider: "portfolio_performance",
        asset_class: "crypto",
        ticker_symbol: "BTC",
        name: "Bitcoin"
      }

      assert {:ok, "https://coingecko/btc.png", :coingecko} =
               LogoLookup.find_url(security, req: stub)
    end

    test "crypto outside the curated map skips without a network call" do
      stub = plug_stub(fn _conn -> flunk("must not hit the network for unknown coins") end)

      security = %Security{
        provider: "portfolio_performance",
        asset_class: "crypto",
        ticker_symbol: "ZZZ",
        name: "Mystery Coin"
      }

      assert :skip = LogoLookup.find_url(security, req: stub)
    end
  end

  describe "find_url/2 Wikipedia search fallback" do
    # User story:
    # As a maintainer with broker-spelled names ("GILEAD SCIENCES") that don't
    # resolve to an exact Wikipedia title, I want a name search to recover the
    # logo, without ever matching an unrelated topic.
    test "searches Wikipedia when no deterministic title resolves" do
      stub =
        plug_stub(fn conn ->
          cond do
            conn.request_path =~ "/w/rest.php/v1/search/page" ->
              json_response(conn, 200, %{
                "pages" => [
                  %{
                    "key" => "Gilead_Sciences",
                    "title" => "Gilead Sciences",
                    "description" => "American biotechnology company"
                  }
                ]
              })

            conn.request_path =~ "/api/rest_v1/page/summary/Gilead_Sciences" ->
              json_response(conn, 200, %{
                "originalimage" => %{"source" => "https://wikipedia/Gilead.png"}
              })

            conn.request_path =~ "/api/rest_v1/page/summary/" ->
              Plug.Conn.send_resp(conn, 404, "not found")
          end
        end)

      security = %Security{provider: "manual", asset_class: "equity", name: "GILEAD SCIENCES"}

      assert {:ok, "https://wikipedia/Gilead.png", :wikipedia} =
               LogoLookup.find_url(security, req: stub)
    end

    test "search ignores candidates that do not look like a company" do
      stub =
        plug_stub(fn conn ->
          cond do
            conn.request_path =~ "/w/rest.php/v1/search/page" ->
              json_response(conn, 200, %{
                "pages" => [
                  %{
                    "key" => "Pomegranate",
                    "title" => "Pomegranate",
                    "description" => "A fruit-bearing shrub"
                  }
                ]
              })

            conn.request_path =~ "/api/rest_v1/page/summary/" ->
              Plug.Conn.send_resp(conn, 404, "not found")

            true ->
              Plug.Conn.send_resp(conn, 404, "not found")
          end
        end)

      security = %Security{provider: "manual", asset_class: "equity", name: "Pomegranate"}

      assert :skip = LogoLookup.find_url(security, req: stub)
    end

    test "the search query strips broker nominal/share noise" do
      {:ok, captured} = Agent.start_link(fn -> nil end)

      stub =
        plug_stub(fn conn ->
          cond do
            conn.request_path =~ "/w/rest.php/v1/search/page" ->
              q = URI.decode_query(conn.query_string)["q"]
              Agent.update(captured, fn _ -> q end)
              json_response(conn, 200, %{"pages" => []})

            conn.request_path =~ "/api/rest_v1/page/summary/" ->
              Plug.Conn.send_resp(conn, 404, "not found")

            true ->
              Plug.Conn.send_resp(conn, 404, "not found")
          end
        end)

      security = %Security{
        provider: "manual",
        asset_class: "equity",
        name: "VESTAS WIND SYS. DK -,20"
      }

      assert :skip = LogoLookup.find_url(security, req: stub)
      assert Agent.get(captured, & &1) == "VESTAS WIND SYS"
    end
  end

  describe "find_url/2 companieslogo fallback and issuer logos" do
    test "equity falls back to companieslogo when Wikipedia has nothing" do
      stub =
        plug_stub(fn conn ->
          cond do
            conn.request_path =~ "/w/rest.php/v1/search/page" ->
              json_response(conn, 200, %{"pages" => []})

            conn.request_path =~ "/api/rest_v1/page/summary/" ->
              Plug.Conn.send_resp(conn, 404, "not found")

            conn.request_path =~ "/baozun/logo/" ->
              conn
              |> Plug.Conn.put_resp_content_type("text/html")
              |> Plug.Conn.send_resp(
                200,
                ~s(<meta property="og:image" content="https://logos/baozun.png">)
              )

            true ->
              Plug.Conn.send_resp(conn, 404, "not found")
          end
        end)

      security = %Security{provider: "manual", asset_class: "equity", name: "Baozun"}

      assert {:ok, "https://logos/baozun.png", :companieslogo} =
               LogoLookup.find_url(security, req: stub)
    end

    # User story:
    # As a maintainer holding leverage certificates (BNP Paribas, Morgan
    # Stanley, …), I want the issuer's logo on the row instead of bare
    # initials, since the product itself has no logo.
    test "a leverage product resolves its issuer's logo" do
      stub =
        plug_stub(fn conn ->
          assert conn.request_path =~ "/api/rest_v1/page/summary/BNP"

          json_response(conn, 200, %{
            "originalimage" => %{"source" => "https://wikipedia/BNP_Paribas.png"}
          })
        end)

      security = %Security{
        provider: "portfolio_performance",
        asset_class: "knock_out",
        name: "BNP Paribas Issuance B.V. Call Turbo o.End DAX"
      }

      assert {:ok, "https://wikipedia/BNP_Paribas.png", :wikipedia} =
               LogoLookup.find_url(security, req: stub)
    end

    test "a leverage product with no recognizable issuer skips without HTTP" do
      stub = plug_stub(fn _conn -> flunk("must not hit the network without an issuer") end)

      security = %Security{provider: "manual", asset_class: "warrant", name: "Generic Turbo XYZ"}

      assert :skip = LogoLookup.find_url(security, req: stub)
    end

    test "candidate?/1 covers equities, crypto and issuer-backed derivatives only" do
      assert LogoLookup.candidate?(%Security{asset_class: "equity", name: "Anything"})
      assert LogoLookup.candidate?(%Security{asset_class: "crypto", name: "Bitcoin"})
      assert LogoLookup.candidate?(%Security{asset_class: "knock_out", name: "BNP Paribas Turbo"})
      refute LogoLookup.candidate?(%Security{asset_class: "warrant", name: "Generic Turbo"})
      refute LogoLookup.candidate?(%Security{asset_class: "government_bond", name: "Bund 2030"})
    end

    # User story:
    # As a maintainer, imported companies whose PP name carries no legal form
    # ("Amazon", "Zalando", "XINJIANG GOLDWIND") infer no asset class but are
    # still companies — background discovery must try them, like the manual
    # "Update logo" already does. Commodities/bonds stay flag/initials.
    test "candidate?/1 includes untagged imported equities, not commodities/bonds" do
      assert LogoLookup.candidate?(%Security{provider: "portfolio_performance", name: "Zalando"})

      assert LogoLookup.candidate?(%Security{
               provider: "portfolio_performance",
               name: "XINJIANG GOLDWIND"
             })

      # Only for imported rows — a manual untagged row is not auto-discovered.
      refute LogoLookup.candidate?(%Security{provider: "manual", name: "Zalando"})

      # Imported commodities/bonds keep their flag/initials fallback.
      refute LogoLookup.candidate?(%Security{
               provider: "portfolio_performance",
               asset_class: "commodity",
               name: "Gold"
             })

      refute LogoLookup.candidate?(%Security{
               provider: "portfolio_performance",
               asset_class: "government_bond",
               name: "Anleihe USA 20/50"
             })
    end

    test "an untagged imported equity still resolves a company logo" do
      stub =
        plug_stub(fn conn ->
          if conn.request_path =~ "/api/rest_v1/page/summary/" do
            json_response(conn, 200, %{
              "originalimage" => %{"source" => "https://wikipedia/Zalando.png"}
            })
          else
            Plug.Conn.send_resp(conn, 404, "not found")
          end
        end)

      security = %Security{provider: "portfolio_performance", asset_class: nil, name: "Zalando"}

      assert {:ok, "https://wikipedia/Zalando.png", :wikipedia} =
               LogoLookup.find_url(security, req: stub)
    end

    test "equity falls back to companieslogo after a Wikipedia transport error" do
      stub =
        plug_stub(fn conn ->
          cond do
            conn.request_path =~ "/api/rest_v1/page/summary/" ->
              Plug.Conn.send_resp(conn, 500, "boom")

            conn.request_path =~ "/baozun/logo/" ->
              conn
              |> Plug.Conn.put_resp_content_type("text/html")
              |> Plug.Conn.send_resp(
                200,
                ~s(<meta property="og:image" content="https://logos/baozun.png">)
              )

            true ->
              Plug.Conn.send_resp(conn, 404, "not found")
          end
        end)

      security = %Security{provider: "manual", asset_class: "equity", name: "Baozun"}

      assert {:ok, "https://logos/baozun.png", :companieslogo} =
               LogoLookup.find_url(security, req: stub)
    end

    test "issuer logo falls back to companieslogo when the issuer page has no image" do
      stub =
        plug_stub(fn conn ->
          cond do
            conn.request_path =~ "/api/rest_v1/page/summary/" ->
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.send_resp(200, Jason.encode!(%{"title" => "BNP"}))

            conn.request_path =~ "/bnp-paribas/logo/" ->
              conn
              |> Plug.Conn.put_resp_content_type("text/html")
              |> Plug.Conn.send_resp(
                200,
                ~s(<meta property="og:image" content="https://logos/bnp.png">)
              )

            true ->
              Plug.Conn.send_resp(conn, 404, "not found")
          end
        end)

      security = %Security{
        provider: "manual",
        asset_class: "warrant",
        name: "BNP Paribas Turbo Call"
      }

      assert {:ok, "https://logos/bnp.png", :companieslogo} =
               LogoLookup.find_url(security, req: stub)
    end
  end

  describe "find_url/2 search resilience" do
    # User story:
    # As a maintainer, I want companies whose Wikipedia article lives under a
    # different title than their brokerage name (BMW vs "Bayerische Motoren
    # Werke", Goldwind vs "Xinjiang Goldwind") to still get a logo — the search
    # accepts the first company-like result regardless of title word overlap.
    test "search accepts a company under a differently-titled article" do
      stub =
        plug_stub(fn conn ->
          cond do
            conn.request_path =~ "/w/rest.php/v1/search/page" ->
              json_response(conn, 200, %{
                "pages" => [
                  %{
                    "key" => "BMW",
                    "title" => "BMW",
                    "description" => "German multinational manufacturer of vehicles"
                  }
                ]
              })

            conn.request_path =~ "/api/rest_v1/page/summary/BMW" ->
              json_response(conn, 200, %{
                "originalimage" => %{"source" => "https://wikipedia/BMW.png"}
              })

            conn.request_path =~ "/api/rest_v1/page/summary/" ->
              Plug.Conn.send_resp(conn, 404, "not found")

            true ->
              Plug.Conn.send_resp(conn, 404, "not found")
          end
        end)

      security = %Security{
        provider: "manual",
        asset_class: "equity",
        name: "Bayerische Motoren Werke AG Vorzugsaktien o.St. EO 1"
      }

      assert {:ok, "https://wikipedia/BMW.png", :wikipedia} =
               LogoLookup.find_url(security, req: stub)
    end

    test "the search query strips ADR, holdings and class-letter noise" do
      {:ok, captured} = Agent.start_link(fn -> nil end)

      stub =
        plug_stub(fn conn ->
          if conn.request_path =~ "/w/rest.php/v1/search/page" do
            Agent.update(captured, fn _ -> URI.decode_query(conn.query_string)["q"] end)
            json_response(conn, 200, %{"pages" => []})
          else
            Plug.Conn.send_resp(conn, 404, "not found")
          end
        end)

      security = %Security{
        provider: "manual",
        asset_class: "equity",
        name: "AMC ENTERTAINMENT HLDGS A"
      }

      assert :skip = LogoLookup.find_url(security, req: stub)
      assert Agent.get(captured, & &1) == "AMC ENTERTAINMENT"
    end
  end
end
