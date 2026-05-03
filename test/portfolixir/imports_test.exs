defmodule Portfolixir.ImportsTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Imports

  defp create_import_source(attrs) do
    base_attrs = %{name: "Test broker", type: "local_file"}

    {:ok, source} = Imports.create_import_source(Map.merge(base_attrs, Map.new(attrs)))
    source
  end

  test "source creation succeeds with defaults and required fields" do
    assert {:ok, source} =
             Imports.create_import_source(%{
               name: "PP XML uploader",
               type: "pp_xml",
               config: %{"endpoint" => "file"}
             })

    assert source.name == "PP XML uploader"
    assert source.type == "pp_xml"
    assert source.status == "active"
    assert source.config == %{"endpoint" => "file"}
  end

  test "raw item duplicate external_id for same source is rejected (expected uniqueness failure)" do
    source = create_import_source(name: "Uploader one")

    assert {:ok, _} =
             Imports.create_raw_import_item(%{
               import_source_id: source.id,
               external_id: "tx-001",
               payload: %{"symbol" => "AAPL"}
             })

    assert {:error, changeset} =
             Imports.create_raw_import_item(%{
               import_source_id: source.id,
               external_id: "tx-001",
               payload: %{"symbol" => "GOOGL"}
             })

    assert %{external_id: ["has already been taken"]} = errors_on(changeset)
  end

  test "raw item duplicate content_hash for same source is rejected (expected uniqueness failure)" do
    source = create_import_source(name: "Uploader two")

    assert {:ok, _} =
             Imports.create_raw_import_item(%{
               import_source_id: source.id,
               content_hash: "sha256:111",
               payload: %{"amount" => "100"}
             })

    assert {:error, changeset} =
             Imports.create_raw_import_item(%{
               import_source_id: source.id,
               content_hash: "sha256:111",
               payload: %{"amount" => "200"}
             })

    assert %{content_hash: ["has already been taken"]} = errors_on(changeset)
  end

  test "raw item allows same external_id for different sources" do
    source_one = create_import_source(name: "Uploader A")
    source_two = create_import_source(name: "Uploader B")

    assert {:ok, _} =
             Imports.create_raw_import_item(%{
               import_source_id: source_one.id,
               external_id: "tx-shared",
               payload: %{"source" => "A"}
             })

    assert {:ok, item} =
             Imports.create_raw_import_item(%{
               import_source_id: source_two.id,
               external_id: "tx-shared",
               payload: %{"source" => "B"}
             })

    assert item.external_id == "tx-shared"
    assert item.import_source_id == source_two.id
  end

  test "raw item allows same content_hash for different sources" do
    source_one = create_import_source(name: "Uploader C")
    source_two = create_import_source(name: "Uploader D")

    assert {:ok, _} =
             Imports.create_raw_import_item(%{
               import_source_id: source_one.id,
               content_hash: "sha256:shared",
               payload: %{"source" => "A"}
             })

    assert {:ok, item} =
             Imports.create_raw_import_item(%{
               import_source_id: source_two.id,
               content_hash: "sha256:shared",
               payload: %{"source" => "B"}
             })

    assert item.content_hash == "sha256:shared"
    assert item.import_source_id == source_two.id
  end

  test "import run can be finished with summary" do
    source = create_import_source(name: "Uploader finish")

    assert {:ok, run} = Imports.create_import_run(%{import_source_id: source.id})

    assert {:ok, finished_run} =
             Imports.finish_import_run(run.id, %{summary: %{"inserted_items" => 2}})

    assert finished_run.status == "finished"
    assert finished_run.summary == %{"inserted_items" => 2}
    assert finished_run.finished_at
  end

  test "finish_import_run/2 works with atom-keyed attrs" do
    source = create_import_source(name: "Atom attrs finish")

    assert {:ok, run} = Imports.create_import_run(%{import_source_id: source.id})

    assert {:ok, finished_run} =
             Imports.finish_import_run(run.id, %{
               status: "completed",
               summary: %{"inserted_items" => 1}
             })

    assert finished_run.status == "completed"
    assert finished_run.summary == %{"inserted_items" => 1}
    assert finished_run.finished_at
  end

  test "finish_import_run/2 works with string-keyed attrs" do
    source = create_import_source(name: "String attrs finish")

    assert {:ok, run} = Imports.create_import_run(%{import_source_id: source.id})

    assert {:ok, finished_run} =
             Imports.finish_import_run(run.id, %{"summary" => %{"inserted_items" => 2}})

    assert finished_run.status == "finished"
    assert finished_run.summary == %{"inserted_items" => 2}
    assert finished_run.finished_at
  end

  test "string-keyed attrs do not get mixed with atom defaults" do
    source = create_import_source(name: "String attrs mix check")

    assert {:ok, run} = Imports.create_import_run(%{import_source_id: source.id})

    assert {:ok, finished_run} =
             Imports.finish_import_run(run.id, %{"summary" => %{"inserted_items" => 3}})

    assert finished_run.status == "finished"
    assert finished_run.summary == %{"inserted_items" => 3}
  end

  test "provided string-keyed status is not overwritten by the default" do
    source = create_import_source(name: "String status guard")

    assert {:ok, run} = Imports.create_import_run(%{import_source_id: source.id})

    assert {:ok, finished_run} =
             Imports.finish_import_run(run.id, %{
               "status" => "completed",
               "summary" => %{"inserted_items" => 4}
             })

    assert finished_run.status == "completed"
  end

  test "provided atom-keyed status is not overwritten by the default" do
    source = create_import_source(name: "Atom status guard")

    assert {:ok, run} = Imports.create_import_run(%{import_source_id: source.id})

    assert {:ok, finished_run} =
             Imports.finish_import_run(run.id, %{
               status: "completed",
               summary: %{"inserted_items" => 5}
             })

    assert finished_run.status == "completed"
  end

  test "raw items can be listed by source" do
    source_one = create_import_source(name: "List source one")
    source_two = create_import_source(name: "List source two")

    assert {:ok, _} =
             Imports.create_raw_import_item(%{
               import_source_id: source_one.id,
               external_id: "tx-list-one",
               payload: %{"source" => "one"}
             })

    assert {:ok, _} =
             Imports.create_raw_import_item(%{
               import_source_id: source_two.id,
               external_id: "tx-list-two",
               payload: %{"source" => "two"}
             })

    assert {:ok, _} =
             Imports.create_raw_import_item(%{
               import_source_id: source_one.id,
               external_id: "tx-list-three",
               payload: %{"source" => "one"}
             })

    source_one_items = Imports.list_raw_import_items_for_source(source_one.id)

    assert length(source_one_items) == 2
    assert Enum.all?(source_one_items, &(&1.import_source_id == source_one.id))
  end

  test "raw item can belong to an import run" do
    source = create_import_source(name: "Run linked source")

    assert {:ok, run} = Imports.create_import_run(%{import_source_id: source.id})

    assert {:ok, item} =
             Imports.create_raw_import_item(%{
               import_source_id: source.id,
               import_run_id: run.id,
               external_id: "tx-run",
               payload: %{"run" => run.id}
             })

    assert item.import_source_id == source.id
    assert item.import_run_id == run.id
  end

  test "raw item can exist without an import run" do
    source = create_import_source(name: "Runless source")

    assert {:ok, item} =
             Imports.create_raw_import_item(%{
               import_source_id: source.id,
               external_id: "tx-runless",
               payload: %{"run" => nil}
             })

    assert item.import_run_id == nil
  end

  test "creating an import source and listing all sources" do
    create_import_source(name: "list-one")
    create_import_source(name: "list-two")

    assert Enum.any?(Imports.list_import_sources(), fn source ->
             source.name in ["list-one", "list-two"]
           end)
  end

  test "import source id is required for raw import item" do
    assert {:error, changeset} =
             Imports.create_raw_import_item(%{external_id: "tx-missing-source"})

    assert %{import_source_id: ["can't be blank"]} = errors_on(changeset)
  end

  test "raw import item stores status defaults to new" do
    source = create_import_source(name: "status default")

    assert {:ok, item} =
             Imports.create_raw_import_item(%{
               import_source_id: source.id,
               payload: %{}
             })

    assert item.status == "new"
  end

  test "payload map defaults to an empty map when omitted" do
    source = create_import_source(name: "payload default")

    assert {:ok, item} =
             Imports.create_raw_import_item(%{
               import_source_id: source.id,
               external_id: "tx-payload-default"
             })

    assert item.payload == %{}
  end

  test "import run defaults to pending when created" do
    source = create_import_source(name: "default run")

    assert {:ok, run} = Imports.create_import_run(%{import_source_id: source.id})

    assert run.status == "pending"
  end

  test "create import source persists type string values without atom conversion" do
    assert {:ok, source} = Imports.create_import_source(%{name: "Manual", type: "document_inbox"})

    assert source.type == "document_inbox"
  end

  test "list_import_sources_with_stats aggregates run/item counts and latest run status" do
    source_alpha = create_import_source(name: "Source Alpha")
    source_beta = create_import_source(name: "Source Beta")

    assert {:ok, _run_alpha_one} =
             Imports.create_import_run(%{
               import_source_id: source_alpha.id,
               status: "finished",
               started_at: ~U[2026-05-01 10:00:00Z],
               finished_at: ~U[2026-05-01 10:00:05Z]
             })

    assert {:ok, _run_alpha_two} =
             Imports.create_import_run(%{
               import_source_id: source_alpha.id,
               status: "completed",
               started_at: ~U[2026-05-01 11:00:00Z],
               finished_at: ~U[2026-05-01 11:00:05Z]
             })

    assert {:ok, _item_alpha_one} =
             Imports.create_raw_import_item(%{
               import_source_id: source_alpha.id,
               external_id: "alpha-1",
               content_hash: "sha256:alpha1",
               original_filename: "alpha1.csv",
               content_type: "text/csv",
               status: "new"
             })

    assert {:ok, _item_alpha_two} =
             Imports.create_raw_import_item(%{
               import_source_id: source_alpha.id,
               external_id: "alpha-2",
               content_hash: "sha256:alpha2",
               original_filename: "alpha2.csv",
               content_type: "text/csv",
               status: "new"
             })

    assert {:ok, _run_beta} =
             Imports.create_import_run(%{
               import_source_id: source_beta.id,
               status: "pending"
             })

    assert {:ok, _item_beta} =
             Imports.create_raw_import_item(%{
               import_source_id: source_beta.id,
               external_id: "beta-1",
               content_hash: "sha256:beta1",
               original_filename: "beta1.csv",
               content_type: "text/csv",
               status: "new"
             })

    [first_stat, second_stat] = Imports.list_import_sources_with_stats()

    assert first_stat.id == source_beta.id
    assert second_stat.id == source_alpha.id

    alpha_stats = Enum.find([first_stat, second_stat], &(&1.id == source_alpha.id))
    beta_stats = Enum.find([first_stat, second_stat], &(&1.id == source_beta.id))

    assert alpha_stats.runs_count == 2
    assert alpha_stats.raw_import_items_count == 2
    assert alpha_stats.latest_import_run_status == "completed"

    assert DateTime.truncate(alpha_stats.latest_import_run_started_at, :second) ==
             ~U[2026-05-01 11:00:00Z]

    assert DateTime.truncate(alpha_stats.latest_import_run_finished_at, :second) ==
             ~U[2026-05-01 11:00:05Z]

    assert beta_stats.runs_count == 1
    assert beta_stats.raw_import_items_count == 1
    assert beta_stats.latest_import_run_status == "pending"
  end

  test "list_recent_import_runs returns run list ordered by started/inserted time and source name" do
    source = create_import_source(name: "Ordered runs source")

    assert {:ok, run_old} =
             Imports.create_import_run(%{
               import_source_id: source.id,
               status: "finished",
               started_at: ~U[2026-05-01 09:00:00Z],
               finished_at: ~U[2026-05-01 09:01:00Z]
             })

    assert {:ok, run_mid} =
             Imports.create_import_run(%{
               import_source_id: source.id,
               status: "completed",
               started_at: ~U[2026-05-01 10:00:00Z],
               finished_at: ~U[2026-05-01 10:01:00Z]
             })

    assert {:ok, run_new} =
             Imports.create_import_run(%{
               import_source_id: source.id,
               status: "started",
               started_at: ~U[2026-05-01 11:00:00Z],
               finished_at: ~U[2026-05-01 11:01:00Z]
             })

    runs = Imports.list_recent_import_runs(2)

    assert Enum.map(runs, & &1.id) == [run_new.id, run_mid.id]
    assert hd(runs).import_source.name == source.name
    assert Enum.at(runs, 1).import_source.name == source.name
  end

  test "list_recent_raw_import_items returns recent items ordered by insertion and source name" do
    source = create_import_source(name: "Ordered raw items source")

    assert {:ok, _first_item} =
             Imports.create_raw_import_item(%{
               import_source_id: source.id,
               external_id: "raw-first",
               content_hash: "sha256:raw-first",
               original_filename: "first.csv",
               content_type: "text/csv",
               status: "new"
             })

    assert {:ok, _second_item} =
             Imports.create_raw_import_item(%{
               import_source_id: source.id,
               external_id: "raw-second",
               content_hash: "sha256:raw-second",
               original_filename: "second.csv",
               content_type: "text/csv",
               status: "new"
             })

    assert {:ok, _} =
             Imports.create_raw_import_item(%{
               import_source_id: source.id,
               external_id: "raw-third",
               content_hash: "sha256:raw-third",
               original_filename: "third.csv",
               content_type: "text/csv",
               status: "new"
             })

    items = Imports.list_recent_raw_import_items(2)

    assert length(items) == 2
    assert Enum.map(items, & &1.external_id) == ["raw-third", "raw-second"]
    assert Enum.all?(items, &(&1.import_source.id == source.id))
  end

  test "create/list/resolve import conflicts works through imports context" do
    source = create_import_source(name: "Conflicts source")
    {:ok, run} = Imports.create_import_run(%{import_source_id: source.id, status: "started"})

    {:ok, raw_item} =
      Imports.create_raw_import_item(%{
        import_source_id: source.id,
        import_run_id: run.id,
        external_id: "conflict-raw-item"
      })

    {:ok, open_conflict} =
      Imports.create_import_conflict(%{
        import_source_id: source.id,
        import_run_id: run.id,
        raw_import_item_id: raw_item.id,
        conflict_type: "duplicate_transaction",
        summary: "Duplicate external transaction id",
        details: %{"external_id" => "tx-123"}
      })

    {:ok, _resolved_conflict} =
      Imports.create_import_conflict(%{
        import_source_id: source.id,
        import_run_id: run.id,
        conflict_type: "stale_position",
        status: "resolved",
        summary: "Position already closed"
      })

    run_conflicts = Imports.list_import_conflicts_for_run(run.id)
    assert Enum.map(run_conflicts, & &1.id) |> Enum.member?(open_conflict.id)

    open_conflicts = Imports.list_open_import_conflicts()
    assert Enum.any?(open_conflicts, &(&1.id == open_conflict.id))

    assert {:ok, resolved} =
             Imports.resolve_import_conflict(open_conflict.id, %{
               details: %{"resolution" => "ignored"}
             })

    assert resolved.status == "resolved"
    assert resolved.details == %{"resolution" => "ignored"}

    assert {:ok, resolved_again} =
             Imports.resolve_import_conflict(open_conflict.id, %{
               import_source_id: source.id + 1,
               import_run_id: run.id + 1,
               raw_import_item_id: nil,
               conflict_type: "tampered_type",
               summary: "tampered summary",
               details: %{"resolution" => "kept"}
             })

    assert resolved_again.import_source_id == source.id
    assert resolved_again.import_run_id == run.id
    assert resolved_again.raw_import_item_id == raw_item.id
    assert resolved_again.conflict_type == "duplicate_transaction"
    assert resolved_again.summary == "Duplicate external transaction id"
    assert resolved_again.details == %{"resolution" => "kept"}

    refute Enum.any?(Imports.list_open_import_conflicts(), &(&1.id == open_conflict.id))
  end

  test "import conflict validates required fields" do
    assert {:error, changeset} = Imports.create_import_conflict(%{})

    assert %{
             import_source_id: ["can't be blank"],
             import_run_id: ["can't be blank"],
             conflict_type: ["can't be blank"],
             summary: ["can't be blank"]
           } =
             errors_on(changeset)
  end
end
