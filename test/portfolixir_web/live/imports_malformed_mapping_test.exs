defmodule PortfolixirWeb.ImportsMalformedMappingTest do
  @moduledoc false
  # The preview store is shared state, so this module runs alone, like the
  # other Imports page tests.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Imports.Mapping
  alias Portfolixir.Imports.PreviewStore
  alias Portfolixir.Portfolios

  @moduletag :capture_log

  @fixtures Path.expand("../../support/fixtures/portfolio_performance", __DIR__)
  @past_bigint "99999999999999999999999"
  @session_token "BBBBBBBBBBBBBBBBBBBBBBBB"

  setup %{conn: conn} do
    {:ok, _portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "PP Import Target",
        base_currency_code: "EUR"
      })

    on_exit(fn -> PreviewStore.delete(PreviewStore.key_for(@session_token)) end)
    %{conn: init_test_session(conn, %{"_csrf_token" => @session_token})}
  end

  # User story (E25 S4, F17):
  # As the operator mid-way through mapping an import,
  # I want a mapping event of the wrong shape to change nothing,
  # so that a crafted or stale push can neither crash the page nor park a
  # mapping that crashes it again on every visit.
  #
  # Acceptance criteria:
  # - Mapping and apply events whose cash, depot, security, remember or
  #   bucket-tag parts are not the maps and strings the form sends leave the
  #   page alive and the parked mapping readable.
  # - An existing-account or existing-security choice past the id range is
  #   refused like any unreadable choice, never handed to a query.
  # - After all of them, /imports remounts on the parked preview.
  test "malformed mapping events leave the preview alive and remountable", %{conn: conn} do
    Process.flag(:trap_exit, true)

    {:ok, view, _html} = live(conn, "/imports")
    upload_sample(view)
    assert render(view) =~ "Preview"

    # E25 S5 (F42): rows are addressed by their opaque key, so the malformed
    # shapes below reach the rows the page knows.
    cash = Mapping.row_key("cash", "Test-Cash")
    depot = Mapping.row_key("depot", "Test-Depot")

    payloads = [
      %{"cash" => "x"},
      %{"depot" => "x"},
      %{"security" => "x"},
      %{"remember" => "x"},
      %{"bucket_tag" => %{"a" => "b"}},
      %{"bucket_tag" => ["a"]},
      %{"cash" => %{cash => %{"a" => "b"}}},
      %{"cash" => %{cash => ["existing:1"]}},
      %{"cash" => %{"not-a-key" => "existing:1", "Test-Cash" => "existing:1"}},
      %{"depot" => %{depot => "existing:1"}},
      %{"depot" => %{depot => %{"target" => %{"a" => "b"}, "cash" => ["x"]}}},
      %{"security" => %{"k" => "x"}},
      %{"security" => %{"k" => %{"choice" => %{"a" => "b"}}}},
      %{"remember" => %{"cash" => "x", "depot" => ["x"]}},
      %{"cash" => %{cash => "existing:#{@past_bigint}"}},
      %{"depot" => %{depot => %{"target" => "existing:#{@past_bigint}", "cash" => ""}}}
    ]

    for event <- ["mapping_changed", "apply"], payload <- payloads do
      try do
        render_hook(view, event, payload)
        render_async(view, 2_000)
      catch
        :exit, reason ->
          flunk("#{event} #{inspect(payload)} took the page down: #{inspect(reason, limit: 5)}")
      end

      assert Process.alive?(view.pid)
    end

    assert {_preview, mapping} = PreviewStore.get(PreviewStore.key_for(@session_token))
    assert is_binary(mapping.bucket_tag)
    assert Enum.all?(mapping.cash, fn {name, choice} -> is_binary(name) and is_binary(choice) end)
    # A key the preview did not hand out, or a bare file name, addresses no row.
    assert Map.keys(mapping.cash) |> Enum.sort() == ["Test-Cash", "Test-Cash-2"]
    assert Enum.all?(mapping.depot, fn {_name, row} -> is_map(row) end)
    assert Enum.all?(mapping.security, fn {_key, row} -> is_map(row) end)

    assert {:ok, _view, html} = live(conn, "/imports")
    assert html =~ "Preview"
  end

  defp upload_sample(view) do
    file_input(view, "#pp-import-form", :pp_file, [
      %{
        name: "sample.json",
        content: File.read!(Path.join(@fixtures, "sample.json")),
        type: "application/json",
        last_modified: 1_700_000_000_000
      }
    ])
    |> render_upload("sample.json")
  end
end
