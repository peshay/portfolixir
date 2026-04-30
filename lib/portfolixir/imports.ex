defmodule Portfolixir.Imports do
  @moduledoc "Import intake context for reproducible raw import items."

  import Ecto.Query

  alias Portfolixir.Imports.{ImportRun, ImportSource, RawImportItem}
  alias Portfolixir.Repo

  def create_import_source(attrs) when is_map(attrs) do
    %ImportSource{}
    |> ImportSource.changeset(attrs)
    |> Repo.insert()
  end

  def list_import_sources do
    Repo.all(from(source in ImportSource, order_by: [asc: source.id]))
  end

  def create_import_run(attrs) when is_map(attrs) do
    %ImportRun{}
    |> ImportRun.changeset(attrs)
    |> Repo.insert()
  end

  def finish_import_run(import_run_id, attrs) when is_integer(import_run_id) and is_map(attrs) do
    case Repo.get(ImportRun, import_run_id) do
      nil ->
        {:error, :not_found}

      %ImportRun{} = import_run ->
        import_run
        |> ImportRun.changeset(attrs |> default_finish_attrs())
        |> Repo.update()
    end
  end

  def create_raw_import_item(attrs) when is_map(attrs) do
    %RawImportItem{}
    |> RawImportItem.changeset(attrs)
    |> Repo.insert()
  end

  def list_raw_import_items_for_source(import_source_id) when is_integer(import_source_id) do
    Repo.all(
      from(item in RawImportItem,
        where: item.import_source_id == ^import_source_id,
        order_by: [asc: item.inserted_at, asc: item.id]
      )
    )
  end

  defp default_finish_attrs(attrs) do
    timestamp = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    attrs
    |> Map.put_new(:status, "finished")
    |> Map.put_new(:finished_at, timestamp)
  end
end
