defmodule Portfolixir.Journal.NoOpUpdateTest do
  # E25 S6 (#891), G02: every journaled update — including one that changes
  # nothing — copied the whole row twice into the append-only journal, so a
  # client resending a record could grow the journal without end. A valid
  # update that changes nothing now writes neither the row nor an entry;
  # ADR-0017's full before and after snapshots stay as they are for a real
  # change.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Tax
  alias Portfolixir.WorldFixtures

  defp owner, do: Actor.owner_ui()

  defp updates(type), do: Journal.list_entries(resource_type: type, operation: :update)

  # User story:
  # As the operator reading the audit journal,
  # I want an update that changes nothing to leave no entry,
  # so that the journal records changes, and resending a record cannot grow
  # it.
  #
  # Acceptance criteria:
  # - Resending a portfolio, a cash account, a depot, a security, a booking,
  #   a classification, an event and a tax statement unchanged writes no
  #   update entry for any of them.
  # - A real change still writes one entry with its before and after.
  test "an update that changes nothing writes no journal entry" do
    world = WorldFixtures.base_world(name: "No-op updates")
    security = WorldFixtures.create_security!(name: "Harbour Tug Services", ticker: "HTS")
    tx = WorldFixtures.deposit!(world, "250", ~D[2026-02-02])

    {:ok, classification} =
      Classifications.create_classification(owner(), %{name: "Style", description: "Mine"})

    {:ok, event} =
      Events.create_event(owner(), %{
        security_id: security.id,
        kind: "earnings",
        date: ~D[2026-11-20],
        timing: "estimated",
        source_quality: "awareness",
        note: "Guided for late November."
      })

    {:ok, snapshot} =
      Tax.create_snapshot(
        owner(),
        %{
          institution: "Example Bank",
          holder: "Owner",
          tax_year: 2025,
          as_of: ~D[2025-12-31],
          note: "Year-end statement."
        },
        today: ~D[2026-01-15]
      )

    resend = [
      {"portfolio",
       fn ->
         Portfolios.update_portfolio(owner(), world.portfolio, %{name: world.portfolio.name})
       end},
      {"cash_account",
       fn -> Portfolios.update_cash_account(owner(), world.cash, %{name: world.cash.name}) end},
      {"securities_account",
       fn ->
         Portfolios.update_securities_account(owner(), world.depot, %{name: world.depot.name})
       end},
      {"security", fn -> Catalog.update_security(owner(), security, %{name: security.name}) end},
      {"transaction", fn -> Ledger.update_transaction(owner(), tx, %{gross_amount: "250"}) end},
      {"classification",
       fn ->
         Classifications.update_classification(owner(), classification, %{description: "Mine"})
       end},
      {"security_event",
       fn -> Events.update_event(owner(), event, %{note: "Guided for late November."}) end},
      {"tax_statement_snapshot",
       fn ->
         Tax.update_snapshot(owner(), snapshot, %{note: "Year-end statement."},
           today: ~D[2026-01-15]
         )
       end}
    ]

    for {type, write} <- resend do
      assert {:ok, _unchanged} = write.()
      assert updates(type) == [], "#{type}: an unchanged update was journaled"
    end

    assert {:ok, _} = Events.update_event(owner(), event, %{note: "Moved to early December."})
    assert [entry] = updates("security_event")
    assert entry.before["note"] == "Guided for late November."
    assert entry.after["note"] == "Moved to early December."
  end
end
