defmodule Portfolixir.NewsFixtures do
  @moduledoc """
  Synthetic news feeds for the fetcher's, the ingest's and the scheduler's
  tests (Sprint 27, N3): a feed row written past the context (the context's
  registration write is N8's), and RSS 2.0 bodies built from plain maps.
  Every host is a synthetic name the test resolver answers for.
  """

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.News
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Feed
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
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

  @doc """
  Answers the news fetcher's requests with `plug` for this test and the
  processes it starts (`Portfolixir.News.NoNetwork`). A process the test
  did not start, such as a supervised scheduler, needs
  `Req.Test.allow(Portfolixir.News.Fetcher, self(), pid)`.
  """
  def serve(plug), do: Req.Test.stub(Portfolixir.News.Fetcher, plug)

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

  # --- S28 N1 begin ---

  @doc """
  A story of `security`: one item of a new issuer feed of it, stored through
  the ingest at `at` (default now), answered as its
  `Portfolixir.News.Cluster`. Options: `:title`, `:link`, `:excerpt`, `:at`,
  `:feed` (an existing feed of the security instead of a new one).
  """
  def story!(security, opts \\ []) do
    n = System.unique_integer([:positive])

    feed =
      Keyword.get_lazy(opts, :feed, fn -> feed!(%{class: "issuer", security_id: security.id}) end)

    link = Keyword.get(opts, :link, "https://ir.example.com/release-#{n}")

    item = %Parsed{
      title: Keyword.get(opts, :title, "Northwind Harbour release #{n}"),
      link: link,
      excerpt: Keyword.get(opts, :excerpt)
    }

    at = Keyword.get_lazy(opts, :at, fn -> DateTime.utc_now() end)
    {:ok, %{stored: 1}} = Ingest.ingest(feed, [item], at)
    %Item{cluster_id: cluster_id} = Repo.get_by!(Item, canonical_url: link, feed_id: feed.id)
    Repo.get!(Cluster, cluster_id)
  end

  # --- S28 N1 end ---

  # --- S28 N2 begin ---

  @doc """
  A label of the story `cluster_id`, written through the one write
  (`Portfolixir.News.put_label/2`) under a labeller's token: model
  `synthetic-model-1`, prompt version `v1`, event type `earnings`,
  materiality 2, tone 0 and confidence `"0.8"` unless `opts` names
  others (as keyword keys of §7's fields). Answers the stored label.
  """
  def label!(cluster_id, opts \\ []) do
    attrs =
      Map.merge(
        %{
          "cluster_id" => cluster_id,
          "model" => "synthetic-model-1",
          "prompt_version" => "v1",
          "event_type" => "earnings",
          "materiality" => 2,
          "tone" => 0,
          "confidence" => "0.8"
        },
        Map.new(opts, fn {key, value} -> {Atom.to_string(key), value} end)
      )

    {:ok, _written, label} = News.put_label(Actor.api_token_rw("labeller"), attrs)
    label
  end

  # --- S28 N2 end ---
end

defmodule Portfolixir.News.NoNetwork do
  @moduledoc """
  The news fetcher's adapter in the test configuration, the one plug the
  fetcher merges (closing act, SEC1: no caller hands it request options).
  A test answers its fetches with `Portfolixir.NewsFixtures.serve/1`, a
  `Req.Test` stub owned by the test and seen by the tasks it starts; every
  request no test stubbed answers as a refused connection, through Req's
  plug path, so no fetch in the suite opens a socket.
  """
  @behaviour Plug

  @stub Portfolixir.News.Fetcher

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case stub() do
      nil -> Req.Test.transport_error(conn, :econnrefused)
      fun when is_function(fun, 1) -> fun.(conn)
      fun when is_function(fun, 2) -> fun.(conn, [])
      module when is_atom(module) -> module.call(conn, module.init([]))
      {module, opts} -> module.call(conn, module.init(opts))
    end
  end

  defp stub do
    Req.Test.__fetch_plug__(@stub)
  rescue
    RuntimeError -> nil
  end
end
