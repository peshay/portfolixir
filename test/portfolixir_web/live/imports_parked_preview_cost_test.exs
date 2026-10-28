defmodule PortfolixirWeb.ImportsParkedPreviewCostTest do
  use PortfolixirWeb.ConnCase

  import ExUnit.CaptureLog

  alias Portfolixir.Imports
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.PreviewStore
  alias Portfolixir.Portfolios

  @moduletag timeout: 300_000

  @mib 1_048_576

  setup do
    PreviewStore.clear()
    on_exit(&PreviewStore.clear/0)

    saved_cap = Application.get_env(:portfolixir, PortfolixirWeb.HeapCap)
    on_exit(fn -> restore_cap(saved_cap) end)

    # An instance with a portfolio, so the hash layers and the correction
    # pass run against it as on a used instance.
    {:ok, _portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Synthetic Import Target",
        base_currency_code: "EUR"
      })

    {:ok, saved_cap: saved_cap}
  end

  # User story (security review 2026-10-12, H07):
  # As the operator of an instance whose UI anyone on the host can reach,
  # I want a plain load of the Imports page to cost the same whatever its
  # browser session has parked,
  # so that repeated loads of a session with a parked preview cannot exhaust
  # the node's memory.
  #
  # Acceptance criteria:
  # - Under a heap cap a fresh session's GET /imports fits, the GET of a
  #   session with a parked preview fits too.
  test "a plain GET /imports needs no more heap under a session with a parked preview",
       %{conn: conn, saved_cap: saved_cap} do
    parked_token = session_token()
    park!(parked_token, 20_000)

    parked_conn = conn |> recycle() |> init_test_session(%{"_csrf_token" => parked_token})
    fresh_conn = conn |> recycle() |> init_test_session(%{"_csrf_token" => session_token()})

    cap_mib = 16
    Application.put_env(:portfolixir, PortfolixirWeb.HeapCap, max_heap_bytes: cap_mib * @mib)

    {results, _log} =
      with_log(fn ->
        fresh = timed_get(fresh_conn)
        parked = timed_get(parked_conn)
        Process.sleep(300)
        {fresh, parked}
      end)

    restore_cap(saved_cap)
    {fresh_capped, parked_capped} = results

    # The control: a GET of a session with nothing parked fits the cap.
    assert match?({200, _ms}, fresh_capped),
           "control failed: a fresh session's GET does not fit #{cap_mib} MiB: #{inspect(fresh_capped)}"

    assert match?({200, _ms}, parked_capped),
           "GET /imports under the parked session was #{inspect(parked_capped)} under a " <>
             "#{cap_mib} MiB heap cap that the fresh session's GET fits"
  end

  # User story (security review 2026-10-12, H07):
  # As the operator of an instance whose UI anyone on the host can reach,
  # I want the parked previews bounded by the memory they hold, not only by
  # their number,
  # so that filling every parking slot with the largest file cannot exhaust
  # the node's memory.
  #
  # Acceptance criteria:
  # - Three sessions parking a file at the parser's row cap leave the store
  #   within a fixed byte budget.
  test "the preview store bounds the bytes its parked previews hold" do
    rows = PortfolioPerformance.max_rows()

    {:ok, preview} =
      Imports.parse_portfolio_performance(synthetic_csv(rows), filename: "export.csv")

    for token <- for(_ <- 1..3, do: session_token()) do
      PreviewStore.put(PreviewStore.key_for(token), preview, mapping_for_synthetic())
    end

    held = ets_bytes()
    budget = 256 * @mib

    assert held <= budget,
           "PreviewStore holds #{mib(held)} MiB for three parked previews, past a " <>
             "#{mib(budget)} MiB byte budget"
  end

  # Parses a synthetic file of `rows` rows and parks it under the session
  # token's key, as the page does after an upload.
  defp park!(token, rows) do
    {:ok, preview} =
      Imports.parse_portfolio_performance(synthetic_csv(rows), filename: "export.csv")

    key = PreviewStore.key_for(token)
    :ok = PreviewStore.put(key, preview, mapping_for_synthetic())
    key
  end

  # One depot, one cash account and one security, none of them stored.
  defp mapping_for_synthetic do
    %{
      bucket_tag: "",
      bucket_skip: false,
      cash: %{"Cash A" => "create:Cash A"},
      depot: %{"Depot A" => %{"target" => "create:Depot A", "cash" => "pp:Cash A"}},
      security: %{},
      remember: %{"cash" => %{}, "depot" => %{}},
      prefill: %{
        "cash" => %{"Cash A" => "create:Cash A"},
        "depot" => %{"Depot A" => "create:Depot A"}
      }
    }
  end

  # Portfolio Performance CSV buy rows; every cell short.
  defp synthetic_csv(rows) do
    header =
      "Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle\n"

    body =
      for i <- 1..rows do
        date = ~D[2000-01-01] |> Date.add(rem(i, 9000)) |> Date.to_iso8601()

        "#{date} 10:01;Kauf;Synthetic Security 1;1,123456;12,345678;13,86;1,00;0,50;15,36;Depot A;Cash A;;\n"
      end

    IO.iodata_to_binary([header | body])
  end

  # A valid CSRF session token (24 characters of base64url), one per browser.
  defp session_token, do: Base.url_encode64(:crypto.strong_rand_bytes(18))

  defp ets_bytes, do: :ets.info(PreviewStore, :memory) * :erlang.system_info(:wordsize)

  defp mib(bytes), do: Float.round(bytes / @mib, 1)

  # GET /imports in a process of its own (the HeapCap plug caps it as it caps
  # every request process): `{status | exit_reason, ms}`.
  defp timed_get(conn) do
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        started = System.monotonic_time(:millisecond)
        response = get(conn, "/imports")

        send(
          parent,
          {:got, self(), response.status, System.monotonic_time(:millisecond) - started}
        )
      end)

    started = System.monotonic_time(:millisecond)

    receive do
      {:got, ^pid, status, ms} ->
        Process.demonitor(ref, [:flush])
        {status, ms}

      {:DOWN, ^ref, :process, ^pid, reason} ->
        {reason, System.monotonic_time(:millisecond) - started}
    after
      120_000 -> {:timeout, nil}
    end
  end

  defp restore_cap(nil), do: Application.delete_env(:portfolixir, PortfolixirWeb.HeapCap)
  defp restore_cap(saved), do: Application.put_env(:portfolixir, PortfolixirWeb.HeapCap, saved)
end
