defmodule Portfolixir.Chains.ReaderOwnUrlTest do
  # Sprint 29, the closing act's security lens on Lane H (finding 2, S2):
  # the operator's own Esplora URL may carry a key in its path (an
  # instance behind a path-token proxy). Before the fix every halving's
  # `source_url` and its journal entry kept that path. The own source's
  # link is now `https://{host}/block/{hash}`: the host alone, never the
  # path (ADR-0059 §3, §5, precision of 2026-11-13). Not async: it sets the
  # adapter's application environment, as config/runtime.exs sets it at
  # boot. Every answer and every name is synthetic.
  use Portfolixir.DataCase, async: false

  import Ecto.Query
  import Portfolixir.EsploraFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Chains
  alias Portfolixir.Chains.Esplora
  alias Portfolixir.Journal.Entry, as: JournalEntry
  alias Portfolixir.Knowledge.SecurityEvent

  @now ~U[2026-11-12 12:00:00Z]
  @tip 870_000
  @secret "k3y-SYNTHETIC-SECRET"

  setup do
    saved = Application.get_env(:portfolixir, Esplora)
    on_exit(fn -> Application.put_env(:portfolixir, Esplora, saved) end)

    Application.put_env(
      :portfolixir,
      Esplora,
      Keyword.put(saved, :own_url, "https://node.example.com/#{@secret}/api")
    )

    :ok
  end

  defp bound! do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Synthetic Coin #{System.unique_integer([:positive])}",
        currency_code: "USD",
        asset_class: "crypto"
      })

    {:ok, bound} =
      Catalog.update_security(Actor.api_token_rw("synthetic-agent"), security, %{
        halving_chain: :bitcoin
      })

    bound
  end

  # User story (ADR-0059 §3, §5):
  # As the operator whose own instance takes a key in its URL's path,
  # I want the halvings' links to name my host and the block, nothing else,
  # so that the key never lands in an event, the journal or an API answer.
  #
  # Acceptance criteria:
  # - Every halving read from the own URL stores
  #   `https://node.example.com/block/{hash}`, the past ones and the
  #   estimate alike.
  # - No journal entry of the run carries the path.
  # - The public sources keep `{base}/block/{hash}`.
  test "the own URL's path is never stored" do
    security = bound!()
    serve(%{"node.example.com" => {:chain, @tip}})

    assert {:ok, %{run: %{status: :ok, host: "node.example.com"}}} =
             Chains.refresh("bitcoin", now: @now)

    events =
      Repo.all(
        from(e in SecurityEvent,
          where: e.security_id == ^security.id,
          order_by: e.chain_height
        )
      )

    assert length(events) == 5

    for event <- events do
      refute event.source_url =~ @secret
      assert event.source_url =~ ~r"\Ahttps://node\.example\.com/block/[0-9a-f]{64}\z"
    end

    assert hd(events).source_url == "https://node.example.com/block/" <> hash(210_000)

    journaled =
      from(j in JournalEntry, where: j.resource_type == "security_event")
      |> Repo.all()
      |> Enum.filter(&(inspect(&1.after) =~ @secret))

    assert journaled == []
  end

  test "the public sources keep their base in the link" do
    Application.put_env(
      :portfolixir,
      Esplora,
      Keyword.delete(Application.get_env(:portfolixir, Esplora), :own_url)
    )

    security = bound!()
    serve(%{"mempool.space" => {:chain, @tip}})
    assert {:ok, %{run: %{status: :ok}}} = Chains.refresh("bitcoin", now: @now)

    event =
      Repo.one!(
        from(e in SecurityEvent,
          where: e.security_id == ^security.id and e.chain_height == 210_000
        )
      )

    assert event.source_url == "https://mempool.space/api/block/" <> hash(210_000)
  end
end
