defmodule PortfolixirWeb.StoredNamesIsolatedTest do
  # Sprint 18 pick H8.8 (#968; board ux-design-2026-10-02/08-dialogs-copy,
  # before/after; DESIGN.md G12.2-B, the `<bdi>` bullet): a stored name set
  # into an action result or a heading is isolated in `<bdi>`, so a direction
  # control a name stored before the refusal still carries — or a
  # right-to-left name — reorders at most the name, never the app's words
  # after it. An ordinary name reads exactly as before.
  use PortfolixirWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Repo
  alias PortfolixirWeb.StoredText

  defp rlo, do: <<0x202E::utf8>>
  defp german(conn), do: Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")

  # A name as the tables held it before the refusal: written straight to the
  # table, with the journal's actor set so its guard lets it through.
  defp legacy_name!(schema, id, name) do
    {:ok, _} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'system_job', true)")
        Repo.update_all(from(r in schema, where: r.id == ^id), set: [name: name])
      end)

    :ok
  end

  defp html(markup), do: Phoenix.HTML.safe_to_string(markup)

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> String.split()
    |> Enum.join(" ")
  end

  describe "StoredText.isolate/2" do
    test "sets each stored value in its own <bdi> and escapes the rest" do
      translated =
        "Merged %{source} into %{target}: <b>2</b> moved."
        |> String.replace("%{source}", StoredText.slot(:source))
        |> String.replace("%{target}", StoredText.slot(:target))

      assert html(StoredText.isolate(translated, source: "Depot <2>", target: "Depot & 1")) ==
               "Merged <bdi>Depot &lt;2&gt;</bdi> into <bdi>Depot &amp; 1</bdi>: &lt;b&gt;2&lt;/b&gt; moved."
    end

    test "takes safe markup as it is, and a link isolates its label" do
      link = StoredText.link("/securities/7?x=1&y=2", "Meridian · XS0000000001")

      assert html(StoredText.isolate("in " <> StoredText.slot(:target), target: link)) ==
               ~s(in <a href="/securities/7?x=1&amp;y=2"><bdi>Meridian · XS0000000001</bdi></a>)

      assert html(StoredText.isolate("no slot", name: "x")) == "no slot"
      assert html(StoredText.bdi("a" <> rlo() <> "b")) == "<bdi>a" <> rlo() <> "b</bdi>"
    end

    # The moduledoc's contract: a slot without a stored value is left out,
    # never printed as its NUL-delimited key and never an empty <bdi>.
    test "leaves out a slot that has no stored value" do
      translated = "Merged " <> StoredText.slot(:source) <> " into " <> StoredText.slot(:target)

      assert html(StoredText.isolate(translated, target: "Depot 1")) ==
               "Merged  into <bdi>Depot 1</bdi>"
    end
  end

  # User story (#968; pick H8.8, board 08-dialogs-copy):
  # As the operator acting on a security whose name was stored before the
  # refusal and carries a right-to-left override,
  # I want the result line to keep the app's words readable,
  # so that "Nordwind tgelegllits GA eirtsudnI" does not happen to the
  # sentence around the name.
  #
  # Acceptance criteria:
  # - "Retired %{name}", "Reactivated %{name}", "Marked %{name} as
  #   benchmark", "%{name} is no longer a benchmark" and "Deleted %{name}"
  #   set the name in `<bdi>`; the German "… stillgelegt" follows it outside.
  # - An ordinary name reads as before in the text.
  test "the securities page's results isolate the name", %{conn: conn} do
    legacy = create_security!(name: "Nordwind Industrie AG", ticker: "NWI")
    stored = "Nordwind " <> rlo() <> "Industrie AG"
    legacy_name!(Security, legacy.id, stored)
    plain = create_security!(name: "Helios Solar Systems SE", ticker: "HSS")

    {:ok, view, _html} = live(german(conn), "/securities")

    row_action(view, legacy, "retire")

    assert view |> element("#securities-action-result") |> render() =~
             "<bdi>" <> stored <> "</bdi> stillgelegt"

    row_action(view, plain, "benchmark")

    assert has_element?(view, "#securities-action-result bdi", "Helios Solar Systems SE")
    assert text(view, "#securities-action-result [role=status]") =~ "Helios Solar Systems SE"

    {:ok, view, _html} = live(conn, "/securities")
    row_action(view, plain, "delete")
    assert has_element?(view, "#securities-action-result bdi", "Helios Solar Systems SE")
    assert text(view, "#securities-action-result") =~ "Deleted Helios Solar Systems SE"
  end

  # User story (#968; pick H8.8):
  # As the operator opening a dialog about a stored account or security,
  # I want its heading to isolate the name,
  # so that "Depot droN zusammenführen" keeps "zusammenführen" readable.
  #
  # Acceptance criteria:
  # - "Rename — %{name}", "Merge %{name}" (accounts and securities), "Set
  #   balance — %{name}", "Buckets for %{name}", "Release manual quotes —
  #   %{name}" set the stored name in `<bdi>` inside the heading.
  test "dialog headings isolate the stored name", %{conn: conn} do
    world = base_world(name: "Kopf", depot_name: "Depot 1", cash_name: "Giro")
    stored = "Depot " <> rlo() <> "Nord"
    legacy_name!(SecuritiesAccount, world.depot.id, stored)

    {:ok, view, _html} = live(german(conn), "/portfolios")

    open_account_item(view, world.depot.id, "rename")
    assert view |> element("#rename-dialog h2") |> render() =~ "<bdi>" <> stored <> "</bdi>"
    view |> element("#rename-dialog .modal-footer button", "Abbrechen") |> render_click()

    open_account_item(view, world.depot.id, "merge")

    assert view |> element("#merge-dialog h2") |> render() =~
             "<bdi>" <> stored <> "</bdi> zusammenführen"

    view |> element("#merge-dialog header button.icon-button") |> render_click()

    view |> element("#set-balance-#{world.cash.id}") |> render_click()
    assert has_element?(view, "#balance-dialog-title bdi", "Giro")

    security = create_security!(name: "Meridian Global Equity ETF", ticker: "MGEQ")
    put_quote!(security, ~D[2026-01-05], "75.90")

    {:ok, view, _html} = live(conn, "/securities")

    view
    |> element(
      ~s(#securities-table button[phx-click="open_row_menu"][phx-value-id="#{security.id}"])
    )
    |> render_click()

    view |> element("#row-menu-#{security.id} [data-role='menu-merge']") |> render_click()
    assert has_element?(view, "#security-merge-dialog h2 bdi", "Meridian Global Equity ETF")

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=quotes")
    view |> element("[data-role='release-manual-quotes']") |> render_click()
    assert has_element?(view, "#quote-release-dialog h2 bdi", "Meridian Global Equity ETF")

    {:ok, bucket_view} = Buckets.create_view(Actor.owner_ui(), %{name: "Ohne Spekulation"})
    {:ok, view, _html} = live(conn, "/buckets")
    render_hook(view, "edit_view_buckets", %{"id" => to_string(bucket_view.id)})
    assert has_element?(view, "#view-bucket-modal h2 bdi", "Ohne Spekulation")

    assert Portfolios.get_securities_account(world.depot.id).name == stored
  end

  defp row_action(view, security, action) do
    view
    |> element(
      ~s(#securities-table button[phx-click="open_row_menu"][phx-value-id="#{security.id}"])
    )
    |> render_click()

    view
    |> element(~s(#row-menu-#{security.id} button[phx-value-action="#{action}"]))
    |> render_click()
  end

  defp open_account_item(view, depot_id, item) do
    view |> element("#account-kebab-#{depot_id}") |> render_click()
    view |> element("#account-row-menu-#{depot_id} [data-role='menu-#{item}']") |> render_click()
  end
end
