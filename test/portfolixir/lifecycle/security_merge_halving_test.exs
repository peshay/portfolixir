defmodule Portfolixir.Lifecycle.SecurityMergeHalvingTest do
  # ADR-0048's amendment of 2026-11-12, item 8, and ADR-0059 §13 item 7
  # (Sprint 29 H1, FR-58): a security merge never duplicates a halving.
  # ADR-0050 §9 moves every event of the source; a source's halving moves
  # only when the target is bound to the same chain and holds no event at
  # that height, and is otherwise dropped, journaled and listed in the
  # preview. Every name and height is synthetic.
  use Portfolixir.DataCase, async: true

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Lifecycle

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  defp pair!(source_chain, target_chain) do
    name = "Coin Twin #{System.unique_integer([:positive])}"
    {bound(name, target_chain), bound(name, source_chain)}
  end

  defp bound(name, chain) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        currency_code: "EUR",
        asset_class: "crypto"
      })

    {:ok, security} = Catalog.update_security(agent(), security, %{halving_chain: chain})
    security
  end

  defp halving!(security, height) do
    {:ok, event} =
      Events.create_event(agent(), %{
        security_id: security.id,
        kind: "halving",
        chain_height: height,
        date: ~D[2019-08-05],
        timing: "exact",
        confirmed: true,
        source_quality: "primary"
      })

    event
  end

  defp journal_mark, do: Repo.one(from(e in Journal.Entry, select: max(e.id))) || 0

  defp entries_since(mark),
    do: Repo.all(from(e in Journal.Entry, where: e.id > ^mark, order_by: e.id))

  defp merge!(source, target) do
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    {:ok, record, :applied} =
      Lifecycle.merge_security(agent(), source.id, target.id, %{plan_digest: preview.plan_digest})

    {preview, record}
  end

  defp event_entries(mark) do
    for %{resource_type: "security_event"} = entry <- entries_since(mark),
        do: {entry.operation, entry.resource_id}
  end

  # User story (ADR-0048's amendment, item 8):
  # As the operator merging two listings of one coin, both bound to the same
  # chain,
  # I want a halving both carry kept once, the target's, and a halving only
  # the source carries moved,
  # so that the merged security has one row per halving and the unique
  # height never breaks the merge.
  #
  # Acceptance criteria:
  # - Both bound to litecoin, the source with 840,000 and 1,680,000, the
  #   target with 840,000: the preview moves 1,680,000 and drops the source's
  #   840,000 with reason :height_held.
  # - After the merge the target holds its own 840,000 and the moved
  #   1,680,000; the journal has one delete and one update; the merge record
  #   lists the dropped row.
  test "the same chain: a held height is dropped, the rest moves" do
    {target, source} = pair!(:litecoin, :litecoin)
    t_840 = halving!(target, 840_000)
    s_840 = halving!(source, 840_000)
    s_1680 = halving!(source, 1_680_000)

    mark = journal_mark()
    {preview, record} = merge!(source, target)

    assert Enum.map(preview.events.moved, & &1.id) == [s_1680.id]

    assert preview.events.dropped == [
             %{
               id: s_840.id,
               kind: :halving,
               date: ~D[2019-08-05],
               chain_height: 840_000,
               reason: :height_held
             }
           ]

    assert preview.events.possible_duplicates == []

    assert target.id
           |> Events.list_for_security()
           |> Enum.map(&{&1.id, &1.chain_height})
           |> Enum.sort() == Enum.sort([{t_840.id, 840_000}, {s_1680.id, 1_680_000}])

    assert Enum.sort(event_entries(mark)) ==
             Enum.sort([{:delete, to_string(s_840.id)}, {:update, to_string(s_1680.id)}])

    assert [%{"id" => dropped_id, "reason" => "height_held"}] =
             record.manifest["security_events"]["dropped"]

    assert dropped_id == s_840.id
  end

  # User story (ADR-0048's amendment, item 8):
  # As the operator merging a coin onto a security of another chain or of
  # none,
  # I want every halving of the source dropped, journaled,
  # so that no fact about one chain lands on a security of another.
  #
  # Acceptance criteria:
  # - Source bound to litecoin, target bound to bitcoin_cash or unbound:
  #   both source halvings are dropped with reason :chain_differs, nothing
  #   moves, and the target holds no halving afterwards.
  test "another chain or none: every halving of the source is dropped" do
    for target_chain <- [:bitcoin_cash, nil] do
      {target, source} = pair!(:litecoin, target_chain)
      s1 = halving!(source, 840_000)
      s2 = halving!(source, 1_680_000)

      mark = journal_mark()
      {preview, _record} = merge!(source, target)

      assert preview.events.moved == []

      assert preview.events.dropped |> Enum.map(&{&1.id, &1.reason}) |> Enum.sort() ==
               Enum.sort([{s1.id, :chain_differs}, {s2.id, :chain_differs}])

      assert Events.count_halvings(target.id) == 0

      assert Enum.sort(event_entries(mark)) ==
               Enum.sort([{:delete, to_string(s1.id)}, {:delete, to_string(s2.id)}])
    end
  end
end
