defmodule Portfolixir.Ledger.KindProseSyncTest do
  # Issue #686 pin: the root cause of the tax_refund discoverability failure
  # was a hand-maintained prose kind-list drifting from the schema. These
  # tests hold every prose list — the MCP tool descriptions and the API
  # documentation (EN + DE) — against `Transaction.kinds/0`, so the next kind
  # cannot go missing the same way.
  use ExUnit.Case, async: true

  alias Portfolixir.Ledger.Transaction

  # `balance_adjustment` is owned by the dedicated set_balance surface and
  # `split` by the dedicated split flow; every other kind is bookable through
  # the generic create surface and must be named where kinds are enumerated.
  @non_generic_kinds ["balance_adjustment", "split"]

  defp bookable_kinds, do: Transaction.kinds() -- @non_generic_kinds

  defp read!(relative), do: File.read!(Path.join(File.cwd!(), relative))

  # User story (issue #686):
  # As the operating LLM agent reading the MCP tool schemas,
  # I want the transactions.create description to name every bookable kind,
  # including in its direction enumeration the kind that credits a refund,
  # so that no ledger capability is undiscoverable from the tool surface.
  #
  # Acceptance criteria:
  # - Every kind in Transaction.kinds/0 except balance_adjustment/split is
  #   named in the transactions.create tool description.
  # - The direction enumeration reaches tax_refund on the credit side.
  # - The reconcile repair list names tax_refund.
  test "the MCP transactions.create description names every bookable kind" do
    tools_source = read!("mcp-server/src/tools.ts")

    [description] =
      Regex.run(
        ~r/"portfolixir\.transactions\.create", "Create transaction", "((?:[^"\\]|\\.)*)"/,
        tools_source,
        capture: :all_but_first
      )

    for kind <- bookable_kinds() do
      assert description =~ kind,
             "mcp-server/src/tools.ts: transactions.create description no longer names #{kind}"
    end

    # The direction enumeration credits tax_refund (gap D2).
    assert description =~ "deposit/dividend/interest/tax_refund credit"
  end

  test "the MCP holdings.reconcile repair list names tax_refund" do
    tools_source = read!("mcp-server/src/tools.ts")

    [description] =
      Regex.run(
        ~r/"portfolixir\.holdings\.reconcile",[^"]*"[^"]*",\s*"((?:[^"\\]|\\.)*)"/,
        tools_source,
        capture: :all_but_first
      )

    assert description =~ "tax_refund",
           "mcp-server/src/tools.ts: holdings.reconcile repair guidance no longer names tax_refund"
  end

  # User story (issue #686, gap D4):
  # As a maintainer or agent reading the API documentation,
  # I want the transactions documentation (EN and DE) to name every bookable
  # kind by its literal type value,
  # so that there is a page a human or an agent can be pointed at for any
  # kind — tax_refund included.
  #
  # Acceptance criteria:
  # - docs/integration/api-and-mcp.md names every bookable kind verbatim.
  # - The DE variant does too (type values are not translated).
  for doc <- ["docs/integration/api-and-mcp.md", "docs/de/integration/api-and-mcp.md"] do
    test "#{doc} names every bookable kind" do
      content = read!(unquote(doc))

      for kind <- bookable_kinds() do
        assert content =~ "`#{kind}`",
               "#{unquote(doc)} no longer names the bookable kind `#{kind}`"
      end
    end
  end
end
