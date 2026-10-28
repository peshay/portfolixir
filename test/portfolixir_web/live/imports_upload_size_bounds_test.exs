defmodule PortfolixirWeb.ImportsUploadSizeBoundsTest do
  use PortfolixirWeb.ConnCase

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Imports.PreviewStore
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.HeapCap

  @moduletag timeout: 180_000
  @session_token "HHHHHHHHHHHHHHHHHHHHHH59"
  @csv_header "Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle"

  setup %{conn: conn} do
    {:ok, _portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "PP Import Target",
        base_currency_code: "EUR"
      })

    on_exit(fn -> PreviewStore.delete(PreviewStore.key_for(@session_token)) end)
    %{conn: init_test_session(conn, %{"_csrf_token" => @session_token})}
  end

  # Drops one file on /imports. Answers the page, how the upload call ended,
  # whether the page's process went down, and the log captured meanwhile.
  defp drop(conn, name, content, type) do
    {:ok, view, _html} = live(conn, "/imports")
    ref = Process.monitor(view.pid)
    started = System.monotonic_time(:millisecond)

    {outcome, log} =
      with_log(fn ->
        try do
          html =
            view
            |> file_input("#pp-import-form", :pp_file, [
              %{name: name, content: content, type: type, last_modified: 1_700_000_000_000}
            ])
            |> render_upload(name)

          {:ok, html}
        catch
          :exit, reason -> {:exit, reason}
        end
      end)

    down =
      receive do
        {:DOWN, ^ref, :process, _pid, reason} -> {:down, reason}
      after
        1_000 -> :alive
      end

    elapsed = System.monotonic_time(:millisecond) - started
    %{view: view, outcome: outcome, down: down, log: log, ms: elapsed}
  end

  defp excerpt(log), do: log |> String.replace("\n", " ") |> String.slice(0, 400)

  defp assert_page_answered(%{outcome: outcome, down: down, log: log, ms: ms}, what) do
    assert down == :alive and match?({:ok, _html}, outcome),
           "#{what}: the Imports page process ended (#{inspect(down)}) after #{ms} ms " <>
             "instead of answering a named file error; upload call: " <>
             "#{outcome |> inspect(limit: 6) |> String.slice(0, 200)}; log: #{excerpt(log)}"
  end

  # The page parses in its own process, which HeapCap caps at mount. A
  # process capped the same way, holding the same body, stands in for it.
  defp in_capped_process(fun) do
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        HeapCap.cap!()
        send(parent, {:parsed, self(), fun.()})
      end)

    receive do
      {:parsed, ^pid, result} ->
        Process.demonitor(ref, [:flush])
        {:returned, result}

      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:down, reason}
    after
      90_000 ->
        Process.exit(pid, :kill)
        {:down, :test_timeout}
    end
  end

  defp parse_capped(body, filename) do
    started = System.monotonic_time(:millisecond)

    {result, log} =
      with_log(fn ->
        result = in_capped_process(fn -> PortfolioPerformance.parse(body, filename: filename) end)
        # The runtime reports a heap-cap kill asynchronously; let the report
        # reach this capture rather than the console.
        if match?({:down, _}, result), do: Process.sleep(500)
        result
      end)

    {result, log, System.monotonic_time(:millisecond) - started}
  end

  defp deposit_row(betrag, note),
    do: "2024-01-15 10:01:00;Einlage;;;;#{betrag};;;;Test-Cash;;#{note};"

  describe "control: below the bounds the guards answer as before" do
    test "1 MB of empty lines is refused with the row cap, and the page lives", %{conn: conn} do
      body = @csv_header <> "\n" <> String.duplicate("\n", 1_000_000)
      result = drop(conn, "rows.csv", body, "text/csv")

      assert_page_answered(result, "1 MB of empty lines")
      assert render(result.view) =~ "sized for at most"
    end

    test "a deposit row with a short note previews, a 20,000-character note is a row error" do
      ok = @csv_header <> "\n" <> deposit_row("100,00", "short note")

      assert {{:returned, {:ok, %Preview{entries: [_], errors: []}}}, _, _} =
               parse_capped(ok, "n.csv")

      long = @csv_header <> "\n" <> deposit_row("100,00", String.duplicate("a", 20_000))

      assert {{:returned, {:ok, %Preview{entries: [], errors: [%{row: 2}]}}}, _, _} =
               parse_capped(long, "n.csv")
    end
  end

  describe "through /imports" do
    # User story (security review 2026-10-12, H59):
    # As the operator dropping a file on the Imports page,
    # I want a CSV file with more rows than the import is sized for refused
    # before its rows are built,
    # so that the page answers with the row cap's message instead of being
    # stopped by its own memory bound.
    #
    # Acceptance criteria:
    # - A large CSV of empty lines is refused with the row cap's message, and
    #   the page process lives.
    test "a CSV of 6 MB of empty lines is refused with the row cap, and the page lives",
         %{conn: conn} do
      body = @csv_header <> "\n" <> String.duplicate("\n", 6_000_000)
      result = drop(conn, "rows.csv", body, "text/csv")

      assert_page_answered(result, "6 MB CSV of empty lines")
      assert render(result.view) =~ "sized for at most"
    end

    # User story (security review 2026-10-12, H59):
    # As the operator dropping a file on the Imports page,
    # I want a JSON file with more transactions than the import is sized for
    # refused before its transactions are decoded,
    # so that the page answers with the row cap's message instead of being
    # stopped by its own memory bound.
    #
    # Acceptance criteria:
    # - A large JSON export of empty transactions is refused with the row
    #   cap's message, and the page process lives.
    test "a JSON export of 11 MB of empty transactions is refused with the row cap, and the page lives",
         %{conn: conn} do
      body = ~s({"version":1,"transactions":[) <> String.duplicate("{},", 3_600_000) <> "{}]}"
      result = drop(conn, "x.json", body, "application/json")

      assert_page_answered(result, "11 MB JSON of empty transactions")
      assert render(result.view) =~ "sized for at most"
    end
  end

  describe "per value, in a process capped as the page is" do
    # User story (security review 2026-10-12, H59):
    # As the operator,
    # I want a CSV line far longer than any booking refused before it is read
    # as cells,
    # so that one oversized cell is a named error, never a stopped parser.
    #
    # Acceptance criteria:
    # - A row with an oversized note or an oversized amount is a named row
    #   error or a named file error, and the parser process returns.
    test "a CSV deposit whose note is 10 MB is a named row error, not a killed parser" do
      body = @csv_header <> "\n" <> deposit_row("100,00", String.duplicate("a", 10_000_000))
      {result, log, ms} = parse_capped(body, "note.csv")

      assert match?({:returned, {:ok, %Preview{errors: [_ | _]}}}, result) or
               match?({:returned, {:error, _}}, result),
             "10 MB note: the parser process ended (#{inspect(result, limit: 4)}) after #{ms} ms " <>
               "instead of naming the row; log: #{excerpt(log)}"
    end

    test "a CSV deposit whose Betrag is 19 MB of digits is a named row error, not a killed parser" do
      body = @csv_header <> "\n" <> deposit_row("1," <> String.duplicate("1", 19_000_000), "")
      {result, log, ms} = parse_capped(body, "betrag.csv")

      assert match?({:returned, {:ok, %Preview{errors: [_ | _]}}}, result) or
               match?({:returned, {:error, _}}, result),
             "19 MB Betrag: the parser process ended (#{inspect(result, limit: 4)}) after #{ms} ms " <>
               "instead of naming the row; log: #{excerpt(log)}"
    end

    # User story (security review 2026-10-12, H59):
    # As the operator,
    # I want a JSON file nested deeper than any export refused before it is
    # decoded,
    # so that its nesting is a named file error, never a stopped parser.
    #
    # Acceptance criteria:
    # - Such a file is a named file error, and the parser process returns.
    test "a JSON export nested millions of levels deep is a named file error, not a killed parser" do
      body =
        ~s({"version":1,"transactions":) <>
          String.duplicate("[", 5_000_000) <> String.duplicate("]", 5_000_000) <> "}"

      {result, log, ms} = parse_capped(body, "deep.json")

      assert result == {:returned, {:error, :malformed_payload}},
             "deep nesting: the parser process ended (#{inspect(result, limit: 4)}) after " <>
               "#{ms} ms instead of naming the file; log: #{excerpt(log)}"
    end
  end
end
