defmodule Portfolixir.Chains.Esplora do
  @moduledoc """
  The chain source (ADR-0059 §3, §7, §10): Bitcoin's tip height and single
  blocks' hash, height and timestamp, read over the read-only Esplora REST
  API. It reads and checks; it **writes nothing** (the run that stores what
  it read is `Portfolixir.Chains`' reader).

  **Three reads, nothing else** (§1, §3):

  | Request | Answer read |
  |---|---|
  | `GET {base}/blocks/tip/height` | the tip height, as text |
  | `GET {base}/block-height/{height}` | the block hash at that height, as text |
  | `GET {base}/block/{hash}` | the block's `id`, `height` and `timestamp`, as JSON |

  **Sources.** `https://mempool.space/api` first, `https://blockstream.info/api`
  only when the first fails, both from the application config. The
  operator's own base URL (`PORTFOLIXIR_BITCOIN_ESPLORA_URL`, read at boot
  by `config/runtime.exs`, never written by the app) **replaces both** and
  has no fallback. It passes the URL policy with name resolution before
  every run (`check_own_url/1`): https, no userinfo, no query or fragment,
  a host that resolves to public addresses only. A refused own URL makes no
  request and fails the run with `url_not_allowed:<reason>`.

  **The client** (§7, B2). Every request goes through `Portfolixir.Net.Http`,
  GET only, under a 64 KiB byte cap and a 10-second deadline. Each source's
  client carries its own registered host as its allow-list (the config's
  `allowed_hosts`; the own URL's `:any` narrows to that URL's one host,
  and no other source may be `:any`: its client reaches nothing), so a base
  on any other host is refused by the chokepoint and makes no request. **A redirect is never followed**, not even within the same host:
  it fails the source with `redirect_refused`. Bodies are decoded here with
  string keys; no atom is ever made from an answer.

  **Every answer is checked before it is handed on** (§7):

    * the tip is a decimal integer of at most 12 digits (`invalid_tip`),
      not more than 6 below the last stored tip (`tip_behind`), not below
      the fourth halving's height 840,000 (`tip_too_low`), and not above the
      height ten-minute spacing gives for the time since the genesis block,
      times 1.1 (`tip_ahead`);
    * a hash has exactly 64 hex characters (`invalid_hash`), so a hash
      placed in a path is one segment of hex and nothing else;
    * a block has an `id`, an integer `height` and an integer `timestamp`
      (`invalid_block`), and its `id` and `height` echo the hash and height
      asked (`block_mismatch`);
    * a timestamp lies between the genesis block's time and the server's
      clock + 2 hours (`timestamp_out_of_bounds`);
    * of two blocks read at least 2,016 heights apart, the higher one has
      the later timestamp (`blocks_out_of_order`);
    * when the caller says the day's check is due, the hash at height 0 is
      Bitcoin's registered genesis hash (`wrong_chain`), so an instance on
      testnet or signet is refused.

  **Failure behaviour** (§7). A source that fails in any way (a timeout, a
  429, a 5xx or any other status, a refused connection, an oversized body,
  a redirect, a refused answer) is followed in the same run by the next
  source, which reads everything again: a reading is always one source's,
  never a mix (§13 item 2). When every source fails the answer is
  `{:error, failures}` and nothing is handed on, so nothing can be written.
  Each failure is a short code; no answer body is kept (§9).
  """

  alias Portfolixir.Chains.Registry
  alias Portfolixir.Net.Http
  alias Portfolixir.Net.UrlPolicy

  @chain :bitcoin
  # Bitcoin's genesis block timestamp, 2009-01-03 18:15:05 UTC: no block's
  # timestamp lies before it.
  @genesis_time 1_231_006_505
  # A block's timestamp may run ahead of the clock by two hours at most
  # (Bitcoin's own consensus rule for a block's time).
  @future_slack_seconds 2 * 60 * 60
  @max_tip_lag 6
  # The tip's floor (ADR-0059 §7, the attack lens): the fourth halving,
  # height 840,000, mined on 2024-04-20. A height the chain has passed never
  # comes back, so a lower tip is a lie or a node still syncing, and every
  # height a run asks below an honest tip (the tip, 2,016 below it, a past
  # halving) stays non-negative.
  @min_tip 4 * Registry.halving_interval(@chain)
  # The tip's ceiling (ADR-0059 §7, the attack lens): the height ten-minute
  # spacing gives for the time since the genesis block, times 11/10. The
  # chain ran 4.4 % ahead of that spacing at the fourth halving; 10 % is
  # more than twice that lead, so only a forged tip passes it.
  @tip_ceiling_factor {11, 10}
  @target_spacing Registry.target_spacing(@chain)
  @max_bytes 64 * 1024
  @deadline_ms 10_000
  @user_agent "portfolixir/0.1 (+https://github.com/portfolixir)"
  @accept "text/plain, application/json"
  @read_options [:last_tip, :genesis_due?, :now]

  @type source :: :mempool | :blockstream | :own
  @type block :: %{height: non_neg_integer(), hash: String.t(), timestamp: integer()}
  @type failure :: %{source: source(), host: String.t() | nil, error: String.t()}
  @type reading :: %{
          source: source(),
          host: String.t(),
          base: String.t(),
          tip: non_neg_integer(),
          blocks: %{non_neg_integer() => block()},
          genesis_checked: boolean(),
          attempts: [failure()]
        }

  @doc """
  One run's reads from the first source that answers them all: the tip,
  the genesis check when it is due, and the hash and block of every height
  `heights_for` returns for that tip. A result that is not a list of
  integers raises; a height outside 0 and the tip fails that source
  (`heights_out_of_range`) before any block is asked.

  `{:ok, reading}` carries the source, its host and base, the tip, the
  blocks by height, whether the genesis was checked, and the `attempts` of
  the sources that failed before it. `{:error, failures}` lists each
  source's failure, in order.

  Options: `:last_tip` (the last stored tip, for `tip_behind`; none by
  default; anything but a non-negative integer or `nil` raises, so a wrong
  type cannot turn the check off), `:genesis_due?` (a function of the source's host, true when the
  day's genesis check is due; always due by default), `:now` (the server's
  clock for the timestamp bound; `DateTime.utc_now/0` by default). Any
  other option raises: no caller hands this module a URL, a host or a
  request option.
  """
  @spec read((non_neg_integer() -> [non_neg_integer()]), keyword()) ::
          {:ok, reading()} | {:error, [failure()]}
  def read(heights_for, opts \\ []) when is_function(heights_for, 1) do
    opts = Keyword.validate!(opts, @read_options)
    validate_last_tip!(Keyword.get(opts, :last_tip))

    case sources() do
      {:ok, sources} -> first_answer(sources, heights_for, opts, [])
      {:error, failure} -> {:error, [failure]}
    end
  end

  @doc """
  The URL policy's check of the operator's own base URL, with name
  resolution and the URL's own host as the allow-list, plus no query and
  no fragment (a base, not a request): `:ok` or
  `{:error, {:url_not_allowed, reason}}`. `read/2` runs it before every run.
  """
  @spec check_own_url(term()) :: :ok | {:error, {:url_not_allowed, atom()}}
  def check_own_url(url) when is_binary(url) do
    uri = URI.parse(url)
    allowed = if is_binary(uri.host), do: [uri.host], else: []

    with :ok <- UrlPolicy.check(url, resolve: true, allowed_hosts: allowed) do
      if is_nil(uri.query) and is_nil(uri.fragment),
        do: :ok,
        else: {:error, {:url_not_allowed, :query}}
    end
  end

  def check_own_url(_url), do: {:error, {:url_not_allowed, :scheme}}

  @doc """
  The hosts the reads ask, in the order they ask them, and whether they are
  the operator's own URL (Sprint 29 H7): `%{own?: false, hosts:
  ["mempool.space", "blockstream.info"]}` from the config, or `%{own?: true,
  hosts: [its host]}` while `PORTFOLIXIR_BITCOIN_ESPLORA_URL` replaces both.
  The chart's health line names a host that is not the first one the
  fallback (ADR-0059 §8). Reads the config only; resolves and asks nothing.
  """
  @spec hosts() :: %{own?: boolean(), hosts: [String.t() | nil]}
  def hosts do
    config = config()

    case Keyword.get(config, :own_url) do
      nil ->
        %{
          own?: false,
          hosts: for({_source, base} <- Keyword.fetch!(config, :sources), do: host(base(base)))
        }

      url ->
        %{own?: true, hosts: [host(base(url))]}
    end
  end

  # -- sources -----------------------------------------------------------------

  defp sources do
    config = config()

    case Keyword.get(config, :own_url) do
      nil ->
        sources = Keyword.fetch!(config, :sources)

        # The own source is the operator's environment URL alone, checked
        # with name resolution; a config source named `:own` would borrow
        # its `:any` without that check.
        if Keyword.has_key?(sources, :own),
          do:
            raise(ArgumentError, "the own source comes from PORTFOLIXIR_BITCOIN_ESPLORA_URL only")

        {:ok, for({source, base} <- sources, do: {source, base(base)})}

      url ->
        base = base(url)

        case check_own_url(base) do
          :ok -> {:ok, [{:own, base}]}
          {:error, reason} -> {:error, failure({:own, base}, error_code(reason))}
        end
    end
  end

  defp base(url), do: url |> String.trim() |> String.trim_trailing("/")

  defp first_answer([], _heights_for, _opts, failures), do: {:error, Enum.reverse(failures)}

  defp first_answer([source | rest], heights_for, opts, failures) do
    case read_source(source, heights_for, opts) do
      {:ok, reading} ->
        {:ok, Map.put(reading, :attempts, Enum.reverse(failures))}

      {:error, code} ->
        first_answer(rest, heights_for, opts, [failure(source, code) | failures])
    end
  end

  defp failure({source, base}, code), do: %{source: source, host: host(base), error: code}

  defp host(base), do: URI.parse(base).host

  # -- one source's reads ------------------------------------------------------

  defp read_source({source, base}, heights_for, opts) do
    req = client(source, base)
    host = host(base)
    genesis? = genesis_due?(opts, host)

    now = now(opts)

    with {:ok, tip} <- tip(req, base, Keyword.get(opts, :last_tip), now),
         :ok <- if(genesis?, do: genesis(req, base), else: :ok),
         {:ok, heights} <- heights(heights_for, tip),
         {:ok, blocks} <- blocks(req, base, heights, now),
         :ok <- in_order(blocks) do
      {:ok,
       %{
         source: source,
         host: host,
         base: base,
         tip: tip,
         blocks: blocks,
         genesis_checked: genesis?
       }}
    end
  end

  defp tip(req, base, last_tip, now) do
    with {:ok, body} <- get(req, base <> "/blocks/tip/height"),
         {:ok, tip} <- parse_height(body) do
      cond do
        is_integer(last_tip) and tip < last_tip - @max_tip_lag -> {:error, "tip_behind"}
        tip < @min_tip -> {:error, "tip_too_low"}
        tip > tip_ceiling(now) -> {:error, "tip_ahead"}
        true -> {:ok, tip}
      end
    end
  end

  defp tip_ceiling(now) do
    {numerator, denominator} = @tip_ceiling_factor

    div((DateTime.to_unix(now) - @genesis_time) * numerator, @target_spacing * denominator)
  end

  defp genesis(req, base) do
    with {:ok, hash} <- hash_at(req, base, 0) do
      if hash == Registry.genesis_hash(@chain), do: :ok, else: {:error, "wrong_chain"}
    end
  end

  defp blocks(req, base, heights, now) do
    Enum.reduce_while(heights, {:ok, %{}}, fn height, {:ok, acc} ->
      case block(req, base, height, now) do
        {:ok, block} -> {:cont, {:ok, Map.put(acc, height, block)}}
        {:error, code} -> {:halt, {:error, code}}
      end
    end)
  end

  defp block(req, base, height, now) do
    with {:ok, hash} <- hash_at(req, base, height),
         # The hash is 64 hex characters (parse_hash/1): one path segment.
         {:ok, body} <- get(req, base <> "/block/" <> hash),
         {:ok, fields} <- decode_block(body),
         :ok <- echoes(fields, hash, height),
         :ok <- in_bounds(fields.timestamp, now) do
      {:ok, %{height: height, hash: hash, timestamp: fields.timestamp}}
    end
  end

  defp hash_at(req, base, height) do
    with {:ok, body} <- get(req, base <> "/block-height/" <> Integer.to_string(height)) do
      parse_hash(body)
    end
  end

  # -- the checks --------------------------------------------------------------

  defp parse_height(body) do
    text = String.trim(body)

    if Regex.match?(~r/\A[0-9]{1,12}\z/, text),
      do: {:ok, String.to_integer(text)},
      else: {:error, "invalid_tip"}
  end

  defp parse_hash(body) do
    text = String.trim(body)

    if Regex.match?(~r/\A[0-9a-fA-F]{64}\z/, text),
      do: {:ok, String.downcase(text)},
      else: {:error, "invalid_hash"}
  end

  defp decode_block(body) do
    case Jason.decode(body) do
      {:ok, %{"id" => id, "height" => height, "timestamp" => timestamp}}
      when is_binary(id) and is_integer(height) and is_integer(timestamp) ->
        {:ok, %{id: id, height: height, timestamp: timestamp}}

      _other ->
        {:error, "invalid_block"}
    end
  end

  defp echoes(%{id: id, height: height}, hash, height) do
    if String.downcase(id) == hash, do: :ok, else: {:error, "block_mismatch"}
  end

  defp echoes(_fields, _hash, _height), do: {:error, "block_mismatch"}

  defp in_bounds(timestamp, now) do
    if timestamp >= @genesis_time and
         timestamp <= DateTime.to_unix(now) + @future_slack_seconds,
       do: :ok,
       else: {:error, "timestamp_out_of_bounds"}
  end

  # The blocks of one run against each other (ADR-0059 §7, the attack
  # lens): of two blocks read at least 2,016 heights apart, the higher one
  # is the later. A block's time may run behind its predecessors' by an
  # hour or two, never by two weeks of blocks; so a tip block older than
  # the block 2,016 below it, which would make the recent mean block time
  # negative, fails the source.
  defp in_order(blocks) do
    sorted = blocks |> Map.values() |> Enum.sort_by(& &1.height)

    ordered? =
      for low <- sorted, high <- sorted, high.height - low.height >= 2016, reduce: true do
        acc -> acc and high.timestamp > low.timestamp
      end

    if ordered?, do: :ok, else: {:error, "blocks_out_of_order"}
  end

  defp validate_last_tip!(nil), do: :ok
  defp validate_last_tip!(tip) when is_integer(tip) and tip >= 0, do: :ok

  defp validate_last_tip!(tip),
    do:
      raise(ArgumentError, "last_tip must be a non-negative integer or nil, got: #{inspect(tip)}")

  # A result that is not a list of integers is the caller's bug and raises.
  # An integer outside 0..tip follows from the tip, which is the source's
  # claim, so it fails that source and the next one is asked (the attack
  # lens: a hostile tip crashed the run instead of asking the fallback).
  defp heights(heights_for, tip) do
    heights = heights_for.(tip)

    cond do
      not (is_list(heights) and Enum.all?(heights, &is_integer/1)) ->
        raise ArgumentError, "heights_for must return a list of integer heights"

      Enum.all?(heights, &(&1 >= 0 and &1 <= tip)) ->
        {:ok, Enum.uniq(heights)}

      true ->
        {:error, "heights_out_of_range"}
    end
  end

  defp genesis_due?(opts, host) do
    case Keyword.get(opts, :genesis_due?) do
      nil -> true
      due? when is_function(due?, 1) -> due?.(host) == true
    end
  end

  defp now(opts), do: Keyword.get(opts, :now) || DateTime.utc_now()

  # -- the request -------------------------------------------------------------

  defp client(source, base) do
    Http.new(
      max_bytes: @max_bytes,
      allowed_hosts: allowed_hosts(source, base),
      deadline_ms: @deadline_ms,
      receive_timeout: @deadline_ms,
      max_redirects: 0,
      decode_body: false,
      headers: [{"user-agent", @user_agent}, {"accept", @accept}]
    )
    |> merge_test_plug()
  end

  # The source's registered hosts; the own URL's `:any` narrows to the
  # base's one host. Only `:own` may be `:any` (the attack lens: a config
  # source `extra: :any` reached any host); any other source's `:any`, and a
  # source the config does not list, reach nothing, so the chokepoint
  # refuses its first request (`url_not_allowed:host_not_allowed`).
  defp allowed_hosts(source, base) do
    case Map.get(Keyword.get(config(), :allowed_hosts, %{}), source, []) do
      :any when source == :own -> [host(base)]
      hosts when is_list(hosts) -> hosts
      _other -> []
    end
  end

  defp merge_test_plug(req) do
    case Keyword.get(config(), :plug) do
      nil -> req
      plug -> Req.merge(req, plug: plug)
    end
  end

  defp get(req, url) do
    case Http.get(req, url: url) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "http_#{status}"}
      {:error, reason} -> {:error, error_code(reason)}
    end
  end

  # Req's exceptions are matched by shape, as the news fetcher matches them.
  defp error_code(:deadline), do: "timeout"
  defp error_code(%{__exception__: true, reason: :timeout}), do: "timeout"
  defp error_code(%Http.BodyTooLarge{}), do: "body_too_large"
  defp error_code({:url_not_allowed, reason}), do: "url_not_allowed:#{reason}"
  defp error_code(:too_many_redirects), do: "redirect_refused"
  defp error_code(%{__exception__: true, reason: _reason}), do: "transport_error"
  defp error_code(_other), do: "fetch_failed"

  defp config, do: Application.get_env(:portfolixir, __MODULE__, [])
end
