defmodule Portfolixir.Knowledge.HalvingEventsTest do
  # ADR-0048's amendment of 2026-11-12 and ADR-0059 §4, §5 (Sprint 29 H1,
  # FR-58): the event kind `halving`, its chain height checked against the
  # registry, its one writer on a chain with a source, its place in the
  # staleness read, and the binding change that deletes it. Every name,
  # date and height is synthetic, the heights k × the registered interval.
  use Portfolixir.DataCase, async: true

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Journal.Entry, as: JournalEntry
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Knowledge.SecurityEvent

  @today ~D[2026-11-12]

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  # The chain reader's actor (ADR-0059 §10), which H3's run builds and
  # registers; the context function takes the actor its caller passes.
  defp reader, do: Actor.system_job("chain_read")

  defp security!(chain) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Coin #{System.unique_integer([:positive])}",
        currency_code: "EUR",
        asset_class: "crypto"
      })

    if chain do
      {:ok, bound} = Catalog.update_security(agent(), security, %{halving_chain: chain})
      bound
    else
      security
    end
  end

  defp halving(security, height, attrs \\ %{}) do
    Map.merge(
      %{
        "security_id" => security.id,
        "kind" => "halving",
        "chain_height" => height,
        "date" => "2027-01-10",
        "timing" => "estimated",
        "source_quality" => "unverified"
      },
      attrs
    )
  end

  defp entries_since(mark),
    do: Repo.all(from(e in JournalEntry, where: e.id > ^mark, order_by: e.id))

  defp journal_mark, do: Repo.one(from(e in JournalEntry, select: max(e.id))) || 0

  # User story (ADR-0048's amendment, items 1 to 3):
  # As the operator or agent recording a Litecoin halving by hand,
  # I want the halving kind to need a bound security and a height that is a
  # halving of its chain,
  # so that even a typed halving is checked against the protocol constant.
  #
  # Acceptance criteria:
  # - On an unbound security a halving answers {:error, :no_halving_chain}.
  # - On a security bound to litecoin, chain_height 840,000 is stored;
  #   420,000 is a field error naming litecoin's interval; a missing height
  #   is a field error; a second row at the same height is refused.
  # - chain_height on any other kind is a field error.
  test "a halving needs a bound security and a halving height of its chain" do
    unbound = security!(nil)

    assert {:error, :no_halving_chain} =
             Events.create_event(agent(), halving(unbound, 840_000))

    litecoin = security!(:litecoin)

    assert {:ok, event} = Events.create_event(agent(), halving(litecoin, 840_000))
    assert event.kind == :halving
    assert event.chain_height == 840_000

    assert {:error, changeset} = Events.create_event(agent(), halving(litecoin, 420_000))

    assert %{chain_height: ["is not a halving of litecoin (a multiple of 840000 blocks)"]} =
             errors_on(changeset)

    assert {:error, changeset} =
             Events.create_event(agent(), Map.delete(halving(litecoin, nil), "chain_height"))

    assert %{chain_height: ["is required for a halving event"]} = errors_on(changeset)

    assert {:error, changeset} = Events.create_event(agent(), halving(litecoin, 840_000))
    assert %{chain_height: ["has already been taken"]} = errors_on(changeset)

    assert {:error, changeset} =
             Events.create_event(
               agent(),
               halving(litecoin, 1_680_000, %{"kind" => "earnings"})
             )

    assert %{chain_height: ["is only recorded on a halving event"]} = errors_on(changeset)
  end

  # User story (ADR-0048's amendment, item 4; ADR-0059 §3):
  # As the operator whose Bitcoin halvings come from the chain,
  # I want no hand and no token to create, change or delete a halving on a
  # security bound to Bitcoin, while the chain reader upserts it by height,
  # so that the chain stays the one source and a run repeated writes nothing
  # twice.
  #
  # Acceptance criteria:
  # - create, update and delete of a halving on a bitcoin-bound security
  #   answer {:error, {:halving_from_chain, :bitcoin}} and write nothing;
  #   an earnings event on it is written as before.
  # - put_chain_halving/5 inserts the halving at its height, journaled; the
  #   same call again writes no row and no journal entry; a changed date
  #   updates the one row, one journal update.
  # - It refuses a height that is no halving of the chain, and a chain that
  #   is no longer the security's binding ({:error, :binding_changed}).
  test "on a chain with a source only the chain reader writes, idempotent by height" do
    bitcoin = security!(:bitcoin)

    assert {:error, {:halving_from_chain, :bitcoin}} =
             Events.create_event(agent(), halving(bitcoin, 1_050_000))

    attrs = %{
      date: ~D[2028-03-30],
      date_end: ~D[2028-04-17],
      timing: :window,
      confirmed: false,
      source_quality: :unverified,
      checked_at: @today,
      note: "Synthetic window."
    }

    mark = journal_mark()

    assert {:ok, event} =
             Events.put_chain_halving(reader(), bitcoin.id, :bitcoin, 1_050_000, attrs,
               today: @today
             )

    assert [%{operation: :create, resource_type: "security_event"}] = entries_since(mark)
    assert event.chain_height == 1_050_000 and event.timing == :window

    mark = journal_mark()

    assert {:ok, again} =
             Events.put_chain_halving(reader(), bitcoin.id, :bitcoin, 1_050_000, attrs,
               today: @today
             )

    assert again.id == event.id
    assert entries_since(mark) == []

    moved = %{attrs | date: ~D[2028-03-29]}

    assert {:ok, updated} =
             Events.put_chain_halving(reader(), bitcoin.id, :bitcoin, 1_050_000, moved,
               today: @today
             )

    assert updated.id == event.id and updated.date == ~D[2028-03-29]
    assert [%{operation: :update}] = entries_since(mark)
    assert Repo.aggregate(SecurityEvent, :count, :id) == 1

    mark = journal_mark()

    assert {:error, {:halving_from_chain, :bitcoin}} =
             Events.update_event(agent(), updated, %{"note" => "by hand"})

    assert {:error, {:halving_from_chain, :bitcoin}} = Events.delete_event(agent(), updated)
    assert entries_since(mark) == []

    assert {:ok, _earnings} =
             Events.create_event(agent(), %{
               "security_id" => bitcoin.id,
               "kind" => "earnings",
               "date" => "2027-01-10",
               "timing" => "exact",
               "source_quality" => "primary"
             })

    assert {:error, %Ecto.Changeset{} = changeset} =
             Events.put_chain_halving(reader(), bitcoin.id, :bitcoin, 1_000_000, attrs,
               today: @today
             )

    assert %{chain_height: [_]} = errors_on(changeset)

    assert {:error, :binding_changed} =
             Events.put_chain_halving(reader(), bitcoin.id, :litecoin, 840_000, attrs,
               today: @today
             )
  end

  # User story (ADR-0048's amendment, item 6):
  # As the operator reading the stale calendar,
  # I want a confirmed halving left out of it and the unconfirmed next one
  # kept in it,
  # so that a 2012 fact is never stale and a dead chain source shows.
  #
  # Acceptance criteria:
  # - With checked_at a year ago: a confirmed halving is not listed, an
  #   unconfirmed halving and a confirmed earnings event are.
  test "the staleness read leaves out confirmed halvings only" do
    litecoin = security!(:litecoin)
    old = Date.add(@today, -365)

    {:ok, confirmed} =
      Events.create_event(
        agent(),
        halving(litecoin, 840_000, %{
          "confirmed" => true,
          "timing" => "exact",
          "date" => "2019-08-05",
          "source_quality" => "primary",
          "checked_at" => Date.to_iso8601(old)
        })
      )

    {:ok, next} =
      Events.create_event(
        agent(),
        halving(litecoin, 1_680_000, %{"checked_at" => Date.to_iso8601(old)})
      )

    {:ok, earnings} =
      Events.create_event(agent(), %{
        "security_id" => litecoin.id,
        "kind" => "earnings",
        "date" => "2026-01-10",
        "timing" => "exact",
        "confirmed" => true,
        "source_quality" => "primary",
        "checked_at" => Date.to_iso8601(old)
      })

    stale_ids = [today: @today] |> Events.stale() |> Enum.map(& &1.id)

    refute confirmed.id in stale_ids
    assert next.id in stale_ids
    assert earnings.id in stale_ids
  end

  # User story (ADR-0059 §4; ADR-0048's amendment, item 7):
  # As the operator who bound a coin to the wrong chain,
  # I want rebinding or unbinding it to delete its halving events in the
  # same write, journaled and counted,
  # so that no halving of the wrong chain stays on the security.
  #
  # Acceptance criteria:
  # - A litecoin-bound security with two halvings and an earnings event,
  #   rebound to bitcoin_cash: both halvings are gone, each with a journaled
  #   delete, the earnings event stays, and the report counts 2.
  # - Resending the same chain deletes nothing and counts 0; count_halvings/1
  #   counts what a rebinding would delete.
  # - Unbinding deletes the halvings of the new binding the same way.
  test "unbinding or rebinding deletes the security's halving events, journaled" do
    security = security!(:litecoin)
    {:ok, h1} = Events.create_event(agent(), halving(security, 840_000))
    {:ok, h2} = Events.create_event(agent(), halving(security, 1_680_000))

    {:ok, earnings} =
      Events.create_event(agent(), %{
        "security_id" => security.id,
        "kind" => "earnings",
        "date" => "2027-01-10",
        "timing" => "exact",
        "source_quality" => "primary"
      })

    assert Events.count_halvings(security.id) == 2

    assert {:ok, same, %{halving_events_deleted: 0}} =
             Catalog.update_security(agent(), security, %{"halving_chain" => "litecoin"},
               report: true
             )

    assert Events.count_halvings(security.id) == 2

    mark = journal_mark()

    assert {:ok, rebound, %{halving_events_deleted: 2}} =
             Catalog.update_security(agent(), same, %{"halving_chain" => "bitcoin_cash"},
               report: true
             )

    assert rebound.halving_chain == :bitcoin_cash
    assert Enum.map(Events.list_for_security(security.id), & &1.id) == [earnings.id]

    deletes =
      for %{resource_type: "security_event", operation: :delete, resource_id: id} <-
            entries_since(mark),
          do: id

    assert Enum.sort(deletes) == Enum.sort([to_string(h1.id), to_string(h2.id)])

    {:ok, _h3} = Events.create_event(agent(), halving(rebound, 210_000))

    assert {:ok, unbound} = Catalog.update_security(agent(), rebound, %{"halving_chain" => nil})
    assert unbound.halving_chain == nil
    assert Events.count_halvings(security.id) == 0
  end
end
