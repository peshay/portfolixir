defmodule PortfolixirWeb.JournalRowNamesTest do
  # Sprint 23 V3 (board ux-design-2026-11-02-sprint23/03-journal), the
  # stacked PR's closing act: the journal's „Eintrag“ cell reads the entry
  # as its kind, its id and its stored name, but the name rule read only a
  # `name` field, so a recorded statement, a merge and a research note —
  # whose images hold no `name` — lost theirs. Every name is synthetic.
  use PortfolixirWeb.ConnCase

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Journal.Entry
  alias Portfolixir.Knowledge
  alias Portfolixir.Lifecycle
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo
  alias Portfolixir.Tax

  defp agent, do: Actor.api_token_rw("review seed")

  defp created_entry(type, id) do
    Repo.one!(
      from(e in Entry,
        where:
          e.resource_type == ^type and e.resource_id == ^to_string(id) and
            e.operation == :create
      )
    )
  end

  defp entity(view, entry) do
    view
    |> element("#journal-entry-#{entry.id} a:not([data-phx-link])")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp href(view, entry) do
    view
    |> element("#journal-entry-#{entry.id} a:not([data-phx-link])")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.attribute("href")
  end

  defp cash!(portfolio, name) do
    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: "EUR"
      })

    cash
  end

  # User story (Sprint 23 V3; stacked PR closing act, S3):
  # As the operator reading the audit journal,
  # I want every entry named as the board names it,
  # so that I see which statement, which merge and which security's note
  # the agent wrote without opening each.
  #
  # Acceptance criteria:
  # - A recorded statement reads its institution: „Erfasste Abrechnung 2 ·
  #   Beispiel Direktbank“.
  # - A merge reads what it merged: „Zusammenführung 5 · Verrechnungskonten“
  #   (Depots, Wertpapiere for the other two kinds).
  # - A research note reads its security's name, linked to the security.
  test "a statement, a merge and a research note are named", %{conn: conn} do
    {:ok, statement} =
      Tax.create_snapshot(
        agent(),
        %{
          institution: "Beispiel Direktbank",
          holder: "Owner",
          tax_year: 2025,
          as_of: ~D[2025-12-31]
        },
        today: ~D[2026-01-15]
      )

    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Main", base_currency_code: "EUR"})

    source = cash!(portfolio, "Festgeld")
    target = cash!(portfolio, "Festgeld Plus")
    {:ok, preview} = Lifecycle.preview_cash_merge(source.id, target.id)

    {:ok, merge, :applied} =
      Lifecycle.merge_cash_account(agent(), source.id, target.id, %{
        plan_digest: preview.plan_digest,
        collapse_key_equal: false
      })

    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Alder Creek Fund",
        currency_code: "EUR"
      })

    {:ok, note} =
      Knowledge.append_note(agent(), %{
        security_id: security.id,
        author: "agent",
        kind: "evidence",
        body: "A synthetic finding.",
        source_quality: "primary",
        as_of: ~D[2026-08-01]
      })

    statement_entry = created_entry("tax_statement_snapshot", statement.id)
    merge_entry = created_entry("merge_record", merge.id)
    note_entry = created_entry("security_note", note.id)

    {:ok, view, _html} = live(conn, "/journal?locale=de")

    assert entity(view, statement_entry) ==
             "Erfasste Abrechnung #{statement.id} · Beispiel Direktbank"

    assert entity(view, merge_entry) == "Zusammenführung #{merge.id} · Verrechnungskonten"
    assert entity(view, note_entry) == "Research-Notiz #{note.id} · Alder Creek Fund"
    assert href(view, note_entry) == ["/securities/#{security.id}"]

    {:ok, view, _html} = live(conn, "/journal?locale=en")
    assert entity(view, merge_entry) == "Merge #{merge.id} · Cash accounts"
    assert entity(view, note_entry) == "Research note #{note.id} · Alder Creek Fund"
  end
end
