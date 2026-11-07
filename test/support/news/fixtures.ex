defmodule Portfolixir.NewsFixtures do
  @moduledoc """
  Synthetic news feeds for the fetcher's, the ingest's and the scheduler's
  tests (Sprint 27, N3): a feed row written past the context (the context's
  registration write is N8's), and RSS 2.0 bodies built from plain maps.
  Every host is a synthetic name the test resolver answers for.
  """

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.News.Feed
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  @doc "A security to bind an issuer or regulatory feed to."
  def security!(name \\ "Northwind Harbour Logistics AG"),
    do: WorldFixtures.create_security!(name: name, ticker: nil, asset_class: "equity")

  @doc "A category to bind a thematic feed to."
  def category! do
    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{
        name: "Themes #{System.unique_integer([:positive])}"
      })

    {:ok, category} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Water"
      })

    category
  end

  @doc """
  A feed. Feeds are journal-armed (B7) and their registering writer is a
  later story's, so this names an actor for the guard and inserts the row.
  """
  def feed!(attrs) do
    Repo.query!("SELECT set_config('portfolixir.journal_actor', 'synthetic-fetcher-test', true)")

    attrs =
      Map.merge(
        %{
          url: "https://newsroom.example.com/feed-#{System.unique_integer([:positive])}.xml",
          language: "en"
        },
        attrs
      )

    %Feed{} |> Feed.changeset(attrs) |> Repo.insert!()
  end

  @doc "An RSS 2.0 body with one `<item>` per map (`:title`, `:link`, `:pub`, `:source`)."
  def rss(items) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0"><channel><title>Synthetic</title><link>https://wire.example.com/</link>
    <description>synthetic</description>
    #{Enum.map_join(items, "\n", &rss_item/1)}
    </channel></rss>
    """
  end

  defp rss_item(item) do
    [
      "<item>",
      tag("title", item[:title]),
      tag("link", item[:link]),
      item[:pub] && tag("pubDate", Calendar.strftime(item[:pub], "%a, %d %b %Y %H:%M:%S GMT")),
      item[:source] && ~s(<source url="#{item[:source]}">Source</source>),
      "</item>"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join()
  end

  defp tag(_name, nil), do: nil
  defp tag(name, value), do: "<#{name}>#{value}</#{name}>"
end

defmodule Portfolixir.News.NoNetwork do
  @moduledoc """
  The news fetcher's default adapter in the test configuration: every
  request a test did not stub answers as a refused connection, through
  Req's plug path, so no fetch in the suite opens a socket.
  """
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts), do: Req.Test.transport_error(conn, :econnrefused)
end
