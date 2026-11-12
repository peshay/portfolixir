defmodule Portfolixir.Chains.ChainReadTest do
  # The chain's state row (ADR-0059 §8, §9) meets the writers' rules: the
  # input sweeps (test/portfolixir/input/text_sweep_test.exs,
  # bounded_date_sweep_test.exs) read its changeset, and this test pins
  # what that changeset refuses. Synthetic hosts only.
  use ExUnit.Case, async: true

  alias Portfolixir.Chains.ChainRead
  alias Portfolixir.Input.BoundedDate

  # User story (Sprint 29 H3, the input sweeps):
  # As the operator whose instance stores what a chain source answered,
  # I want the state row checked like every other row a writer stores,
  # so that a name outside the registry, a date out of range or text with
  # a control character never reaches the database.
  #
  # Acceptance criteria:
  # - A chain outside the registry is refused; a registered one passes.
  # - A genesis check day outside the bounded range is refused.
  # - The host and the error are one-line text within their columns.
  test "the state row's changeset refuses what the writers' rules refuse" do
    ok = %{chain: "bitcoin", source_host: "esplora.example", genesis_checked_on: ~D[2026-11-13]}
    assert ChainRead.changeset(%ChainRead{}, ok).valid?

    refute ChainRead.changeset(%ChainRead{}, %{ok | chain: "zcash"}).valid?

    too_early = ChainRead.changeset(%ChainRead{}, %{ok | genesis_checked_on: ~D[1899-12-31]})
    assert {message, _} = too_early.errors[:genesis_checked_on]
    assert message == BoundedDate.message()

    refute ChainRead.changeset(%ChainRead{}, Map.put(ok, :last_error, "bad\nanswer")).valid?

    refute ChainRead.changeset(%ChainRead{}, Map.put(ok, :last_error, String.duplicate("x", 513))).valid?

    refute ChainRead.changeset(%ChainRead{}, %{ok | source_host: String.duplicate("h", 256)}).valid?
  end
end
