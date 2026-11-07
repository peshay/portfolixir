defmodule PortfolixirWeb.Api.V1.NewsReadController do
  @moduledoc """
  The news layer's reads (ADR-0056 §6, §9, §11, B4; Sprint 27, N7):

    * `GET /api/v1/news/stories` (`news.list`) — one page of rows of exactly
      one selector: `security_id` or `category_id` (the scope's stories),
      `cluster_id` (the story's items) or `assignment=unassigned|ambiguous`
      (the remainder, with candidates). `since` (by `first_seen_at`, B4),
      `tier_min` (`primary`, `secondary`, `awareness`), `limit` (default 20,
      at most 100), `fields=slim|std` (`std` adds `url` and `note_ids`) and
      `cursor` (the `cursor` of a truncated page). See
      `Portfolixir.News.Reads.list/2`.
    * `GET /api/v1/news/stories/:id` and `GET /api/v1/news/items/:id`
      (`news.get`) — one story or one item: the only reads with the excerpt
      and the link.
    * `GET /api/v1/news/health` (`news.health`) — `Portfolixir.News.health/1`
      at the server's clock.

  **Compact by §9's rule:** enums as their codes, times to the second in
  UTC, names at most 20 characters, a field without a value left out, and
  no link or excerpt in a list. **Closed:** a parameter a read does not take
  answers 422 naming it, never dropped in silence — `min_materiality` and
  `event_types` are the labels' (Sprint 28) and are refused until then.
  Stored text is answered as stored (ADR-0054 §4); the companion spells
  what an operator cannot see.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.News
  alias Portfolixir.News.Reads
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.ListLimit
  alias PortfolixirWeb.Api.V1.SinceParam

  @selectors ~w(security_id category_id cluster_id assignment)
  @list_params @selectors ++ ~w(since tier_min limit fields cursor)
  @list_default 20
  @list_max 100

  @tiers %{"primary" => :primary, "secondary" => :secondary, "awareness" => :awareness}
  @assignments %{"unassigned" => :unassigned, "ambiguous" => :ambiguous}
  @fields ~w(slim std)

  def index(conn, params) do
    with :ok <- closed(conn, @list_params),
         {:ok, selector} <- selector(params),
         {:ok, opts} <- list_opts(params),
         {:ok, page} <- Reads.list(selector, opts) do
      std? = Map.get(params, "fields") == "std"

      data =
        compact(%{
          kind: page.kind,
          rows: Enum.map(page.rows, &row(page.kind, &1, std?)),
          limit: opts[:limit],
          truncated: page.truncated,
          cursor: encode_cursor(page.cursor),
          since: params["since"],
          as_of: time(opts[:as_of])
        })

      json(conn, %{data: data})
    else
      {:error, :not_found} -> not_found(conn)
      {:error, errors} -> refuse(conn, errors)
    end
  end

  def show_story(conn, %{"id" => id}), do: show(conn, id, &Reads.story/1, &story_json/1)
  def show_item(conn, %{"id" => id}), do: show(conn, id, &Reads.item/1, &item_json/1)

  def health(conn, _params) do
    case closed(conn, []) do
      :ok ->
        report = News.health(DateTime.utc_now())

        json(conn, %{
          data: %{
            as_of: time(report.as_of),
            feeds: Enum.map(report.feeds, &feed_health_json/1),
            day: Map.update!(report.day, :date, &Date.to_iso8601/1)
          }
        })

      {:error, errors} ->
        refuse(conn, errors)
    end
  end

  defp show(conn, id, read, render) do
    with :ok <- closed(conn, []),
         {:ok, id} <- id_or_not_found(id),
         {:ok, record} <- read.(id) do
      json(conn, %{data: render.(record)})
    else
      {:error, :not_found} -> not_found(conn)
      {:error, errors} -> refuse(conn, errors)
    end
  end

  # -- parameters -------------------------------------------------------------

  # A read's closed query: every key not taken is named (path parameters are
  # the route's, not the query's).
  defp closed(conn, allowed) do
    case Map.keys(conn.query_params) -- allowed do
      [] ->
        :ok

      unknown ->
        message =
          if allowed == [],
            do: "is unknown: this read takes no parameters",
            else: "is unknown: this read takes only #{Enum.join(allowed, ", ")}"

        {:error, Map.new(unknown, &{&1, [message]})}
    end
  end

  defp selector(params) do
    case Enum.filter(@selectors, &present?(params[&1])) do
      [key] ->
        parse_selector(key, params[key])

      [] ->
        {:error,
         %{
           "security_id" => [
             "one of security_id, category_id, cluster_id or assignment is required"
           ]
         }}

      keys ->
        {:error,
         Map.new(keys, &{&1, ["only one of security_id, category_id, cluster_id or assignment"]})}
    end
  end

  defp parse_selector("assignment", value) do
    case Map.fetch(@assignments, value) do
      {:ok, assignment} -> {:ok, {:assignment, assignment}}
      :error -> {:error, %{"assignment" => ["must be unassigned or ambiguous"]}}
    end
  end

  defp parse_selector(key, value) do
    scope =
      case key do
        "security_id" -> :security
        "category_id" -> :category
        "cluster_id" -> :cluster
      end

    case IdParam.parse(value) do
      {:ok, id} -> {:ok, {scope, id}}
      :error -> {:error, %{key => ["is invalid"]}}
    end
  end

  defp list_opts(params) do
    with {:ok, since} <- since(params),
         {:ok, tier_min} <- tier_min(params["tier_min"]),
         {:ok, limit} <- limit(params),
         :ok <- fields(params["fields"]),
         {:ok, cursor} <- decode_cursor(params["cursor"]) do
      {:ok,
       [since: since, tier_min: tier_min, limit: limit, cursor: cursor, as_of: Reads.as_of()]}
    end
  end

  defp since(params) do
    case SinceParam.parse(params) do
      {:ok, nil} -> {:ok, nil}
      {:ok, %{cut: cut}} -> {:ok, DateTime.from_naive!(cut, "Etc/UTC")}
      {:error, :since} -> {:error, %{"since" => ["must be an ISO8601 datetime or date"]}}
    end
  end

  defp tier_min(value) when value in [nil, ""], do: {:ok, nil}

  defp tier_min(value) do
    case Map.fetch(@tiers, value) do
      {:ok, tier} -> {:ok, tier}
      :error -> {:error, %{"tier_min" => ["must be primary, secondary or awareness"]}}
    end
  end

  defp limit(params) do
    case ListLimit.parse(params, @list_default, @list_max) do
      {:ok, limit} -> {:ok, limit}
      {:error, :limit} -> {:error, %{"limit" => ["must be a positive integer"]}}
    end
  end

  defp fields(value) when value in [nil | @fields], do: :ok
  defp fields(_value), do: {:error, %{"fields" => ["must be slim or std"]}}

  defp decode_cursor(value) when value in [nil, ""], do: {:ok, nil}

  defp decode_cursor(value) when is_binary(value) do
    with [instant, id] <- String.split(value, "~"),
         {:ok, at, 0} <- DateTime.from_iso8601(instant),
         {:ok, id} <- IdParam.parse(id) do
      {:ok, {at, id}}
    else
      _malformed -> {:error, %{"cursor" => ["is not a cursor this read answered"]}}
    end
  end

  defp decode_cursor(_value), do: {:error, %{"cursor" => ["is not a cursor this read answered"]}}

  defp encode_cursor(nil), do: nil
  defp encode_cursor({at, id}), do: DateTime.to_iso8601(at) <> "~" <> Integer.to_string(id)

  defp present?(value), do: value not in [nil, ""]

  defp id_or_not_found(id) do
    case IdParam.parse(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  # -- answers ----------------------------------------------------------------

  defp row(:stories, story, std?) do
    slim = %{
      id: story.id,
      title: story.title,
      tier: story.tier,
      at: time(story.at),
      count: story.count
    }

    if std?, do: Map.merge(slim, %{url: story.url, note_ids: story.note_ids}), else: slim
  end

  defp row(:items, item, std?) do
    slim =
      compact(%{
        id: item.id,
        title: item.title,
        tier: item.tier,
        at: time(item.at),
        domain: item.domain,
        candidates: non_empty(item.candidates)
      })

    if std?, do: Map.merge(slim, %{url: item.url, note_ids: item.note_ids}), else: slim
  end

  defp story_json(story) do
    story
    |> Map.merge(%{
      kind: :story,
      published_at: time(story.published_at),
      first_seen_at: time(story.first_seen_at),
      members: Enum.map(story.members, &%{&1 | at: time(&1.at)})
    })
    |> compact()
  end

  defp item_json(item) do
    item
    |> Map.merge(%{
      kind: :item,
      published_at: time(item.published_at),
      first_seen_at: time(item.first_seen_at),
      candidates: non_empty(item.candidates)
    })
    |> compact()
  end

  defp feed_health_json(feed) do
    feed
    |> Map.merge(%{
      last_ok_at: time(feed.last_ok_at),
      yield_30d: feed.yield_30d && Decimal.to_string(feed.yield_30d, :normal)
    })
    |> compact()
  end

  defp time(nil), do: nil
  defp time(%DateTime{} = at), do: at |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp non_empty([]), do: nil
  defp non_empty(list), do: list

  defp compact(map), do: map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()

  defp refuse(conn, errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end
end
