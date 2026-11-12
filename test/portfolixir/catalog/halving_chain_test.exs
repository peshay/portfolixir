defmodule Portfolixir.Catalog.HalvingChainTest do
  # ADR-0059 §4 (Sprint 29 H1, FR-58): a security is bound to a registered
  # chain by the operator or an agent, through the security's update,
  # journaled, and never by a guess. Every name and identifier is synthetic.
  use Portfolixir.DataCase, async: true

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Journal

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  defp security!(attrs) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(%{name: "Coin H1", currency_code: "EUR", asset_class: "crypto"}, attrs)
      )

    security
  end

  # User story (ADR-0059 §4):
  # As the operator or the agent who knows which chain a coin lives on,
  # I want to bind a security to a registered chain through its update, and
  # to clear the binding again,
  # so that the halvings it gets are the ones of the chain I chose.
  #
  # Acceptance criteria:
  # - halving_chain takes "bitcoin", "bitcoin_cash" or "litecoin" (or the
  #   atom), and nil clears it; each write is one journaled security update
  #   whose before and after name the chain.
  # - An unknown chain ("zcash") is a field error on halving_chain and writes
  #   nothing.
  # - Nothing binds by itself: a security whose provider id is "bitcoin"
  #   stays unbound.
  test "binds, clears and refuses a halving chain, journaled" do
    security = security!(%{provider: "coingecko", online_id: "bitcoin", ticker_symbol: "BTC"})
    assert security.halving_chain == nil

    {:ok, bound} = Catalog.update_security(agent(), security, %{"halving_chain" => "bitcoin"})
    assert bound.halving_chain == :bitcoin

    entry = last_security_entry(security.id)
    assert entry.operation == :update
    assert entry.before["halving_chain"] == nil
    assert entry.after["halving_chain"] == "bitcoin"

    {:ok, rebound} = Catalog.update_security(agent(), bound, %{halving_chain: :litecoin})
    assert rebound.halving_chain == :litecoin

    assert {:error, changeset} =
             Catalog.update_security(agent(), rebound, %{"halving_chain" => "zcash"})

    assert %{halving_chain: ["is not a registered chain"]} = errors_on(changeset)
    assert Catalog.get_security(security.id).halving_chain == :litecoin

    {:ok, cleared} = Catalog.update_security(agent(), rebound, %{"halving_chain" => nil})
    assert cleared.halving_chain == nil
    assert last_security_entry(security.id).after["halving_chain"] == nil
  end

  defp last_security_entry(id) do
    Repo.one!(
      from(e in Journal.Entry,
        where: e.resource_type == "security" and e.resource_id == ^to_string(id),
        order_by: [desc: e.id],
        limit: 1
      )
    )
  end
end
