defmodule Portfolixir.News.DeleteSecurityTest do
  # Closing act, EDGE2 (ADR-0056 §2, B3; ADR-0050 §11): what a security's
  # delete does with the ambiguous items that list it. Synthetic securities,
  # aliases and hosts only.
  use Portfolixir.DataCase, async: true

  import Ecto.Query
  import Portfolixir.NewsFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.Repo

  defp watched!(name, token) do
    security = security!(name)

    {:ok, security} =
      Catalog.update_security(Actor.owner_ui(), security, %{
        news_watch: true,
        news_aliases: [%{token: token, context: [], case: "sensitive"}]
      })

    security
  end

  defp item(n), do: Repo.get_by!(Item, canonical_url: "https://wire.example.com/n/#{n}")

  # User story (closing act, EDGE2):
  # As the agent that resolves ambiguous items,
  # I want a deleted security to leave the candidates of every item that
  # listed it,
  # so that no item stays ambiguous between a security and an id that
  # answers 404.
  #
  # Acceptance criteria:
  # - Deleting a security drops its id from every item's candidates, in the
  #   delete's transaction.
  # - An item left with one candidate is assigned to it, out of the
  #   ambiguous queue, and folded into that security's stories, as a
  #   merge's collapse assigns it.
  # - An item left with two or more stays ambiguous between them.
  test "a deleted security leaves every item's candidates" do
    alpha = watched!("Alphaport Holdings AG", "Alphaport")
    beta = watched!("Betaline Shipping AG", "Betaline")
    gamma = watched!("Gammaway Freight AG", "Gammaway")
    feed = feed!(%{class: "aggregator"})
    now = DateTime.utc_now()

    items = [
      %Parsed{
        title: "Alphaport and Betaline agree to merge",
        link: "https://wire.example.com/n/1",
        source_domain: "wire.example.com"
      },
      %Parsed{
        title: "Alphaport, Betaline and Gammaway form a pool",
        link: "https://wire.example.com/n/2",
        source_domain: "wire.example.com"
      }
    ]

    assert {:ok, %{stored: 2}} = Ingest.ingest(feed, items, now)
    assert %{assignment: :ambiguous} = item(1)
    assert Enum.sort(item(2).candidates) == Enum.sort([alpha.id, beta.id, gamma.id])

    assert {:ok, _deleted} = Catalog.delete_security(Actor.owner_ui(), beta)

    one = item(1)
    assert one.assignment == :assigned
    assert one.security_id == alpha.id
    assert one.candidates == []
    assert one.cluster_id, "the assigned item is folded into a story"

    two = item(2)
    assert two.assignment == :ambiguous
    assert Enum.sort(two.candidates) == Enum.sort([alpha.id, gamma.id])

    refute Repo.exists?(from(i in Item, where: ^beta.id in i.candidates))
  end
end
