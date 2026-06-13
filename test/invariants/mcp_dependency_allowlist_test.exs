defmodule Portfolixir.Invariants.McpDependencyAllowlistTest do
  use ExUnit.Case, async: true

  # User story:
  # As a maintainer keeping the MCP companion thin,
  # I want a meta-test that fails when the MCP server gains a dependency
  # outside an explicit allowlist or any database driver,
  # so that ADR-0002 (thin MCP over the JSON API) cannot be regressed by a
  # dependency that bypasses the API to reach data directly.
  #
  # Acceptance criteria:
  # - mcp-server runtime dependencies are a subset of an explicit allowlist.
  # - mcp-server devDependencies are a subset of an explicit allowlist.
  # - No dependency (runtime or dev) matches a known database / ORM / direct
  #   data-access driver pattern.

  # The MCP server may only depend on the MCP SDK, its HTTP layer, and schema
  # validation. Anything that reaches data must go through the JSON API, so a
  # new dependency here is a deliberate decision that must extend this list.
  @runtime_allowlist MapSet.new([
                       "@modelcontextprotocol/sdk",
                       "express",
                       "zod"
                     ])

  @dev_allowlist MapSet.new([
                   "@types/express",
                   "@types/node",
                   "tsx",
                   "typescript"
                 ])

  # Substrings that flag a database driver, ORM, query builder, or other
  # direct data-access library. Matched case-insensitively against package
  # names with their scope stripped.
  @forbidden_fragments ~w(
    pg postgres postgresql mysql mariadb sqlite sqlite3 mssql tedious oracledb
    mongo mongodb mongoose redis ioredis cassandra
    ecto knex prisma typeorm sequelize objection drizzle kysely mikro-orm bookshelf
  )

  setup do
    package = "mcp-server/package.json" |> File.read!() |> Jason.decode!()
    {:ok, package: package}
  end

  test "runtime dependencies stay within the allowlist", %{package: package} do
    deps = package |> Map.get("dependencies", %{}) |> Map.keys()
    extra = Enum.reject(deps, &MapSet.member?(@runtime_allowlist, &1))

    assert extra == [],
           "Unlisted MCP runtime dependencies (extend @runtime_allowlist only " <>
             "if they still go through the JSON API, ADR-0002): #{inspect(extra)}"
  end

  test "dev dependencies stay within the allowlist", %{package: package} do
    deps = package |> Map.get("devDependencies", %{}) |> Map.keys()
    extra = Enum.reject(deps, &MapSet.member?(@dev_allowlist, &1))

    assert extra == [],
           "Unlisted MCP dev dependencies (extend @dev_allowlist deliberately): #{inspect(extra)}"
  end

  test "no dependency is a database driver or ORM", %{package: package} do
    deps =
      package
      |> Map.take(["dependencies", "devDependencies"])
      |> Map.values()
      |> Enum.flat_map(&Map.keys/1)

    offenders = Enum.filter(deps, &data_access_driver?/1)

    assert offenders == [],
           "MCP must not depend on DB drivers / ORMs (ADR-0002): #{inspect(offenders)}"
  end

  # A name is a driver when one of its dot/slash-delimited segments equals a
  # forbidden fragment. Segment matching avoids false positives such as
  # "express" containing "pg" only as a substring.
  defp data_access_driver?(name) do
    name
    |> String.replace(~r{^@[^/]+/}, "")
    |> String.downcase()
    |> String.split(~r{[-./@]})
    |> Enum.any?(&(&1 in @forbidden_fragments))
  end
end
