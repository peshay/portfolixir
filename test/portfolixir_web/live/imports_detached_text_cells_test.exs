defmodule PortfolixirWeb.ImportsDetachedTextCellsTest do
  # async: false -- the sandbox is shared with the page and its tasks, and one
  # test lifts the heap cap through the application environment.
  use PortfolixirWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Portfolixir.Imports
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Imports.PreviewStore
  alias PortfolixirWeb.CappedAsync

  @moduletag timeout: 110_000

  @header "Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle"

  # 24 characters of base64url, so Plug.CSRFProtection keeps them.
  @token_upload "H58aH58aH58aH58aH58aH58a"
  @token_parked "H58bH58bH58bH58bH58bH58b"

  setup do
    on_exit(fn ->
      PreviewStore.delete(PreviewStore.key_for(@token_upload))
      PreviewStore.delete(PreviewStore.key_for(@token_parked))
    end)

    :ok
  end

  # A synthetic export of `rows` deposits, each with a note of exactly
  # `note_bytes` bytes.
  defp notes_csv(rows, note_bytes) do
    lines =
      for i <- 1..rows do
        date = ~D[2015-01-01] |> Date.add(i) |> Date.to_iso8601()
        filler = String.duplicate("x", note_bytes - 23 - 6)
        note = "Synthetic booking note " <> filler <> String.pad_leading("#{i}", 6, "0")
        ^note_bytes = byte_size(note)
        "#{date} 00:00:00;Einlage;;;;10,00;;;10,00;Synthetic-Cash;;#{note};"
      end

    Enum.join([@header | lines], "\n") <> "\n"
  end

  # A synthetic JSON v1 export of `rows` buys of one fund named `name`.
  defp fund_json(rows, name) do
    txs =
      for i <- 1..rows do
        %{
          "type" => "PURCHASE",
          "account" => "Synthetic-Cash",
          "portfolio" => "Synthetic-Depot",
          "date" => ~D[2015-01-01] |> Date.add(i) |> Date.to_iso8601(),
          "time" => "10:00",
          "currency" => "EUR",
          "amount" => 100.0,
          "shares" => 1.5,
          "security" => %{"name" => name, "currency" => "EUR"}
        }
      end

    Jason.encode!(%{"version" => 1, "transactions" => txs})
  end

  # How many off-heap references a copy of `term` holds in another process,
  # and how many bytes they name. The probe process is not capped.
  defp probe(term) do
    parent = self()

    spawn(fn ->
      {:binary, bins} = Process.info(self(), :binary)
      # `term` is read after the count, so the closure carries the copy.
      held = is_struct(term)

      send(
        parent,
        {:probe, length(bins), Enum.sum(for {_id, size, _refc} <- bins, do: size), held}
      )
    end)

    receive do
      {:probe, refs, bytes, true} -> {refs, bytes}
    after
      10_000 -> flunk("probe timed out")
    end
  end

  # The dead render of `live/2` runs the endpoint, HeapCap plug included, in
  # the test process; the test's own bookkeeping is not what is under test.
  defp uncap_self, do: Process.flag(:max_heap_size, %{size: 0})

  defp mib(bytes), do: Float.round(bytes / 1_048_576, 1)

  defp upload(view, name, content, type) do
    file_input(view, "#pp-import-form", :pp_file, [
      %{name: name, content: content, type: type, last_modified: 1_700_000_000_000}
    ])
    |> render_upload(name)

    render_async(view)
  end

  # Uploads through /imports and reports whether the page process is still
  # alive 3 s after the upload (the background count refinement has run).
  defp upload_and_watch(conn, name, content, type) do
    {:ok, view, _html} = live(conn, "/imports")
    uncap_self()
    Process.flag(:trap_exit, true)
    page_ref = Process.monitor(view.pid)

    capture_log(fn ->
      outcome =
        try do
          upload(view, name, content, type)
          :rendered
        catch
          :exit, reason -> {:exit, reason}
        end

      state =
        receive do
          {:DOWN, ^page_ref, :process, _pid, reason} -> {:down, reason}
        after
          3_000 -> :alive
        end

      send(self(), {:watched, state, outcome})
      # Let the logs of a killed page and task land inside the capture.
      Process.sleep(500)
    end)

    assert_received {:watched, state, outcome}
    {view, state, outcome}
  end

  # User story (security review 2026-10-12, H58):
  # As the operator importing my own Portfolio Performance export,
  # I want the parsed preview to hold only the text it keeps, never the whole
  # upload once per long text cell,
  # so that handing the preview to a capped background task does not count the
  # upload many times over and kill it.
  #
  # Acceptance criteria:
  # - A capped task holding the preview of an export with many notes
  #   survives its first garbage collection.
  test "a parsed export handed to a capped task survives the task's first collection" do
    body = notes_csv(2_000, 100)

    {:ok, %Preview{entries: entries} = preview} =
      Imports.parse_portfolio_performance(body, filename: "synthetic.csv")

    assert length(entries) == 2_000

    {_refs, bytes} = probe(preview)
    parent = self()

    capture_log(fn ->
      {:ok, pid} =
        CappedAsync.start(fn ->
          :erlang.garbage_collect()
          send(parent, {:survived, length(preview.entries)})
        end)

      ref = Process.monitor(pid)

      result =
        receive do
          {:survived, n} -> {:survived, n}
          {:DOWN, ^ref, :process, ^pid, reason} -> {:down, reason}
        after
          10_000 -> :timeout
        end

      send(parent, {:result, result})
      Process.sleep(200)
    end)

    assert_received {:result, result}

    assert result == {:survived, 2_000},
           "a capped task holding the preview of a #{byte_size(body)}-byte export was " <>
             "#{inspect(result)}: it counted #{mib(bytes)} MiB of off-heap binaries"
  end

  # User story (security review 2026-10-12, H58):
  # As the operator dropping an export whose bookings carry notes,
  # I want the Imports page to preview it and stay alive,
  # so that an ordinary file of mine can be previewed and applied.
  #
  # Acceptance criteria:
  # - A CSV export whose rows carry notes previews, and the page process is
  #   alive after its background work.
  test "uploading a 2,000-row CSV export with 100-byte notes keeps the Imports page alive",
       %{conn: conn} do
    conn = init_test_session(conn, %{"_csrf_token" => @token_upload})
    body = notes_csv(2_000, 100)

    {view, state, _outcome} = upload_and_watch(conn, "synthetic.csv", body, "text/csv")

    assert state == :alive, "the Imports page process went #{inspect(state)} after the upload"
    assert render(view) =~ "Preview"
  end

  # User story (security review 2026-10-12, H58):
  # As the operator of a savings plan in a long-named fund,
  # I want a JSON export of its buys to preview,
  # so that the fund's name does not cost the page its life.
  #
  # Acceptance criteria:
  # - A JSON export of many buys of a long-named fund previews, and the page
  #   process stays alive.
  test "uploading a JSON export of 2,000 buys of a fund with a 67-byte name keeps the page alive",
       %{conn: conn} do
    name = "Synthetic Global Developed Markets Equity Index UCITS ETF EUR Acc A"
    assert byte_size(name) == 67
    body = fund_json(2_000, name)

    {view, state, _outcome} = upload_and_watch(conn, "synthetic.json", body, "application/json")

    assert state == :alive, "the Imports page process went #{inspect(state)} after the upload"
    assert render(view) =~ "Preview"
  end

  # User story (security review 2026-10-12, H58):
  # As the operator,
  # I want an ordinary note length not to decide whether my export previews,
  # so that an export with slightly longer notes behaves as one with shorter
  # notes does.
  #
  # Acceptance criteria:
  # - Both exports preview, and the page process stays alive.
  test "uploading 2,200 rows with 65-byte notes keeps the Imports page alive", %{conn: conn} do
    body = notes_csv(2_200, 65)

    {view, state, _outcome} = upload_and_watch(conn, "synthetic.csv", body, "text/csv")

    assert state == :alive, "the Imports page process went #{inspect(state)} after the upload"
    assert render(view) =~ "Preview"
  end

  test "control: 2,200 rows with 64-byte notes keep the Imports page alive", %{conn: conn} do
    body = notes_csv(2_200, 64)

    {view, state, _outcome} = upload_and_watch(conn, "synthetic.csv", body, "text/csv")

    assert state == :alive
    assert render(view) =~ "Preview"
  end

  # User story (security review 2026-10-12, H58):
  # As the operator whose preview of a long-noted export was parked,
  # I want every later visit of the Imports page to answer,
  # so that the page is never locked for my browser session.
  #
  # Acceptance criteria:
  # - With such a preview parked, later GET /imports of the session answer 200
  #   under the default heap cap.
  test "a parked preview of such an export does not kill every later GET /imports",
       %{conn: conn} do
    conn = init_test_session(conn, %{"_csrf_token" => @token_parked})
    key = PreviewStore.key_for(@token_parked)
    body = notes_csv(2_000, 100)

    # Control: this browser session's GET /imports answers 200 before.
    assert get_in_own_process(conn, "/imports") == 200

    # Park the preview through the page's own flow, with the cap lifted for
    # the upload only.
    prior = Application.get_env(:portfolixir, PortfolixirWeb.HeapCap)
    on_exit(fn -> restore_cap(prior) end)
    Application.put_env(:portfolixir, PortfolixirWeb.HeapCap, max_heap_bytes: 0)

    {view, state, _outcome} = upload_and_watch(conn, "synthetic.csv", body, "text/csv")
    assert state == :alive, "control: with the cap lifted the page survives the upload"
    assert render(view) =~ "Preview"
    assert :ets.member(PreviewStore, key), "control: the page parked the preview"
    GenServer.stop(view.pid, :normal)
    flush_exits()

    # The default cap again, as every instance runs it.
    restore_cap(prior)

    capture_log(fn ->
      statuses = for _attempt <- 1..3, do: get_in_own_process(conn, "/imports")
      send(self(), {:statuses, statuses})
      Process.sleep(300)
    end)

    assert_received {:statuses, statuses}

    assert statuses == [200, 200, 200],
           "every GET /imports of the browser session holding the parked preview: #{inspect(statuses)}"
  end

  defp restore_cap(nil), do: Application.delete_env(:portfolixir, PortfolixirWeb.HeapCap)
  defp restore_cap(prior), do: Application.put_env(:portfolixir, PortfolixirWeb.HeapCap, prior)

  defp flush_exits do
    receive do
      {:EXIT, _pid, _reason} -> flush_exits()
      {:DOWN, _ref, :process, _pid, _reason} -> flush_exits()
    after
      100 -> :ok
    end
  end

  # `get/2` dispatches the endpoint in the calling process, as Bandit runs one
  # request in one process: a process of its own per request.
  defp get_in_own_process(conn, path) do
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        conn = get(conn, path)
        send(parent, {:status, self(), conn.status})
      end)

    receive do
      {:status, ^pid, status} ->
        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
        after
          1_000 -> :ok
        end

        status

      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:down, reason}
    after
      15_000 -> :timeout
    end
  end
end
