defmodule PortfolixirWeb.ApiV1NewsWritesTest do
  # ADR-0056 §9, B1, B2, B7 (Sprint 27, N8): the news layer's upkeep writes
  # over the API — a feed registered, changed and removed, a source rated by
  # hand, and a security's news identity and watch flag. Every name resolves
  # through the test resolver; no test opens a socket. The domain it rates
  # is this module's own (`*.writes-test.example.com`), so no other async
  # module's uncommitted rating blocks it (Sprint 28, #1424).
  use PortfolixirWeb.ConnCase

  import Ecto.Query
  import Portfolixir.NewsFixtures, only: [category!: 0, feed!: 1, security!: 0, security!: 1]

  alias Portfolixir.Clock
  alias Portfolixir.Journal
  alias Portfolixir.News.Feed
  alias Portfolixir.News.FeedDay
  alias Portfolixir.News.Item
  alias Portfolixir.News.Source
  alias Portfolixir.News.Sources
  alias Portfolixir.Repo

  @agent_token String.duplicate("a", 40)

  setup %{conn: conn} do
    previous = Application.get_env(:portfolixir, :api_tokens)
    Application.put_env(:portfolixir, :api_tokens, [{"mcp", @agent_token}])
    on_exit(fn -> Application.put_env(:portfolixir, :api_tokens, previous) end)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer " <> @agent_token)

    %{conn: conn}
  end

  defp put_feed(conn, feed), do: put(conn, "/api/v1/news/feeds", Jason.encode!(%{feed: feed}))

  defp entries(resource_type) do
    Journal.list_entries(resource_type: resource_type, limit: 50)
  end

  defp issuer_feed(security, attrs \\ %{}) do
    Map.merge(
      %{
        class: "issuer",
        url: "https://newsroom.example.com/feed-#{System.unique_integer([:positive])}.xml",
        security_id: security.id,
        language: "en"
      },
      attrs
    )
  end

  # User story (ADR-0056 B1, §9):
  # As the agent that keeps the news layer,
  # I want to register a feed through the API, change it and see what is
  # stored, in a compact answer,
  # so that the fetcher has something to fetch without anyone opening the
  # database.
  #
  # Acceptance criteria:
  # - PUT /api/v1/news/feeds with a new URL creates the feed (201): its id,
  #   class, URL, binding, enabled, interval (the class's default when none
  #   is sent) and language; a field that is null is left out.
  # - The same URL again updates that feed (200), and so does `id`, which
  #   may change the URL; keys not sent keep their stored values.
  # - Each write is journaled as `news_feed` under the token's name.
  describe "PUT /api/v1/news/feeds" do
    test "registers a feed, then updates it by URL and by id", %{conn: conn} do
      security = security!()
      url = "https://newsroom.example.com/press.xml"

      created =
        conn
        |> put_feed(%{class: "issuer", url: url, security_id: security.id, language: "en"})
        |> json_response(201)
        |> Map.fetch!("data")

      assert %{
               "class" => "issuer",
               "url" => ^url,
               "enabled" => true,
               "interval_minutes" => 15,
               "language" => "en"
             } = created

      assert created["security_id"] == security.id
      refute Map.has_key?(created, "category_id")

      by_url =
        conn
        |> put_feed(%{url: url, enabled: false, interval_minutes: 30})
        |> json_response(200)
        |> Map.fetch!("data")

      assert by_url["id"] == created["id"]
      assert %{"enabled" => false, "interval_minutes" => 30, "class" => "issuer"} = by_url

      moved_url = "https://newsroom.example.com/moved.xml"

      by_id =
        conn
        |> put_feed(%{id: created["id"], url: moved_url, language: "de"})
        |> json_response(200)
        |> Map.fetch!("data")

      assert %{"url" => ^moved_url, "language" => "de", "enabled" => false} = by_id
      assert Repo.aggregate(Feed, :count) == 1

      assert [update2, update1, create] = entries("news_feed")

      assert {create.operation, update1.operation, update2.operation} ==
               {:create, :update, :update}

      for entry <- [create, update1, update2] do
        assert entry.actor_type == :api_token_rw
        assert entry.actor_label == "mcp"
        assert entry.resource_id == to_string(created["id"])
      end

      assert update2.after["url"] == moved_url
    end

    test "an id that names no feed answers 404 and writes nothing", %{conn: conn} do
      assert conn |> put_feed(%{id: 999_999, enabled: false}) |> json_response(404)
      assert entries("news_feed") == []
    end

    # User story (ADR-0056 B2):
    # As the operator,
    # I want a feed's URL checked with name resolution the moment it is
    # registered,
    # so that a URL that points into my own network is refused before the
    # fetcher ever holds it.
    #
    # Acceptance criteria:
    # - A URL whose name resolves to a private, loopback or link-local
    #   address, a name that does not resolve, http and userinfo answer 422
    #   naming `url` and the reason; nothing is stored or journaled.
    # - A changed URL is checked again; an update that keeps the URL is not
    #   refused for it.
    test "a URL that resolves privately is refused at once with its reason", %{conn: conn} do
      security = security!()

      for {host, reason} <- [
            {"internal.test", "private_address"},
            {"loopback.test", "private_address"},
            {"meta.test", "private_address"},
            {"mixed.test", "private_address"},
            {"unresolvable.test", "unresolvable"}
          ] do
        %{"errors" => %{"url" => [message]}} =
          conn
          |> put_feed(issuer_feed(security, %{url: "https://#{host}/feed.xml"}))
          |> json_response(422)

        assert message =~ "url_not_allowed:#{reason}", host
      end

      %{"errors" => %{"url" => [_shape]}} =
        conn
        |> put_feed(issuer_feed(security, %{url: "http://newsroom.example.com/feed.xml"}))
        |> json_response(422)

      %{"errors" => %{"url" => [_shape]}} =
        conn
        |> put_feed(issuer_feed(security, %{url: "https://u:p@newsroom.example.com/feed.xml"}))
        |> json_response(422)

      assert Repo.aggregate(Feed, :count) == 0
      assert entries("news_feed") == []

      %{"data" => %{"id" => id}} =
        conn |> put_feed(issuer_feed(security)) |> json_response(201)

      %{"errors" => %{"url" => [message]}} =
        conn
        |> put_feed(%{id: id, url: "https://lan.test/feed.xml"})
        |> json_response(422)

      assert message =~ "url_not_allowed:private_address"
      refute Repo.get!(Feed, id).url =~ "lan.test"
    end

    # User story (ADR-0056 §2):
    # As the agent registering feeds,
    # I want the class to decide what a feed is bound to,
    # so that an issuer's feed never lands on a category and an aggregator's
    # never on one security.
    #
    # Acceptance criteria:
    # - issuer and regulatory feeds name a security_id; thematic a
    #   category_id; aggregator neither: anything else is a 422 naming the
    #   field.
    # - An issuer feed of an ETF is allowed (§2: "an issuer feed only where
    #   the fund's provider publishes one"); an aggregator feed binds to
    #   nothing, so there is no ETF to refuse.
    # - The class of a feed with stored items cannot change (its items'
    #   class is the feed's): 422 naming class.
    test "the class decides the binding", %{conn: conn} do
      security = security!()
      category = category!()

      etf =
        security!("Synthetic World Index ETF")
        |> then(&Repo.get!(Portfolixir.Catalog.Security, &1.id))

      {:ok, etf} =
        Portfolixir.Catalog.update_security(Portfolixir.Actor.owner_ui(), etf, %{
          asset_class: "etf"
        })

      %{"errors" => errors} =
        conn
        |> put_feed(%{class: "issuer", url: "https://a.example.com/f.xml", language: "en"})
        |> json_response(422)

      assert Map.has_key?(errors, "security_id")

      %{"errors" => errors} =
        conn
        |> put_feed(%{
          class: "aggregator",
          url: "https://b.example.com/f.xml",
          language: "en",
          security_id: security.id
        })
        |> json_response(422)

      assert Map.has_key?(errors, "security_id")

      %{"errors" => errors} =
        conn
        |> put_feed(%{
          class: "thematic",
          url: "https://c.example.com/f.xml",
          language: "en",
          security_id: security.id
        })
        |> json_response(422)

      assert Map.has_key?(errors, "category_id")

      assert %{"data" => %{"category_id" => category_id, "interval_minutes" => 180} = thematic} =
               conn
               |> put_feed(%{
                 class: "thematic",
                 url: "https://c.example.com/f.xml",
                 language: "en",
                 category_id: category.id
               })
               |> json_response(201)

      assert category_id == category.id
      refute Map.has_key?(thematic, "security_id")

      assert %{"data" => %{"class" => "aggregator"} = aggregator} =
               conn
               |> put_feed(%{
                 class: "aggregator",
                 url: "https://d.example.com/f.xml",
                 language: "en"
               })
               |> json_response(201)

      refute Map.has_key?(aggregator, "security_id")

      assert %{"data" => %{"security_id" => etf_id}} =
               conn |> put_feed(issuer_feed(etf)) |> json_response(201)

      assert etf_id == etf.id

      fed = feed!(%{class: "issuer", security_id: security.id})
      item!(fed)

      %{"errors" => errors} =
        conn
        |> put_feed(%{id: fed.id, class: "regulatory"})
        |> json_response(422)

      assert Map.has_key?(errors, "class")
      assert Repo.get!(Feed, fed.id).class == :issuer
    end

    # User story (ADR-0056 §7's closed schema, applied to every news write):
    # As the operator,
    # I want a write that carries a field it does not take refused by name,
    # so that a misspelt or a system field is never dropped in silence.
    #
    # Acceptance criteria:
    # - An unknown field inside `feed` (a fetcher's field included) and an
    #   unknown key beside it answer 422 naming each; nothing is written.
    # - A `feed` that is not an object answers 422 naming `feed`.
    test "an unknown field is refused with 422 naming it", %{conn: conn} do
      security = security!()

      %{"errors" => errors} =
        conn
        |> put_feed(issuer_feed(security, %{last_ok_at: "2026-11-07T10:00:00Z", colour: "red"}))
        |> json_response(422)

      assert Map.keys(errors) |> Enum.sort() == ["colour", "last_ok_at"]
      assert hd(errors["colour"]) =~ "is unknown"

      %{"errors" => errors} =
        conn
        |> put("/api/v1/news/feeds", Jason.encode!(%{feed: issuer_feed(security), force: true}))
        |> json_response(422)

      assert Map.keys(errors) == ["force"]

      for bad <- ["x", 42, ["x"]] do
        %{"errors" => errors} =
          conn |> put("/api/v1/news/feeds", Jason.encode!(%{feed: bad})) |> json_response(422)

        assert Map.has_key?(errors, "feed")
      end

      assert Repo.aggregate(Feed, :count) == 0
      assert entries("news_feed") == []
    end

    # User story (ADR-0056 §7's closed schema; Sprint 28, N1 attack AT3):
    # As the operator,
    # I want a write's wrapper sent in the query string beside its JSON body
    # refused naming it,
    # so that a field sent there (`?feed[enabled]=false`) is never dropped
    # in silence while the write answers as if it had taken it.
    #
    # Acceptance criteria:
    # - PUT /api/v1/news/feeds?feed[enabled]=false or ?feed=x with a valid
    #   JSON feed, and PUT /api/v1/news/sources?source[tier]=blocked with a
    #   valid JSON source: 422 naming the wrapper; nothing written or
    #   journaled.
    test "a wrapper in the query beside a JSON body is refused naming it", %{conn: conn} do
      security = security!()
      feed = Jason.encode!(%{feed: issuer_feed(security)})

      for query <- ["feed[enabled]=false", "feed=x"] do
        %{"errors" => errors} =
          conn |> put("/api/v1/news/feeds?" <> query, feed) |> json_response(422)

        assert Map.keys(errors) == ["feed"], "?#{query}: #{inspect(errors)}"
      end

      source = Jason.encode!(%{source: %{domain: "a.example.com", tier: "primary"}})

      %{"errors" => errors} =
        conn |> put("/api/v1/news/sources?source[tier]=blocked", source) |> json_response(422)

      assert Map.keys(errors) == ["source"]
      assert Repo.aggregate(Feed, :count) == 0 and Repo.aggregate(Source, :count) == 0
      assert entries("news_feed") == [] and entries("news_source") == []
    end
  end

  # User story (ADR-0056 §9, §12, B7):
  # As the agent that keeps the news layer,
  # I want to remove a feed I no longer want fetched,
  # so that it stops, while what it already brought stays until retention
  # and a promoted item stays for good.
  #
  # Acceptance criteria:
  # - DELETE /api/v1/news/feeds/:id removes the feed and its day counters,
  #   detaches its items (feed_id null, every other field kept) and answers
  #   the id and the count detached.
  # - The delete is journaled as `news_feed` under the token's name; the
  #   items and day rows are not (B7).
  # - A second delete answers 404; any query or body parameter answers 422
  #   naming it, and deletes nothing.
  describe "DELETE /api/v1/news/feeds/:id" do
    test "removes the feed and its days, keeps its items detached", %{conn: conn} do
      security = security!()
      feed = feed!(%{class: "issuer", security_id: security.id})
      other = feed!(%{class: "issuer", security_id: security.id})
      item = item!(feed)
      kept = item!(other)

      Repo.insert!(%FeedDay{feed_id: feed.id, day: Clock.today(), items_stored: 1})
      Repo.insert!(%FeedDay{feed_id: other.id, day: Clock.today(), items_stored: 1})

      %{"errors" => errors} =
        conn |> delete("/api/v1/news/feeds/#{feed.id}?force=true") |> json_response(422)

      assert Map.keys(errors) == ["force"]
      assert Repo.get(Feed, feed.id)

      assert %{"data" => %{"id" => id, "items_detached" => 1}} =
               conn |> delete("/api/v1/news/feeds/#{feed.id}") |> json_response(200)

      assert id == feed.id
      refute Repo.get(Feed, feed.id)

      detached = Repo.get!(Item, item.id)
      assert detached.feed_id == nil
      assert detached.title == item.title
      assert detached.security_id == security.id
      assert Repo.get!(Item, kept.id).feed_id == other.id

      assert Repo.aggregate(from(d in FeedDay, where: d.feed_id == ^feed.id), :count) == 0
      assert Repo.aggregate(from(d in FeedDay, where: d.feed_id == ^other.id), :count) == 1

      assert [%{operation: :delete, actor_label: "mcp", after: nil} = entry] =
               Enum.filter(entries("news_feed"), &(&1.resource_id == to_string(feed.id)))

      assert entry.before["url"] == feed.url
      assert entries("news_item") == []

      assert conn |> delete("/api/v1/news/feeds/#{feed.id}") |> json_response(404)
      assert conn |> delete("/api/v1/news/feeds/abc") |> json_response(404)
    end
  end

  # User story (ADR-0056 §3, §9):
  # As the agent that rates sources,
  # I want to set a domain's tier by hand through the API,
  # so that the next fetch stores its items with that tier and no seed
  # undoes my correction.
  #
  # Acceptance criteria:
  # - PUT /api/v1/news/sources {source: {domain, tier}} stores the domain
  #   normalized with the tier and set_by hand, answers domain, tier and
  #   set_by, and is journaled as `news_source` under the token's name.
  # - A later seed leaves the hand row as it is.
  # - An unknown field, a missing or malformed domain and an unknown tier
  #   answer 422 naming the field.
  describe "PUT /api/v1/news/sources" do
    test "rates a domain by hand, journaled under the token", %{conn: conn} do
      assert %{
               "data" => %{
                 "domain" => "wire.writes-test.example.com",
                 "tier" => "blocked",
                 "set_by" => "hand"
               }
             } =
               conn
               |> put(
                 "/api/v1/news/sources",
                 Jason.encode!(%{
                   source: %{domain: "WWW.Wire.Writes-Test.Example.com", tier: "blocked"}
                 })
               )
               |> json_response(200)

      assert [%{operation: :upsert, actor_type: :api_token_rw, actor_label: "mcp"} = entry] =
               entries("news_source")

      assert entry.after["tier"] == "blocked"

      assert {:kept, _row} =
               Sources.put_source(
                 Portfolixir.Actor.owner_ui(),
                 "wire.writes-test.example.com",
                 :primary,
                 set_by: :seed
               )

      assert Repo.get_by!(Source, domain: "wire.writes-test.example.com").tier == :blocked
    end

    test "an unknown field, a bad domain or tier answers 422 naming it", %{conn: conn} do
      put_source = fn body -> put(conn, "/api/v1/news/sources", Jason.encode!(body)) end

      %{"errors" => errors} =
        put_source.(%{source: %{domain: "a.example.com", tier: "primary", set_by: "seed"}})
        |> json_response(422)

      assert Map.keys(errors) == ["set_by"]

      %{"errors" => errors} = put_source.(%{source: %{tier: "primary"}}) |> json_response(422)
      assert Map.has_key?(errors, "domain")

      %{"errors" => errors} =
        put_source.(%{source: %{domain: 42, tier: "primary"}}) |> json_response(422)

      assert Map.has_key?(errors, "domain")

      %{"errors" => errors} =
        put_source.(%{source: %{domain: "a.example.com", tier: "gold"}}) |> json_response(422)

      assert Map.has_key?(errors, "tier")

      %{"errors" => errors} = put_source.(%{source: "x"}) |> json_response(422)
      assert Map.has_key?(errors, "source")

      assert Repo.aggregate(Source, :count) == 0
      assert entries("news_source") == []
    end
  end

  # User story (ADR-0056 §2, §9, B1):
  # As the agent that keeps the news layer,
  # I want to give a security its CIK, its aliases and its watch flag through
  # the security's own update,
  # so that the matcher can find it in aggregator titles and a candidate
  # without a holding is in the universe.
  #
  # Acceptance criteria:
  # - PATCH /api/v1/securities/:id takes `news_identity` {cik, aliases} and
  #   `news_watch`; the answer and the security's read carry both; a key of
  #   news_identity not sent keeps its stored value.
  # - The write is journaled as `security` under the token's name, with the
  #   news fields in its after-image.
  # - An unknown key in news_identity or in an alias, a raw `news_cik` or
  #   `news_aliases`, a news_identity that is not an object and a pattern
  #   token answer 422 naming the field under news_identity; nothing is
  #   written.
  describe "PATCH /api/v1/securities/:id with news_identity and news_watch" do
    test "stores the news identity and the watch flag, journaled", %{conn: conn} do
      security = security!()

      body = %{
        security: %{
          news_identity: %{
            cik: "320193",
            aliases: [
              %{token: "Northwind", case: "insensitive"},
              %{token: "NWH", context: ["shares", "stock"], case: "sensitive"}
            ]
          },
          news_watch: true
        }
      }

      %{"data" => data} =
        conn
        |> patch("/api/v1/securities/#{security.id}", Jason.encode!(body))
        |> json_response(200)

      assert data["news_watch"] == true

      assert data["news_identity"] == %{
               "cik" => "0000320193",
               "aliases" => [
                 %{"token" => "Northwind", "context" => [], "case" => "insensitive"},
                 %{"token" => "NWH", "context" => ["shares", "stock"], "case" => "sensitive"}
               ]
             }

      %{"data" => shown} =
        conn |> get("/api/v1/securities/#{security.id}") |> json_response(200)

      assert shown["news_identity"] == data["news_identity"]

      # A key not sent keeps its stored value.
      %{"data" => data} =
        conn
        |> patch(
          "/api/v1/securities/#{security.id}",
          Jason.encode!(%{security: %{news_identity: %{cik: nil}}})
        )
        |> json_response(200)

      assert data["news_identity"]["cik"] == nil
      assert length(data["news_identity"]["aliases"]) == 2

      assert [cleared, written | _] = entries("security")
      assert written.actor_label == "mcp" and cleared.actor_label == "mcp"
      assert written.after["news_watch"] == true
      assert written.after["news_cik"] == "0000320193"
      assert [%{"token" => "Northwind"}, %{"token" => "NWH"}] = written.after["news_aliases"]
    end

    test "an unknown key, a raw column or a pattern answers 422 naming it", %{conn: conn} do
      security = security!()
      before = Repo.get!(Portfolixir.Catalog.Security, security.id)

      patch_security = fn attrs ->
        conn
        |> patch("/api/v1/securities/#{security.id}", Jason.encode!(%{security: attrs}))
        |> json_response(422)
        |> Map.fetch!("errors")
      end

      assert %{"news_identity" => %{"regex" => [message]}} =
               patch_security.(%{news_identity: %{regex: "N.*"}})

      assert message =~ "is unknown"

      assert %{"news_identity" => %{"aliases" => [%{}, %{"pattern" => [_]}]}} =
               patch_security.(%{
                 news_identity: %{
                   aliases: [
                     %{token: "Northwind", case: "insensitive"},
                     %{token: "NWH", case: "sensitive", pattern: "N.*"}
                   ]
                 }
               })

      assert %{"news_identity" => %{"aliases" => [%{"token" => [_]}]}} =
               patch_security.(%{news_identity: %{aliases: [%{token: "N.*", case: "sensitive"}]}})

      assert %{"news_identity" => %{"cik" => [_]}} =
               patch_security.(%{news_identity: %{cik: "CIK12"}})

      assert %{"news_cik" => [_]} = patch_security.(%{news_cik: "320193"})
      assert %{"news_aliases" => [_]} = patch_security.(%{news_aliases: []})

      for bad <- ["x", 42, nil, ["x"]] do
        assert %{"news_identity" => [_]} = patch_security.(%{news_identity: bad})
      end

      assert %{"news_watch" => [_]} = patch_security.(%{news_watch: "often"})

      assert Repo.get!(Portfolixir.Catalog.Security, security.id) == before
      assert entries("security") |> Enum.filter(&(&1.operation == :update)) == []
    end
  end

  # --- closing act, Fix-1 ---------------------------------------------------

  # User story (closing act, SEC4):
  # As the agent that registers a security with its news identity,
  # I want the create to read `news_identity` as the update does,
  # so that a security is never stored with a pattern or a raw column the
  # update would have refused.
  #
  # Acceptance criteria:
  # - `POST /api/v1/securities` with `news_identity` {cik, aliases} stores
  #   the identity; an unknown key in it, a key of an alias other than
  #   token, context and case, and `news_cik` / `news_aliases` sent raw
  #   answer 422 naming them, and nothing is created.
  describe "POST /api/v1/securities with news_identity (closing act, SEC4)" do
    test "stores the identity and refuses what the update refuses", %{conn: conn} do
      create = fn attrs, status ->
        conn
        |> post("/api/v1/securities", Jason.encode!(%{security: attrs}))
        |> json_response(status)
      end

      base = %{name: "Probe Harbour AG", currency_code: "EUR"}

      %{"data" => data} =
        create.(
          Map.put(base, :news_identity, %{
            cik: "320193",
            aliases: [%{token: "Probe Harbour", case: "insensitive"}]
          }),
          201
        )

      assert data["news_identity"] == %{
               "cik" => "0000320193",
               "aliases" => [
                 %{"token" => "Probe Harbour", "context" => [], "case" => "insensitive"}
               ]
             }

      count = Repo.aggregate(Portfolixir.Catalog.Security, :count)

      assert %{"errors" => %{"news_identity" => %{"regex" => [_]}}} =
               create.(Map.put(base, :news_identity, %{cik: "320193", regex: "x"}), 422)

      assert %{"errors" => %{"news_identity" => %{"aliases" => [%{"regex" => [_]}]}}} =
               create.(
                 Map.put(base, :news_identity, %{
                   aliases: [%{token: "Probe", case: "sensitive", regex: "P.*"}]
                 }),
                 422
               )

      assert %{"errors" => %{"news_cik" => [_], "news_aliases" => [_]}} =
               create.(
                 Map.merge(base, %{
                   news_cik: "320193",
                   news_aliases: [%{token: "Probe", case: "sensitive", regex: "P.*"}]
                 }),
                 422
               )

      assert %{"errors" => %{"news_identity" => %{"cik" => [_]}}} =
               create.(Map.put(base, :news_identity, %{cik: "CIK12"}), 422)

      assert Repo.aggregate(Portfolixir.Catalog.Security, :count) == count
    end
  end

  # User story (closing act, COR1):
  # As the operator whose feed already stored items,
  # I want its binding and its language kept while it has items, as its
  # class is,
  # so that a feed re-bound to another security does not leave its stored
  # items on the old one for good.
  #
  # Acceptance criteria:
  # - An issuer feed with items answers 422 on `security_id` for another
  #   security and on `language` for another language; a thematic one on
  #   `category_id`; nothing is written.
  # - Without items, the same changes are written; with items, a change of
  #   interval or enabled is.
  describe "PUT /api/v1/news/feeds keeps a fed feed's binding (closing act, COR1)" do
    test "the binding and the language do not change while the feed has items", %{conn: conn} do
      security = security!()
      other = security!("Southwind Shipping AG")
      category = category!()
      other_category = category!()

      fed = feed!(%{class: "issuer", security_id: security.id})
      item!(fed)

      for {change, field} <- [
            {%{security_id: other.id}, "security_id"},
            {%{language: "de"}, "language"}
          ] do
        %{"errors" => errors} =
          conn |> put_feed(Map.put(change, :id, fed.id)) |> json_response(422)

        assert [message] = errors[field], inspect(errors)
        assert message =~ "stored items"
      end

      thematic = feed!(%{class: "thematic", category_id: category.id})
      item!(thematic)

      %{"errors" => errors} =
        conn
        |> put_feed(%{id: thematic.id, category_id: other_category.id})
        |> json_response(422)

      assert [_message] = errors["category_id"]

      assert %{security_id: security_id, language: "en"} = Repo.get!(Feed, fed.id)
      assert security_id == security.id
      assert Repo.get!(Feed, thematic.id).category_id == category.id

      assert %{"data" => %{"interval_minutes" => 30}} =
               conn |> put_feed(%{id: fed.id, interval_minutes: 30}) |> json_response(200)

      empty = feed!(%{class: "issuer", security_id: security.id})

      assert %{"data" => %{"security_id" => other_id, "language" => "de"}} =
               conn
               |> put_feed(%{id: empty.id, security_id: other.id, language: "de"})
               |> json_response(200)

      assert other_id == other.id
    end
  end

  # User story (closing act, EDGE3 and POLISH):
  # As the agent that keeps a security's aliases,
  # I want an alias's context read as I sent it — null as none, a blank word
  # refused — and a token that names nothing refused,
  # so that a gated alias never turns unconditional in silence and no alias
  # matches nearly everything.
  #
  # Acceptance criteria:
  # - `context: null` stores no context words (200), never a 500.
  # - A blank context word (`""`, `"  "`) answers 422 on the alias's
  #   context; nothing is stored.
  # - A token without a letter or a digit (".", "--", "&") answers 422 on
  #   the token; a single letter stays allowed (one-letter tickers exist).
  describe "PATCH /api/v1/securities/:id aliases (closing act, EDGE3, POLISH)" do
    test "a null context is none, a blank word and an empty token are refused", %{conn: conn} do
      security = security!()

      patch_aliases = fn aliases, status ->
        conn
        |> patch(
          "/api/v1/securities/#{security.id}",
          Jason.encode!(%{security: %{news_identity: %{aliases: aliases}}})
        )
        |> json_response(status)
      end

      %{"data" => data} =
        patch_aliases.([%{token: "Northwind", case: "insensitive", context: nil}], 200)

      assert [%{"token" => "Northwind", "context" => []}] = data["news_identity"]["aliases"]

      for context <- [[""], ["  "], ["shares", ""]] do
        %{"errors" => errors} =
          patch_aliases.([%{token: "NWH", case: "sensitive", context: context}], 422)

        assert %{"news_identity" => %{"aliases" => aliases}} = errors
        assert Enum.any?(aliases, &match?(%{"context" => [_]}, &1)), inspect(context)
      end

      for token <- [".", "--", "&", " - "] do
        %{"errors" => errors} = patch_aliases.([%{token: token, case: "sensitive"}], 422)

        assert %{"news_identity" => %{"aliases" => aliases}} = errors

        assert Enum.any?(aliases, fn entry ->
                 match?(%{"token" => [message]} when is_binary(message), entry) and
                   hd(entry["token"]) =~ "letter or a digit"
               end),
               inspect(token)
      end

      %{"data" => data} = patch_aliases.([%{token: "X", case: "sensitive"}], 200)
      assert [%{"token" => "X"}] = data["news_identity"]["aliases"]

      assert [%{token: "X"}] = Repo.get!(Portfolixir.Catalog.Security, security.id).news_aliases
    end
  end

  # --- end closing act, Fix-1 -----------------------------------------------

  defp item!(feed) do
    attrs = %{
      feed_id: feed.id,
      class: feed.class,
      security_id: feed.security_id,
      category_id: feed.category_id,
      assignment: "assigned",
      first_seen_at: DateTime.utc_now(),
      published_at_claimed: DateTime.utc_now(),
      title: "Northwind opens a new harbour terminal",
      canonical_url:
        "https://wire.writes-test.example.com/a-#{System.unique_integer([:positive])}",
      domain: "wire.writes-test.example.com",
      tier: "primary",
      language: feed.language,
      content_hash: String.duplicate("a", 64),
      title_norm_hash: String.duplicate("b", 64),
      title_words: ~w(northwind opens new harbour terminal)
    }

    %Item{} |> Item.changeset(attrs) |> Repo.insert!()
  end
end
