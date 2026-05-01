defmodule Portfolixir.Catalog.FactsheetAllocationPreview do
  @moduledoc "Preview parser for simple factsheet allocation sections in extracted text."

  alias Portfolixir.Catalog.FundDocument
  alias Portfolixir.Repo

  @source_default "factsheet_text"
  @default_confidence Decimal.new("1")
  @section_sum_warning_threshold Decimal.new("105")

  @section_headers %{
    "regions" => "region",
    "countries" => "country",
    "sectors" => "sector",
    "asset classes" => "asset_class"
  }

  @allocation_line_re ~r/^(?<label>.+?)\s+(?<weight>\d+(?:[.,]\d+)?)\s*%?\s*$/

  @doc """
  Parse a fund document by id and preview allocations from persisted extracted text.

  Returns `{:ok, preview}` with string-keyed maps.
  """
  def preview_fund_document(fund_document_id) when is_integer(fund_document_id) do
    case Repo.get(FundDocument, fund_document_id) do
      %FundDocument{} = fund_document ->
        preview_text(fund_document.extracted_text, %{
          "fund_document_id" => fund_document.id,
          "security_id" => fund_document.security_id
        })

      nil ->
        {:error, :not_found}
    end
  end

  def preview_fund_document(_), do: {:error, :invalid_arguments}

  @doc """
  Parse extracted factsheet text and return a stable preview payload.

  The parser is deterministic and intentionally small:
  it supports simple section headers and `Label Weight` lines.
  """
  def preview_text(text, opts \\ %{})

  def preview_text(nil, opts) when is_map(opts), do: preview_text("", opts)

  def preview_text(text, opts) when is_binary(text) and is_map(opts) do
    base_state = %{
      current_section: nil,
      section_order: [],
      section_items: %{},
      section_sums: %{},
      warnings: []
    }

    state =
      text
      |> String.split(~r/\R/, trim: true)
      |> Enum.reduce(base_state, &parse_line/2)

    allocations =
      state.section_order
      |> Enum.map(fn allocation_type ->
        items = Map.get(state.section_items, allocation_type, [])

        if items == [] do
          nil
        else
          %{
            "allocation_type" => allocation_type,
            "source" => opt_as_string(opts, :source, @source_default),
            "as_of_date" => opt_as_string(opts, :as_of_date, nil),
            "items" => items
          }
        end
      end)
      |> Enum.reject(&is_nil/1)

    final_warnings =
      state.warnings
      |> build_sum_warnings(state.section_order, state.section_sums)
      |> maybe_append_empty_text_warning(text)

    preview = %{
      "fund_document_id" => opt_as_integer(opts, :fund_document_id, nil),
      "security_id" => opt_as_integer(opts, :security_id, nil),
      "allocations" => allocations,
      "warnings" => final_warnings,
      "counts" => %{
        "allocations" => length(allocations),
        "items" => Enum.reduce(allocations, 0, &(length(&1["items"]) + &2))
      }
    }

    {:ok, preview}
  end

  def preview_text(_, _), do: {:error, {:invalid_input, "Expected extracted text as string."}}

  defp parse_line(line, state) do
    trimmed_line = String.trim(line)

    cond do
      trimmed_line == "" ->
        state

      (section_type = allocation_section(trimmed_line)) != nil ->
        section_order =
          if section_type in state.section_order do
            state.section_order
          else
            state.section_order ++ [section_type]
          end

        section_items = Map.put_new(state.section_items, section_type, [])
        section_sums = Map.put_new(state.section_sums, section_type, Decimal.new("0"))

        %{
          state
          | current_section: section_type,
            section_order: section_order,
            section_items: section_items,
            section_sums: section_sums
        }

      state.current_section == nil ->
        state

      true ->
        parse_allocation_line(trimmed_line, state)
    end
  end

  defp parse_allocation_line(trimmed_line, %{current_section: current_section} = state)
       when is_binary(current_section) do
    case Regex.named_captures(@allocation_line_re, trimmed_line) do
      %{"label" => raw_label, "weight" => raw_weight} ->
        label = normalize_label(raw_label)

        case normalize_weight(raw_weight) do
          {:ok, weight} when label != "" ->
            item = %{
              "label" => label,
              "weight" => weight,
              "confidence" => @default_confidence,
              "raw_line" => trimmed_line
            }

            items = Map.get(state.section_items, current_section, [])
            updated_items = items ++ [item]

            updated_sums =
              Map.update(state.section_sums, current_section, weight, &Decimal.add(&1, weight))

            state
            |> Map.put(
              :section_items,
              Map.put(state.section_items, current_section, updated_items)
            )
            |> Map.put(:section_sums, updated_sums)

          _ ->
            warn_unparseable_line(state, trimmed_line)
        end

      nil ->
        warn_unparseable_line(state, trimmed_line)
    end
  end

  defp parse_allocation_line(_, state), do: state

  defp warn_unparseable_line(state, line) do
    warning = "Could not parse allocation line: \"#{line}\"."
    Map.update!(state, :warnings, &(&1 ++ [warning]))
  end

  defp build_sum_warnings(warnings, section_order, section_sums) do
    section_order
    |> Enum.reduce(warnings, fn section_type, acc ->
      total = Map.get(section_sums, section_type, Decimal.new("0"))

      if Decimal.gt?(total, @section_sum_warning_threshold) do
        warning =
          "The #{section_type} allocation total (" <>
            Decimal.to_string(total, :normal) <> "% ) appears above 105%."

        acc ++ [warning]
      else
        acc
      end
    end)
  end

  defp maybe_append_empty_text_warning(warnings, text) do
    if text == "" && !Enum.member?(warnings, "No extracted factsheet text is available.") do
      warnings ++ ["No extracted factsheet text is available."]
    else
      warnings
    end
  end

  defp allocation_section(line) do
    normalized =
      line
      |> String.trim_trailing(":")
      |> String.downcase()
      |> normalize_spaces()

    Map.get(@section_headers, normalized)
  end

  defp normalize_spaces(value) do
    value
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp normalize_label(label) do
    label
    |> String.trim()
    |> normalize_spaces()
  end

  defp normalize_weight(raw_weight) do
    normalized = String.replace(raw_weight, ",", ".")

    case Decimal.parse(normalized) do
      {weight, ""} -> {:ok, weight}
      _ -> :error
    end
  end

  defp opt_as_string(opts, key, default) do
    case option_value(opts, key) do
      nil -> default
      value when is_binary(value) -> value
      value when is_atom(value) -> Atom.to_string(value)
      value -> to_string(value)
    end
  end

  defp opt_as_integer(opts, key, default) do
    case option_value(opts, key) do
      nil ->
        default

      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> parsed
          _ -> default
        end

      _ ->
        default
    end
  end

  defp option_value(opts, key) do
    cond do
      Map.has_key?(opts, key) ->
        Map.get(opts, key)

      Map.has_key?(opts, to_string(key)) ->
        Map.get(opts, to_string(key))

      true ->
        nil
    end
  end
end
