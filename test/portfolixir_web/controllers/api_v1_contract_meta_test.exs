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

  # User story (#1024):
  # As the operating agent that read the companion's prompts at connect time,
  # I want the manifest to name every MCP prompt the companion offers, as it
  # names every tool,
  # so that a prompt added, renamed or removed without an entry fails the
  # build instead of changing what my agent is told unannounced.
  #
  # Acceptance criteria:
  # - The union of the manifest's prompts, removals applied, equals the
  #   companion's prompt inventory (PROMPTS in mcp-server/src/prompts.ts)
  #   exactly, in both directions.
  # - Sprint 17's entry (version 9), which introduced first_setup and
  #   import_converter, names both; every entry carries both lists.
  test "the manifest's prompts are exactly the MCP companion's prompt inventory" do
    source = File.read!("mcp-server/src/prompts.ts")
    [prompts] = Regex.run(~r/^export const PROMPTS: Prompt\[\] = \[$.*?^\];$/ms, source)

    # A prompt's own name sits four spaces in; an argument's name eight.
    companion =
      ~r/^ {4}name: "([a-z0-9_]+)",$/m
      |> Regex.scan(prompts, capture: :all_but_first)
      |> List.flatten()
      |> MapSet.new()

    assert MapSet.size(companion) > 0, "no prompt found in mcp-server/src/prompts.ts"

    manifest = Contract.prompts()

    assert MapSet.difference(companion, manifest) |> Enum.sort() == [],
           "MCP prompts without a manifest entry — add them to the newest Contract entry:\n" <>
             Enum.join(MapSet.difference(companion, manifest), "\n")

    assert MapSet.difference(manifest, companion) |> Enum.sort() == [],
           "manifest prompts the companion no longer offers — record the removal:\n" <>
             Enum.join(MapSet.difference(manifest, companion), "\n")

    sprint17 = Enum.find(Contract.entries(), &(&1.version == 9))
    assert sprint17.prompts == ["first_setup", "import_converter"]

    for entry <- Contract.entries() do
      assert is_list(entry.prompts), "entry #{entry.version} has no prompts list"
      assert is_list(entry.removed_prompts), "entry #{entry.version} has no removed_prompts list"
    end
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
