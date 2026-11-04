defmodule PortfolixirWeb.ApiV1JournalSinceTest do
  # Sprint 24 J2 (I16, decision D-4): GET /api/v1/journal takes since= as the
  # family's paged delta (K17). Every entry is synthetic and backdated: rows
  # stamped "now" lie past the read's in-flight bound, which a full page
  # never steps over (Portfolixir.DeltaCursor).
  use PortfolixirWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Portfolixir.Journal.Entry
  alias Portfolixir.Repo

  @max_polls 200

  defp api_conn do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp read(params) do
    conn = get(api_conn(), "/api/v1/journal?" <> URI.encode_query(params))
    {conn.status, Jason.decode!(conn.resp_body)}
  end

  # Ten minutes ago at a fixed fraction of its second: the journal stamps
  # to the microsecond, so a cursor must carry the fraction too.
  defp at(seconds_ago, microsecond) do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.add(-seconds_ago, :second)
    |> Map.put(:microsecond, {microsecond, 6})
  end

  defp entry!(inserted_at, attrs \\ []) do
    row =
      Map.merge(
        %{
          actor_type: :owner_ui,
          actor_label: nil,
          operation: :update,
          resource_type: "security",
          resource_id: "1",
          before: %{"name" => "Synthetic A"},
          after: %{"name" => "Synthetic B"},
          scenario_id: nil,
          inserted_at: inserted_at
        },
        Map.new(attrs)
      )

    {1, [%{id: id}]} = Repo.insert_all(Entry, [row], returning: [:id])
    id
  end

  # Thirteen entries: five share one stamp, three share another a fraction
  # of a second later in the same second, so page boundaries of two fall
  # inside both groups, and one entry is a what-if scenario's.
  defp fixture! do
    early = for _ <- 1..2, do: entry!(at(900, 0))
    shared = for n <- 1..5, do: entry!(at(600, 250_000), resource_id: "#{n}")
    same_second = for _ <- 1..3, do: entry!(at(600, 750_000), operation: :delete, after: nil)
    late = for _ <- 1..2, do: entry!(at(300, 999_999), actor_type: :api_token_rw)
    scenario = entry!(at(300, 999_999), scenario_id: 7)

    %{ids: early ++ shared ++ same_second ++ late, scenario: scenario}
  end

  # Follows the answered `as_of` literally as the next `since` until a page
  # says no more rows wait (D-9 rule 4), bounded.
  defp walk(params) do
    Enum.reduce_while(1..@max_polls, {params["since"], []}, fn _poll, {since, pages} ->
      assert {200, body} = read(Map.put(params, "since", since))
      pages = pages ++ [body]

      if body["has_more"],
        do: {:cont, {body["as_of"], pages}},
        else: {:halt, pages}
    end)
  end

  defp walked_ids(pages),
    do: Enum.flat_map(pages, fn page -> Enum.map(page["data"], & &1["id"]) end)

  defp real_entry_ids,
    do: Repo.all(from(e in Entry, where: is_nil(e.scenario_id), select: e.id))

  # User story (Sprint 24 J2, I16; decision D-4, D-1 criterion 2):
  # As the agent reading the audit journal,
  # I want `since=` on the journal read to answer the entries after the cut,
  # oldest first, as a page whose `as_of` continues where it ended,
  # so that a walk from any date reaches every entry exactly once, including
  # the entries past the newest 1000 that no plain read can reach.
  #
  # Acceptance criteria:
  # - A walk from since=1970-01-01, feeding each answered `as_of` back as
  #   the next `since` literally, returns every real entry exactly once, on
  #   a fixture of more than one page, also where entries share a stamp
  #   across a page boundary.
  # - Each page is oldest first; a full page carries has_more true, the
  #   applied limit, truncated true and a cursor `<instant>~<id>`; the last
  #   page carries has_more false.
  test "a cursor walk from 1970-01-01 returns every entry exactly once" do
    %{ids: ids, scenario: scenario} = fixture!()

    pages = walk(%{"since" => "1970-01-01", "limit" => "2"})
    walked = walked_ids(pages)

    assert length(pages) > 1
    assert length(walked) == length(Enum.uniq(walked)), "an entry was delivered twice"
    assert MapSet.new(walked) == MapSet.new(real_entry_ids())
    assert MapSet.subset?(MapSet.new(ids), MapSet.new(walked))
    refute scenario in walked

    [first | _] = pages
    assert first["has_more"] == true
    assert first["truncated"] == true
    assert first["limit"] == 2
    assert first["since"] == "1970-01-01"
    assert first["as_of"] =~ ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z~\d+$/
    assert first["meta"]["order"] == "inserted_at:asc,id:asc"
    assert first["meta"]["filters"]["since"] == "1970-01-01"
    assert first["delta_note"] =~ "oldest first"
    assert first["delta_note"] =~ "A cursor belongs to the read that answered it"

    assert List.last(pages)["has_more"] == false

    # Oldest first, by the stamp and then the id, across the whole walk.
    stamps =
      pages
      |> Enum.flat_map(& &1["data"])
      |> Enum.map(fn entry ->
        {:ok, at, 0} = DateTime.from_iso8601(entry["inserted_at"])
        {DateTime.to_unix(at, :microsecond), entry["id"]}
      end)

    assert stamps == Enum.sort(stamps)
  end

  # User story (Sprint 24 J2, I16; decision D-4):
  # As the agent narrowing the journal,
  # I want `since` to combine with the five existing filters and to be
  # echoed with them,
  # so that "what did the agent delete since Monday" is one walk.
  #
  # Acceptance criteria:
  # - since with actor_type, operation, resource_type and resource_id
  #   answers only the entries after the cut that match all of them.
  # - include_scenarios=true adds the scenario's entry after the cut.
  # - meta.filters echoes since beside the other filters.
  test "since combines with the five filters and is echoed in meta.filters" do
    %{scenario: scenario} = fixture!()
    cut = at(600, 500_000) |> DateTime.to_iso8601()

    assert {200, deletes} = read(%{"since" => cut, "operation" => "delete"})
    assert length(deletes["data"]) == 3
    assert Enum.all?(deletes["data"], &(&1["operation"] == "delete"))
    assert deletes["has_more"] == false
    assert deletes["meta"]["filters"]["since"] == cut
    assert deletes["meta"]["filters"]["operation"] == "delete"

    assert {200, agent} = read(%{"since" => cut, "actor_type" => "api_token_rw"})
    assert length(agent["data"]) == 2

    assert {200, one} =
             read(%{"since" => "1970-01-01", "resource_type" => "security", "resource_id" => "3"})

    assert [%{"resource_id" => "3"}] = one["data"]

    assert {200, with_scenarios} =
             read(%{"since" => cut, "resource_type" => "security", "include_scenarios" => "true"})

    assert scenario in Enum.map(with_scenarios["data"], & &1["id"])
    assert length(with_scenarios["data"]) == 6
  end

  # User story (Sprint 24 J2, I16; decision D-4):
  # As an existing client of the journal read,
  # I want the read without `since` to answer as it did,
  # so that nothing I already call changes under me.
  #
  # Acceptance criteria:
  # - Without since: newest first, no has_more, no delta envelope, and
  #   meta.filters.since null.
  # - An unreadable since, or a malformed cursor, is a 422 naming since.
  test "without since the read is unchanged, and an unreadable since is a 422" do
    fixture!()

    assert {200, plain} = read(%{})
    refute Map.has_key?(plain, "has_more")
    refute Map.has_key?(plain, "delta_note")
    assert plain["meta"]["order"] == "inserted_at:desc,id:desc"
    assert plain["meta"]["filters"]["since"] == nil

    newest_first =
      Repo.all(
        from(e in Entry,
          where: is_nil(e.scenario_id),
          order_by: [desc: e.inserted_at, desc: e.id],
          select: e.id
        )
      )

    assert Enum.map(plain["data"], & &1["id"]) == newest_first

    for since <- ["soon", "2026-13-01", "~5", "2026-01-01T00:00:00Z~0", "a~b~c"] do
      assert {422, %{"errors" => %{"since" => _}}} = read(%{"since" => since}), since
    end
  end
end
