defmodule Portfolixir.Catalog.FactsheetAllocationImport do
  @moduledoc "Confirmation flow for parsed factsheet allocation previews."

  import Ecto.Query

  alias Portfolixir.Catalog

  alias Portfolixir.Catalog.{
    FactsheetAllocationPreview,
    FundAllocation,
    FundAllocationItem,
    Security
  }

  alias Portfolixir.Repo

  @summary_sections ["allocations", "fund_allocation_items"]
  @source "factsheet"
  @allocation_types ["region", "country", "sector", "asset_class"]
  @zero_decimal Decimal.new("0")
  @one_decimal Decimal.new("1")
  @no_allocations_warning "No allocation rows were available for confirmation."

  def confirm_fund_document(fund_document_id) when is_integer(fund_document_id) do
    with {:ok, preview} <- FactsheetAllocationPreview.preview_fund_document(fund_document_id) do
      confirm_preview(preview)
    end
  end

  def confirm_fund_document(_),
    do: {:error, {:invalid_input, "Expected integer fund_document_id."}}

  def confirm_preview(preview) when is_map(preview) do
    with {:ok, security_id} <- extract_security_id(preview),
         :ok <- ensure_security_exists(security_id) do
      fund_document_id = extract_fund_document_id(preview)

      summary =
        base_summary(security_id, fund_document_id)
        |> append_preview_warnings(preview)

      allocations = extract_allocations(preview)

      if allocations == [] do
        {:ok, append_warning(summary, @no_allocations_warning)}
      else
        case Repo.transaction(fn ->
               Enum.reduce(allocations, summary, &persist_allocation(security_id, &1, &2))
             end) do
          {:ok, confirmation_summary} -> {:ok, confirmation_summary}
          {:error, reason} -> {:error, reason}
        end
      end
    else
      {:error, _reason} = error -> error
    end
  end

  def confirm_preview(_), do: {:error, {:invalid_input, "Expected preview map."}}

  defp ensure_security_exists(security_id) when is_integer(security_id) do
    case Catalog.get_security(security_id) do
      %Security{} -> :ok
      _ -> {:error, {:security_not_found, "security_id #{security_id} does not exist."}}
    end
  end

  defp extract_security_id(preview) do
    case Map.get(preview, "security_id") do
      nil ->
        {:error, {:missing_security_id, "preview['security_id'] is required for confirmation."}}

      id when is_integer(id) ->
        {:ok, id}

      id when is_binary(id) ->
        case Integer.parse(id) do
          {parsed_id, ""} -> {:ok, parsed_id}
          _ -> {:error, {:invalid_security_id, "security_id must be an integer."}}
        end

      _ ->
        {:error, {:invalid_security_id, "security_id must be an integer."}}
    end
  end

  defp extract_fund_document_id(preview) do
    case Map.get(preview, "fund_document_id") do
      id when is_integer(id) -> id
      id when is_binary(id) -> parse_int(id)
      _ -> nil
    end
  end

  defp parse_int(value) do
    case Integer.parse(value) do
      {parsed_id, ""} -> parsed_id
      _ -> nil
    end
  end

  defp append_preview_warnings(summary, preview) do
    preview_warnings = Map.get(preview, "warnings")

    if is_list(preview_warnings) do
      Map.update!(summary, "warnings", &(&1 ++ preview_warnings))
    else
      summary
    end
  end

  defp extract_allocations(preview) do
    case Map.get(preview, "allocations") do
      allocations when is_list(allocations) ->
        Enum.filter(allocations, &is_map/1)

      _ ->
        []
    end
  end

  defp persist_allocation(security_id, allocation, summary) do
    case allocation_type(allocation) do
      {:ok, allocation_type} ->
        case parse_as_of_date(Map.get(allocation, "as_of_date")) do
          {:ok, as_of_date} ->
            case get_or_create_allocation(security_id, allocation_type, as_of_date) do
              {:ok, allocation_record, :created} ->
                summary
                |> increment("created", "allocations")
                |> process_allocation_items(allocation_record, allocation)

              {:ok, allocation_record, :existing} ->
                summary
                |> increment("skipped", "allocations")
                |> process_allocation_items(allocation_record, allocation)

              {:error, summary_warning} ->
                summary
                |> increment("failed", "allocations")
                |> append_warning(summary_warning)
            end

          {:error, reason} ->
            summary
            |> increment("failed", "allocations")
            |> append_warning(
              "Skipping allocation #{inspect(Map.get(allocation, "allocation_type"))}: #{inspect(reason)}"
            )
        end

      {:error, reason} ->
        summary
        |> increment("failed", "allocations")
        |> append_warning("Skipping allocation: #{inspect(reason)}")
    end
  end

  defp process_allocation_items(summary, allocation_record, allocation) do
    items = Map.get(allocation, "items")

    case items do
      items when is_list(items) ->
        Enum.reduce(items, summary, fn item, acc ->
          process_allocation_item(allocation_record.id, item, acc)
        end)

      _ ->
        append_warning(
          summary,
          "Allocation #{allocation_record.id} skipped because items were invalid."
        )
    end
  end

  defp get_or_create_allocation(security_id, allocation_type, as_of_date) do
    attrs = %{
      security_id: security_id,
      source: @source,
      allocation_type: allocation_type,
      as_of_date: as_of_date
    }

    existing_allocation = get_existing_allocation(security_id, allocation_type, as_of_date)

    case existing_allocation do
      %FundAllocation{} = allocation_record ->
        {:ok, allocation_record, :existing}

      nil ->
        case Catalog.create_fund_allocation(attrs) do
          {:ok, allocation_record} ->
            {:ok, allocation_record, :created}

          {:error, changeset} ->
            {:error,
             "Could not create allocation #{allocation_type}: #{inspect(changeset.errors)}"}
        end
    end
  end

  defp get_existing_allocation(security_id, allocation_type, nil) do
    from(fa in FundAllocation,
      where:
        fa.security_id == ^security_id and
          fa.source == ^@source and
          fa.allocation_type == ^allocation_type and
          is_nil(fa.as_of_date)
    )
    |> Repo.one()
  end

  defp get_existing_allocation(security_id, allocation_type, as_of_date) do
    Repo.get_by(FundAllocation,
      security_id: security_id,
      source: @source,
      allocation_type: allocation_type,
      as_of_date: as_of_date
    )
  end

  defp process_allocation_item(allocation_id, item, summary) when is_map(item) do
    with {:ok, label} <- parse_item_label(item),
         {:ok, weight} <- parse_item_weight(item),
         {:ok, confidence} <- parse_item_confidence(item) do
      attrs =
        %{
          fund_allocation_id: allocation_id,
          label: label,
          weight: weight,
          confidence: confidence
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Enum.into(%{})

      case Repo.get_by(FundAllocationItem,
             fund_allocation_id: allocation_id,
             label: label
           ) do
        %FundAllocationItem{} ->
          summary
          |> increment("skipped", "fund_allocation_items")

        nil ->
          case Catalog.create_fund_allocation_item(attrs) do
            {:ok, _} ->
              increment(summary, "created", "fund_allocation_items")

            {:error, changeset} ->
              summary
              |> increment("failed", "fund_allocation_items")
              |> append_warning(
                "Could not create allocation item #{label}: #{inspect(changeset.errors)}"
              )
          end
      end
    else
      {:error, :invalid_item_confidence} = error ->
        summary
        |> increment("failed", "fund_allocation_items")
        |> append_warning("Invalid allocation item confidence: #{inspect(error)}")

      {:error, reason} ->
        summary
        |> increment("skipped", "fund_allocation_items")
        |> append_warning("Invalid allocation item: #{inspect(reason)}")
    end
  end

  defp process_allocation_item(_allocation_id, _item, summary) do
    summary
    |> increment("failed", "fund_allocation_items")
    |> append_warning("Skipping invalid allocation item payload.")
  end

  defp parse_item_label(item) do
    case Map.get(item, "label") do
      label when is_binary(label) ->
        label = String.trim(label)

        if label == "" do
          {:error, :missing_label}
        else
          {:ok, label}
        end

      _ ->
        {:error, :missing_label}
    end
  end

  defp parse_item_weight(item) do
    case Map.get(item, "weight") do
      %Decimal{} = decimal ->
        if Decimal.compare(decimal, @zero_decimal) == :lt do
          {:error, :negative_weight}
        else
          {:ok, decimal}
        end

      value when is_binary(value) ->
        case Decimal.parse(value) do
          {decimal, ""} ->
            if Decimal.compare(decimal, @zero_decimal) == :lt do
              {:error, :negative_weight}
            else
              {:ok, decimal}
            end

          _ ->
            {:error, :invalid_weight}
        end

      _ ->
        {:error, :invalid_weight}
    end
  end

  defp parse_item_confidence(item) do
    case Map.get(item, "confidence") do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        case Decimal.parse(value) do
          {decimal, ""} ->
            if Decimal.compare(decimal, @zero_decimal) != :lt and
                 Decimal.compare(decimal, @one_decimal) != :gt do
              {:ok, decimal}
            else
              {:error, :invalid_item_confidence}
            end

          _ ->
            {:error, :invalid_item_confidence}
        end

      value when is_struct(value, Decimal) ->
        if Decimal.compare(value, @zero_decimal) != :lt and
             Decimal.compare(value, @one_decimal) != :gt do
          {:ok, value}
        else
          {:error, :invalid_item_confidence}
        end

      _ ->
        {:error, :invalid_item_confidence}
    end
  end

  defp allocation_type(allocation) do
    case Map.get(allocation, "allocation_type") do
      type when type in @allocation_types -> {:ok, type}
      nil -> {:error, :missing_allocation_type}
      _ -> {:error, :unsupported_allocation_type}
    end
  end

  defp parse_as_of_date(nil), do: {:ok, nil}
  defp parse_as_of_date(date) when is_struct(date, Date), do: {:ok, date}

  defp parse_as_of_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, as_of_date} -> {:ok, as_of_date}
      {:error, _} -> {:error, :invalid_as_of_date}
    end
  end

  defp parse_as_of_date(_), do: {:error, :invalid_as_of_date}

  defp increment(summary, bucket, section) do
    update_in(summary, [bucket, section], &(&1 + 1))
  end

  defp append_warning(summary, warning) do
    Map.update!(summary, "warnings", &(&1 ++ [warning]))
  end

  defp base_summary(security_id, fund_document_id) do
    zeroes =
      Enum.reduce(@summary_sections, %{}, fn section, acc ->
        Map.put(acc, section, 0)
      end)

    %{
      "created" => zeroes,
      "updated" => zeroes,
      "skipped" => zeroes,
      "failed" => zeroes,
      "warnings" => [],
      "security_id" => security_id,
      "fund_document_id" => fund_document_id
    }
  end
end
