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
end
