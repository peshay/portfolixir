defmodule Portfolixir.SeededUpgrade.NewsTest do
  # ADR-0056 (Sprint 27, N2): the two migrations of the news layer's
  # tables. The first creates new tables whose foreign keys point at the
  # catalog an instance already holds; the second adds three columns with
  # CHECKs and a NOT NULL to `securities`. Each runs over seeded rows here
  # (docs/development/guide.md, "Upgrade migrations over legacy rows").
  # Every value is synthetic.
  #
  # async: false -- see Portfolixir.SeededUpgrade, "Where the cases run".
  use ExUnit.Case, async: false

  alias Portfolixir.SeededUpgrade

  @moduletag :seeded_upgrade

  # The migration before each of the two.
  @before_news_tables 20_261_105_170_000
  @before_news_identity 20_261_107_120_000

  # User story (ADR-0056 §2, §4):
  # As the operator upgrading an instance whose catalog holds securities
  # and a custom classification,
  # I want the upgrade that adds the news tables to keep every row and let
  # a feed bind to a security and a category I already have,
  # so that the release boots and the first feed can be registered at once.
  #
  # Acceptance criteria:
  # - Seeded with two securities and a category, the database migrates to
  #   head and both securities are still there.
  # - After the upgrade, an issuer feed on a seeded security and a thematic
  #   feed on the seeded category are stored; an issuer feed without a
  #   security is refused by its binding check.
  @tag seeded_upgrade: 20_261_107_120_000
  test "the news tables do not stop the upgrade over a catalog", %{seeded_upgrade: migration} do
    upgrade = SeededUpgrade.upgrade!(from: @before_news_tables, seed: &seed_catalog/1)
    seeded = upgrade.seeded

    assert migration in upgrade.migrated
    assert List.last(upgrade.migrated) == SeededUpgrade.head()
    assert %{rows: [[2]]} = SeededUpgrade.query!(upgrade, "SELECT count(*) FROM securities")

    # Feeds are journal-armed (B7): each write names an actor.
    SeededUpgrade.journaled!(upgrade, fn ->
      insert_feed!(upgrade, "issuer", seeded.first, nil)
      insert_feed!(upgrade, "thematic", nil, seeded.category)
    end)

    assert_raise Postgrex.Error, ~r/news_feeds_binding_check/, fn ->
      SeededUpgrade.journaled!(upgrade, fn -> insert_feed!(upgrade, "issuer", nil, nil) end)
    end

    assert %{rows: [[2]]} = SeededUpgrade.query!(upgrade, "SELECT count(*) FROM news_feeds")
  end

  # User story (ADR-0056 §2):
  # As the operator upgrading an instance with securities of every kind,
  # I want the news identity columns added without touching them,
  # so that the release boots and every security reads as having no CIK, no
  # aliases and no watch until I or the agent set them.
  #
  # Acceptance criteria:
  # - Seeded with a security carrying the bond master data and one with
  #   only a name, the database migrates to head.
  # - Both read news_cik NULL, news_aliases [] and news_watch false, which
  #   the new CHECKs accept; a CIK of the wrong shape written afterwards is
  #   refused.
  @tag seeded_upgrade: 20_261_107_120_100
  test "the news identity columns do not stop the upgrade over stored securities",
       %{seeded_upgrade: migration} do
    upgrade = SeededUpgrade.upgrade!(from: @before_news_identity, seed: &seed_securities/1)

    assert migration in upgrade.migrated

    assert %{rows: rows} =
             SeededUpgrade.query!(
               upgrade,
               "SELECT news_cik, news_aliases, news_watch FROM securities ORDER BY id"
             )

    assert rows == [[nil, [], false], [nil, [], false]]

    assert_raise Postgrex.Error, ~r/securities_news_cik_check/, fn ->
      SeededUpgrade.journaled!(upgrade, fn ->
        SeededUpgrade.query!(upgrade, "UPDATE securities SET news_cik = '123' WHERE id = $1", [
          upgrade.seeded.bond
        ])
      end)
    end
  end

  defp seed_catalog(db) do
    first = insert!(db, "INSERT INTO securities #{row(~w(name currency_code))}", ["Alpha", "EUR"])

    _second =
      insert!(db, "INSERT INTO securities #{row(~w(name currency_code))}", ["Beta", "EUR"])

    classification =
      insert!(db, "INSERT INTO classifications #{row(~w(name))}", ["Themes"])

    category =
      insert!(
        db,
        "INSERT INTO classification_categories #{row(~w(classification_id name))}",
        [classification, "Water"]
      )

    %{first: first, category: category}
  end

  defp seed_securities(db) do
    bond =
      insert!(
        db,
        "INSERT INTO securities #{row(~w(name currency_code coupon_rate maturity_date))}",
        ["Gamma 2.5% 2031", "EUR", Decimal.new("2.5"), ~D[2031-06-01]]
      )

    plain = insert!(db, "INSERT INTO securities #{row(~w(name currency_code))}", ["Delta", "USD"])
    %{bond: bond, plain: plain}
  end

  defp insert_feed!(db, class, security, category) do
    SeededUpgrade.query!(
      db,
      """
      INSERT INTO news_feeds
        (class, url, security_id, category_id, interval_minutes, language, inserted_at,
         updated_at)
      VALUES ($1, $2, $3, $4, 15, 'en', now() AT TIME ZONE 'UTC', now() AT TIME ZONE 'UTC')
      """,
      [
        class,
        "https://feeds.example.com/#{System.unique_integer([:positive])}",
        security,
        category
      ]
    )
  end

  defp row(columns) do
    placeholders = Enum.map_join(1..length(columns), ", ", &"$#{&1}")

    "(#{Enum.join(columns, ", ")}, inserted_at, updated_at) " <>
      "VALUES (#{placeholders}, LOCALTIMESTAMP(0), LOCALTIMESTAMP(0)) RETURNING id"
  end

  defp insert!(db, sql, params) do
    %{rows: [[id]]} = SeededUpgrade.query!(db, sql, params)
    id
  end
end
