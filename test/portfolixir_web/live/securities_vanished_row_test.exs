defmodule PortfolixirWeb.SecuritiesVanishedRowTest do
  # Sprint 18 pick H8.6 = A (#920; board ux-design-2026-10-02/08-dialogs-copy):
  # a row action that finds its security gone — deleted or merged away over
  # the API, MCP or another tab — reloads the list, drops a detail pane on the
  # vanished security, and says in one note why the row went. A merge names
  # and links the survivor. The API and MCP are unchanged.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Lifecycle

  defp agent, do: Actor.api_token_rw("synthetic-agent")
  defp german(conn), do: Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")

  defp security!(name, isin) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        isin: isin,
        currency_code: "EUR",
        asset_class: "etf"
      })

    security
  end

  defp merge!(source, target) do
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    {:ok, _record, :applied} =
      Lifecycle.merge_security(agent(), source.id, target.id, %{
        plan_digest: preview.plan_digest,
        collapse_key_equal: false,
        identity_choice: "keep_target_isin"
      })
  end

  defp open_menu(view, security) do
    view
    |> element(
      ~s(#securities-table button[phx-click="open_row_menu"][phx-value-id="#{security.id}"])
    )
    |> render_click()
  end

  defp click(view, security, action) do
    view
    |> element(~s(#row-menu-#{security.id} button[phx-value-action="#{action}"]))
    |> render_click()
  end

  defp note_text(view) do
    view
    |> element("#securities-action-result [role=status]")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> String.split()
    |> Enum.join(" ")
  end

  defp row?(view, security),
    do: has_element?(view, ~s(#securities-table tr[phx-value-id="#{security.id}"]))

  # User story (#920; pick H8.6 = A, board 08-dialogs-copy):
  # As the operator acting on a row whose security another writer merged
  # away or deleted since the list loaded,
  # I want the list reloaded with one note saying why the row went,
  # so that a click on Edit, Retire or Merge into… does not silently do
  # nothing, and a vanished row does not read as a lost click.
  #
  # Acceptance criteria:
  # - Edit on a merged-away row reloads the list without the row and shows
  #   a note: "“Meridian Global Equity ETF · XS0000000025” was merged into
  #   Meridian Global Equity ETF · XS0000000017 meanwhile; the list is
  #   reloaded." — the names as the stale list told the twins apart, the
  #   survivor a link to its detail, each name in <bdi>.
  # - Retire on a deleted row reloads the list without it: "“Helios Solar
  #   Systems SE” was deleted meanwhile; the list is reloaded."
  # - No dialog opens for the vanished security.
  test "a row action on a vanished security reloads the list and says why", %{conn: conn} do
    target = security!("Meridian Global Equity ETF", "XS0000000017")
    source = security!("Meridian Global Equity ETF", "XS0000000025")
    helios = security!("Helios Solar Systems SE", nil)

    {:ok, view, _html} = live(conn, "/securities")

    open_menu(view, source)
    merge!(source, target)
    click(view, source, "edit")

    refute row?(view, source)
    assert row?(view, target)
    refute has_element?(view, "#security-form-dialog")

    assert note_text(view) =~
             "“Meridian Global Equity ETF · XS0000000025” was merged into Meridian Global Equity ETF · XS0000000017 meanwhile; the list is reloaded."

    assert has_element?(
             view,
             ~s(#securities-action-result a[href^="/securities/#{target.id}"] bdi),
             "Meridian Global Equity ETF · XS0000000017"
           )

    open_menu(view, helios)
    {:ok, _} = Catalog.delete_security(agent(), helios)
    click(view, helios, "retire")

    refute row?(view, helios)

    assert note_text(view) =~
             "“Helios Solar Systems SE” was deleted meanwhile; the list is reloaded."
  end

  # Acceptance criteria:
  # - A detail pane open on the security that vanished closes with the
  #   reload (the URL drops its id) and the note stays.
  # - The delete's own "not found" branch says the same.
  # - The note reads in German.
  test "the detail pane on the vanished security closes, and the note reads in German",
       %{conn: conn} do
    helios = security!("Helios Solar Systems SE", nil)
    other = security!("Nordic Timber Holdings AB", nil)

    {:ok, view, _html} = live(german(conn), "/securities/#{helios.id}")
    assert has_element?(view, "[data-role='overview-basis']")

    open_menu(view, helios)
    {:ok, _} = Catalog.delete_security(agent(), helios)
    click(view, helios, "delete")

    assert_patch(view, "/securities")
    refute has_element?(view, "[data-role='overview-basis']")

    assert note_text(view) =~
             "„Helios Solar Systems SE“ wurde inzwischen gelöscht; die Liste ist neu geladen."

    assert row?(view, other)
  end

  # User story (#920; pick H8.6 = A, with #918's "Cannot delete"):
  # As the operator taking "Cannot delete"'s way out on a security another
  # writer merged away while the dialog stood open,
  # I want the dialog to close and the note to say where the security went,
  # so that "Merge into…" does not open a merge for a row that is gone.
  #
  # Acceptance criteria:
  # - "Merge into…" in "Cannot delete" on a security merged away meanwhile
  #   closes the dialog, opens no merge dialog, drops the row, and the note
  #   names the survivor and links it.
  test "Cannot delete's way out on a security merged away meanwhile closes and says why",
       %{conn: conn} do
    target = security!("Meridian Global Equity ETF", "XS0000000017")
    source = security!("Meridian Global Equity ETF", "XS0000000025")
    put_quotes!(source, [{~D[2026-01-05], "100"}, {~D[2026-01-06], "101"}])

    {:ok, view, _html} = live(conn, "/securities")

    open_menu(view, source)
    click(view, source, "delete")
    assert has_element?(view, "#delete-blocked-dialog [data-role='delete-blocked-merge']")

    merge!(source, target)

    view
    |> element("#delete-blocked-dialog [data-role='delete-blocked-merge']")
    |> render_click()

    refute has_element?(view, "#delete-blocked-dialog")
    refute has_element?(view, "#security-merge-dialog")
    refute row?(view, source)

    assert note_text(view) =~
             "“Meridian Global Equity ETF · XS0000000025” was merged into Meridian Global Equity ETF · XS0000000017 meanwhile; the list is reloaded."

    assert has_element?(view, ~s(#securities-action-result a[href^="/securities/#{target.id}"]))
  end

  # User story (#920; pick H8.6 = A):
  # As the operator acting on a row that was merged into a security created
  # after the list loaded,
  # I want the note to name that survivor all the same,
  # so that the link leads somewhere I can recognise.
  #
  # Acceptance criteria:
  # - The survivor, absent from the list the page showed, is named by its
  #   stored name and linked to its detail.
  test "a survivor the list did not show yet is named from the catalog", %{conn: conn} do
    source = security!("Halvorsen Shipping Bond 2031", "XS0000000025")

    {:ok, view, _html} = live(conn, "/securities")

    survivor = security!("Halvorsen Shipping Bond 2031 (EUR)", "XS0000000017")
    open_menu(view, source)
    merge!(source, survivor)
    click(view, source, "edit")

    refute row?(view, source)
    assert row?(view, survivor)

    assert note_text(view) =~
             "“Halvorsen Shipping Bond 2031” was merged into Halvorsen Shipping Bond 2031 (EUR) meanwhile; the list is reloaded."

    assert has_element?(
             view,
             ~s(#securities-action-result a[href^="/securities/#{survivor.id}"] bdi),
             "Halvorsen Shipping Bond 2031 (EUR)"
           )
  end
end
