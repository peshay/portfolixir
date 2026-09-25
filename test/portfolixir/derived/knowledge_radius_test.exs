defmodule Portfolixir.Derived.KnowledgeRadiusTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Derived.BlastRadius
  alias Portfolixir.Derived.DataVersion
  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Knowledge.SecurityEvent
  alias Portfolixir.Knowledge.SecurityNote
  alias Portfolixir.Portfolios

  # User story (E25 S6, F53):
  # As the operator whose pages are served from derived values,
  # I want a research entry or a security event — a write that moves no
  # figure — to leave every portfolio's derived values current,
  # so that a stream of notes does not keep the refresher recomputing every
  # portfolio's walk.
  #
  # Acceptance criteria:
  # - A note append and an event create, update and delete leave every
  #   portfolio's basis version unchanged.
  # - The answer is resolved per struct: the same resource type with a record
  #   of another shape still widens to every portfolio.
  test "note and event writes leave other portfolios' basis versions unchanged" do
    actor = Actor.owner_ui()

    {:ok, portfolio} =
      Portfolios.create_portfolio(actor, %{name: "Radius Folio", base_currency_code: "EUR"})

    {:ok, security} = Catalog.create_security(actor, %{name: "Radius AG", currency_code: "EUR"})
    basis = DataVersion.portfolio_basis(portfolio.id)
    before = DataVersion.current(basis)

    {:ok, _note} =
      Knowledge.append_note(
        actor,
        %{
          security_id: security.id,
          author: "operator",
          kind: "evidence",
          body: "A synthetic observation.",
          source_quality: "unverified",
          as_of: ~D[2026-01-15]
        },
        today: ~D[2026-01-15]
      )

    {:ok, event} =
      Events.create_event(actor, %{
        security_id: security.id,
        kind: "earnings",
        date: ~D[2026-10-15],
        timing: "exact",
        source_quality: "unverified"
      })

    {:ok, event} = Events.update_event(actor, event, %{note: "Moved to the afternoon."})
    {:ok, _event} = Events.delete_event(actor, event)

    assert DataVersion.current(basis) == before
  end

  test "a note or event resolves to no portfolio per struct, and widens otherwise" do
    assert BlastRadius.for_write("security_note", %SecurityNote{security_id: 1}) == []
    assert BlastRadius.for_write("security_event", %SecurityEvent{security_id: 1}) == []

    assert BlastRadius.for_write("security_note", %{security_id: 1}) == :all
    assert BlastRadius.for_write("security_event", %{security_id: 1}) == :all
  end
end
