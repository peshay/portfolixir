defmodule Portfolixir.ClassificationExposure do
  @moduledoc "Read-only classification exposure report for a portfolio."

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Taxonomies

  @zero Decimal.new("0")
  @hundred Decimal.new("100")

  def report_for_portfolio(portfolio_id) when is_integer(portfolio_id) do
    exposures =
      portfolio_id
      |> positions_by_security()
      |> Enum.flat_map(&exposures_for_security/1)

    total_value =
      Enum.reduce(exposures, @zero, fn exposure, acc ->
        Decimal.add(acc, exposure.value)
      end)

    rows =
      exposures
      |> Enum.group_by(& &1.category_name)
      |> Enum.map(fn {category_name, grouped} ->
        value = Enum.reduce(grouped, @zero, fn row, acc -> Decimal.add(acc, row.value) end)

        %{
          category_name: category_name,
          value: value,
          percentage: percent(value, total_value),
          source_securities:
            grouped |> Enum.map(& &1.security_name) |> Enum.uniq() |> Enum.sort(),
          drilldown_details: build_drilldown_details(grouped),
          valuation_unavailable?: Enum.any?(grouped, &valuation_unavailable?/1)
        }
      end)
      |> Enum.sort_by(&{&1.category_name == "Unmapped", &1.category_name})

    %{
      rows: rows,
      total_value: total_value,
      warnings:
        exposures
        |> Enum.map(& &1.warning)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
    }
  end

  defp positions_by_security(portfolio_id) do
    Ledger.positions_for_portfolio(portfolio_id)
    |> Enum.reduce(%{}, fn {{_account_id, security_id}, quantity}, acc ->
      Map.update(acc, security_id, quantity, &Decimal.add(&1, quantity))
    end)
    |> Enum.map(fn {security_id, quantity} ->
      security = Catalog.get_security(security_id)
      quote = Catalog.get_latest_security_quote(security_id)

      market_value =
        if quote do
          Decimal.mult(quantity, quote.close)
        else
          @zero
        end

      %{
        security_id: security_id,
        security_name: (security && security.name) || "Unknown",
        market_value: market_value,
        valuation_warning:
          if(quote, do: nil, else: "missing_quote_fallback_quantity:#{security_id}")
      }
    end)
  end

  defp exposures_for_security(position) do
    mapped = Taxonomies.resolve_mapped_fund_allocation_exposures(position.security_id)

    if mapped.items == [] do
      direct_exposures(position)
    else
      mapped_exposures(position, mapped)
    end
  end

  defp direct_exposures(position) do
    categories = Catalog.list_security_categories(position.security_id)

    case categories do
      [] ->
        [unmapped_exposure(position, position.valuation_warning)]

      _ ->
        share = Decimal.div(position.market_value, Decimal.new(length(categories)))

        Enum.map(categories, fn category ->
          %{
            category_name: category.name,
            security_name: position.security_name,
            value: share,
            warning: position.valuation_warning,
            source_type: "direct-assignment",
            status: "mapped",
            allocation_type: nil,
            source_label: nil,
            detail_note: nil
          }
        end)
    end
  end

  defp mapped_exposures(position, mapped) do
    mapped.items
    |> Enum.map(fn item ->
      value = Decimal.mult(position.market_value, Decimal.div(item.weight, @hundred))

      category_name = if item.status == :mapped, do: item.category_name, else: "Unmapped"

      warning =
        if item.status == :mapped,
          do: position.valuation_warning,
          else: "unmapped_allocation:#{item.allocation_type}:#{item.source_label}"

      %{
        category_name: category_name,
        security_name: position.security_name,
        value: value,
        warning: warning,
        source_type: "weighted-allocation",
        status: to_string(item.status),
        allocation_type: item.allocation_type,
        source_label: item.source_label,
        detail_note:
          if(item.status == :mapped, do: nil, else: "No category mapping for allocation input")
      }
    end)
    |> Kernel.++(
      Enum.map(mapped.warnings, fn warning ->
        %{
          category_name: "Unmapped",
          security_name: position.security_name,
          value: @zero,
          warning: warning,
          source_type: "weighted-allocation",
          status: "unknown",
          allocation_type: nil,
          source_label: nil,
          detail_note: warning
        }
      end)
    )
  end

  defp unmapped_exposure(position, warning) do
    %{
      category_name: "Unmapped",
      security_name: position.security_name,
      value: position.market_value,
      warning: warning,
      source_type: "direct-assignment",
      status: "unmapped",
      allocation_type: nil,
      source_label: nil,
      detail_note: "No direct category assignment"
    }
  end

  defp build_drilldown_details(grouped) do
    grouped
    |> Enum.map(fn exposure ->
      %{
        source_type: exposure.source_type,
        status: exposure.status,
        security_name: exposure.security_name,
        value: exposure.value,
        valuation_unavailable?: valuation_unavailable?(exposure),
        allocation_type: exposure.allocation_type,
        source_label: exposure.source_label,
        note: exposure.detail_note
      }
    end)
    |> Enum.sort_by(fn detail ->
      {detail.source_type, detail.status, detail.security_name, detail.allocation_type || "",
       detail.source_label || ""}
    end)
  end

  defp valuation_unavailable?(%{warning: "missing_quote_fallback_quantity:" <> _}), do: true
  defp valuation_unavailable?(_exposure), do: false

  defp percent(value, total) do
    if Decimal.equal?(total, @zero) do
      @zero
    else
      Decimal.mult(Decimal.div(value, total), @hundred)
    end
  end
end
