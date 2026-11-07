defmodule Portfolixir.Repo.Migrations.AddNewsIdentityToSecurities do
  @moduledoc """
  ADR-0056 §2: a security's news identity and its watch flag, as columns
  on `securities` (ADR-0052 put a bond's master data in typed columns too):

    * `news_cik` — the SEC's Central Index Key, stored as its 10 digits
      zero-padded, or NULL;
    * `news_aliases` — the aliases the matcher looks up, a JSON array of
      `{token, context, case}` objects (at most 50), written only through
      `Portfolixir.Catalog.Security.changeset/2`, which checks each one
      (`Portfolixir.News.Alias`);
    * `news_watch` — whether the security is in the news universe without a
      holding or a target (§2), false unless set.

  Upgrade-safe: every stored row takes NULL, `[]` and false, which the
  three CHECKs accept, so no row an older instance holds can stop the
  upgrade.
  """
  use Ecto.Migration

  def change do
    alter table(:securities) do
      add(:news_cik, :string, size: 10)
      add(:news_aliases, :jsonb, null: false, default: fragment("'[]'::jsonb"))
      add(:news_watch, :boolean, null: false, default: false)
    end

    create(
      constraint(:securities, :securities_news_cik_check,
        check: "news_cik IS NULL OR news_cik ~ '^[0-9]{10}$'"
      )
    )

    create(
      constraint(:securities, :securities_news_aliases_check,
        check: "jsonb_typeof(news_aliases) = 'array' AND jsonb_array_length(news_aliases) <= 50"
      )
    )
  end
end
