defmodule Portfolixir.McpAgentSurfaceDocsTest do
  # E25 S7 (#892), the companion's half: what the MCP companion tells a host
  # and an agent is stated where the operator reads it, in English and
  # German. The behaviour itself is pinned by the companion's own tests
  # (mcp-server/test/published.test.ts, http.test.ts, tools.test.ts).
  use ExUnit.Case, async: true

  defp assert_fragments(pairs) do
    for {path, fragments} <- pairs do
      doc = path |> File.read!() |> String.replace(~r/\s+/, " ")

      for fragment <- fragments do
        assert doc =~ fragment, "#{path}: #{fragment}"
      end
    end
  end

  # User story (E25 S7, F21):
  # As the operator or the agent reading the MCP reference,
  # I want it to say that the schema a host receives is the tool's own
  # definition and that every call is checked against it first,
  # so that a refused argument is expected and names what was wrong.
  #
  # Acceptance criteria:
  # - The EN and DE MCP pages state the published schema, the check before the
  #   API call, and the bodiless answer of a delete.
  test "the MCP pages state what a host receives from tools/list" do
    assert_fragments([
      {"docs/integration/api-and-mcp.md",
       [
         "The schema a host receives from `tools/list` is each tool's own definition",
         "a refused argument answers a tool error naming the tool and the field",
         "a delete's `204`, is a result without structured content"
       ]},
      {"docs/de/integration/api-and-mcp.md",
       [
         "Das Schema, das ein Host über `tools/list` erhält, ist die Definition des Tools selbst",
         "Ein abgelehntes Argument ergibt einen Tool-Fehler, der Tool und Feld nennt",
         "das `204` eines Löschens, ist ein Ergebnis ohne strukturierten Inhalt"
       ]}
    ])
  end
end
