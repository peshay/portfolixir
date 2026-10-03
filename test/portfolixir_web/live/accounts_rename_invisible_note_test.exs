defmodule PortfolixirWeb.AccountsRenameInvisibleNoteTest do
  # Sprint 18 pick H8.5 = A (#966; board ux-design-2026-10-02/08-dialogs-copy;
  # DESIGN.md G12.2-B, "Where it stands"): the rename dialog on Accounts &
  # depots carries the G20 attention note for a name stored before every
  # writer refused invisible characters — under the field, following what is
  # typed — and a second one inside "Former names" when a former name
  # carries such characters, since retyping the name leaves the old spelling
  # there and an import that writes it exactly so still finds the account.
  use PortfolixirWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures, only: [base_world: 1]

  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Repo

  defp zwsp, do: <<0x200B::utf8>>
  defp german(conn), do: Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")

  # A write as the tables held it before the refusal: straight to the
  # table, with the journal's actor set so its guard lets it through.
  defp legacy!(schema, id, fields) do
    {:ok, _} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'system_job', true)")
        Repo.update_all(from(r in schema, where: r.id == ^id), set: fields)
      end)

    :ok
  end

  defp words(html) do
    html |> Floki.parse_fragment!() |> Floki.text() |> String.split() |> Enum.join(" ")
  end

  defp open_rename(view, "depot", id) do
    view |> element("#account-kebab-#{id}") |> render_click()
    view |> element("#account-row-menu-#{id} [data-role='menu-rename']") |> render_click()
  end

  defp open_rename(view, "cash", id) do
    view |> element("#cash-kebab-#{id}") |> render_click()
    view |> element("#cash-row-menu-#{id} [data-role='menu-rename']") |> render_click()
  end

  defp current_note(_view),
    do: "#rename-dialog #rename-name-note[data-role='invisible-text-note']"

  defp former_note(view) do
    view
    |> element("#rename-dialog details > #rename-former-names-note")
    |> render()
    |> words()
  end

  # User story (#966; pick H8.5 = A, board 08-dialogs-copy):
  # As the operator renaming a depot whose name was stored with a character
  # I cannot see,
  # I want the rename dialog to say so under the field, and to mark a former
  # name that still carries such a character,
  # so that I can retype the name and decide, seeing it, whether an import
  # may keep finding the depot under the old spelling.
  #
  # Acceptance criteria:
  # - With the stored name in the field, one attention note follows the form:
  #   "The name contains 1 invisible character. Typed in anew, it is clean.",
  #   its disclosure spelling "Depot[U+200B] Nord"; typed in anew, the note
  #   goes.
  # - A former name carrying such characters adds a note inside the open
  #   "Former names", above the list: "A former name contains 1 invisible
  #   character. An import that writes it exactly so keeps booking to this
  #   depot.", its disclosure "Names with the characters made visible"
  #   spelling it; the list row itself carries no mark.
  # - Clean names carry neither note.
  # - In German the notes read "Der Name enthält 1 unsichtbares Zeichen. Neu
  #   eingegeben ist er sauber." and "Ein früherer Name enthält 1
  #   unsichtbares Zeichen. Ein Import, der ihn genau so schreibt, bucht
  #   weiter auf dieses Depot."
  test "the rename dialog marks a stored name and a former name with invisible characters",
       %{conn: conn} do
    world = base_world(name: "Unsichtbar", depot_name: "Depot Nord", cash_name: "Giro")
    stored = "Depot" <> zwsp() <> " Nord"

    legacy!(SecuritiesAccount, world.depot.id,
      name: stored,
      former_names: ["Depot 2", "Depot" <> zwsp() <> " Alt"]
    )

    {:ok, view, _html} = live(conn, "/portfolios")
    open_rename(view, "depot", world.depot.id)

    note = view |> element(current_note(view)) |> render()
    assert note =~ "data-note--attention"

    assert words(note) =~
             "The name contains 1 invisible character. Typed in anew, it is clean."

    assert note =~ "Depot[U+200B] Nord"

    assert former_note(view) =~
             "A former name contains 1 invisible character. An import that writes it exactly so keeps booking to this depot."

    assert former_note(view) =~ "Names with the characters made visible"
    assert former_note(view) =~ "Depot[U+200B] Alt"

    refute view
           |> element("#rename-dialog [data-role='former-names']")
           |> render() =~ "invisible-text-note"

    view |> form("#rename-form", rename: %{name: "Depot Nord"}) |> render_change()
    refute has_element?(view, current_note(view))

    {:ok, view, _html} = live(german(conn), "/portfolios")
    open_rename(view, "depot", world.depot.id)

    assert view |> element(current_note(view)) |> render() |> words() =~
             "Der Name enthält 1 unsichtbares Zeichen. Neu eingegeben ist er sauber."

    assert former_note(view) =~
             "Ein früherer Name enthält 1 unsichtbares Zeichen. Ein Import, der ihn genau so schreibt, bucht weiter auf dieses Depot."

    assert former_note(view) =~ "Namen mit sichtbar gemachten Zeichen"
  end

  test "a clean cash account carries no note; a former name says account", %{conn: conn} do
    world = base_world(name: "Sauber", depot_name: "Depot 1", cash_name: "Giro")

    {:ok, view, _html} = live(conn, "/portfolios")
    open_rename(view, "cash", world.cash.id)
    refute has_element?(view, "#rename-dialog [data-role='invisible-text-note']")

    legacy!(CashAccount, world.cash.id,
      former_names: ["Giro" <> zwsp(), "Tages" <> zwsp() <> "geld"]
    )

    {:ok, view, _html} = live(conn, "/portfolios")
    open_rename(view, "cash", world.cash.id)
    refute has_element?(view, current_note(view))

    assert former_note(view) =~
             "Former names contain 2 invisible characters. An import that writes one of them exactly so keeps booking to this account."
  end
end
