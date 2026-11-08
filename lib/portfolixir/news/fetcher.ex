defmodule Portfolixir.News.Fetcher do
  @moduledoc """
  Fetches one registered feed (ADR-0056 §5, A1, A3, B2), as the system job
  `news_fetch`: the URL check, the request, the parser, the ingest, and the
  feed's record of how it went.

  **The URL, every time (B2).** Before every request the feed's URL passes
  `Portfolixir.Net.UrlPolicy` **with name resolution**: https only, no
  userinfo, and every address the name maps to public. `check_url/2` is the
  same check for the registering writer. The bounded client
  (`Portfolixir.Net.Http`) is built with **the feed's own host as its only
  allow-list**, so a redirect to another host is refused and makes no
  request, and every hop it follows is checked with resolution again. The
  policy's stated limit stays stated: the check and the connection resolve
  the name separately, so a rebinding name with a very short lifetime can
  pass between them; the byte cap, the deadline and the redirect check
  bound what such a fetch can do.

  **Only a stored feed (closing act, SEC1).** `fetch/2` loads the feed's
  row and fetches the URL stored for it; no caller hands it a URL, a
  header or request options, and the request path is private. B2 pins
  this module's stored-feed allow-list to it and registers its callers
  (`Portfolixir.News` and `Portfolixir.News.Scheduler`).

  **The request.** GET only, the parser's byte cap
  (`Portfolixir.News.Parser.max_bytes/0`, 8 MiB), a deadline on the whole
  request (30 s) and a receive timeout (10 s). The user agent is the
  app's own, except **for a feed on `sec.gov`** or a subdomain (a trailing
  dot or capitals in the name change nothing), which is sent
  `PORTFOLIXIR_NEWS_USER_AGENT` (read in `config/runtime.exs`) and no
  other host is (ADR-0056 C6): without the operator's user agent it makes
  no request and records `user_agent_missing` (the SEC asks for a contact;
  the repository carries none); its requests are paced to at most 10 a
  second across every feed (`Portfolixir.News.Pace`); and they go over
  IPv4, which Mint uses unless a caller sets `inet6: true`, as nothing here
  does.

  **The record** on the feed (`News.Feed.health_changeset/2`, not
  journaled, B7): `last_fetch_at` the clock, read after the answer; on
  success `last_ok_at` the clock, `last_error` cleared and the backoff
  reset. On failure `last_error` is a short code —
  `url_not_allowed:<reason>`, `http_<status>`, `timeout`,
  `transport_error`, `body_too_large`, `too_many_redirects`,
  `parse_refused:<reason>` (A1), `user_agent_missing`, `fetch_failed` — and
  the day's `errors` count one more (§6's `err_24h`). A 429 or a 5xx also
  backs off: `failures` counts one more and `retry_at` is the clock plus
  the feed's interval times 2^failures, at most a day (`backoff_minutes/2`).
  A failure is the feed's own: nothing here touches another feed.
  """

  require Logger

  alias Portfolixir.Actor
  alias Portfolixir.Net.Http
  alias Portfolixir.Net.UrlPolicy
  alias Portfolixir.News.Feed
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Pace
  alias Portfolixir.News.Parser
  alias Portfolixir.Repo

  @default_user_agent "portfolixir/0.1 (+https://github.com/portfolixir)"
  @accept "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8"
  @deadline_ms 30_000
  @receive_timeout_ms 10_000
  @backoff_max_minutes 24 * 60
  @paced_host "sec.gov"

  @type code :: String.t()

  @fetch_options [:now, :clock, :user_agent, :deadline_ms, :pace]

  @doc """
  Fetches the **stored** feed — given as its id or as a loaded `Feed` whose
  id is read — and records the outcome on it. The row is loaded here, so
  the request goes to the URL stored for the feed and nowhere a caller's
  struct points (closing act, SEC1); a feed that is not stored answers
  `{:error, "feed_not_found"}` and makes no request.

  Options: `:clock` (a function answering the server's time, default
  `DateTime.utc_now/0`), read **once the answer arrived**, for the items'
  `first_seen_at` and the feed's record; `:now` (a fixed time, a test's
  clock); `:user_agent`
  (overrides the configured one; nil is none), `:deadline_ms`, `:pace` (a
  function of the paced host returning the milliseconds to wait, default
  `Portfolixir.News.Pace.reserve/1`). Any other option, request options
  among them, raises `ArgumentError`: no caller adds a header, a plug or a
  host to the request. The one plug merged is the test configuration's
  (`config :portfolixir, Portfolixir.News.Fetcher, plug: ...`).
  """
  @spec fetch(Feed.t() | integer(), keyword()) :: {:ok, Ingest.summary()} | {:error, code()}
  def fetch(feed_or_id, opts \\ [])

  def fetch(%Feed{id: id}, opts), do: fetch(id, opts)

  def fetch(id, opts) do
    opts = Keyword.validate!(opts, @fetch_options)

    case stored(id) do
      nil -> {:error, "feed_not_found"}
      %Feed{} = feed -> run(feed, opts)
    end
  end

  defp stored(id) when is_integer(id), do: Repo.get(Feed, id)
  defp stored(_id), do: nil

  # The clock is read once the answer arrived (or failed), after the pace
  # and the request (closing act, KNOWN): an item's `first_seen_at` is never
  # earlier than the moment the server could have stored it.
  defp run(feed, opts) do
    actor = actor()
    clock = clock(opts)

    case get(feed, opts) do
      {:ok, body} ->
        now = clock.()

        case parse(body) do
          {:ok, items} ->
            {:ok, summary} = Ingest.ingest(feed, items, now)
            record(actor, feed, now, :ok)
            {:ok, summary}

          {:error, code} ->
            failed(actor, feed, now, code)
        end

      {:error, code} ->
        failed(actor, feed, clock.(), code)
    end
  end

  defp failed(actor, feed, now, code) do
    record(actor, feed, now, {:error, code})
    {:error, code}
  end

  defp clock(opts) do
    case Keyword.get(opts, :now) do
      %DateTime{} = now -> fn -> now end
      nil -> Keyword.get(opts, :clock, &DateTime.utc_now/0)
    end
  end

  # The request part of `fetch/2` without any write: checks the URL, builds
  # the request, waits for the pace and runs it. `{:ok, body}` for a 2xx
  # answer, else `{:error, code}`.
  defp get(%Feed{url: url} = feed, opts) do
    with :ok <- check(url),
         {:ok, req} <- request(feed, opts) do
      pace(host(url), opts)

      case Http.get(req, url: url) do
        {:ok, %{status: status, body: body}} when status in 200..299 and is_binary(body) ->
          {:ok, body}

        {:ok, %{status: status}} ->
          {:error, "http_#{status}"}

        {:error, reason} ->
          {:error, error_code(reason)}
      end
    end
  end

  @doc """
  B2's check of a feed's URL, with name resolution and the URL's own host as
  the allow-list: `:ok` or `{:error, {:url_not_allowed, reason}}`. The
  fetcher runs it before every request; the registering writer runs it too.
  Options go to `Portfolixir.Net.UrlPolicy.check/2` (a test's `:resolver`).
  """
  @spec check_url(String.t(), keyword()) :: :ok | {:error, {:url_not_allowed, atom()}}
  def check_url(url, opts \\ []) when is_binary(url) do
    allowed = if host = host(url), do: [host], else: []
    UrlPolicy.check(url, Keyword.merge(opts, resolve: true, allowed_hosts: allowed))
  end

  # The bounded request for `feed` (see the moduledoc), or
  # `{:error, "user_agent_missing"}` for a `sec.gov` feed without the
  # operator's user agent. Only the configuration's test plug is merged.
  defp request(%Feed{url: url}, opts) do
    host = host(url)
    paced? = paced?(host)
    # C6: the operator's contact goes to sec.gov and its subdomains only.
    user_agent = if paced?, do: user_agent(opts)

    if paced? and is_nil(user_agent) do
      {:error, "user_agent_missing"}
    else
      req =
        Http.new(
          max_bytes: Parser.max_bytes(),
          allowed_hosts: [host],
          deadline_ms: Keyword.get(opts, :deadline_ms, @deadline_ms),
          receive_timeout: @receive_timeout_ms,
          decode_body: false,
          headers: [{"user-agent", user_agent || @default_user_agent}, {"accept", @accept}]
        )

      {:ok, merge_test_plug(req)}
    end
  end

  defp merge_test_plug(req) do
    case Keyword.get(config(), :plug) do
      nil -> req
      plug -> Req.merge(req, plug: plug)
    end
  end

  @doc """
  The backoff after `failures` consecutive 429 or 5xx answers, in minutes:
  the feed's interval times 2^failures, at most a day.
  """
  @spec backoff_minutes(pos_integer(), pos_integer()) :: pos_integer()
  def backoff_minutes(interval_minutes, failures)
      when is_integer(interval_minutes) and interval_minutes > 0 and is_integer(failures) and
             failures > 0 do
    if failures >= 11,
      do: @backoff_max_minutes,
      else: min(interval_minutes * Integer.pow(2, failures), @backoff_max_minutes)
  end

  # -- steps -------------------------------------------------------------------

  defp check(url) do
    case check_url(url) do
      :ok -> :ok
      {:error, {:url_not_allowed, reason}} -> {:error, "url_not_allowed:#{reason}"}
    end
  end

  # §5: sec.gov's fair-access rate, one budget for the host and its
  # subdomains. The task that fetches waits; nothing else does.
  defp pace(host, opts) do
    if paced?(host) do
      reserve = Keyword.get(opts, :pace, &Pace.reserve/1)

      case reserve.(@paced_host) do
        delay when is_integer(delay) and delay > 0 -> Process.sleep(delay)
        _now -> :ok
      end
    end

    :ok
  end

  defp parse(body) do
    case Parser.parse(body) do
      {:ok, %{items: items}} -> {:ok, items}
      {:error, {:parse_refused, reason}} -> {:error, "parse_refused:#{reason}"}
    end
  end

  # Req's exceptions are matched by shape: the outbound backstop keeps every
  # Req name but the response out of this module.
  defp error_code(:deadline), do: "timeout"
  defp error_code(%{__exception__: true, reason: :timeout}), do: "timeout"
  defp error_code(%Http.BodyTooLarge{}), do: "body_too_large"
  defp error_code({:url_not_allowed, reason}), do: "url_not_allowed:#{reason}"
  defp error_code(:too_many_redirects), do: "too_many_redirects"
  defp error_code(%{__exception__: true, reason: _reason}), do: "transport_error"
  defp error_code(_other), do: "fetch_failed"

  # -- the record --------------------------------------------------------------

  @doc """
  Records a failure the fetch could not record itself (its task raised or
  was killed, `Portfolixir.News.Scheduler`): `last_fetch_at`, `last_error`
  and one more error in the day's row, as `fetch/2` records one.
  """
  @spec record_failure(Feed.t(), DateTime.t(), code()) :: :ok
  def record_failure(%Feed{} = feed, %DateTime{} = now, code) when is_binary(code),
    do: record(actor(), feed, now, {:error, code})

  defp actor, do: Actor.system_job("news_fetch")

  defp record(%Actor{label: job}, %Feed{id: id}, now, outcome) do
    case Repo.get(Feed, id) do
      nil ->
        :ok

      feed ->
        if match?({:error, _code}, outcome), do: Ingest.add_to_day(id, now, errors: 1)

        feed
        |> Feed.health_changeset(health(feed, now, outcome))
        |> Repo.update()
        |> case do
          {:ok, _feed} ->
            :ok

          {:error, changeset} ->
            Logger.warning(
              "#{job}: feed #{id}'s fetch not recorded: #{inspect(changeset.errors)}"
            )
        end
    end
  end

  defp health(_feed, now, :ok),
    do: %{last_fetch_at: now, last_ok_at: now, last_error: nil, failures: 0, retry_at: nil}

  defp health(feed, now, {:error, code}) do
    if backoff?(code) do
      failures = feed.failures + 1
      retry_at = DateTime.add(now, backoff_minutes(feed.interval_minutes, failures), :minute)
      %{last_fetch_at: now, last_error: code, failures: failures, retry_at: retry_at}
    else
      %{last_fetch_at: now, last_error: code}
    end
  end

  # §5: the host asked for less (429) or is failing (5xx).
  defp backoff?("http_" <> status) do
    case Integer.parse(status) do
      {429, ""} -> true
      {code, ""} -> code in 500..599
      _other -> false
    end
  end

  defp backoff?(_code), do: false

  # -- helpers -----------------------------------------------------------------

  defp user_agent(opts) do
    value =
      case Keyword.fetch(opts, :user_agent) do
        {:ok, value} -> value
        :error -> Keyword.get(config(), :user_agent)
      end

    if is_binary(value) and String.trim(value) != "", do: value
  end

  # A name with a trailing dot is the same name (C6), so `www.sec.gov.`
  # cannot skip the user agent or the pace.
  defp paced?(host) when is_binary(host) do
    host = String.trim_trailing(host, ".")
    host == @paced_host or String.ends_with?(host, "." <> @paced_host)
  end

  defp paced?(_host), do: false

  defp host(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" -> String.downcase(host)
      _other -> nil
    end
  end

  defp config, do: Application.get_env(:portfolixir, __MODULE__, [])
end
