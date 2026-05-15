defmodule Portfolixir.Catalog.SecuritySearchTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Catalog.SecuritySearch
  alias Portfolixir.Catalog.SecuritySearch.SearchResult

  test "returns empty list for blank queries without invoking providers" do
    assert {:ok, []} = SecuritySearch.search("")
    assert {:ok, []} = SecuritySearch.search("   ")
    assert {:ok, []} = SecuritySearch.search(nil)
  end

  test "returns canned Fake results for known queries" do
    {:ok, [hit]} = SecuritySearch.search("apple")
    assert %SearchResult{provider: :portfolio_performance, isin: "US0378331005"} = hit
  end

  test "merges results from multiple providers and dedupes by provider+online_id" do
    first = %SearchResult{
      provider: :portfolio_performance,
      online_id: "x",
      name: "First"
    }

    second = %SearchResult{
      provider: :portfolio_performance,
      online_id: "x",
      name: "Duplicate"
    }

    third = %SearchResult{provider: :coingecko, online_id: "y", name: "Third"}

    provider_a = make_stub_module([first])
    provider_b = make_stub_module([second, third])

    {:ok, results} =
      SecuritySearch.search("anything",
        providers: [provider_a, provider_b],
        timeout_ms: 500
      )

    online_ids = Enum.map(results, & &1.online_id)
    assert "x" in online_ids
    assert "y" in online_ids
    assert length(results) == 2
  end

  test "isolates a crashing provider" do
    crashing = make_crash_module()
    healthy = make_stub_module([%SearchResult{provider: :coingecko, online_id: "ok", name: "Ok"}])

    {:ok, results} =
      SecuritySearch.search("anything",
        providers: [crashing, healthy],
        timeout_ms: 500
      )

    assert [%SearchResult{online_id: "ok"}] = results
  end

  # ---- helpers ------------------------------------------------------------

  defp make_stub_module(results) do
    name = String.to_atom("Stub#{System.unique_integer([:positive])}")

    Module.create(
      name,
      quote do
        @behaviour Portfolixir.Catalog.SecuritySearch.Provider

        @impl true
        def id, do: :stub

        @impl true
        def search(_query, _opts), do: {:ok, unquote(Macro.escape(results))}
      end,
      Macro.Env.location(__ENV__)
    )

    name
  end

  defp make_crash_module do
    name = String.to_atom("Crashy#{System.unique_integer([:positive])}")

    Module.create(
      name,
      quote do
        @behaviour Portfolixir.Catalog.SecuritySearch.Provider

        @impl true
        def id, do: :crashy

        @impl true
        def search(_query, _opts), do: raise("boom")
      end,
      Macro.Env.location(__ENV__)
    )

    name
  end
end
