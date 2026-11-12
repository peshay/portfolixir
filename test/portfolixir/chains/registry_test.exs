defmodule Portfolixir.Chains.RegistryTest do
  # ADR-0059 §2 (Sprint 29 H1, FR-58, idea I12): the chains the app knows,
  # as protocol constants in code, never detected and never rows.
  use ExUnit.Case, async: true

  alias Portfolixir.Chains.Registry

  # User story (ADR-0059 §2):
  # As the operator who binds a coin to its block chain,
  # I want the chains the app knows to carry the subsidy halving interval and
  # the target block spacing their consensus rules state, fixed in code,
  # so that one mistyped digit can never produce a wrong cycle.
  #
  # Acceptance criteria:
  # - Bitcoin and Bitcoin Cash halve every 210,000 blocks at a 600-second
  #   target, Litecoin every 840,000 blocks at 150 seconds.
  # - Zcash, Ethereum and every other name are not registered.
  # - Only Bitcoin has a source (ADR-0059 §3), with the public genesis hash.
  # - Halving k is the block at k times the interval, k >= 1.
  test "registers three chains with their protocol constants" do
    assert Registry.chains() == [:bitcoin, :bitcoin_cash, :litecoin]
    assert Registry.names() == ["bitcoin", "bitcoin_cash", "litecoin"]

    assert Registry.halving_interval(:bitcoin) == 210_000
    assert Registry.target_spacing(:bitcoin) == 600
    assert Registry.halving_interval(:bitcoin_cash) == 210_000
    assert Registry.target_spacing(:bitcoin_cash) == 600
    assert Registry.halving_interval(:litecoin) == 840_000
    assert Registry.target_spacing(:litecoin) == 150

    assert Registry.has_source?(:bitcoin)
    refute Registry.has_source?(:bitcoin_cash)
    refute Registry.has_source?(:litecoin)

    assert Registry.genesis_hash(:bitcoin) ==
             "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"

    assert Registry.genesis_hash(:litecoin) == nil

    for name <- ["zcash", "ethereum", "Bitcoin", " bitcoin", "", "dogecoin"] do
      assert Registry.fetch(name) == :error, name
    end

    assert Registry.fetch("bitcoin") == {:ok, :bitcoin}
    assert Registry.fetch(:litecoin) == {:ok, :litecoin}
    assert Registry.fetch(:zcash) == :error

    assert Registry.halving_height?(:bitcoin, 840_000)
    assert Registry.halving_height?(:litecoin, 840_000)
    refute Registry.halving_height?(:litecoin, 420_000)
    refute Registry.halving_height?(:bitcoin, 0)
    refute Registry.halving_height?(:bitcoin, -210_000)
    refute Registry.halving_height?(:bitcoin, 210_001)
  end

  # User story (AGENTS.md: never an atom from external input):
  # As the operator whose instance reads a chain name from any caller,
  # I want an unknown name refused without becoming an atom,
  # so that input can never fill the atom table.
  #
  # Acceptance criteria:
  # - An unknown name answers :error and exists as no atom afterwards.
  test "maps a name through the known list and never makes an atom" do
    name = "chain_h1_never_an_atom_" <> Integer.to_string(System.unique_integer([:positive]))

    assert Registry.fetch(name) == :error
    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
  end
end
