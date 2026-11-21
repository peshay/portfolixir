defmodule PortfolixirWeb.Journal.DashboardKindTest do
  # Sprint 31 D2 (ADR-0062 §2, §11; D1's lens found it): a dashboard's
  # write is journaled under resource_type "dashboard", and the audit
  # journal's page names it in words, offers it in its kind select, and
  # draws the stored name escaped, as text. Every name is synthetic.
  #
  # group: :dashboards -- every module that creates a dashboard joins it
  # (the create's count lock, `Portfolixir.LockTable` row 30).
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest

  alias PortfolixirWeb.Journal.Row

  # User story (ADR-0062 §2, §8):
  # As the operator reading the audit journal,
  # I want an agent's dashboard named as a dashboard, with the name it
  # gave it drawn as text,
  # so that I see what the agent composed, and a name cannot turn into
  # markup on my screen.
  #
  # Acceptance criteria:
  # - "dashboard" reads „Dashboard“ (German „Dashboard“), and the kind
  #   select offers it after the snapshots.
  # - A dashboard created over the API with markup in its name appears on
  #   /journal as „Dashboard <id> · <name>“, the name escaped: no element
  #   the name spells is in the page.
  test "a dashboard's entry is named in words, its name drawn as text", %{conn: conn} do
    assert Row.kind_label("dashboard") == "Dashboard"

    assert Enum.drop_while(Row.kinds(), &(&1 != "snapshot")) |> Enum.take(2) ==
             ["snapshot", "dashboard"]

    Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
      assert Row.kind_label("dashboard") == "Dashboard"
    end)

    name = ~s[<img src=x onerror="alert(1)"> Kurzfristig]

    %{"data" => %{"id" => id}} =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")
      |> post("/api/v1/dashboards", %{"dashboard" => %{"name" => name}})
      |> json_response(201)

    {:ok, view, html} = live(build_conn(), "/journal?resource_type=dashboard")

    assert html =~ "Dashboard #{id} · &lt;img src=x onerror=&quot;alert(1)&quot;&gt; Kurzfristig"
    refute html =~ "<img src=x"
    refute has_element?(view, "img[src=x]")
    assert has_element?(view, "option[value=dashboard]", "Dashboard")
  end
end
