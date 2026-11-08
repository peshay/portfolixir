defmodule PortfolixirWeb.Api.V1.NewsReadController do
  @moduledoc """
  The news layer's reads (ADR-0056 §6, §9, §11, B4; Sprint 27, N7):

    * `GET /api/v1/news/stories` (`news.list`) — one page of rows of exactly
      one selector: `security_id` or `category_id` (the scope's stories),
      `cluster_id` (the story's items) or `assignment=unassigned|ambiguous`
      (the remainder, with candidates). `since` (by `scope_at`, B4, C3),
      `tier_min` (`primary`, `secondary`, `awareness`), `limit` (default 20,
      at most 100), `fields=slim|std` (`std` adds `url` and `note_ids`) and
      `cursor` (the `cursor` of a truncated page). See
      `Portfolixir.News.Reads.list/2`.
    * `GET /api/v1/news/stories/:id` and `GET /api/v1/news/items/:id`
      (`news.get`) — one story or one item: the only reads with the excerpt
      and the link.
    * `GET /api/v1/news/health` (`news.health`) — `Portfolixir.News.health/1`
      at the server's clock.
    * `GET /api/v1/news/digest` (`news.digest`) — one row per security with
      something new since `since` (default 24 hours before now), without
      labels and without a consumer cursor (§11): `view_id` (else the news
      universe), `include_unlabeled` (`false`), `max_rows` (12, at most 40, C5).
      See `Portfolixir.News.Reads.digest/4`.

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

  @digest_params ~w(view_id since include_unlabeled max_rows)
  @digest_rows 12
  @digest_rows_max 40
  @day_seconds 24 * 60 * 60

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

  def digest(conn, params) do
    with :ok <- closed(conn, @digest_params),
         {:ok, view_id} <- view_id(params["view_id"]),
         {:ok, since} <- digest_since(params),
         {:ok, include_unlabeled} <- include_unlabeled(params["include_unlabeled"]),
         {:ok, max_rows} <- max_rows(params["max_rows"]),
         as_of = Reads.as_of(),
         {:ok, security_ids} <- Reads.digest_securities(view_id) do
      digest =
        Reads.digest(security_ids, since, include_unlabeled, max_rows, view: not is_nil(view_id))

      data =
        compact(%{
          since: time(since),
          as_of: time(as_of),
          view_id: view_id,
          rows: Enum.map(digest.rows, &digest_row/1),
          categories: digest.categories && Enum.map(digest.categories, &digest_row/1),
          quiet: digest.quiet,
          hidden: digest.hidden,
          unassigned: digest.unassigned,
          ambiguous: digest.ambiguous,
          truncated: digest.truncated,
          more: digest.more
        })

      json(conn, %{data: data})
    else
      {:error, :not_found} -> not_found(conn)
      {:error, errors} -> refuse(conn, errors)
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
  # Every parameter a news read takes is one value: a list or a map
  # (`max_rows[]=5`) is refused naming it, never read as a string.
  defp closed(conn, allowed) do
    case Map.keys(conn.query_params) -- allowed do
      [] ->
        scalars(conn.query_params)

      unknown ->
        message =
          if allowed == [],
            do: "is unknown: this read takes no parameters",
            else: "is unknown: this read takes only #{Enum.join(allowed, ", ")}"

        {:error, Map.new(unknown, &{&1, [message]})}
    end
  end

  defp scalars(params) do
    case for({key, value} <- params, not is_binary(value), do: key) do
      [] -> :ok
      keys -> {:error, Map.new(keys, &{&1, ["must be a single value, not a list or a map"]})}
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

  # `<scope_at>~<tier 0..2>~<publication>~<link key>~<id>` (Reads' order).
  defp decode_cursor(value) when is_binary(value) do
    with [instant, rank, published, link_key, id] <- String.split(value, "~"),
         {:ok, seen, 0} <- DateTime.from_iso8601(instant),
         {rank, ""} when rank in 0..2 <- Integer.parse(rank),
         {:ok, at, 0} <- DateTime.from_iso8601(published),
         true <- link_key =~ ~r/\A[0-9a-f]{32}\z/,
         {:ok, id} <- IdParam.parse(id) do
      {:ok, {seen, rank, at, link_key, id}}
    else
      _malformed -> {:error, %{"cursor" => ["is not a cursor this read answered"]}}
    end
  end

  defp decode_cursor(_value), do: {:error, %{"cursor" => ["is not a cursor this read answered"]}}

  defp encode_cursor(nil), do: nil

  defp encode_cursor({seen, rank, at, link_key, id}),
    do: Enum.join([DateTime.to_iso8601(seen), rank, DateTime.to_iso8601(at), link_key, id], "~")

  defp view_id(value) when value in [nil, ""], do: {:ok, nil}

  defp view_id(value) do
    case IdParam.parse(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, %{"view_id" => ["is invalid"]}}
    end
  end

  defp digest_since(params) do
    case since(params) do
      {:ok, nil} -> {:ok, DateTime.add(DateTime.utc_now(), -@day_seconds, :second)}
      other -> other
    end
  end

  defp include_unlabeled(value) when value in [nil, "", "false", false], do: {:ok, false}
  defp include_unlabeled(value) when value in ["true", true], do: {:ok, true}

  defp include_unlabeled(_value),
    do: {:error, %{"include_unlabeled" => ["must be true or false"]}}

  defp max_rows(value) when value in [nil, ""], do: {:ok, @digest_rows}

  defp max_rows(value) do
    case Integer.parse(to_string(value)) do
      {rows, ""} when rows > 0 -> {:ok, min(rows, @digest_rows_max)}
      _other -> {:error, %{"max_rows" => ["must be a positive integer (at most 40 is used)"]}}
    end
  end

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

  defp digest_row(row), do: %{row | top: %{row.top | at: time(row.top.at)}}

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
    |> Map.put(:last_ok_at, time(feed.last_ok_at))
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
