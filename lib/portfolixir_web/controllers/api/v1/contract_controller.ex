defmodule PortfolixirWeb.Api.V1.ContractController do
  @moduledoc """
  `GET /api/v1/contract` (ADR-0044 §8, issue #752): the contract-version read.

  Answers `version`, `last_changed_at`, the current endpoint and tool counts,
  and the manifest entries newest first. `?since=YYYY-MM-DD` narrows the
  entries to those dated strictly after that day and answers `changed` — the
  `?since=` idea applied to the contract instead of the rows, so an agent that
  cached its tool descriptions at connect time can notice a change with one
  cheap poll.
  """
  use PortfolixirWeb, :controller

  alias PortfolixirWeb.Api.V1.Contract
  alias PortfolixirWeb.Api.V1.JSON

  def show(conn, params) do
    case since_param(params) do
      {:ok, nil} ->
        json(conn, %{data: payload(Contract.entries(), nil)})

      {:ok, %Date{} = since} ->
        json(conn, %{data: payload(Contract.entries_since(since), since)})

      :error ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{since: ["is invalid"]}})
    end
  end

  defp payload(entries, since) do
    %{
      version: Contract.version(),
      last_changed_at: JSON.date(Contract.last_changed_at()),
      since: JSON.date(since),
      changed: entries != [],
      endpoints_total: MapSet.size(Contract.endpoints()),
      tools_total: MapSet.size(Contract.tools()),
      entries: Enum.map(entries, &entry/1),
      contract_note:
        "A code-maintained manifest of the API and MCP surface: each entry names the endpoints, " <>
          "tools and parameters a change touched. A meta-test ties the router and the MCP tool " <>
          "inventory to it, so the surface cannot change without an entry. Poll with " <>
          "since=<last_changed_at you stored> and re-read the tool descriptions when changed is true."
    }
  end

  defp entry(entry) do
    %{
      version: entry.version,
      date: JSON.date(entry.date),
      summary: entry.summary,
      endpoints: entry.endpoints,
      tools: entry.tools,
      parameters: entry.parameters,
      removed_endpoints: entry.removed_endpoints,
      removed_tools: entry.removed_tools
    }
  end

  defp since_param(params) do
    case Map.get(params, "since") do
      nil -> {:ok, nil}
      "" -> {:ok, nil}
      value when is_binary(value) -> parse_date(value)
      _ -> :error
    end
  end

  defp parse_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> :error
    end
  end
end
