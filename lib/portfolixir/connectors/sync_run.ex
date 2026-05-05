defmodule Portfolixir.Connectors.SyncRun do
  @moduledoc "Read-only connector sync that stages records as raw import items."

  alias Portfolixir.Connectors
  alias Portfolixir.Imports
  alias Portfolixir.Imports.{ImportSource, RawImportItem}
  alias Portfolixir.Repo

  @source_type "connector"
  @source_status "active"
  @content_type "application/vnd.portfolixir.connector+json"
  @summary_section_keys [
    "accounts",
    "balances",
    "transactions",
    "documents",
    "permissions",
    "raw_items"
  ]
  @sensitive_payload_keys MapSet.new([
                            "access_token",
                            "api_key",
                            "password",
                            "private_key",
                            "refresh_token",
                            "secret",
                            "secret_key",
                            "token"
                          ])

  def run(provider_module, provider_name, config, opts \\ %{})

  def run(provider_module, provider_name, config, opts)
      when is_atom(provider_module) and is_binary(provider_name) and is_map(config) and
             is_map(opts) do
    with {:ok, import_source} <- get_or_create_source(provider_name),
         {:ok, import_run} <- create_import_run(import_source) do
      summary =
        build_summary(provider_name, import_source.id, import_run.id)
        |> sync_records("accounts", fn -> Connectors.accounts(provider_module, config) end)
        |> sync_records("balances", fn -> Connectors.balances(provider_module, config) end)
        |> sync_records("transactions", fn ->
          Connectors.transactions(provider_module, config, opts)
        end)
        |> sync_records("documents", fn ->
          Connectors.documents(provider_module, config, opts)
        end)
        |> sync_permissions(provider_module, config)

      finish_import_run(import_run, summary)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def run(_provider_module, _provider_name, _config, _opts) do
    {:error, :invalid_arguments}
  end

  defp build_summary(provider_name, source_id, run_id) do
    base_counts = Map.new(@summary_section_keys, fn key -> {key, 0} end)

    %{
      "provider" => provider_name,
      "import_source_id" => source_id,
      "import_run_id" => run_id,
      "created" => base_counts,
      "skipped" => base_counts,
      "changed" => base_counts,
      "conflicts" => base_counts,
      "failed" => base_counts,
      "warnings" => [],
      "record_counts" => base_counts
    }
  end

  defp get_or_create_source(provider_name) do
    case Repo.get_by(ImportSource,
           name: "Connector: #{provider_name}",
           type: @source_type,
           status: @source_status
         ) do
      %ImportSource{} = source ->
        {:ok, source}

      nil ->
        Imports.create_import_source(%{
          name: "Connector: #{provider_name}",
          type: @source_type,
          status: @source_status
        })
    end
  end

  defp create_import_run(import_source) do
    Imports.create_import_run(%{
      import_source_id: import_source.id,
      status: "started",
      started_at: utc_now()
    })
  end

  defp sync_records(summary, record_type, fetcher) when is_function(fetcher, 0) do
    case fetcher.() do
      {:ok, records} when is_list(records) ->
        records
        |> Enum.reduce(
          increment_record_count(summary, record_type, length(records)),
          &upsert_connector_record(record_type, &1, &2)
        )

      {:ok, _invalid} ->
        summary
        |> increment("failed", record_type)
        |> append_warning("Could not parse #{record_type} payload: expected list")
        |> increment_record_count(record_type, 0)

      {:error, reason} ->
        summary
        |> increment("failed", record_type)
        |> append_warning("Could not read #{record_type}: #{inspect(reason)}")
        |> increment_record_count(record_type, 0)

      _ ->
        summary
        |> increment("failed", record_type)
        |> append_warning("Could not read #{record_type}: unsupported return type")
        |> increment_record_count(record_type, 0)
    end
  end

  defp upsert_connector_record(record_type, record, summary) when is_map(record) do
    external_id = extract_external_id(record)
    normalized_record = normalize_payload(record)
    create_raw_item(record_type, normalized_record, external_id, summary)
  end

  defp upsert_connector_record(record_type, _record, summary) do
    summary
    |> increment("failed", record_type)
    |> append_warning("Could not parse #{record_type}: expected map payload")
  end

  defp sync_permissions(summary, provider_module, config) do
    case Connectors.permissions(provider_module, config) do
      {:ok, permissions} when is_list(permissions) ->
        normalized_permissions = Enum.sort(Enum.uniq(permissions))

        normalized_permissions
        |> Enum.reduce(
          increment_record_count(summary, "permissions", length(normalized_permissions)),
          &process_permission/2
        )

      {:ok, _invalid} ->
        summary
        |> increment("failed", "permissions")
        |> append_warning("Could not parse permissions payload: expected list")
        |> increment_record_count("permissions", 0)

      {:error, reason} ->
        summary
        |> increment("failed", "permissions")
        |> append_warning("Could not read permissions: #{inspect(reason)}")
        |> increment_record_count("permissions", 0)
    end
  end

  defp process_permission(permission, summary) when is_binary(permission) do
    record = %{"permission" => permission}
    create_raw_item("permissions", record, "permission:#{permission}", summary)
  end

  defp process_permission(permission, summary) do
    summary
    |> increment("failed", "permissions")
    |> append_warning("Could not parse permission #{inspect(permission)}: expected string")
  end

  defp create_raw_item(record_type, normalized_record, external_id, summary) do
    payload = raw_payload(record_type, external_id, summary["provider"], normalized_record)
    content_hash = content_hash(external_id, payload)
    import_source_id = summary["import_source_id"]
    import_run_id = summary["import_run_id"]

    case find_existing_item(import_source_id, external_id, content_hash) do
      {:same, %RawImportItem{}} ->
        summary
        |> increment("skipped", record_type)
        |> increment("skipped", "raw_items")

      {:changed, %RawImportItem{} = existing_item} ->
        summary
        |> increment("changed", record_type)
        |> increment("changed", "raw_items")
        |> increment("conflicts", record_type)
        |> increment("conflicts", "raw_items")
        |> append_warning(
          "Changed #{record_type} detected for external_id #{inspect(existing_item.external_id || external_id)}"
        )

      :new ->
        attrs = %{
          import_source_id: import_source_id,
          import_run_id: import_run_id,
          external_id: external_id,
          content_hash: content_hash,
          content_type: @content_type,
          payload: payload,
          status: "new"
        }

        case Imports.create_raw_import_item(attrs) do
          {:ok, _item} ->
            summary
            |> increment("created", record_type)
            |> increment("created", "raw_items")

          {:error, changeset} ->
            summary
            |> increment("failed", record_type)
            |> increment("failed", "raw_items")
            |> append_warning(
              "Could not create raw import item for #{record_type}: #{inspect(changeset.errors)}"
            )
        end
    end
  end

  defp find_existing_item(import_source_id, external_id, content_hash) do
    by_external_id =
      case external_id do
        id when is_binary(id) ->
          Repo.get_by(RawImportItem, import_source_id: import_source_id, external_id: id)

        _ ->
          nil
      end

    cond do
      match?(%RawImportItem{}, by_external_id) and by_external_id.content_hash == content_hash ->
        {:same, by_external_id}

      match?(%RawImportItem{}, by_external_id) ->
        {:changed, by_external_id}

      item = find_by_content_hash(import_source_id, content_hash) ->
        {:same, item}

      true ->
        :new
    end
  end

  defp find_by_content_hash(import_source_id, content_hash) when is_binary(content_hash) do
    Repo.get_by(RawImportItem, import_source_id: import_source_id, content_hash: content_hash)
  end

  defp find_by_content_hash(_import_source_id, _content_hash), do: nil

  defp content_hash(_external_id, payload) do
    payload
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> then(&"sha256:#{&1}")
  end

  defp raw_payload(record_type, external_id, provider_name, payload) do
    %{
      "provider" => provider_name,
      "record_type" => record_type_singular(record_type),
      "external_id" => external_id,
      "payload" => payload
    }
  end

  defp record_type_singular("accounts"), do: "account"
  defp record_type_singular("balances"), do: "balance"
  defp record_type_singular("transactions"), do: "transaction"
  defp record_type_singular("documents"), do: "document"
  defp record_type_singular("permissions"), do: "permission"
  defp record_type_singular(other), do: other

  defp extract_external_id(record) when is_map(record) do
    Map.get(record, "id") ||
      Map.get(record, :id) ||
      Map.get(record, "external_id") ||
      Map.get(record, :external_id) ||
      Map.get(record, "uuid") ||
      Map.get(record, :uuid) ||
      Map.get(record, "reference_id") ||
      Map.get(record, :reference_id)
  end

  defp extract_external_id(_record), do: nil

  defp normalize_payload(%Decimal{} = value), do: Decimal.to_string(value)

  defp normalize_payload(payload) when is_map(payload) do
    payload
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      key_string = to_string(key)

      if MapSet.member?(@sensitive_payload_keys, String.downcase(key_string)) do
        acc
      else
        Map.put(acc, key_string, normalize_payload(value))
      end
    end)
  end

  defp normalize_payload(payload) when is_list(payload) do
    Enum.map(payload, &normalize_payload/1)
  end

  defp normalize_payload(payload), do: payload

  defp increment(summary, section, key) do
    Map.update!(summary, section, fn section_values ->
      Map.update!(section_values, key, &(&1 + 1))
    end)
  end

  defp increment_record_count(summary, key, count) when is_integer(count) do
    Map.update!(summary, "record_counts", fn section_values ->
      Map.update!(section_values, key, &(&1 + count))
    end)
  end

  defp append_warning(summary, warning) do
    Map.update!(summary, "warnings", fn warnings -> warnings ++ [warning] end)
  end

  defp finish_import_run(import_run, summary) do
    case Imports.finish_import_run(import_run.id, %{
           status: "completed",
           summary: summary,
           finished_at: utc_now()
         }) do
      {:ok, _run} -> {:ok, summary}
      {:error, _reason} -> {:ok, summary}
    end
  end

  defp utc_now do
    DateTime.utc_now() |> DateTime.truncate(:microsecond)
  end
end
