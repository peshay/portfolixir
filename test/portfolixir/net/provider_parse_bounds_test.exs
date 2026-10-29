defmodule Portfolixir.Net.ProviderParseBoundsTest do
  # Provider bodies are parsed in time linear in their size, and every parse
  # runs under a wall-clock guard of its own. Synthetic bodies only, Req plug
  # stubs only: no network. A call still running at the budget is killed, so
  # a regression fails in seconds rather than hanging the suite.
  use Portfolixir.DataCase, async: false

  import ExUnit.CaptureLog

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.LogoDiscovery
  alias Portfolixir.Catalog.LogoLookup.CompaniesLogo
  alias Portfolixir.Catalog.LogoLookup.Wikipedia
  alias Portfolixir.Fx.RateSync
  alias Portfolixir.Fx.RateSync.Ecb
  alias Portfolixir.Net.ParseGuard

  # Above the parse guard's own bound, and far above what a linear parse of
  # the bodies below needs.
  @budget_ms 8_000

  @opener "<Cube time='2020-01-01'>"
  @day "<Cube time='2020-01-02'><Cube currency='USD' rate='1.1'/>" <>
         "<Cube currency='JPY' rate='120.5'/></Cube>\n"

  # -- helpers -----------------------------------------------------------------

  # Runs fun in a task; answers how it ended within the budget. A call still
  # running at the budget is killed and reported as :still_running.
  defp within_budget(fun) do
    started = System.monotonic_time(:millisecond)
    task = Task.async(fun)

    case Task.yield(task, @budget_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, value} -> {:returned, value, System.monotonic_time(:millisecond) - started}
      {:exit, reason} -> {:exited, reason}
      nil -> :still_running
    end
  end

  defp ms(fun) do
    {us, _} = :timer.tc(fun)
    div(us, 1000)
  end

  defp openers_only(bytes), do: String.duplicate(@opener, div(bytes, byte_size(@opener)))

  defp legit_history(bytes),
    do:
      "<gesmes:Envelope><Cube>" <>
        String.duplicate(@day, max(div(bytes, byte_size(@day)), 1)) <> "</Cube></gesmes:Envelope>"

  defp body_stub(test_pid, content_type, body) do
    [
      plug: fn conn ->
        send(test_pid, {:served, conn.host, byte_size(body)})

        conn
        |> Plug.Conn.put_resp_content_type(content_type)
        |> Plug.Conn.send_resp(200, body)
      end
    ]
  end

  defp json(conn, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(body))
  end

  # -- ECB history ---------------------------------------------------------------

  # User story (security review 2026-10-12, H50):
  # As the operator whose FX history comes from the ECB,
  # I want the history parse to cost time in proportion to the body,
  # so that a hostile or broken feed cannot keep a scheduler busy for hours.
  #
  # Acceptance criteria:
  # - A body of dated openers that never close is answered at once with no
  #   rows; a legit-shaped history of twice the size still parses.
  test "ECB history: a body of unclosed dated openers is answered within the budget" do
    test_pid = self()

    # Control: a legit-shaped history twice the hostile size parses at once.
    legit = legit_history(2 * 1024 * 1024)

    assert {:returned, {:ok, rows}, legit_ms} =
             within_budget(fn ->
               Ecb.fetch_history(req: body_stub(test_pid, "text/xml", legit))
             end)

    assert rows != []

    # Scaling evidence, run directly on the public parser.
    small_ms = ms(fn -> Ecb.parse_history(openers_only(32 * 1024)) end)
    double_ms = ms(fn -> Ecb.parse_history(openers_only(64 * 1024)) end)

    hostile = openers_only(1024 * 1024)

    result =
      within_budget(fn -> Ecb.fetch_history(req: body_stub(test_pid, "text/xml", hostile)) end)

    # The fetch itself completed (the stub served the body); what runs on is
    # the parse, outside Net.Http's deadline.
    assert_received {:served, "www.ecb.europa.eu", served} when served == byte_size(hostile)

    assert match?({:returned, {:ok, []}, _}, result),
           "Ecb.fetch_history/1 was still parsing a #{byte_size(hostile)}-byte body of unclosed " <>
             "<Cube time=..> openers after #{@budget_ms} ms (killed). A legit-shaped " <>
             "#{byte_size(legit)}-byte history took #{legit_ms} ms through the same path. " <>
             "parse_history/1 on 32 KiB of openers: #{small_ms} ms, on 64 KiB: #{double_ms} ms " <>
             "(a quadratic parse grows x4 per doubling)."
  end

  # User story (security review 2026-10-12, H50):
  # As the operator or the agent asking for an FX backfill,
  # I want a hostile history body to end its run promptly,
  # so that the next backfill is not refused as already in progress.
  #
  # Acceptance criteria:
  # - Once a hostile body has been served, a second backfill is not
  #   answered {:error, :backfill_in_progress}.
  test "ECB history: the FX-backfill single-flight key is free again after the budget" do
    test_pid = self()
    hostile = openers_only(1024 * 1024)

    {second, _log} =
      with_log(fn ->
        spinning =
          Task.async(fn ->
            RateSync.backfill(provider: Ecb, req: body_stub(test_pid, "text/xml", hostile))
          end)

        assert_receive {:served, "www.ecb.europa.eu", _}, 5_000
        Process.sleep(@budget_ms)

        # The operator's (or the agent's) next backfill, against a healthy body.
        second =
          RateSync.backfill(
            provider: Ecb,
            req: body_stub(test_pid, "text/xml", legit_history(4_000))
          )

        _ = Task.yield(spinning, 0) || Task.shutdown(spinning, :brutal_kill)
        second
      end)

    refute second == {:error, :backfill_in_progress},
           "#{@budget_ms} ms after a hostile ECB history body was served, RateSync.backfill/1 " <>
             "still answers {:error, :backfill_in_progress} (the API's 409): the first run is " <>
             "parsing while it holds :fx_backfill."
  end

  # -- companieslogo og:image ------------------------------------------------------

  # User story (security review 2026-10-12, H50):
  # As the operator whose logos are discovered in the background,
  # I want the companieslogo page to be searched in time linear in its size,
  # so that a hostile page cannot stall a lookup.
  #
  # Acceptance criteria:
  # - A page of tag starts that never close is answered :not_found at once;
  #   a legit page with its og:image last still yields the image.
  test "companieslogo: a page of unclosed <meta starts is answered within the budget" do
    test_pid = self()

    # Control: a 2 MiB page of ordinary closed meta tags with the og:image last.
    legit =
      "<html><head>" <>
        String.duplicate(~s(<meta name="synthetic" content="value">), 52_000) <>
        ~s(<meta property="og:image" content="https://companieslogo.com/img/synthetic.png">) <>
        "</head></html>"

    assert {:returned, {:ok, "https://companieslogo.com/img/synthetic.png"}, legit_ms} =
             within_budget(fn ->
               CompaniesLogo.fetch_image_url("Synthetic Co",
                 req: body_stub(test_pid, "text/html", legit)
               )
             end)

    hostile = String.duplicate("<meta ", div(512 * 1024, 6))

    result =
      within_budget(fn ->
        CompaniesLogo.fetch_image_url("Synthetic Co",
          req: body_stub(test_pid, "text/html", hostile)
        )
      end)

    assert_received {:served, "companieslogo.com", served} when served == byte_size(hostile)

    assert match?({:returned, :not_found, _}, result),
           "CompaniesLogo.fetch_image_url/2 was still matching og:image over a " <>
             "#{byte_size(hostile)}-byte page of '<meta ' starts after #{@budget_ms} ms (killed). " <>
             "A legit #{byte_size(legit)}-byte page took #{legit_ms} ms."
  end

  # -- Wikipedia search title ------------------------------------------------------

  # User story (security review 2026-10-12, H50):
  # As the operator whose logos are discovered in the background,
  # I want a search candidate's text fields bounded before any pattern runs,
  # so that a hostile title cannot stall a lookup.
  #
  # Acceptance criteria:
  # - A title of unclosed parentheses is answered :not_found at once, and so
  #   is a long balanced title.
  test "Wikipedia search: a candidate title of unclosed parentheses is answered within the budget" do
    test_pid = self()

    answer = fn title ->
      [
        plug: fn conn ->
          send(test_pid, {:served, conn.host, conn.request_path})

          case conn.request_path do
            "/w/rest.php/v1/search/page" ->
              json(conn, %{
                "pages" => [
                  %{"key" => "Synthetic_Hostile", "title" => title, "description" => "company"}
                ]
              })

            _ ->
              Plug.Conn.send_resp(conn, 404, "")
          end
        end
      ]
    end

    # Control: a 1 MiB title with balanced parentheses.
    legit_title = String.duplicate("Synthetic Hostile (holding) ", 37_000)

    assert {:returned, :not_found, legit_ms} =
             within_budget(fn ->
               Wikipedia.search_logo("Synthetic Hostile Co", req: answer.(legit_title))
             end)

    hostile_title = String.duplicate("(", 256 * 1024)

    result =
      within_budget(fn ->
        Wikipedia.search_logo("Synthetic Hostile Co", req: answer.(hostile_title))
      end)

    assert match?({:returned, :not_found, _}, result),
           "Wikipedia.search_logo/2 was still tokenizing a #{byte_size(hostile_title)}-byte " <>
             "candidate title of '(' after #{@budget_ms} ms (killed). A " <>
             "#{byte_size(legit_title)}-byte balanced title took #{legit_ms} ms."
  end

  # -- LogoDiscovery GenServer -----------------------------------------------------

  # User story (security review 2026-10-12, H50):
  # As the operator whose logos are discovered in the background,
  # I want the discovery process to stay responsive while it reads a page,
  # so that one hostile page does not stop discovery for every security.
  #
  # Acceptance criteria:
  # - The discovery process answers a state probe within the budget while it
  #   handles a hostile companieslogo page.
  test "LogoDiscovery: the discovery GenServer stays responsive while a hostile logo page is parsed" do
    test_pid = self()
    prior_enabled = Application.get_env(:portfolixir, :enable_logo_discovery, false)
    prior_opts = Application.get_env(:portfolixir, :logo_discovery_opts, [])

    # Created while discovery is off, so nothing is enqueued to the app's own
    # discovery process.
    {:ok, security} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Synthetic Hostile Co",
        currency_code: "EUR",
        provider: "portfolio_performance",
        feed: "PORTFOLIO_PERFORMANCE",
        asset_class: "equity"
      })

    hostile = String.duplicate("<meta ", div(512 * 1024, 6))

    stub = [
      plug: fn conn ->
        send(test_pid, {:served, conn.host, conn.request_path})

        cond do
          conn.host == "companieslogo.com" ->
            conn
            |> Plug.Conn.put_resp_content_type("text/html")
            |> Plug.Conn.send_resp(200, hostile)

          conn.request_path == "/w/rest.php/v1/search/page" ->
            json(conn, %{"pages" => []})

          true ->
            Plug.Conn.send_resp(conn, 404, "")
        end
      end
    ]

    storage =
      Path.join(System.tmp_dir!(), "provider-parse-logos-#{System.unique_integer([:positive])}")

    {{probe, info}, _log} =
      try do
        Application.put_env(:portfolixir, :enable_logo_discovery, true)
        Application.put_env(:portfolixir, :logo_discovery_opts, req: stub, storage_dir: storage)

        # Captured throughout: a fixed version may log a bounded lookup failure
        # from the GenServer while the probe waits.
        with_log(fn ->
          pid = start_supervised!({LogoDiscovery, name: :provider_parse_discovery})
          # The GenServer reached the companieslogo page for this security.
          assert_receive {:served, "companieslogo.com", _}, 10_000

          probe =
            try do
              {:answered, :sys.get_state(pid, @budget_ms)}
            catch
              :exit, {:timeout, _} -> :timeout
            end

          info = Process.info(pid, [:current_stacktrace, :message_queue_len])
          stop_supervised!(:provider_parse_discovery)
          {probe, info}
        end)
      after
        Application.put_env(:portfolixir, :enable_logo_discovery, prior_enabled)
        Application.put_env(:portfolixir, :logo_discovery_opts, prior_opts)
        File.rm_rf(storage)
      end

    assert security.id
    frames = info && Enum.take(info[:current_stacktrace] || [], 4)

    assert match?({:answered, _}, probe),
           "The LogoDiscovery GenServer did not answer a :sys.get_state/2 probe within " <>
             "#{@budget_ms} ms while handling a hostile companieslogo page. Its stack: " <>
             inspect(frames)
  end

  # -- shapes, without a clock -----------------------------------------------------

  # User story (security review 2026-10-12, H50):
  # As the operator whose FX history comes from the ECB,
  # I want each dated block read on its own,
  # so that an opener that never closes costs nothing and hides no day.
  #
  # Acceptance criteria:
  # - The published days around stray unclosed openers parse as before.
  # - A body of openers only yields no rows.
  test "ECB history: dated blocks parse on their own, stray openers yield nothing" do
    days = legit_history(4_000)
    expected = Ecb.parse_history(days)
    assert expected != []

    assert Ecb.parse_history(@opener <> days <> String.duplicate(@opener, 64)) == expected
    assert Ecb.parse_history(openers_only(64 * 1024)) == []
  end

  # User story (security review 2026-10-12, H50):
  # As the operator,
  # I want every provider parse to run under the HTTP client's kind of
  # wall-clock guard,
  # so that a parse that runs long fails alone with a named error.
  #
  # Acceptance criteria:
  # - A parse that returns answers {:ok, value}; one past its bound answers
  #   {:error, :parse_timeout} and leaves no process behind.
  test "a provider parse runs under a wall-clock guard of its own" do
    assert ParseGuard.run(fn -> :parsed end) == {:ok, :parsed}

    test_pid = self()

    assert ParseGuard.run(
             fn ->
               send(test_pid, {:parser, self()})
               Process.sleep(:infinity)
             end,
             50
           ) == {:error, :parse_timeout}

    assert_received {:parser, parser}
    refute Process.alive?(parser)
  end

  # User story (security review 2026-10-12, H50, review note):
  # As the operator,
  # I want a parse that throws to fail alone under the guard,
  # so that it never takes down the caller that asked for it.
  #
  # Acceptance criteria:
  # - A parse that throws answers {:error, {:parse_failed, _}}, and so do a
  #   parse that raises and one that exits; the caller lives on.
  test "a parse that throws, raises or exits fails alone under the guard" do
    assert {:error, {:parse_failed, _}} = ParseGuard.run(fn -> throw(:hostile) end)
    assert {:error, {:parse_failed, _}} = ParseGuard.run(fn -> raise "hostile" end)
    assert {:error, {:parse_failed, _}} = ParseGuard.run(fn -> exit(:hostile) end)
    assert Process.alive?(self())
  end
end
