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
  """
  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.News.Source
  alias Portfolixir.Repo

  @type tier :: :primary | :secondary | :awareness | :blocked
  @type class :: :issuer | :regulatory | :aggregator | :thematic

  @by_construction [:issuer, :regulatory]

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
  def lookup(domains) when is_list(domains) do
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
        tier = Enum.find_value(suffixes, &Map.get(rated, &1)),
        into: %{},
        do: {domain, tier}
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

      Multi.new()
      |> Multi.run(:claim, fn repo, _changes -> claim(repo, domain, attrs) end)
      |> Multi.run(:prior, fn _repo, %{claim: claim} -> {:ok, prior(claim)} end)
      |> Multi.run(:source, fn repo, %{claim: claim} -> written(repo, claim, attrs) end)
      |> Journal.record(actor,
        resource_type: "news_source",
        operation: :upsert,
        source: :source,
        before_step: :prior
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{source: source}} -> {:ok, source}
        {:error, :source, {:kept, prior}, _changes} -> {:kept, prior}
        {:error, :source, {:unchanged, prior}, _changes} -> {:ok, prior}
        {:error, :source, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
        {:error, :claim, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
      end
    end
  end

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
