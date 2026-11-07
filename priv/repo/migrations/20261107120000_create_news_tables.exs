defmodule Portfolixir.Repo.Migrations.CreateNewsTables do
  @moduledoc """
  ADR-0056 §2 to §6, A3 and the amendment of 2026-11-07 (B3 to B5): the news
  layer's tables — `news_sources`, `news_feeds`, `news_clusters`,
  `news_items` and `news_feed_days`. The labels of §7 are Sprint 28's.

  Every rule a row's own fields can state is a CHECK here, behind the
  changesets' field errors (`Portfolixir.News.*`), so a writer that skips a
  changeset still cannot store what the record forbids:

    * the closed sets: a feed's and an item's class, a tier, an item's
      `assignment` and `status`, a source's `set_by`;
    * a feed's binding by its class (§2): `issuer` and `regulatory` name a
      security and no category, `thematic` a category and no security,
      `aggregator` neither; an item's binding the same way, an aggregator's
      item bound to a security only once `assigned`;
    * `published_at` is the feed's claim clamped to `first_seen_at`, the
      server's clock (B4): exactly `least(coalesce(claim, first_seen_at),
      first_seen_at)`;
    * an aggregator's item is never `primary` (B5); no stored item or story
      is `blocked` (a blocked domain's items are dropped at ingest, §3);
    * candidates only on an `ambiguous` item, and then at least two (§2);
      a `promoted` item names at least one note (§8);
    * a title of 1 to 160 characters and an excerpt of at most 600 (§4),
      counted in characters, without control characters; invisible
      characters are kept as received (plan D-6);
    * URLs: a feed's https only, without userinfo, at most 2,048 characters
      (B2); an item's canonical URL http or https (it is shown, never
      fetched: §2 follows no redirect), at most 2,048; domains lower-case;
      languages a lower-case code of 2 to 8 characters; hashes 64
      lower-case hex digits (SHA-256);
    * a feed's interval 1 to 1,440 minutes (a feed fetched less often than
      daily would read `stale` by design, §6); its backoff state never
      negative, a `retry_at` only after a failure, `last_ok_at` never after
      `last_fetch_at`;
    * a story: exactly one of security and category, at least one member,
      its earliest publication never after its earliest first sight; an
      item sits only in a story of its own security (or category) and
      language — composite foreign keys, which follow a story's security
      when a merge moves it (`ON UPDATE CASCADE`), and only an assigned
      item sits in one;
    * counters never negative.

  An item's class is its feed's: a composite key onto `(id, class)` of the
  feed, so a feed's class cannot change under its items.

  **Unique:** a source per domain; a feed per URL (registering it twice
  would fetch it twice); an item per `(feed_id, canonical_url)` — a re-fetch
  of a feed lists the same items again, and the publisher's link stays the
  same when the publisher edits the title or the summary, which would change
  the content hash: so a re-fetch stores nothing new, and the content hash is
  left to cross-feed dedupe (N5).

  **Foreign keys: nothing removes a row by cascade.** The references onto
  `securities` restrict (ADR-0050 §11) and are declared in
  `Portfolixir.Lifecycle.ForeignKeys` with a merge disposition of
  `:repoint`; the references onto `classification_categories` restrict, and
  a category's delete answers them as a changeset error. An item's feed
  restricts too: a feed's delete detaches its items first (`feed_id` set to
  NULL, so they age out by retention and a promoted one stays, §12) and
  removes its day rows; a story restricts the delete of its items, and an
  item the delete of a story naming it as representative.

  A representative's membership in its own story is not a constraint: it
  would need a key checked at commit, which the test sandbox never reaches,
  so a violation would surface only in production. The clustering keeps it.

  **The journal (B7).** Feeds and sources are master data, journaled by
  their writers, and armed here with the journal-actor guard: a source on
  every write, a feed on its insert, its delete and an update of what its
  registration states (class, URL, binding, enabled, interval, language) —
  not on the fetcher's health columns (`last_ok_at`, `last_fetch_at`,
  `last_error`, `failures`, `retry_at`), operational state written on every
  fetch. Items, stories and the day counters are a staging area a system job
  writes, unjournaled and unarmed (`Portfolixir.Journal.Allowlist`).
  """
  use Ecto.Migration

  # An unknown class is the class check's refusal alone: the binding checks
  # pass it, so each refusal names its own rule.
  @classes "('issuer', 'regulatory', 'aggregator', 'thematic')"
  @tiers "('primary', 'secondary', 'awareness', 'blocked')"
  @stored_tiers "('primary', 'secondary', 'awareness')"
  @language "language ~ '^[a-z]{2,3}(-[a-z0-9]{1,5})?$'"
  @domain "~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$' " <>
            "AND char_length(%{column}) <= 253"
  @item_url "~ '^https?://[^[:space:]]+$' AND char_length(%{column}) <= 2048"
  @hex64 "~ '^[0-9a-f]{64}$'"
  @controls "'[\\x01-\\x1f\\x7f-\\x9f]'"
  @multiline_controls "'[\\x01-\\x08\\x0b\\x0c\\x0e-\\x1f\\x7f-\\x9f]'"

  def up do
    # --- news_sources (§3) -----------------------------------------------
    create table(:news_sources) do
      add(:domain, :string, size: 253, null: false)
      add(:tier, :string, null: false)
      add(:set_by, :string, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:news_sources, [:domain]))
    check(:news_sources, :domain, "domain " <> domain("domain"))
    check(:news_sources, :tier, "tier IN #{@tiers}")
    check(:news_sources, :set_by, "set_by IN ('hand', 'seed')")

    # --- news_feeds (§2, §4, §5) -----------------------------------------
    create table(:news_feeds) do
      add(:class, :string, null: false)
      add(:url, :text, null: false)
      add(:security_id, references(:securities, on_delete: :restrict))
      add(:category_id, references(:classification_categories, on_delete: :restrict))
      add(:enabled, :boolean, null: false, default: true)
      add(:interval_minutes, :integer, null: false)
      add(:language, :string, size: 8, null: false)
      add(:last_ok_at, :utc_datetime_usec)
      add(:last_fetch_at, :utc_datetime_usec)
      add(:last_error, :text)
      add(:failures, :integer, null: false, default: 0)
      add(:retry_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:news_feeds, [:url]))
    create(unique_index(:news_feeds, [:id, :class]))
    create(index(:news_feeds, [:security_id]))
    create(index(:news_feeds, [:category_id]))
    check(:news_feeds, :class, "class IN #{@classes}")

    check(
      :news_feeds,
      :binding,
      "(class IN ('issuer', 'regulatory') AND security_id IS NOT NULL AND category_id IS NULL) " <>
        "OR (class = 'thematic' AND category_id IS NOT NULL AND security_id IS NULL) " <>
        "OR (class = 'aggregator' AND security_id IS NULL AND category_id IS NULL) " <>
        "OR class NOT IN #{@classes}"
    )

    check(
      :news_feeds,
      :url,
      "url ~ '^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?([/?#][^[:space:]]*)?$' " <>
        "AND char_length(url) <= 2048"
    )

    check(:news_feeds, :interval_minutes, "interval_minutes BETWEEN 1 AND 1440")
    check(:news_feeds, :language, @language)
    check(:news_feeds, :failures, "failures >= 0")
    check(:news_feeds, :retry_at, "retry_at IS NULL OR failures > 0")

    check(
      :news_feeds,
      :last_ok_at,
      "last_ok_at IS NULL OR (last_fetch_at IS NOT NULL AND last_ok_at <= last_fetch_at)"
    )

    check(
      :news_feeds,
      :last_error,
      "last_error IS NULL OR (char_length(last_error) BETWEEN 1 AND 500 " <>
        "AND last_error !~ #{@controls})"
    )

    # --- news_items (§4) and news_clusters (§4, B3) ----------------------
    # The two reference each other: an item its story, a story its
    # representative. Items first, the story references added after.
    create table(:news_items) do
      add(:feed_id, references(:news_feeds, on_delete: :restrict))
      add(:class, :string, null: false)
      add(:security_id, references(:securities, on_delete: :restrict))
      add(:category_id, references(:classification_categories, on_delete: :restrict))
      add(:cluster_id, :bigint)
      add(:published_at, :utc_datetime_usec, null: false)
      add(:published_at_claimed, :utc_datetime_usec)
      add(:first_seen_at, :utc_datetime_usec, null: false)
      add(:title, :text, null: false)
      add(:canonical_url, :text, null: false)
      add(:domain, :string, size: 253, null: false)
      add(:tier, :string, null: false)
      add(:language, :string, size: 8, null: false)
      add(:excerpt, :text)
      add(:content_hash, :string, size: 64, null: false)
      add(:title_norm_hash, :string, size: 64, null: false)
      add(:title_words, {:array, :text}, null: false, default: [])
      add(:assignment, :string, null: false)
      add(:candidates, {:array, :bigint}, null: false, default: [])
      add(:status, :string, null: false, default: "new")
      add(:note_ids, {:array, :bigint}, null: false, default: [])

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:news_items, [:feed_id, :canonical_url]))
    create(index(:news_items, [:security_id, :first_seen_at]))
    create(index(:news_items, [:category_id, :first_seen_at]))
    create(index(:news_items, [:cluster_id]))
    create(index(:news_items, [:first_seen_at]))
    create(index(:news_items, [:feed_id, :first_seen_at]))
    create(index(:news_items, [:content_hash]))

    create(
      index(:news_items, [:assignment, :first_seen_at],
        where: "assignment <> 'assigned'",
        name: :news_items_open_assignment_index
      )
    )

    check(:news_items, :class, "class IN #{@classes}")
    check(:news_items, :assignment, "assignment IN ('assigned', 'unassigned', 'ambiguous')")
    check(:news_items, :status, "status IN ('new', 'promoted', 'muted')")

    check(
      :news_items,
      :tier,
      "tier IN #{@stored_tiers} AND (class <> 'aggregator' OR tier <> 'primary')"
    )

    check(
      :news_items,
      :binding,
      "(class IN ('issuer', 'regulatory') AND assignment = 'assigned' " <>
        "AND security_id IS NOT NULL AND category_id IS NULL) " <>
        "OR (class = 'thematic' AND assignment = 'assigned' " <>
        "AND category_id IS NOT NULL AND security_id IS NULL) " <>
        "OR (class = 'aggregator' AND category_id IS NULL " <>
        "AND (assignment = 'assigned') = (security_id IS NOT NULL)) " <>
        "OR class NOT IN #{@classes}"
    )

    check(
      :news_items,
      :candidates,
      "array_position(candidates, NULL) IS NULL AND " <>
        "((assignment = 'ambiguous' AND cardinality(candidates) >= 2) " <>
        "OR (assignment <> 'ambiguous' AND cardinality(candidates) = 0))"
    )

    check(
      :news_items,
      :published_at,
      "published_at = LEAST(COALESCE(published_at_claimed, first_seen_at), first_seen_at)"
    )

    check(
      :news_items,
      :title,
      "char_length(title) <= 160 AND char_length(btrim(title)) >= 1 " <>
        "AND title !~ #{@controls}"
    )

    check(
      :news_items,
      :excerpt,
      "excerpt IS NULL OR (char_length(excerpt) <= 600 AND excerpt !~ #{@multiline_controls})"
    )

    check(:news_items, :canonical_url, "canonical_url " <> item_url("canonical_url"))
    check(:news_items, :domain, "domain " <> domain("domain"))
    check(:news_items, :language, @language)
    check(:news_items, :content_hash, "content_hash #{@hex64}")
    check(:news_items, :title_norm_hash, "title_norm_hash #{@hex64}")

    check(
      :news_items,
      :title_words,
      "cardinality(title_words) <= 160 AND array_position(title_words, NULL) IS NULL"
    )

    check(
      :news_items,
      :note_ids,
      "array_position(note_ids, NULL) IS NULL " <>
        "AND (status <> 'promoted' OR cardinality(note_ids) >= 1)"
    )

    check(:news_items, :cluster, "cluster_id IS NULL OR assignment = 'assigned'")

    # The composite keys' target: an item's (id, ...) pair is unique because
    # its id is.
    create table(:news_clusters) do
      add(:security_id, references(:securities, on_delete: :restrict))
      add(:category_id, references(:classification_categories, on_delete: :restrict))
      add(:language, :string, size: 8, null: false)

      add(:representative_item_id, references(:news_items, on_delete: :restrict), null: false)

      add(:member_count, :integer, null: false)
      add(:earliest_first_seen_at, :utc_datetime_usec, null: false)
      add(:earliest_published_at, :utc_datetime_usec, null: false)
      add(:earliest_url, :text, null: false)
      add(:best_tier, :string, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:news_clusters, [:security_id, :language]))
    create(index(:news_clusters, [:category_id, :language]))
    create(index(:news_clusters, [:representative_item_id]))
    create(unique_index(:news_clusters, [:id, :security_id, :language]))
    create(unique_index(:news_clusters, [:id, :category_id, :language]))

    check(
      :news_clusters,
      :scope,
      "(security_id IS NULL) <> (category_id IS NULL)"
    )

    check(:news_clusters, :language, @language)
    check(:news_clusters, :member_count, "member_count >= 1")
    check(:news_clusters, :best_tier, "best_tier IN #{@stored_tiers}")
    check(:news_clusters, :earliest, "earliest_published_at <= earliest_first_seen_at")
    check(:news_clusters, :earliest_url, "earliest_url " <> item_url("earliest_url"))

    # An item's class is its feed's (a feed's class cannot change under its
    # items). An item's story, and the story's scope matching the item's — MATCH
    # SIMPLE, so the security key is checked for a security's item and the
    # category key for a category's. A merge that moves a story onto
    # another security carries its items' security with it.
    execute("""
    ALTER TABLE news_items
      ADD CONSTRAINT news_items_feed_class_fkey
        FOREIGN KEY (feed_id, class) REFERENCES news_feeds (id, class) ON DELETE RESTRICT,
      ADD CONSTRAINT news_items_cluster_id_fkey
        FOREIGN KEY (cluster_id) REFERENCES news_clusters (id) ON DELETE RESTRICT,
      ADD CONSTRAINT news_items_cluster_security_fkey
        FOREIGN KEY (cluster_id, security_id, language)
        REFERENCES news_clusters (id, security_id, language)
        ON DELETE RESTRICT ON UPDATE CASCADE,
      ADD CONSTRAINT news_items_cluster_category_fkey
        FOREIGN KEY (cluster_id, category_id, language)
        REFERENCES news_clusters (id, category_id, language)
        ON DELETE RESTRICT ON UPDATE CASCADE
    """)

    # --- news_feed_days (§6, A3) -----------------------------------------
    create table(:news_feed_days) do
      add(:feed_id, references(:news_feeds, on_delete: :restrict), null: false)
      add(:day, :date, null: false)
      add(:items_stored, :integer, null: false, default: 0)
      add(:errors, :integer, null: false, default: 0)
      add(:dropped_cap, :integer, null: false, default: 0)
      add(:dropped_no_source, :integer, null: false, default: 0)
      add(:dropped_old, :integer, null: false, default: 0)
      add(:dropped_blocked, :integer, null: false, default: 0)
    end

    create(unique_index(:news_feed_days, [:feed_id, :day]))
    create(index(:news_feed_days, [:day]))

    check(
      :news_feed_days,
      :counts,
      "items_stored >= 0 AND errors >= 0 AND dropped_cap >= 0 AND dropped_no_source >= 0 " <>
        "AND dropped_old >= 0 AND dropped_blocked >= 0"
    )

    # --- the journal-actor guard (B7) -------------------------------------
    execute("""
    CREATE TRIGGER news_sources_require_journal_actor
      BEFORE INSERT OR UPDATE OR DELETE ON news_sources
      FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
    """)

    execute("""
    CREATE TRIGGER news_feeds_require_journal_actor
      BEFORE INSERT OR DELETE
        OR UPDATE OF class, url, security_id, category_id, enabled, interval_minutes, language
      ON news_feeds
      FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS news_feeds_require_journal_actor ON news_feeds")
    execute("DROP TRIGGER IF EXISTS news_sources_require_journal_actor ON news_sources")
    drop(table(:news_feed_days))
    execute("ALTER TABLE news_items DROP CONSTRAINT news_items_cluster_category_fkey")
    execute("ALTER TABLE news_items DROP CONSTRAINT news_items_cluster_security_fkey")
    execute("ALTER TABLE news_items DROP CONSTRAINT news_items_cluster_id_fkey")
    execute("ALTER TABLE news_items DROP CONSTRAINT news_items_feed_class_fkey")
    drop(table(:news_clusters))
    drop(table(:news_items))
    drop(table(:news_feeds))
    drop(table(:news_sources))
  end

  defp check(table, name, expression) do
    create(constraint(table, :"#{table}_#{name}_check", check: expression))
  end

  defp domain(column), do: String.replace(@domain, "%{column}", column)
  defp item_url(column), do: String.replace(@item_url, "%{column}", column)
end
