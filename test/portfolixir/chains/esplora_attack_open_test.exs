defmodule Portfolixir.Chains.EsploraAttackOpenConfigTest do
  # F5: the adapter narrows `:any` to the base's host for every source key,
  # not only `:own`, so a config source with `:any` reaches its base's host.
  use ExUnit.Case, async: false

  import Portfolixir.EsploraFixtures

  alias Portfolixir.Chains.Esplora

  test "only the own URL may carry :any; another source with :any reaches nothing" do
    saved = Application.get_env(:portfolixir, Esplora)
    on_exit(fn -> Application.put_env(:portfolixir, Esplora, saved) end)

    Application.put_env(
      :portfolixir,
      Esplora,
      Keyword.merge(saved,
        sources: [extra: "https://api.llm-vendor.example/v1"],
        allowed_hosts: Map.put(saved[:allowed_hosts], :extra, :any)
      )
    )

    serve(%{"api.llm-vendor.example" => {:chain, 870_000}})

    assert {:error, [%{source: :extra, error: "url_not_allowed:host_not_allowed"}]} =
             Esplora.read(&[&1], now: ~U[2026-11-12 12:00:00Z])
  end

  test "a config source named :own raises: the own source is the environment's URL alone" do
    saved = Application.get_env(:portfolixir, Esplora)
    on_exit(fn -> Application.put_env(:portfolixir, Esplora, saved) end)

    Application.put_env(
      :portfolixir,
      Esplora,
      Keyword.put(saved, :sources, own: "https://api.llm-vendor.example/v1")
    )

    serve(%{"api.llm-vendor.example" => {:chain, 870_000}})

    assert_raise ArgumentError, fn -> Esplora.read(&[&1], now: ~U[2026-11-12 12:00:00Z]) end
    refute_received {:esplora, _, _}
  end
end
