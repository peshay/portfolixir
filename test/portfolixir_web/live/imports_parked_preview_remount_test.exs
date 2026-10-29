defmodule PortfolixirWeb.ImportsParkedPreviewRemountTest do
  use PortfolixirWeb.ConnCase

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy
  alias Portfolixir.Imports
  alias Portfolixir.Imports.PreviewStore

  @moduletag timeout: 170_000

  # One browser session: a distinct, valid 24-character CSRF token.
  @token "HHHHHHHHHHHHHHHHHHHHHH08"

  # The passes over every entry the upload computes what the preview shows
  # with (the account-state counts run in the background as well, so they are
  # not counted here).
  @upload_passes [
    {Imports, :resolve_securities, 1},
    {Imports, :resolve_accounts, 1},
    {Imports, :cash_corrections, 1}
  ]

  defp synthetic_csv(rows) do
    header =
      "Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle\n"

    body =
      for i <- 1..rows do
        date = ~D[2000-01-01] |> Date.add(rem(i, 9_000)) |> Date.to_iso8601()

        "#{date} 10:01;Kauf;Synthetic Security 1;1,123456;12,345678;13,86;1,00;0,50;15,36;Depot A;Cash A;;\n"
      end

    IO.iodata_to_binary([header | body])
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp wait_until(deadline_ms, fun) do
    cond do
      fun.() ->
        true

      now_ms() > deadline_ms ->
        false

      true ->
        Process.sleep(100)
        wait_until(deadline_ms, fun)
    end
  end

  # live/2 runs the dead render in the calling process, and the HeapCap plug
  # caps it; the test process itself never holds the preview, so lift it.
  defp lift_cap, do: Process.flag(:max_heap_size, 0)

  # A reload, a locale switch or a second tab: GET /imports under the
  # session, in a process of its own, capped by the HeapCap plug as a
  # request process is in production.
  defp reload(conn) do
    {pid, ref} =
      spawn_monitor(fn ->
        conn = get(conn, "/imports")
        exit({:shutdown, {:status, conn.status}})
      end)

    receive do
      {:DOWN, ^ref, :process, ^pid, {:shutdown, {:status, status}}} -> {:status, status}
      {:DOWN, ^ref, :process, ^pid, reason} -> {:died, reason}
    after
      100_000 ->
        Process.exit(pid, :kill)
        :timeout
    end
  end

  # A live navigation to /imports from another page of the live_session:
  # only the connected mount runs, in a new LiveView process capped by the
  # live_session's HeapCap on_mount hook.
  defp navigate(conn) do
    {:ok, other, _html} = live(conn, "/buckets")
    lift_cap()

    try do
      case live_redirect(other, to: "/imports") do
        {:ok, view, html} ->
          ClientProxy.stop(elem(view.proxy, 2), {:shutdown, :closed})
          {:mounted, html =~ "Preview"}

        other ->
          {:other, other}
      end
    catch
      :exit, {reason, {Phoenix.LiveViewTest, :live, _}} -> {:died, reason}
      :exit, reason -> {:died, reason}
    end
  end

  # Counts the calls of each upload pass in any process from now on.
  defp count_upload_passes do
    Code.ensure_loaded!(Imports)
    for mfa <- @upload_passes, do: assert(:erlang.trace_pattern(mfa, true, [:call_count]) == 1)

    on_exit(fn ->
      for mfa <- @upload_passes, do: :erlang.trace_pattern(mfa, false, [:call_count])
    end)
  end

  defp restart_counts,
    do: for(mfa <- @upload_passes, do: :erlang.trace_pattern(mfa, :restart, [:call_count]))

  defp upload_pass_calls do
    Map.new(@upload_passes, fn {_module, function, _arity} = mfa ->
      {:call_count, count} = :erlang.trace_info(mfa, :call_count)
      {function, count}
    end)
  end

  # User story (security review 2026-10-12, H08):
  # As the operator who previewed a large export of mine,
  # I want the Imports page to open again in my browser session with that
  # preview, by reload and by navigation, showing what the upload computed,
  # so that a preview the page could show once never locks the page.
  #
  # Acceptance criteria:
  # - A preview that rendered on upload is parked.
  # - A reload of /imports in the session answers 200.
  # - A live navigation to /imports in the session mounts with the preview.
  # - Neither runs again the passes over every entry the upload ran.
  test "a parked preview remounts, by reload and by live navigation, without its upload passes",
       %{conn: conn} do
    count_upload_passes()

    conn = init_test_session(conn, %{"_csrf_token" => @token})
    key = PreviewStore.key_for(@token)
    PreviewStore.delete(key)
    on_exit(fn -> PreviewStore.delete(key) end)

    csv = synthetic_csv(20_000)

    Process.flag(:trap_exit, true)

    {observed, _log} =
      with_log(fn ->
        # 1. The operator drops the export on the page, as the browser does.
        {:ok, page, _html} = live(conn, "/imports")
        lift_cap()

        upload =
          file_input(page, "#pp-import-form", :pp_file, [
            %{
              name: "export.csv",
              content: csv,
              type: "text/csv",
              last_modified: 1_700_000_000_000
            }
          ])

        # The test client stops waiting after a few seconds; the page keeps
        # parsing, as it does for a browser.
        try do
          render_upload(upload, "export.csv")
        catch
          :exit, _client_gave_up -> :ok
        end

        # render/1 pings the page, so it answers once the page has parsed,
        # rendered and handled its park message.
        rendered_preview? =
          try do
            render(page) =~ "Preview"
          catch
            :exit, _page_gone -> false
          end

        parked? = wait_until(now_ms() + 10_000, fn -> :ets.member(PreviewStore, key) end)

        restart_counts()

        # 2. A reload (or a locale switch, or a second tab): the dead render.
        reload_result = reload(conn)

        # 3. A live navigation to /imports from another page: connected mount.
        nav_result = navigate(conn)
        remount_passes = upload_pass_calls()

        if Process.alive?(page.pid),
          do: ClientProxy.stop(elem(page.proxy, 2), {:shutdown, :closed})

        # Let the runtime's reports reach this capture.
        Process.sleep(1_000)

        %{
          upload_rendered_preview: rendered_preview?,
          parked_after_upload: parked?,
          reload: reload_result,
          live_navigation: nav_result,
          remount_passes: remount_passes
        }
      end)

    flush_exits()

    assert observed.upload_rendered_preview and observed.parked_after_upload,
           "control: the upload did not render and park its preview: #{inspect(observed)}"

    assert match?(
             %{reload: {:status, 200}, live_navigation: {:mounted, true}},
             observed
           ),
           """
           A preview that rendered on upload was parked, but its remounts did not answer.
           Reload (dead render): #{inspect(observed.reload)}
           Live navigation (connected mount): #{inspect(observed.live_navigation)}
           """

    assert Enum.all?(observed.remount_passes, fn {_pass, calls} -> calls == 0 end),
           "the remounts ran the upload's passes over every entry again: " <>
             inspect(observed.remount_passes)
  end

  # A Portfolio Performance CSV whose rows carry fees or taxes, so its
  # Gesamtpreis differs from its Betrag: stored under the older reading, it
  # lists bookings to correct.
  @correctable_csv """
  Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
  2024-01-02 00:00:00;Einlage;;;;10.000,00;;;10.000,00;Girokonto;;;
  2024-01-15 10:01:00;Kauf;Nordwind Industrie AG;10;150,00;1.500,00;2,50;;1.502,50;Depot;Girokonto;;
  2024-06-30 00:00:00;Zinsen;;;;5,75;;1,20;4,55;Tagesgeld;;;
  """

  # User story (security review 2026-10-12, H08):
  # As the operator who corrected the bookings a parked preview listed,
  # I want a remount of the page to show the preview as it is after the
  # correction,
  # so that what the upload computed never brings back what I already did.
  #
  # Acceptance criteria:
  # - After the correction, a remount in the session shows the preview with
  #   no booking left to correct.
  test "a remount after a correction shows the parked preview as it is now", %{conn: conn} do
    conn = init_test_session(conn, %{"_csrf_token" => @token})
    key = PreviewStore.key_for(@token)
    on_exit(fn -> PreviewStore.delete(key) end)

    {:ok, portfolio} =
      Portfolixir.Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Correction target",
        base_currency_code: "EUR"
      })

    {:ok, preview} =
      Imports.parse_portfolio_performance(@correctable_csv, filename: "export.csv")

    old =
      Enum.map(preview.entries, fn entry ->
        %{entry | gross_amount: entry.hash_amount, price: entry.hash_price || entry.price}
      end)

    {:ok, _result} = Imports.apply(%{preview | entries: old}, %{portfolio_id: portfolio.id})

    {:ok, view, _html} = live(conn, "/imports")

    view
    |> file_input("#pp-import-form", :pp_file, [
      %{
        name: "export.csv",
        content: @correctable_csv,
        type: "text/csv",
        last_modified: 1_700_000_000_000
      }
    ])
    |> render_upload("export.csv")

    render_async(view)
    assert has_element?(view, "#import-correction")
    assert PreviewStore.parked?(key)

    view |> element("#import-correction-open") |> render_click()
    view |> element("#import-correction-confirm") |> render_click()
    render_async(view)
    refute has_element?(view, "#import-correction")

    {:ok, remounted, html} = live(conn, "/imports")
    render_async(remounted)
    assert html =~ "Preview"
    refute has_element?(remounted, "#import-correction")
  end

  # The assigns a mounted Imports page holds, by name.
  defp assign_keys(view) do
    %{socket: socket} = :sys.get_state(view.pid)
    socket.assigns |> Map.keys() |> MapSet.new()
  end

  # User story (security review 2026-10-12, H08):
  # As the operator who reloads the Imports page with a preview parked,
  # I want the remount to hold everything the upload showed the preview with,
  # so that a remount from what was parked never fails on something the
  # upload computed and the parked summary left out.
  #
  # Acceptance criteria:
  # - A remount from the parked summary holds the same assigns as the page
  #   that uploaded the file, and as a remount that computes them again,
  #   with the same values.
  test "a remount from the parked summary sets every assign the upload set", %{conn: conn} do
    conn = init_test_session(conn, %{"_csrf_token" => @token})
    key = PreviewStore.key_for(@token)
    on_exit(fn -> PreviewStore.delete(key) end)

    {:ok, page, _html} = live(conn, "/imports")

    page
    |> file_input("#pp-import-form", :pp_file, [
      %{
        name: "export.csv",
        content: @correctable_csv,
        type: "text/csv",
        last_modified: 1_700_000_000_000
      }
    ])
    |> render_upload("export.csv")

    render_async(page)
    assert PreviewStore.parked?(key)
    uploaded = assign_keys(page)

    {:ok, remounted, _html} = live(conn, "/imports")
    render_async(remounted)
    from_summary = assign_keys(remounted)

    # The same preview parked without a summary: the remount computes again.
    {preview, mapping} = PreviewStore.get(key)
    :ok = PreviewStore.put(key, preview, mapping)
    {:ok, recomputed, _html} = live(conn, "/imports")
    render_async(recomputed)
    from_recompute = assign_keys(recomputed)

    assert MapSet.difference(uploaded, from_summary) == MapSet.new(),
           "the remount from the parked summary lacks assigns the upload set"

    assert MapSet.difference(from_recompute, from_summary) == MapSet.new(),
           "the remount from the parked summary lacks assigns a recomputing remount sets"

    # And holds them as computed: every assign but the page's own upload
    # handle and its background-count token reads as the recomputing remount
    # reads it, the database being unchanged in between.
    %{socket: %{assigns: summary_assigns}} = :sys.get_state(remounted.pid)
    %{socket: %{assigns: recompute_assigns}} = :sys.get_state(recomputed.pid)

    differing =
      for {name, value} <- recompute_assigns,
          name not in [:uploads, :counts_token],
          Map.get(summary_assigns, name) != value,
          do: name

    assert differing == [],
           "the remount from the parked summary holds other values for #{inspect(differing)}"
  end

  defp flush_exits do
    receive do
      {:EXIT, _pid, _reason} -> flush_exits()
    after
      0 -> :ok
    end
  end
end
