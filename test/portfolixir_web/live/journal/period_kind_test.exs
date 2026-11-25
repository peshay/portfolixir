defmodule PortfolixirWeb.Journal.PeriodKindTest do
  # Sprint 32 T2 (ADR-0062's amendment of 2026-11-25, point 6): a stored
  # period's write is journaled under resource_type "period", and the
  # audit journal's page names it in words, offers it in its kind select,
  # and draws the stored name escaped, as text. Every name is synthetic.
  #
  # group: :periods -- every module that creates a period joins it (the
  # create's count lock, `Portfolixir.LockTable` row 31).
  use PortfolixirWeb.ConnCase, async: true, group: :periods

  import Phoenix.LiveViewTest

  alias PortfolixirWeb.Journal.Row

  # User story:
  # As the operator reading the audit journal,
  # I want an agent's own period named as a period, with the name it gave
  # it drawn as text,
  # so that I see what the agent stored, and a name cannot turn into
  # markup on my screen.
  #
  # Acceptance criteria:
  # - "period" reads „Zeitraum“ in German and the kind select offers it
  #   after the dashboards.
  # - A period created over the API with markup in its name appears on
  #   /journal, the name escaped: no element the name spells is in the page.
  test "a period's entry is named in words, its name drawn as text", %{conn: conn} do
    assert Enum.drop_while(Row.kinds(), &(&1 != "dashboard")) |> Enum.take(2) ==
             ["dashboard", "period"]

    Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
      assert Row.kind_label("period") == "Zeitraum"
    end)

    name = ~s[<b>Sommer</b> 2026]

    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> post("/api/v1/periods", %{"period" => %{"name" => name, "from" => "2026-06-01"}})
    |> json_response(201)

    {:ok, view, html} = live(build_conn(), "/journal?resource_type=period")

    assert html =~ "&lt;b&gt;Sommer&lt;/b&gt; 2026"
    refute has_element?(view, "b", "Sommer")
    assert has_element?(view, "option[value=period]")
  end
end
