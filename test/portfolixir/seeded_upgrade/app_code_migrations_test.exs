defmodule Portfolixir.SeededUpgrade.AppCodeMigrationsTest do
  # #1042 (Sprint 19 β, B1): the migrations that call application code, each
  # given one of the two answers #1015 defined (docs/development/guide.md,
  # "Upgrade migrations over legacy rows"). The bucket seed of
  # 20260712130000 is frozen in `Portfolixir.Buckets.ScopeSeed`, and its
  # case proves the upgrade it used to stop. The other four are pinned: each
  # case seeds, with plain SQL, the rows that reach the code the migration
  # calls, so a later schema change that makes that code read or write a
  # column the migration's version lacks turns its case red in the pull
  # request that makes it.
  #
  # Each case is mutation-verified (the evidence is in the commit that adds
  # it): the bucket seed's against the unfrozen seed, the four pins against a
  # throwaway later migration whose column the code they call was made to
  # read or write.
  #
  # async: false -- see Portfolixir.SeededUpgrade, "Where the cases run".
  use ExUnit.Case, async: false

  alias Portfolixir.Catalog.Security
  alias Portfolixir.SeededUpgrade

  @moduletag :seeded_upgrade

  # The migration before the bucket seed: the scope dimension and the seed
  # markers exist, the seed has not run.
  @before_scope_seed 20_260_712_120_000

  # The migration before each pinned one.
  @before_former_names 20_260_925_150_000
  @before_tax_identities 20_260_925_220_000
  @before_first_asset_class_backfill 20_260_518_100_000
  @before_second_asset_class_backfill 20_260_607_120_000

  # User story:
  # As the operator upgrading a self-hosted instance from before the
  # buckets-and-views model, with depots and cash accounts in my portfolios,
  # I want the portfolio scope seed to run on the schema of its own version,
  # so that the release boots and my portfolios become scope buckets and
  # views exactly as they did for everyone who upgraded at the time.
  #
  # Acceptance criteria:
  # - Seeded at 20260712120000 with two portfolios, each holding a depot and a
  #   cash account, one cash account already carrying a scope bucket of the
  #   operator's, and a tag bucket named like the second portfolio, the
  #   database migrates to head.
  # - Each portfolio gets one "scope" bucket and one view carrying its id,
  #   the view including exactly that bucket; the second pair is named
  #   "<name> (Portfolio)", because the operator's bucket holds the name.
  # - Every account is tagged with its portfolio's bucket, the tags it had
  #   are kept, and the account that already carries a scope bucket keeps it
  #   and is skipped.
  # - The journal holds, under the seed's system job, one bucket create per
  #   seeded bucket with the bucket's row as its after-image, and one
  #   assignment update per tagged account with the account's new bucket
  #   set; the views are not journaled.
  @tag seeded_upgrade: 20_260_712_130_000
  test "the portfolio scope seed does not stop the upgrade over depots and cash accounts",
       %{seeded_upgrade: migration} do
    upgrade = SeededUpgrade.upgrade!(from: @before_scope_seed, seed: &seed_two_portfolios/1)
    world = upgrade.seeded

    assert migration in upgrade.migrated
    assert List.last(upgrade.migrated) == SeededUpgrade.head()

    beta_seeded = world.beta.name <> " (Portfolio)"

    assert %{rows: buckets} =
             SeededUpgrade.query!(
               upgrade,
               """
               SELECT id, name, color, dimension, source_portfolio_id,
                      to_char(inserted_at, 'YYYY-MM-DD"T"HH24:MI:SS'),
                      to_char(updated_at, 'YYYY-MM-DD"T"HH24:MI:SS')
                 FROM buckets WHERE source_portfolio_id IS NOT NULL ORDER BY id
               """
             )

    assert [
             [alpha_bucket, alpha_name, nil, "scope", alpha_id | alpha_times],
             [beta_bucket, ^beta_seeded, nil, "scope", beta_id | beta_times]
           ] = buckets

    assert {alpha_name, alpha_id, beta_id} ==
             {world.alpha.name, world.alpha.portfolio, world.beta.portfolio}

    assert %{rows: views} =
             SeededUpgrade.query!(
               upgrade,
               """
               SELECT v.name, v.include_all, v.source_portfolio_id, array_agg(i.bucket_id)
                 FROM views v JOIN view_include_buckets i ON i.view_id = v.id
                WHERE v.source_portfolio_id IS NOT NULL
                GROUP BY v.id ORDER BY v.id
               """
             )

    assert views == [
             [world.alpha.name, false, world.alpha.portfolio, [alpha_bucket]],
             [beta_seeded, false, world.beta.portfolio, [beta_bucket]]
           ]

    assert bucket_sets(upgrade, "securities_account_buckets", "securities_account_id") == %{
             world.alpha.depot => [world.tag, alpha_bucket],
             world.beta.depot => [beta_bucket]
           }

    assert bucket_sets(upgrade, "cash_account_buckets", "cash_account_id") == %{
             world.alpha.cash => [alpha_bucket],
             world.beta.cash => [world.own_scope]
           }

    assert system_journal(upgrade, "portfolio_scope_seed") == [
             [
               "bucket",
               "create",
               Integer.to_string(alpha_bucket),
               nil,
               bucket_image(alpha_bucket, world.alpha.name, world.alpha.portfolio, alpha_times)
             ],
             [
               "depot_bucket_assignment",
               "update",
               nil,
               nil,
               %{
                 "id" => nil,
                 "securities_account_id" => world.alpha.depot,
                 "bucket_ids" => [world.tag, alpha_bucket]
               }
             ],
             [
               "cash_account_bucket_assignment",
               "update",
               nil,
               nil,
               %{
                 "id" => nil,
                 "cash_account_id" => world.alpha.cash,
                 "bucket_ids" => [alpha_bucket]
               }
             ],
             [
               "bucket",
               "create",
               Integer.to_string(beta_bucket),
               nil,
               bucket_image(beta_bucket, beta_seeded, world.beta.portfolio, beta_times)
             ],
             [
               "depot_bucket_assignment",
               "update",
               nil,
               nil,
               %{
                 "id" => nil,
                 "securities_account_id" => world.beta.depot,
                 "bucket_ids" => [beta_bucket]
               }
             ]
           ]
  end

  # User story:
  # As the operator installing a fresh instance,
  # I want the portfolio scope seed to find nothing and write nothing,
  # so that a database migrated from empty holds no bucket, view or journal
  # entry it did not ask for.
  #
  # Acceptance criteria:
  # - Migrated from an empty database at 20260712120000 to head, no bucket,
  #   view or journal entry under the seed's system job exists.
  @tag seeded_upgrade: 20_260_712_130_000
  test "the portfolio scope seed writes nothing on a fresh install" do
    upgrade = SeededUpgrade.upgrade!(from: @before_scope_seed, seed: fn _db -> :empty end)

    assert %{rows: [[0, 0]]} =
             SeededUpgrade.query!(
               upgrade,
               "SELECT (SELECT count(*) FROM buckets), (SELECT count(*) FROM views)"
             )

    assert system_journal(upgrade, "portfolio_scope_seed") == []
  end

  # User story:
  # As a developer reverting the portfolio scope seed on a database at its
  # own version,
  # I want the migration's down to remove what its up seeded and nothing else,
  # so that the database is back at 20260712120000 with the operator's
  # buckets and assignments intact.
  #
  # Acceptance criteria:
  # - Seeded at 20260712120000 with a portfolio holding a depot and a cash
  #   account, and an operator bucket assigned to the depot, the database
  #   migrates to exactly 20260712130000 and then runs that migration's down.
  # - No bucket or view carries a seed marker; the operator's bucket and its
  #   link to the depot survive.
  # - The journal holds one bucket delete per seeded bucket under the seed's
  #   system job, with the bucket's row, as its create recorded it, on both
  #   sides; the latest applied migration is 20260712120000.
  @tag seeded_upgrade: 20_260_712_130_000
  test "the portfolio scope seed's down removes what its up seeded, at its own version",
       %{seeded_upgrade: migration} do
    upgrade =
      SeededUpgrade.upgrade!(from: @before_scope_seed, to: migration, seed: &seed_one_portfolio/1)

    world = upgrade.seeded
    assert upgrade.migrated == [migration]

    assert SeededUpgrade.down!(upgrade, 1) == [migration]

    assert %{rows: [[0, 0]]} =
             SeededUpgrade.query!(
               upgrade,
               """
               SELECT (SELECT count(*) FROM buckets WHERE source_portfolio_id IS NOT NULL),
                      (SELECT count(*) FROM views WHERE source_portfolio_id IS NOT NULL)
               """
             )

    assert SeededUpgrade.query!(upgrade, "SELECT id FROM buckets").rows == [[world.tag]]

    assert bucket_sets(upgrade, "securities_account_buckets", "securities_account_id") == %{
             world.depot => [world.tag]
           }

    assert bucket_sets(upgrade, "cash_account_buckets", "cash_account_id") == %{}

    journal = system_journal(upgrade, "portfolio_scope_seed")

    assert [["bucket", "create", seeded, nil, image]] =
             for(["bucket", "create" | _] = entry <- journal, do: entry)

    assert for([_type, "delete" | _] = entry <- journal, do: entry) == [
             ["bucket", "delete", seeded, image, image]
           ]

    assert %{rows: [[@before_scope_seed]]} =
             SeededUpgrade.query!(upgrade, "SELECT max(version) FROM schema_migrations")
  end

  # User story:
  # As the operator upgrading an instance on which I renamed a cash account
  # and a depot before accounts kept their former names, and on which an
  # import later created a zombie account under one of the old names,
  # I want the former-name backfill to finish over that journal,
  # so that the release boots, the renamed accounts answer to their old
  # names, and the name a zombie holds is reported instead of written.
  #
  # Acceptance criteria:
  # - Seeded at 20260925150000 with the journaled creates and renames of two
  #   cash accounts and a depot, and a zombie cash account created after the
  #   renames under one of the old names, the database migrates to head.
  # - The renamed depot and cash account carry their old names in
  #   `former_names`, each write journaled as an update under the backfill's
  #   system job; the account whose old name the zombie holds keeps none.
  # - The upgrade's log names that refusal.
  @tag seeded_upgrade: 20_260_925_150_100
  test "the former-name backfill does not stop the upgrade over journaled renames",
       %{seeded_upgrade: migration} do
    upgrade = SeededUpgrade.upgrade!(from: @before_former_names, seed: &seed_renames/1)
    world = upgrade.seeded

    assert migration in upgrade.migrated
    assert List.last(upgrade.migrated) == SeededUpgrade.head()

    assert former_names(upgrade, "cash_accounts") == %{
             world.cash => ["Settlement Cash"],
             world.reserve => [],
             world.zombie => []
           }

    assert former_names(upgrade, "securities_accounts") == %{world.depot => ["Broker Depot"]}

    assert for(
             [type, operation, id, before, after_image] <-
               system_journal(upgrade, "former_names_backfill"),
             do: {type, operation, id, before["former_names"], after_image["former_names"]}
           ) == [
             {"cash_account", "update", Integer.to_string(world.cash), [], ["Settlement Cash"]},
             {"securities_account", "update", Integer.to_string(world.depot), [],
              ["Broker Depot"]}
           ]

    assert upgrade.log =~
             ~s|cash account ##{world.reserve} keeps no former name "Old Reserve": | <>
               "cash account ##{world.zombie} carries it as its live name"
  end

  # User story:
  # As the operator upgrading an instance whose tax records name a holder or
  # an institution with a no-break space, a thin space, a double space or a
  # zero-width space,
  # I want the identity normalisation to finish over those rows,
  # so that the release boots, the lookups reach the rows again, and a row
  # that normalises onto another row's key is reported, not merged.
  #
  # Acceptance criteria:
  # - Seeded at 20260925220000 with a profile, an allowance order and a
  #   statement snapshot spelled that way, and two orders whose spellings
  #   normalise to one key, the database migrates to head.
  # - The three rows hold the normalised holder and institution, each write
  #   journaled as an update under the backfill's system job with both
  #   spellings before and after; of the two orders, the one
  #   that would take the other's key keeps its spelling, and the upgrade's
  #   log names it.
  @tag seeded_upgrade: 20_260_925_230_000
  test "the tax identity normalisation does not stop the upgrade over unnormalised spellings",
       %{seeded_upgrade: migration} do
    upgrade = SeededUpgrade.upgrade!(from: @before_tax_identities, seed: &seed_tax_identities/1)
    rows = upgrade.seeded

    assert migration in upgrade.migrated
    assert List.last(upgrade.migrated) == SeededUpgrade.head()

    assert identities(upgrade, "tax_profiles", ~w(holder)) == %{
             rows.profile => ["Synthetic Holder"]
           }

    assert identities(upgrade, "allowance_orders", ~w(holder institution)) == %{
             rows.order => ["Synthetic Holder", "Synthetic Bank"],
             rows.kept => ["Synthetic Holder", "Synthetic Bank"],
             rows.duplicate => ["Synthetic\u00A0Holder", "Synthetic Bank"]
           }

    assert identities(upgrade, "tax_statement_snapshots", ~w(holder institution)) == %{
             rows.snapshot => ["Synthetic Holder", "Synthetic Bank"]
           }

    assert for(
             [type, operation, id, before, after_image] <-
               system_journal(upgrade, "tax_identity_backfill"),
             do:
               {type, operation, id, Map.take(before, ~w(holder institution)),
                Map.take(after_image, ~w(holder institution))}
           ) == [
             {"tax_profile", "update", Integer.to_string(rows.profile),
              %{"holder" => "Synthetic\u00A0Holder"}, %{"holder" => "Synthetic Holder"}},
             {"allowance_order", "update", Integer.to_string(rows.order),
              %{"holder" => "Synthetic  Holder", "institution" => "Synthetic \u200BBank"},
              %{"holder" => "Synthetic Holder", "institution" => "Synthetic Bank"}},
             {"tax_statement_snapshot", "update", Integer.to_string(rows.snapshot),
              %{"holder" => "Synthetic Holder", "institution" => "Synthetic\u2009Bank"},
              %{"holder" => "Synthetic Holder", "institution" => "Synthetic Bank"}}
           ]

    assert upgrade.log =~
             "allowance_orders ##{rows.duplicate} keeps its stored holder or institution " <>
               "spelling: normalised, it is the identity allowance_orders ##{rows.kept}"
  end

  # User story:
  # As the operator upgrading an instance whose securities were imported
  # before asset classes were inferred,
  # I want the first asset-class backfill to finish over those rows,
  # so that the release boots and every security the inference recognises
  # carries the class the securities list filters on.
  #
  # Acceptance criteria:
  # - Seeded at 20260518100000 with unclassed securities the inference
  #   recognises, one whose class is set and one it cannot read, the
  #   database migrates to 20260523120000 and stops there, before the second
  #   backfill can run the same code again.
  # - The recognised rows carry the class today's inference gives them (the
  #   drift from the inference of the backfill's own day is deliberate: the
  #   second backfill exists to apply newer rules); the set class is
  #   untouched and the unreadable row stays unclassed.
  @tag seeded_upgrade: 20_260_523_120_000
  test "the first asset-class backfill does not stop the upgrade over unclassed securities",
       %{seeded_upgrade: migration} do
    assert_asset_class_backfill(@before_first_asset_class_backfill, migration, migration)
  end

  # User story:
  # As the operator upgrading an instance whose securities were imported
  # before the inference recognised certificates and leverage products,
  # I want the second asset-class backfill to finish over the rows still
  # unclassed,
  # so that the release boots and those securities are sorted into the
  # classes the newer rules recognise.
  #
  # Acceptance criteria:
  # - Seeded at 20260607120000 with unclassed securities the inference
  #   recognises (a knock-out among them), one whose class is set and one it
  #   cannot read, the database migrates to head.
  # - The recognised rows carry the class today's inference gives them; the
  #   set class is untouched and the unreadable row stays unclassed.
  @tag seeded_upgrade: 20_260_608_120_000
  test "the derivative asset-class backfill does not stop the upgrade over unclassed securities",
       %{seeded_upgrade: migration} do
    assert_asset_class_backfill(@before_second_asset_class_backfill, :head, migration)
  end

  defp assert_asset_class_backfill(from, to, migration) do
    upgrade = SeededUpgrade.upgrade!(from: from, to: to, seed: &seed_securities/1)
    securities = upgrade.seeded

    assert migration in upgrade.migrated
    assert List.last(upgrade.migrated) == if(to == :head, do: SeededUpgrade.head(), else: to)

    %{rows: rows} = SeededUpgrade.query!(upgrade, "SELECT id, asset_class FROM securities")
    classes = Map.new(rows, fn [id, class] -> {id, class} end)

    for {id, name} <- securities.recognised do
      inferred = Security.effective_asset_class(%Security{name: name})
      assert is_binary(inferred), "today's inference no longer recognises #{inspect(name)}"
      assert classes[id] == inferred, name
    end

    assert classes[securities.set] == "equity"
    assert classes[securities.unreadable] == nil
  end

  # -- seeds: plain SQL, in the shape of each migration's version -------------

  # Two portfolios, each with a cash account and a depot settling into it.
  # Alpha's depot carries a tag bucket named like Beta, so Beta's seeded
  # bucket falls back to "<name> (Portfolio)"; Beta's cash account already
  # carries a scope bucket of the operator's.
  defp seed_two_portfolios(db) do
    alpha = seed_portfolio(db, "Upgrade Alpha")
    beta = seed_portfolio(db, "Upgrade Beta")

    tag = insert_bucket!(db, beta.name, "tag")
    own_scope = insert_bucket!(db, "Operator Scope", "scope")

    SeededUpgrade.query!(
      db,
      "INSERT INTO securities_account_buckets (securities_account_id, bucket_id) VALUES ($1, $2)",
      [alpha.depot, tag]
    )

    SeededUpgrade.query!(
      db,
      "INSERT INTO cash_account_buckets (cash_account_id, bucket_id) VALUES ($1, $2)",
      [beta.cash, own_scope]
    )

    %{alpha: alpha, beta: beta, tag: tag, own_scope: own_scope}
  end

  # One portfolio with a cash account and a depot, the depot carrying a tag
  # bucket of the operator's.
  defp seed_one_portfolio(db) do
    portfolio = seed_portfolio(db, "Downgrade Alpha")
    tag = insert_bucket!(db, "Operator Tag", "tag")

    SeededUpgrade.query!(
      db,
      "INSERT INTO securities_account_buckets (securities_account_id, bucket_id) VALUES ($1, $2)",
      [portfolio.depot, tag]
    )

    Map.put(portfolio, :tag, tag)
  end

  defp seed_portfolio(db, name) do
    portfolio =
      insert!(db, "INSERT INTO portfolios #{row(~w(name base_currency_code))}", [name, "EUR"])

    cash =
      insert!(db, "INSERT INTO cash_accounts #{row(~w(portfolio_id name currency_code))}", [
        portfolio,
        name <> " Cash",
        "EUR"
      ])

    depot =
      insert!(
        db,
        "INSERT INTO securities_accounts #{row(~w(portfolio_id cash_account_id name))}",
        [portfolio, cash, name <> " Depot"]
      )

    %{name: name, portfolio: portfolio, cash: cash, depot: depot}
  end

  defp insert_bucket!(db, name, dimension) do
    insert!(db, "INSERT INTO buckets #{row(~w(name dimension))}", [name, dimension])
  end

  # Two cash accounts and a depot, each created and renamed with its entries
  # in the journal, and a zombie cash account an import created afterwards
  # under the reserve account's old name.
  defp seed_renames(db) do
    portfolio =
      insert!(db, "INSERT INTO portfolios #{row(~w(name base_currency_code))}", [
        "Renamed Portfolio",
        "EUR"
      ])

    cash = insert_cash!(db, portfolio, "Settlement Cash")
    reserve = insert_cash!(db, portfolio, "Old Reserve")

    depot =
      insert!(
        db,
        "INSERT INTO securities_accounts #{row(~w(portfolio_id cash_account_id name))}",
        [portfolio, cash, "Broker Depot"]
      )

    journal_account!(db, "cash_account", cash, {nil, "Settlement Cash"}, portfolio)
    journal_account!(db, "cash_account", reserve, {nil, "Old Reserve"}, portfolio)
    journal_account!(db, "securities_account", depot, {nil, "Broker Depot"}, portfolio)

    rename!(
      db,
      {"cash_accounts", "cash_account"},
      cash,
      {"Settlement Cash", "Renamed Cash"},
      portfolio
    )

    rename!(
      db,
      {"cash_accounts", "cash_account"},
      reserve,
      {"Old Reserve", "Reserve Cash"},
      portfolio
    )

    rename!(
      db,
      {"securities_accounts", "securities_account"},
      depot,
      {"Broker Depot", "Renamed Depot"},
      portfolio
    )

    zombie = insert_cash!(db, portfolio, "Old Reserve")
    journal_account!(db, "cash_account", zombie, {nil, "Old Reserve"}, portfolio)

    %{cash: cash, reserve: reserve, depot: depot, zombie: zombie}
  end

  defp insert_cash!(db, portfolio, name) do
    insert!(db, "INSERT INTO cash_accounts #{row(~w(portfolio_id name currency_code))}", [
      portfolio,
      name,
      "EUR"
    ])
  end

  defp rename!(db, {table, resource_type}, id, {previous, name}, portfolio) do
    SeededUpgrade.query!(db, "UPDATE #{table} SET name = $1 WHERE id = $2", [name, id])
    journal_account!(db, resource_type, id, {previous, name}, portfolio)
  end

  # A create (no previous name) or an update of an account, as the journal
  # held it: the account's image with its name and portfolio.
  defp journal_account!(db, resource_type, id, {previous, name}, portfolio) do
    image = fn name -> name && %{"id" => id, "name" => name, "portfolio_id" => portfolio} end

    SeededUpgrade.query!(
      db,
      """
      INSERT INTO audit_journal
        (actor_type, actor_label, operation, resource_type, resource_id, before, after,
         inserted_at)
      VALUES ('owner_ui', NULL, $1, $2, $3, $4, $5, now())
      """,
      [
        if(previous, do: "update", else: "create"),
        resource_type,
        Integer.to_string(id),
        image.(previous),
        image.(name)
      ]
    )
  end

  # A profile, an allowance order and a statement snapshot whose holder or
  # institution a write would normalise, and two orders of one year whose
  # spellings normalise to one key: the first is kept, the second is the
  # duplicate.
  defp seed_tax_identities(db) do
    profile =
      insert!(db, "INSERT INTO tax_profiles #{row(~w(holder valid_from))}", [
        "Synthetic\u00A0Holder",
        ~D[2026-01-01]
      ])

    order = insert_order!(db, {"Synthetic  Holder", "Synthetic \u200BBank"}, 2026)
    kept = insert_order!(db, {"Synthetic Holder", "Synthetic Bank"}, 2025)
    duplicate = insert_order!(db, {"Synthetic\u00A0Holder", "Synthetic Bank"}, 2025)

    snapshot =
      insert!(
        db,
        "INSERT INTO tax_statement_snapshots #{row(~w(institution holder tax_year as_of))}",
        ["Synthetic\u2009Bank", "Synthetic Holder", 2025, ~D[2025-12-31]]
      )

    %{profile: profile, order: order, kept: kept, duplicate: duplicate, snapshot: snapshot}
  end

  defp insert_order!(db, {holder, institution}, tax_year) do
    insert!(
      db,
      "INSERT INTO allowance_orders #{row(~w(holder institution tax_year amount_granted))}",
      [holder, institution, tax_year, Decimal.new("500")]
    )
  end

  # Securities with no class the inference reads as an ETF, an equity and a
  # knock-out, one whose class the operator set (its name would read as an
  # ETF), and one the inference cannot read.
  defp seed_securities(db) do
    recognised =
      for name <- [
            "Synthetic World UCITS ETF",
            "Synthetic Harbor Registered Shares",
            "Synthetic Index Turbo Call"
          ],
          do: {insert_security!(db, name, nil), name}

    %{
      recognised: recognised,
      set: insert_security!(db, "Synthetic Pinned UCITS ETF", "equity"),
      unreadable: insert_security!(db, "Synthetic Basin Minerals", nil)
    }
  end

  defp insert_security!(db, name, asset_class) do
    insert!(db, "INSERT INTO securities #{row(~w(name currency_code asset_class))}", [
      name,
      "EUR",
      asset_class
    ])
  end

  # -- reads ---------------------------------------------------------------------

  # `%{account id => former names}` of an account table.
  defp former_names(db, table) do
    %{rows: rows} = SeededUpgrade.query!(db, "SELECT id, former_names FROM #{table}")
    Map.new(rows, fn [id, names] -> {id, names} end)
  end

  # `%{row id => [the identity columns' values]}` of a tax table.
  defp identities(db, table, columns) do
    %{rows: rows} =
      SeededUpgrade.query!(db, "SELECT id, #{Enum.join(columns, ", ")} FROM #{table}")

    Map.new(rows, fn [id | spelling] -> {id, spelling} end)
  end

  # `%{owner id => [bucket ids, ascending]}` of an assignment table.
  defp bucket_sets(db, table, owner) do
    %{rows: rows} =
      SeededUpgrade.query!(
        db,
        "SELECT #{owner}, array_agg(bucket_id ORDER BY bucket_id) FROM #{table} GROUP BY #{owner}"
      )

    Map.new(rows, fn [id, bucket_ids] -> {id, bucket_ids} end)
  end

  # The journal entries a system job wrote, in the order it wrote them.
  defp system_journal(db, label) do
    %{rows: rows} =
      SeededUpgrade.query!(
        db,
        """
        SELECT resource_type, operation, resource_id, before, after FROM audit_journal
         WHERE actor_type = 'system_job' AND actor_label = $1 ORDER BY id
        """,
        [label]
      )

    rows
  end

  # A bucket's journal image: every column of its row at the seed's version,
  # timestamps in ISO 8601 at second precision.
  defp bucket_image(id, name, portfolio, [inserted_at, updated_at]) do
    %{
      "id" => id,
      "name" => name,
      "color" => nil,
      "dimension" => "scope",
      "source_portfolio_id" => portfolio,
      "inserted_at" => inserted_at,
      "updated_at" => updated_at
    }
  end

  # `(columns..., inserted_at, updated_at) VALUES ($1, ..., now, now)
  # RETURNING id` for an insert of one row.
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
