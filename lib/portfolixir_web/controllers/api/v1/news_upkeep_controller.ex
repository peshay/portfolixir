defmodule PortfolixirWeb.Api.V1.NewsUpkeepController do
  @moduledoc """
  The news layer's upkeep writes (ADR-0056 §9, B1, B2, B7; Sprint 27, N8):

    * `PUT /api/v1/news/feeds` (`news.feeds_put`) registers a feed or changes
      one: `{"feed": {id?, class, url, security_id, category_id,
      interval_minutes, language, enabled}}`. With `id` that feed; without,
      the feed registered under `url`, else a new one (201). A URL new to the
      feed is checked with name resolution at once (B2) and refused with 422
      on `url` naming its code. See `Portfolixir.News.put_feed/3`.
    * `DELETE /api/v1/news/feeds/:id` (`news.feeds_delete`) removes a feed;
      its items stay, detached, and its day counters go
      (`Portfolixir.News.delete_feed/2`).
    * `PUT /api/v1/news/sources` (`news.sources_put`) rates a domain by hand:
      `{"source": {domain, tier}}` (`Portfolixir.News.Sources.put_source/4`
      with `set_by: :hand`, which no later seed overwrites).
    * `PUT /api/v1/news/items/:id/assignment` (`news.assign`, S28 N4)
      assigns an aggregator item by hand, `{"assignment": {"security_id":
      id}}`, or with `null` gives it back to the matcher; its stories are
      reclustered in the write's transaction
      (`Portfolixir.News.assign_item/4`). Answers the item's `id`,
      `story_id`, `assignment`, `security_id` and `candidates`.

  Every write is journaled under the token that made it (B7, ADR-0054), and
  every one is closed: a key it does not take is refused with 422 naming it
  (`PortfolixirWeb.Api.V1.ClosedBody`). Answers are compact by §9's rule:
  short codes, null fields left out.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.News
  alias Portfolixir.News.Sources
  alias PortfolixirWeb.Api.V1.ClosedBody
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON

  plug(PortfolixirWeb.Api.V1.BodyObject, "feed" when action in [:put_feed])
  plug(PortfolixirWeb.Api.V1.BodyObject, "source" when action in [:put_source])
  # --- S28 N4 begin ---
  plug(PortfolixirWeb.Api.V1.BodyObject, "assignment" when action in [:assign_item])
  # --- S28 N4 end ---

  @feed_fields ~w(id class url security_id category_id interval_minutes language enabled)
  @source_fields ~w(domain tier)

  def put_feed(conn, params) do
    attrs = Map.get(params, "feed", %{})

    with :ok <- ClosedBody.check(conn, "feed", @feed_fields),
         {:ok, opts} <- feed_id(attrs),
         {:ok, written, feed} <- News.put_feed(conn.assigns.actor, Map.delete(attrs, "id"), opts) do
      conn
      |> put_status(if written == :created, do: :created, else: :ok)
      |> json(%{data: feed_json(feed)})
    else
      {:error, :not_found} -> not_found(conn)
      {:error, %Ecto.Changeset{} = changeset} -> ClosedBody.refuse(conn, JSON.errors(changeset))
      {:error, errors} -> ClosedBody.refuse(conn, errors)
    end
  end

  def delete_feed(conn, %{"id" => id}) do
    with :ok <- ClosedBody.check(conn, nil, []),
         {:ok, feed_id} <- parse_id(id),
         {:ok, %{feed: feed, items_detached: detached}} <-
           News.delete_feed(conn.assigns.actor, feed_id) do
      json(conn, %{data: %{id: feed.id, items_detached: detached}})
    else
      {:error, :not_found} -> not_found(conn)
      {:error, errors} -> ClosedBody.refuse(conn, errors)
    end
  end

  def put_source(conn, params) do
    attrs = Map.get(params, "source", %{})

    with :ok <- ClosedBody.check(conn, "source", @source_fields),
         {:ok, domain} <- domain(attrs) do
      case Sources.put_source(conn.assigns.actor, domain, attrs["tier"], set_by: :hand) do
        {:ok, source} -> json(conn, %{data: source_json(source)})
        {:error, changeset} -> ClosedBody.refuse(conn, JSON.errors(changeset))
      end
    else
      {:error, errors} -> ClosedBody.refuse(conn, errors)
    end
  end

  # --- S28 N4 begin ---
  # news.assign (§9): `{"assignment": {"security_id": id | null}}`, closed;
  # null gives the item back to the matcher (`Portfolixir.News.assign_item/4`).
  @assignment_fields ~w(security_id)

  def assign_item(conn, %{"id" => id} = params) do
    with :ok <- ClosedBody.check(conn, "assignment", @assignment_fields),
         {:ok, item_id} <- parse_id(id),
         {:ok, security_id} <- assignment_target(params),
         {:ok, item} <- News.assign_item(conn.assigns.actor, item_id, security_id) do
      json(conn, %{data: assignment_json(item)})
    else
      {:error, :not_found} ->
        not_found(conn)

      {:error, {:write_refused, changeset}} ->
        ClosedBody.refuse(conn, JSON.errors(changeset))

      {:error, errors} ->
        ClosedBody.refuse(conn, errors)
    end
  end

  # security_id is required, and null is a value: the undo.
  defp assignment_target(%{"assignment" => %{"security_id" => nil}}), do: {:ok, nil}

  defp assignment_target(%{"assignment" => %{"security_id" => id}})
       when is_integer(id) and id > 0,
       do: {:ok, id}

  defp assignment_target(%{"assignment" => %{"security_id" => _other}}),
    do: {:error, %{"security_id" => ["must be a security id or null"]}}

  defp assignment_target(%{"assignment" => %{}}),
    do: {:error, %{"security_id" => ["can't be blank: a security id, or null to undo"]}}

  defp assignment_target(_params), do: {:error, %{"assignment" => ["can't be blank"]}}

  defp assignment_json(item) do
    compact(%{
      id: item.id,
      story_id: item.cluster_id,
      assignment: item.assignment,
      security_id: item.security_id,
      candidates: if(item.candidates != [], do: item.candidates)
    })
  end

  # --- S28 N4 end ---

  defp feed_id(attrs) do
    case Map.fetch(attrs, "id") do
      :error ->
        {:ok, []}

      {:ok, value} ->
        case IdParam.parse(value) do
          {:ok, id} -> {:ok, [id: id]}
          :error -> {:error, %{"id" => ["is invalid"]}}
        end
    end
  end

  defp parse_id(id) do
    case IdParam.parse(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  # The tier is the changeset's to judge (a closed set cast from text, never
  # an atom made from input); the domain must be text to be normalized.
  defp domain(%{"domain" => domain}) when is_binary(domain), do: {:ok, domain}
  defp domain(%{"domain" => _not_text}), do: {:error, %{"domain" => ["is invalid"]}}
  defp domain(_attrs), do: {:error, %{"domain" => ["can't be blank"]}}

  defp feed_json(feed) do
    compact(%{
      id: feed.id,
      class: feed.class,
      url: feed.url,
      security_id: feed.security_id,
      category_id: feed.category_id,
      enabled: feed.enabled,
      interval_minutes: feed.interval_minutes,
      language: feed.language
    })
  end

  defp source_json(source),
    do: %{domain: source.domain, tier: source.tier, set_by: source.set_by}

  defp compact(map), do: map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end
end
