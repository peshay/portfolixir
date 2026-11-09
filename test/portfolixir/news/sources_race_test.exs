defmodule Portfolixir.News.SourcesRaceTest do
  # #1424 (ADR-0056 §3, B7): two puts of one new domain on two connections.
  # The SQL sandbox serializes connections, and a second writer inside the
  # call's own transaction is not the race, so both run outside it with
  # real commits, the other writer at the exact point of the call through
  # `Portfolixir.Interleave`, as Sprint 27's ORD tests placed theirs; the
  # rows they commit are removed afterwards. Synthetic domains only.
  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]

  alias Ecto.Adapters.SQL.Sandbox
  alias Portfolixir.Actor
  alias Portfolixir.Interleave
  alias Portfolixir.Journal
  alias Portfolixir.News.Source
  alias Portfolixir.News.Sources
  alias Portfolixir.Repo

  @agent Actor.api_token_rw("synthetic-agent")
  @seeder Actor.system_job("synthetic-seed")

  # On a connection of its own, committing.
  defp elsewhere(fun),
    do: fn -> Sandbox.unboxed_run(Repo, fun) end |> Task.async() |> Task.await()

  defp delete_unguarded(sql, params) do
    {:ok, _} =
      Repo.transaction(fn ->
        Repo.query!("SET LOCAL session_replication_role = replica")
        Repo.query!(sql, params)
      end)
  end

  # User story (#1424; ADR-0056 §3, B7):
  # As the operator whose agent rates a source while a seed rates the same
  # new domain,
  # I want both writes to land, the later on the earlier's row, each
  # journaled with the image before it,
  # so that a concurrent rating never fails with "has already been taken"
  # (the flaky IngestTest of #1424) and the journal chains instead of
  # claiming the domain was new twice.
  #
  # Acceptance criteria:
  # - A put of a new domain whose read found no row, while another
  #   connection inserts and commits that domain before it writes, answers
  #   {:ok, source}: its tier, by hand, on the one row.
  # - The journal holds the other put's insert (before none) and this put's
  #   upsert, whose before-image is the other's row.
  test "a put racing another connection's put of the same new domain lands on its row" do
    domain = "race-#{System.unique_integer([:positive])}.example.com"

    Sandbox.unboxed_run(Repo, fn ->
      try do
        racing_point? = fn %{query: query} ->
          query =~ "news_sources" and query =~ "FOR UPDATE"
        end

        {result, other} =
          Interleave.run(
            racing_point?,
            fn ->
              elsewhere(fn -> Sources.put_source(@seeder, domain, :secondary, set_by: :seed) end)
            end,
            fn -> Sources.put_source(@agent, domain, :primary) end
          )

        assert {:ok, %Source{tier: :secondary, set_by: :seed}} = other
        assert {:ok, %Source{tier: :primary, set_by: :hand, id: id}} = result

        assert %Source{id: ^id, tier: :primary, set_by: :hand} =
                 Repo.get_by!(Source, domain: domain)

        assert [seeded, corrected] =
                 Journal.list_entries(
                   resource_type: "news_source",
                   resource_id: to_string(id),
                   order: :asc
                 )

        assert {seeded.actor_label, seeded.before} == {"synthetic-seed", nil}
        assert corrected.actor_label == "synthetic-agent"
        assert corrected.before["tier"] == "secondary"
        assert corrected.after["tier"] == "primary"
      after
        ids = Repo.all(from(s in Source, where: s.domain == ^domain, select: s.id))

        delete_unguarded(
          "DELETE FROM audit_journal WHERE resource_type = 'news_source' AND resource_id = ANY($1)",
          [Enum.map(ids, &to_string/1)]
        )

        delete_unguarded("DELETE FROM news_sources WHERE domain = $1", [domain])
      end
    end)
  end
end
