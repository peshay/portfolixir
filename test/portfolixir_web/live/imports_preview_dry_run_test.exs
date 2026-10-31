defmodule PortfolixirWeb.ImportsPreviewDryRunTest do
  # The Imports page's dry run (ADR-0050 as amended on 2026-10-09) before any
  # confirm: the preview judges a dropped file the way the apply would, in the
  # background, and must take no write lock and write nothing while it does.
  # Its answer is kept with the parked preview, so a remount (a reload, a
  # language switch, a second tab) shows it instead of running it again.
  #
  # Races against other writers on real connections are pinned in
  # `Portfolixir.LockRace.PreviewDryRunTest`.
  #
  # Every name, amount and identifier is synthetic.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Isin
  alias Portfolixir.Catalog.IdentifierAliases
  alias Portfolixir.Imports.PreviewStore
  alias Portfolixir.Lifecycle.AccountNames
  alias Portfolixir.Portfolios

  # 24 characters of base64url, so Plug.CSRFProtection keeps it and both
  # mounts share one PreviewStore key.
  @session_token "HHHHHHHHHHHHHHHHHHHHH053"

  setup %{conn: conn} do
    {:ok, _portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Synthetic Target",
        base_currency_code: "EUR"
      })

    on_exit(fn -> PreviewStore.delete(PreviewStore.key_for(@session_token)) end)
    %{conn: init_test_session(conn, %{"_csrf_token" => @session_token})}
  end

  # User story (security review 2026-10-12, H53):
  # As the operator who drops a file on the Imports page, and reopens the
  # page while its preview is parked,
  # I want the preview to take no write lock and write nothing before I
  # confirm,
  # so that looking at a file never holds up my agent's writes.
  #
  # Acceptance criteria:
  # - Dropping a file of three purchases of new securities and two deposits
  #   sends, before any confirm, no blocking account-identity lock, no ISIN
  #   write lock, and no insert of a security, an account or a booking; its
  #   counts are refined all the same (five bookings new).
  # - The remount of the parked preview sends none of them either, and
  #   nothing is persisted.
  test "dropping a file, and remounting its parked preview, take no write lock before confirm",
       %{conn: conn} do
    observe_queries!()

    {:ok, view, _html} = live(conn, "/imports")
    _mount = drain_queries()

    upload!(view, file(3, 2, "XS", 10))
    on_upload = drain_queries() |> summarize()

    assert PreviewStore.get(PreviewStore.key_for(@session_token)) != nil

    assert view
           |> element("#mapping-cash-#{row_key("Synthetic Cash")} [data-role='mapping-count']")
           |> render() =~ "5 bookings new"

    {:ok, remounted, _html} = live(conn, "/imports")
    render_async(remounted)
    on_remount = drain_queries() |> summarize()

    secure = %{
      identity_lock: 0,
      isin_write_lock: 0,
      security_inserts: 0,
      account_inserts: 0,
      booking_inserts: 0
    }

    assert %{upload: on_upload, remount: on_remount} == %{upload: secure, remount: secure}
    assert Catalog.count_securities() == 0
  end

  # User story (security review 2026-10-12, H53):
  # As the operator who reloads the Imports page, switches its language or
  # opens it in a second tab while a preview is parked,
  # I want the page to show the dry run's answer it already has,
  # so that every mount does not judge the whole file again.
  #
  # Acceptance criteria:
  # - Once the upload's dry run has answered, a remount of the parked
  #   preview starts no dry run, and shows the refined counts.
  test "a remount of an answered preview runs no dry run again", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports")
    upload!(view, file(3, 2, "XS", 20))

    Application.put_env(:portfolixir, :imports_refine_gate, self())
    on_exit(fn -> Application.delete_env(:portfolixir, :imports_refine_gate) end)

    {:ok, remounted, _html} = live(conn, "/imports")
    refute_receive {:imports_refine_gate, _task}, 500

    assert remounted
           |> element("#mapping-cash-#{row_key("Synthetic Cash")} [data-role='mapping-count']")
           |> render() =~ "5 bookings new"
  end

  defp row_key(name), do: Portfolixir.Imports.Mapping.row_key("cash", name)

  defp upload!(view, rows) do
    file_input(view, "#pp-import-form", :pp_file, [
      %{
        name: "synthetic.json",
        content: Jason.encode!(%{"version" => 1, "transactions" => rows}),
        type: "application/json",
        last_modified: 1_700_000_000_000
      }
    ])
    |> render_upload("synthetic.json")

    render_async(view)
  end

  # --- files ---------------------------------------------------------------------

  # A synthetic ISIN with a valid check digit.
  defp isin(prefix, n) do
    base = prefix <> String.pad_leading(Integer.to_string(n), 9, "0")
    Enum.find_value(0..9, fn d -> if Isin.valid?(base <> "#{d}"), do: base <> "#{d}" end)
  end

  defp num(digits), do: Jason.Fragment.new(digits)

  # `buys` purchases, each of its own new security, then `deposits` deposits.
  defp file(buys, deposits, prefix, offset) do
    purchases =
      for n <- 1..buys//1 do
        %{
          "type" => "PURCHASE",
          "account" => "Synthetic Cash",
          "portfolio" => "Synthetic Depot",
          "date" => Date.to_iso8601(Date.add(~D[2015-01-05], n)),
          "currency" => "EUR",
          "amount" => num("#{100 + n}.25"),
          "shares" => num("1"),
          "security" => %{
            "name" => "Synthetic Fund #{offset + n}",
            "isin" => isin(prefix, offset + n),
            "currency" => "EUR"
          }
        }
      end

    deposits =
      for n <- 1..deposits//1 do
        %{
          "type" => "DEPOSIT",
          "account" => "Synthetic Cash",
          "date" => Date.to_iso8601(Date.add(~D[2000-01-03], offset + n)),
          "currency" => "EUR",
          "amount" => num("#{offset + n}.01")
        }
      end

    purchases ++ deposits
  end

  # --- observing queries -----------------------------------------------------------

  defp observe_queries! do
    handler = "preview-dry-run-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:portfolixir, :repo, :query],
        &__MODULE__.forward_query/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  @doc false
  def forward_query(_event, _measurements, metadata, test_pid) do
    send(test_pid, {:preview_query, Map.get(metadata, :query), Map.get(metadata, :params)})
  end

  defp drain_queries(acc \\ []) do
    receive do
      {:preview_query, query, params} -> drain_queries([{query, params} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp summarize(queries) do
    %{
      identity_lock: Enum.count(queries, &blocking_lock?(&1, AccountNames.lock_key())),
      isin_write_lock:
        Enum.count(queries, &blocking_lock?(&1, IdentifierAliases.isin_write_lock_key())),
      security_inserts: Enum.count(queries, &insert?(&1, "securities")),
      account_inserts:
        Enum.count(queries, &(insert?(&1, "cash_accounts") or insert?(&1, "securities_accounts"))),
      booking_inserts: Enum.count(queries, &insert?(&1, "transactions"))
    }
  end

  # The blocking form only: a try-lock does not match "pg_advisory_xact_lock(".
  defp blocking_lock?({query, [key | _]}, key) when is_binary(query),
    do: String.contains?(query, "pg_advisory_xact_lock(")

  defp blocking_lock?(_query, _key), do: false

  defp insert?({query, _params}, table) when is_binary(query),
    do: String.starts_with?(query, ~s(INSERT INTO "#{table}"))

  defp insert?(_query, _table), do: false
end
