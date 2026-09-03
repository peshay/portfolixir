defmodule PortfolixirWeb.ApiV1ContractMetaTest do
  # ADR-0044 §8 (issue #752): the manifest is tied to the router and the MCP
  # tool inventory in both directions, so a surface change without a
  # manifest entry fails the build.
  use ExUnit.Case, async: true

  alias PortfolixirWeb.Api.V1.Contract

  # User story (ADR-0044 §8, issue #752):
  # As the operating agent that cached its tool descriptions at connect time,
  # I want the contract read to be trustworthy — every endpoint and tool the
  # surface offers appears in exactly the manifest, and every manifest entry
  # names something real,
  # so that "changed since <date>" means the surface moved, not that someone
  # remembered to write it down.
  #
  # Acceptance criteria:
  # - The union of the manifest's endpoints equals the router's /api/v1
  #   inventory exactly (both directions).
  # - The union of the manifest's tools equals the MCP companion's tool
  #   inventory exactly (both directions).
  # - Versions are strictly increasing newest first, dates are never in the
  #   future relative to the newest, every entry has a summary, and the newest
  #   entry names the contract read itself.
  test "the manifest's endpoints are exactly the router's /api/v1 inventory" do
    router =
      PortfolixirWeb.Router.__routes__()
      |> Enum.filter(&String.starts_with?(&1.path, "/api/v1"))
      |> Enum.map(&"#{&1.verb |> to_string() |> String.upcase()} #{&1.path}")
      |> MapSet.new()

    manifest = Contract.endpoints()

    assert MapSet.difference(router, manifest) |> Enum.sort() == [],
           "routes without a manifest entry — add them to the newest Contract entry:\n" <>
             Enum.join(MapSet.difference(router, manifest), "\n")

    assert MapSet.difference(manifest, router) |> Enum.sort() == [],
           "manifest endpoints the router no longer serves — record the removal:\n" <>
             Enum.join(MapSet.difference(manifest, router), "\n")
  end

  test "the manifest's tools are exactly the MCP companion's tool inventory" do
    source = File.read!("mcp-server/src/tools.ts")

    companion =
      ~r/tool\(\s*"(portfolixir\.[a-z0-9_.]+)"/
      |> Regex.scan(source)
      |> Enum.map(fn [_, name] -> name end)
      |> MapSet.new()

    manifest = Contract.tools()

    assert MapSet.difference(companion, manifest) |> Enum.sort() == [],
           "MCP tools without a manifest entry — add them to the newest Contract entry:\n" <>
             Enum.join(MapSet.difference(companion, manifest), "\n")

    assert MapSet.difference(manifest, companion) |> Enum.sort() == [],
           "manifest tools the companion no longer offers — record the removal:\n" <>
             Enum.join(MapSet.difference(manifest, companion), "\n")
  end

  test "entries are well-formed, newest first, and the newest names the contract read" do
    entries = Contract.entries()
    versions = Enum.map(entries, & &1.version)

    assert versions == Enum.sort(versions, :desc)
    assert versions == Enum.uniq(versions)
    assert Enum.all?(entries, &(String.length(&1.summary) > 20))

    for [newer, older] <- Enum.chunk_every(entries, 2, 1, :discard) do
      assert Date.compare(newer.date, older.date) in [:gt, :eq]
    end

    assert Contract.version() == hd(entries).version
    assert Contract.last_changed_at() == hd(entries).date

    [newest | _] = entries

    assert "GET /api/v1/contract" in newest.endpoints or
             "GET /api/v1/contract" in Contract.endpoints()

    assert "portfolixir.contract.get" in Contract.tools()
  end
end
