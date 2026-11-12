defmodule Portfolixir.News.Sources do
  @moduledoc """
  The tier table (ADR-0056 §3) and the tier an item is stored with (B5).

  `news_sources` maps a domain to `primary`, `secondary`, `awareness` or
  `blocked` (`Portfolixir.News.Source`). This module reads it and writes it.

  ## The tier of an item (`tier/2`, `tier_for/2`)

    * **An unknown domain is `awareness`** until someone rates it (§3).
    * **`primary` comes only by construction** (B5): an `issuer` or a
      `regulatory` item is `primary` whatever its domain's row says — the
      feed belongs to the security, so its items are the issuer's or the
      regulator's own word, wherever their links point (a newsroom hosted
      on a wire service's domain is still the issuer's).
    * **An `aggregator` item is at most `secondary`** (B5): its domain is a
      claim inside the item (`<source>`), so a domain rated `primary` gives
      it `secondary`. A `thematic` item is capped the same way: B5 gives
      `primary` to issuer and regulatory feeds only, and a sector feed is
      neither.
    * **A `blocked` domain is `blocked` for every class**, by-construction
      ones included: the operator's block is the stronger statement, and the
      item is dropped at ingest and counted (`dropped_blocked`, §3). A
      blocked item is never stored.

  ## How a domain is matched

  A domain is **normalized** (`normalize_domain/1`): trimmed, lower-cased,
  a trailing dot removed and one leading `www.` removed, so `WWW.Example.com.`
  and `example.com` are one source. An international name is kept as
  received, lower-cased: the table stores names in their punycode form only
  (the shape `Portfolixir.News.Shapes.domain/2` checks), so a Unicode name
  is refused by `put_source/4` and matches no row on a read (`awareness`).

  **A row covers its subdomains** unless a subdomain has a row of its own:
  the longest stored suffix on a label boundary wins, so a rating of
  `example.com` reads for `markets.example.com`, and a block of a domain
  cannot be dodged by a fresh subdomain. A suffix of one label (`com`) is
  never looked up, so a single-label row matches only itself.

  ## Writes (`put_source/4`)

  Journaled under the writer's actor as a `news_source` upsert (B7; the
  table is armed with the journal-actor guard). `set_by: :hand` is the
  operator's or the agent's correction; `set_by: :seed` is a seed's or an
  import's rating. **A correction by hand is never overwritten by a later
  seed** (§3, ADR-0044 §2's invariant): a seed write onto a `hand` row
  writes and journals nothing and answers `{:kept, row}`.

  **A write that changes a row's tier re-rates the stored items it covers**
  (ADR-0056 E1), in the same transaction: `Portfolixir.News.Retier`. The
  journal entry's after-image carries, beside the row, the counts
  `items_rerated`, `items_removed` and `items_kept_promoted`.
  """
  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.News.Retier
  alias Portfolixir.News.Source
  alias Portfolixir.Repo

  @type tier :: :primary | :secondary | :awareness | :blocked
  @type class :: :issuer | :regulatory | :aggregator | :thematic

  @by_construction [:issuer, :regulatory]

  # --- S29 N1 begin ---
  # How often a rating runs again when its items moved (`put_attempt/4`).
  @attempts 3
  # --- S29 N1 end ---

  # --- S28 N7 begin ---
  @doc """
  Every rated domain (§3), by domain: what the news page's „Quellen“ tab
  shows (ADR-0056 §10). An unrated domain has no row and reads as
  `awareness`.
  """
  @spec list() :: [Source.t()]
  def list, do: Repo.all(from(s in Source, order_by: s.domain))

  # --- S28 N7 end ---

  @doc """
  The tier an item of `class` from `domain` is stored with, or `:blocked`
  when it must be dropped. Reads the table; see the moduledoc.
  """
  @spec tier_for(String.t(), class()) :: tier()
  def tier_for(domain, class) when is_binary(domain),
    do: tier(class, Map.get(lookup([domain]), domain))

  @doc """
  The tier rule without the table: `rated` is the domain's stored tier, or
  `nil` for an unknown domain.
  """
  @spec tier(class(), tier() | nil) :: tier()
  def tier(_class, :blocked), do: :blocked
  def tier(class, _rated) when class in @by_construction, do: :primary
  def tier(_class, nil), do: :awareness
  def tier(_class, :primary), do: :secondary
  def tier(_class, rated) when rated in [:secondary, :awareness], do: rated

  @doc "Whether `domain` (or a parent domain of it) is rated `blocked`."
  @spec blocked?(String.t()) :: boolean()
  def blocked?(domain) when is_binary(domain), do: lookup([domain]) == %{domain => :blocked}

  @doc """
  The stored tier of each of `domains` that has one (by itself or through a
  parent domain), keyed by the domain as given; an unknown domain is left
  out. One query for the whole list.
  """
  @spec lookup([String.t()]) :: %{String.t() => tier()}
  def lookup(domains) when is_list(domains),
    do: Map.new(deciding_rows(domains), fn {domain, {_row, tier}} -> {domain, tier} end)

  # --- S29 N1 begin ---
  @doc """
  The stored domain whose row decides each of `domains` (§3's longest
  suffix on a label boundary), keyed by the domain as given; a domain no
  row decides is left out. One query for the whole list. The re-rating of
  ADR-0056 E1 (`Portfolixir.News.Retier`) keeps the items a row decides.
  """
  @spec decider([String.t()]) :: %{String.t() => String.t()}
  def decider(domains) when is_list(domains),
    do: Map.new(deciding_rows(domains), fn {domain, {row, _tier}} -> {domain, row} end)

  # The first key of the tier locks (`pg_advisory_xact_lock(int, int)`),
  # distinct from the app's other advisory locks; the second is a domain's
  # hash. `Portfolixir.LockTable`, rows 22 and 23.
  @tier_lock 727_227_007

  @doc """
  The rating's tier locks (ADR-0056 E1, "Order"; `Portfolixir.LockTable`,
  row 22), for the caller's open transaction: `domain`'s own key
  exclusive, and the key of each parent domain of at least two labels
  shared, in ascending key order.

  The fetch takes the key of every suffix of its items' domains shared
  (`lock_ingest/1`) before it reads their tiers, and holds it until its
  items commit. So a rating waits for every fetch storing an item its row
  could decide, and re-rates what those fetches stored; a fetch that
  starts while a rating holds its key reads the tier the rating wrote.
  Two ratings of which one domain is a suffix of the other meet at the
  shorter's key (exclusive against shared), so the later reads the
  earlier's row; two ratings of unrelated domains do not wait for each
  other.
  """
  @spec lock_rating(String.t()) :: :ok
  def lock_rating(domain) when is_binary(domain) do
    [own | parents] = domain |> normalize_domain() |> suffixes()
    own_key = tier_key(own)

    parents
    |> Enum.map(&tier_key/1)
    |> Enum.reject(&(&1 == own_key))
    |> Enum.map(&{&1, :shared})
    |> Enum.concat([{own_key, :exclusive}])
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.sort()
    |> Enum.each(fn
      {key, :exclusive} ->
        Repo.query!("SELECT pg_advisory_xact_lock($1, $2) /* news tier: rating */", [
          @tier_lock,
          key
        ])

      {key, :shared} ->
        Repo.query!("SELECT pg_advisory_xact_lock_shared($1, $2) /* news tier: parent */", [
          @tier_lock,
          key
        ])
    end)
  end

  @doc """
  The fetch's tier locks (`Portfolixir.LockTable`, row 23), for the
  caller's open transaction: the key of every suffix of `domains` (as
  `lookup/1` reads them) shared, in ascending key order. See
  `lock_rating/1`.
  """
  @spec lock_ingest([String.t()]) :: :ok
  def lock_ingest(domains) when is_list(domains) do
    domains
    |> Enum.flat_map(&suffixes(normalize_domain(&1)))
    |> Enum.map(&tier_key/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.each(
      &Repo.query!("SELECT pg_advisory_xact_lock_shared($1, $2) /* news tier: ingest */", [
        @tier_lock,
        &1
      ])
    )
  end

  defp tier_key(domain), do: :erlang.phash2(domain)

  # --- S29 N1 end ---

  defp deciding_rows(domains) do
    suffixes_by_domain = Map.new(domains, &{&1, suffixes(normalize_domain(&1))})
    candidates = suffixes_by_domain |> Map.values() |> List.flatten() |> Enum.uniq()

    rated =
      if candidates == [],
        do: %{},
        else:
          Map.new(
            Repo.all(
              from(s in Source, where: s.domain in ^candidates, select: {s.domain, s.tier})
            )
          )

    for {domain, suffixes} <- suffixes_by_domain,
        row = Enum.find(suffixes, &Map.has_key?(rated, &1)),
        into: %{},
        do: {domain, {row, Map.fetch!(rated, row)}}
  end

  # The domain itself, then each parent of at least two labels, longest first.
  defp suffixes(domain) do
    labels = String.split(domain, ".")
    count = length(labels)

    if count < 2,
      do: [domain],
      else: for(drop <- 0..(count - 2), do: labels |> Enum.drop(drop) |> Enum.join("."))
  end

  @doc """
  A domain as the table stores and matches it: trimmed, lower-case, without
  a trailing dot and without one leading `www.`.
  """
  @spec normalize_domain(String.t()) :: String.t()
  def normalize_domain(domain) when is_binary(domain) do
    domain
    |> String.trim()
    |> String.downcase()
    |> String.trim_trailing(".")
    |> case do
      "www." <> rest when rest != "" -> rest
      normalized -> normalized
    end
  end

  @doc """
  Rates `domain` as `tier` on behalf of `actor`, journaled (see the
  moduledoc). `set_by:` is `:hand` (the default) or `:seed`.

  Answers `{:ok, source}` for a write (or a write that changed nothing,
  which records nothing), `{:kept, source}` when a seed met a hand row, or
  `{:error, changeset}`.
  """
  @spec put_source(Actor.t(), String.t(), tier() | String.t(), keyword()) ::
          {:ok, Source.t()} | {:kept, Source.t()} | {:error, Ecto.Changeset.t()}
  def put_source(%Actor{} = actor, domain, tier, opts \\ []) when is_binary(domain) do
    set_by = Keyword.get(opts, :set_by, :hand)

    unless set_by in [:hand, :seed],
      do: raise(ArgumentError, "set_by is :hand or :seed, got: #{inspect(set_by)}")

    attrs = %{domain: normalize_domain(domain), tier: tier, set_by: set_by}
    changeset = Source.changeset(%Source{}, attrs)

    with {:ok, _valid} <- Ecto.Changeset.apply_action(changeset, :insert) do
      domain = Ecto.Changeset.get_field(changeset, :domain)
      now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
      put_attempt(actor, {domain, attrs, changeset}, now, @attempts)
    end
  end

  # --- S29 N1 begin ---
  # E1: an item that moved between scopes while the re-rating took its
  # locks (`Retier`, `:moved`) rolls the write back, releasing every lock,
  # and the next attempt reads it where it is now, as `news.assign` runs
  # again (D4). After the last attempt the write is refused naming `domain`.
  defp put_attempt(_actor, {_domain, _attrs, changeset}, _now, 0) do
    {:error,
     Ecto.Changeset.add_error(
       changeset,
       :domain,
       "its items moved between stories while it was rated: send it again"
     )}
  end

  defp put_attempt(actor, {domain, attrs, _changeset} = put, now, attempts) do
    Multi.new()
    |> Multi.run(:claim, fn repo, _changes -> claim(repo, domain, attrs) end)
    |> Multi.run(:prior, fn _repo, %{claim: claim} -> {:ok, prior(claim)} end)
    |> Multi.run(:source, fn repo, %{claim: claim} -> written(repo, claim, attrs) end)
    |> Multi.run(:retier, fn _repo, %{prior: prior, source: source} ->
      Retier.run(prior, source, now)
    end)
    |> Multi.run(:image, fn _repo, %{source: source, retier: counts} ->
      {:ok, image(source, counts)}
    end)
    |> Journal.record(actor,
      resource_type: "news_source",
      operation: :upsert,
      source: :image,
      before_step: :prior
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{source: source}} -> {:ok, source}
      {:error, :source, {:kept, prior}, _changes} -> {:kept, prior}
      {:error, :source, {:unchanged, prior}, _changes} -> {:ok, prior}
      {:error, :source, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
      {:error, :claim, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
      {:error, :retier, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
      {:error, :retier, :moved, _changes} -> put_attempt(actor, put, now, attempts - 1)
    end
  end

  # E1 rule 6: the journal entry's after-image is the row as written and,
  # beside its tier, the counts of the items the write re-rated, removed and
  # left because promoted.
  defp image(%Source{} = source, counts),
    do: source |> Map.take(Source.__schema__(:fields)) |> Map.merge(counts)

  # --- S29 N1 end ---

  # --- S28 N4 begin ---
  # #1424: the domain's row, read under its lock, or this put's insert. A
  # read that finds no row does not decide the insert: another put may
  # insert the domain between the two (the flaky IngestTest's "has already
  # been taken"). So the insert yields to a row that exists by then (ON
  # CONFLICT DO NOTHING waits for the other put's transaction), and that
  # row, read again under the lock, is this put's prior: the later put
  # lands on the earlier's row, and the journal chains the two.
  defp claim(repo, domain, attrs) do
    case locked(repo, domain) do
      %Source{} = row ->
        {:ok, {:existing, row}}

      nil ->
        case repo.insert(Source.changeset(%Source{}, attrs),
               on_conflict: :nothing,
               conflict_target: :domain
             ) do
          {:ok, %Source{id: nil}} -> {:ok, {:existing, locked(repo, domain)}}
          {:ok, %Source{} = inserted} -> {:ok, {:inserted, inserted}}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  defp locked(repo, domain),
    do: repo.one(from(s in Source, where: s.domain == ^domain, lock: "FOR UPDATE"))

  defp prior({:existing, row}), do: row
  defp prior({:inserted, _row}), do: nil

  defp written(_repo, {:inserted, row}, _attrs), do: {:ok, row}
  defp written(repo, {:existing, row}, attrs), do: write(repo, row, attrs)

  # --- S28 N4 end ---

  # §3: a seed leaves a hand row as it is. A write equal to the stored row
  # writes nothing, so it records no entry either. Both end the transaction
  # before the journal step.
  defp write(_repo, %Source{set_by: :hand} = prior, %{set_by: :seed}),
    do: {:error, {:kept, prior}}

  defp write(repo, %Source{} = prior, attrs) do
    changeset = Source.changeset(prior, attrs)

    if changeset.changes == %{},
      do: {:error, {:unchanged, prior}},
      else: repo.update(changeset)
  end
end
