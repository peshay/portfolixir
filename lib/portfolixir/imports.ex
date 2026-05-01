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

  def list_import_sources_with_stats do
    latest_import_runs =
      from(run in ImportRun,
        order_by: [desc: run.started_at, desc: run.inserted_at, desc: run.id],
        distinct: [asc: run.import_source_id],
        select: %{
          import_source_id: run.import_source_id,
          status: run.status,
          started_at: run.started_at,
          finished_at: run.finished_at
        }
      )

    import_run_counts =
      from(run in ImportRun,
        group_by: run.import_source_id,
        select: %{import_source_id: run.import_source_id, count: count(run.id)}
      )

    raw_import_item_counts =
      from(item in RawImportItem,
        group_by: item.import_source_id,
        select: %{import_source_id: item.import_source_id, count: count(item.id)}
      )

    query =
      from(source in ImportSource,
        left_join: run_count in subquery(import_run_counts),
        on: run_count.import_source_id == source.id,
        left_join: raw_item_count in subquery(raw_import_item_counts),
        on: raw_item_count.import_source_id == source.id,
        left_join: latest_import_run in subquery(latest_import_runs),
        on: latest_import_run.import_source_id == source.id,
        order_by: [desc: source.inserted_at, desc: source.id],
        select: %{
          id: source.id,
          name: source.name,
          type: source.type,
          status: source.status,
          created_at: source.inserted_at,
          runs_count: fragment("COALESCE(?, 0)", run_count.count),
          raw_import_items_count: fragment("COALESCE(?, 0)", raw_item_count.count),
          latest_import_run_status: latest_import_run.status,
          latest_import_run_started_at: latest_import_run.started_at,
          latest_import_run_finished_at: latest_import_run.finished_at
        }
      )

    Repo.all(query)
  end

  def list_recent_import_runs(limit \\ 20)

  def list_recent_import_runs(limit) when is_integer(limit) do
    Repo.all(
      from(run in ImportRun,
        preload: [:import_source],
        order_by: [desc: run.started_at, desc: run.inserted_at, desc: run.id],
        limit: ^limit
      )
    )
  end

  def list_recent_import_runs(_invalid_limit), do: []

  def list_recent_raw_import_items(limit \\ 20)

  def list_recent_raw_import_items(limit) when is_integer(limit) do
    Repo.all(
      from(item in RawImportItem,
        preload: [:import_source],
        order_by: [desc: item.inserted_at, desc: item.id],
        limit: ^limit
      )
    )
  end

  def list_recent_raw_import_items(_invalid_limit), do: []

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
    |> normalize_key_types()
    |> Map.put_new("status", "finished")
    |> Map.put_new("finished_at", timestamp)
  end

  defp normalize_key_types(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp normalize_key_types(_attrs), do: %{}
end
