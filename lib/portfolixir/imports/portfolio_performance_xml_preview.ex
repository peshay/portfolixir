defmodule Portfolixir.Imports.PortfolioPerformanceXmlPreview do
  @moduledoc "Preview parser for Portfolio Performance XML payloads."

  @doctype_re ~r/<!DOCTYPE/i
  @external_entity_re ~r/<!ENTITY\b[^>]*\b(SYSTEM|PUBLIC)\b[^>]*>/i

  def preview(xml_binary_or_string)
      when is_binary(xml_binary_or_string) or is_list(xml_binary_or_string) do
    xml = to_string(xml_binary_or_string)

    with :ok <- validate_xml_safety(xml),
         {:ok, document} <- parse_xml(xml) do
      {:ok, build_preview(document)}
    end
  end

  def preview(_), do: {:error, {:invalid_input, "Expected XML binary or string."}}

  defp validate_xml_safety(xml) when is_binary(xml) do
    cond do
      Regex.match?(@doctype_re, xml) ->
        {:error, {:unsafe_xml, "DOCTYPE declarations are not allowed in preview."}}

      Regex.match?(@external_entity_re, xml) ->
        {:error, {:unsafe_xml, "External entity declarations are not allowed in preview."}}

      true ->
        :ok
    end
  end

  defp validate_xml_safety(_), do: {:error, {:invalid_input, "Expected XML binary or string."}}

  defp parse_xml(xml) when is_binary(xml) do
    try do
      {document, _rest} = :xmerl_scan.string(String.to_charlist(xml), quiet: true)
      {:ok, document}
    catch
      :exit, {:fatal, reason} ->
        {:error, {:invalid_xml, format_parse_error(reason)}}

      kind, reason ->
        {:error, {:invalid_xml, "#{kind}: #{inspect(reason)}"}}
    end
  end

  defp build_preview(document) do
    securities = parse_securities(document)
    accounts = parse_accounts(document)
    portfolios = parse_portfolios(document)
    transactions = parse_transactions(document)
    taxonomies = parse_taxonomies(document)
    categories = parse_categories(document)

    %{
      "securities" => securities,
      "accounts" => accounts,
      "portfolios" => portfolios,
      "transactions" => transactions,
      "taxonomies" => taxonomies,
      "categories" => categories,
      "warnings" => [],
      "counts" => %{
        "securities" => length(securities),
        "accounts" => length(accounts),
        "portfolios" => length(portfolios),
        "transactions" => length(transactions),
        "taxonomies" => length(taxonomies),
        "categories" => length(categories)
      }
    }
  end

  defp parse_securities(document) do
    query(document, "//*[local-name()='security']")
    |> Enum.map(&parse_security/1)
  end

  defp parse_security(node) do
    %{
      "external_id" => node_external_id(node),
      "name" => coalesce([node_attr(node, :name), node_text(node, :name)]),
      "isin" => node_text(node, :isin),
      "ticker" => coalesce([node_text(node, :ticker), node_text(node, :symbol)]),
      "symbol" => node_text(node, :symbol),
      "currency" => coalesce([node_attr(node, :currency), node_text(node, :currency)])
    }
  end

  defp parse_accounts(document) do
    query(document, "//*[local-name()='account']")
    |> Enum.map(&parse_account/1)
  end

  defp parse_account(node) do
    %{
      "external_id" => node_external_id(node),
      "name" => coalesce([node_attr(node, :name), node_text(node, :name)]),
      "currency" => coalesce([node_attr(node, :currency), node_text(node, :currency)]),
      "type" => coalesce([node_attr(node, :type), node_text(node, :type)])
    }
  end

  defp parse_portfolios(document) do
    query(document, "//*[local-name()='portfolio']")
    |> Enum.map(&parse_portfolio/1)
  end

  defp parse_portfolio(node) do
    %{
      "external_id" => node_external_id(node),
      "name" => coalesce([node_attr(node, :name), node_text(node, :name)]),
      "base_currency" =>
        coalesce([
          node_attr(node, :base_currency),
          node_attr(node, :baseCurrency),
          node_text(node, :base_currency),
          node_text(node, :baseCurrency)
        ])
    }
  end

  defp parse_transactions(document) do
    query(document, "//*[local-name()='transaction']")
    |> Enum.map(&parse_transaction/1)
  end

  defp parse_transaction(node) do
    %{
      "external_id" => node_external_id(node),
      "type" => coalesce([node_attr(node, :type), node_text(node, :type)]),
      "date" => coalesce([node_attr(node, :date), node_text(node, :date)]),
      "amount" => coalesce([node_attr(node, :amount), node_text(node, :amount)]),
      "currency" => coalesce([node_attr(node, :currency), node_text(node, :currency)]),
      "security_reference_id" =>
        coalesce([
          node_text(node, :security_ref),
          node_text(node, :securityRef),
          node_text(node, :security_id),
          node_text(node, :securityId)
        ]),
      "account_reference_id" =>
        coalesce([
          node_text(node, :account_ref),
          node_text(node, :accountRef),
          node_text(node, :account_id),
          node_text(node, :accountId)
        ])
    }
  end

  defp parse_taxonomies(document) do
    query(document, "//*[local-name()='taxonomy']")
    |> Enum.map(&parse_taxonomy/1)
  end

  defp parse_taxonomy(node) do
    %{
      "external_id" => node_external_id(node),
      "name" => coalesce([node_attr(node, :name), node_text(node, :name)])
    }
  end

  defp parse_categories(document) do
    by_taxonomy =
      query(document, "//*[local-name()='taxonomy']")
      |> Enum.flat_map(fn taxonomy_node ->
        taxonomy_external_id = node_external_id(taxonomy_node)

        direct = query(taxonomy_node, "./*[local-name()='category']")
        nested = query(taxonomy_node, "./*[local-name()='categories']/*[local-name()='category']")

        (direct ++ nested)
        |> Enum.map(fn category_node ->
          map = parse_category(category_node)
          Map.put(map, "taxonomy_external_id", taxonomy_external_id)
        end)
      end)

    standalone =
      query(
        document,
        "//*[not(ancestor::*[local-name()='taxonomy']) and local-name()='category']"
      )
      |> Enum.map(&parse_category/1)

    (by_taxonomy ++ standalone)
    |> Enum.uniq_by(& &1["external_id"])
  end

  defp parse_category(node) do
    %{
      "external_id" => node_external_id(node),
      "name" => coalesce([node_attr(node, :name), node_text(node, :name)]),
      "taxonomy_external_id" => nil
    }
  end

  defp node_external_id(node) do
    coalesce([
      node_attr(node, :uuid),
      node_attr(node, :id),
      node_attr(node, :externalId),
      node_attr(node, :external_id)
    ])
  end

  defp node_attr(node, attr_name) when is_atom(attr_name) do
    case xml_attributes(node) do
      nil ->
        nil

      attrs ->
        case :xmerl_lib.find_attribute(attr_name, attrs) do
          {:value, value} ->
            String.trim(to_string(value))

          false ->
            nil
        end
    end
  end

  defp node_text(node, field_name) when is_atom(field_name) do
    path = "./*[local-name()='#{field_name}']/text()"

    case query(node, path) do
      [first | _] ->
        xml_text_to_string(first)

      _ ->
        nil
    end
  end

  defp xml_attributes(
         {:xmlElement, _kind, _name, _expanded, _namespace, _parents, _line, attrs, _content,
          _content2, _path, _undeclared}
       ),
       do: attrs

  defp xml_attributes(_), do: nil

  defp xml_text_to_string({:xmlText, _p1, _p2, _p3, text, _p4}) when is_list(text) do
    text
    |> to_string()
    |> String.trim()
  end

  defp xml_text_to_string(_), do: nil

  defp coalesce([]), do: nil
  defp coalesce([value | tail]), do: if(is_nil(value), do: coalesce(tail), else: value)

  defp query(node, path) when is_binary(path), do: query(node, String.to_charlist(path))
  defp query(node, path) when is_list(path), do: :xmerl_xpath.string(path, node)

  defp format_parse_error(reason) do
    inspect(reason)
  end
end
