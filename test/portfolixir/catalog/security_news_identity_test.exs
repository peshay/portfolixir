defmodule Portfolixir.Catalog.SecurityNewsIdentityTest do
  # ADR-0056 §2 and B1 (Sprint 27, N2): the security's news identity — a
  # CIK and a list of aliases `{token, context, case}` — and its
  # `news_watch` flag, as the security's changeset casts and checks them and
  # as the database holds them. The API's `securities.update` takes them in
  # N8. Synthetic data only.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.News.Alias
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  defp security!,
    do:
      WorldFixtures.create_security!(
        name: "Northwind Harbour Logistics AG",
        ticker: nil,
        asset_class: "equity"
      )

  defp write(security, attrs), do: Catalog.update_security(Actor.owner_ui(), security, attrs)

  defp errors(security, attrs), do: errors_on(Security.changeset(security, attrs))

  # User story (ADR-0056 §2):
  # As the operator's agent naming how a company appears in news text,
  # I want to store aliases as a token, an optional context of words and a
  # case rule, together with the company's CIK and whether I watch it,
  # so that the matcher can bind an aggregator's item to it by looking
  # words up, and a candidate I hold no position in is still in the
  # universe.
  #
  # Acceptance criteria:
  # - A new security has no CIK, no aliases and is not watched.
  # - A CIK of 1 to 10 digits is stored as 10 digits, zero-padded.
  # - Aliases are stored in the order given, the token trimmed, a context's
  #   words trimmed, without repeats; an empty context is stored as none.
  # - The update is journaled with the aliases in its after-image.
  test "a security stores its CIK, its aliases and whether it is watched" do
    security = security!()

    assert security.news_cik == nil
    assert security.news_aliases == []
    assert security.news_watch == false

    assert {:ok, updated} =
             write(security, %{
               news_cik: " 320193 ",
               news_watch: true,
               news_aliases: [
                 %{token: " Northwind ", case: "insensitive"},
                 %{
                   token: "NHL",
                   context: ["stock", " shares", "stock", "Northwind"],
                   case: "sensitive"
                 },
                 %{token: "Northwind Harbour", context: [], case: "insensitive"}
               ]
             })

    assert updated.news_cik == "0000320193"
    assert updated.news_watch == true

    assert [
             %Alias{token: "Northwind", context: [], case: :insensitive},
             %Alias{token: "NHL", context: ["stock", "shares", "Northwind"], case: :sensitive},
             %Alias{token: "Northwind Harbour", context: [], case: :insensitive}
           ] = Repo.reload!(updated).news_aliases

    [entry] =
      Portfolixir.Journal.list_entries(
        resource_type: "security",
        resource_id: to_string(security.id)
      )
      |> Enum.filter(&(&1.operation == :update))

    assert [%{"token" => "Northwind", "case" => "insensitive", "context" => []} | _] =
             entry.after["news_aliases"]

    assert entry.after["news_cik"] == "0000320193"
    assert entry.after["news_watch"] == true
  end

  # User story (ADR-0056 §2):
  # As the operator whose instance matches foreign text against my aliases,
  # I want an alias to be a literal name or symbol, never a pattern, and
  # bounded,
  # so that nothing I or an agent store runs as a regular expression against
  # a feed's text, and an alias list cannot grow without end.
  #
  # Acceptance criteria:
  # - A token is required, at most 64 characters, without a pattern's
  #   characters (\ * ? [ ] ( ) { } | ^ $), control or invisible
  #   characters.
  # - A context word is one word of at most 64 characters, under the same
  #   rule; at most 20 words.
  # - The case is sensitive or insensitive, and stated.
  # - At most 50 aliases, and no token twice.
  # - A CIK of more than 10 digits or with anything but digits is refused.
  test "an alias is a literal token, a bounded context and a stated case" do
    security = security!()

    alias_errors = fn alias_attrs ->
      security
      |> errors(%{news_aliases: [alias_attrs]})
      |> Map.fetch!(:news_aliases)
      |> hd()
    end

    for token <- ["North.*", "^NHL$", "(Northwind)", "N[HL]", "a|b", "back\\slash", "a?", "x{2}"] do
      assert %{token: ["is matched literally as a name or symbol; patterns are not accepted"]} =
               alias_errors.(%{token: token, case: "sensitive"}),
             token
    end

    assert %{token: ["can't be blank"]} = alias_errors.(%{token: "  ", case: "sensitive"})
    assert %{token: [_]} = alias_errors.(%{token: String.duplicate("n", 65), case: "sensitive"})
    assert %{token: [_]} = alias_errors.(%{token: "North\u200Bwind", case: "sensitive"})
    assert %{token: [_]} = alias_errors.(%{token: "North\nwind", case: "sensitive"})
    assert %{case: ["can't be blank"]} = alias_errors.(%{token: "NHL"})
    assert %{case: ["is invalid"]} = alias_errors.(%{token: "NHL", case: "regex"})

    assert %{context: ["each word is one word of at most 64 characters, matched literally"]} =
             alias_errors.(%{token: "NHL", context: ["two words"], case: "sensitive"})

    assert %{context: [_]} =
             alias_errors.(%{token: "NHL", context: ["sto*ck"], case: "sensitive"})

    assert %{context: [_]} =
             alias_errors.(%{
               token: "NHL",
               context: [String.duplicate("w", 65)],
               case: "sensitive"
             })

    assert %{context: [_]} =
             alias_errors.(%{
               token: "NHL",
               context: Enum.map(1..21, &"w#{&1}"),
               case: "sensitive"
             })

    assert %{context: [_]} = alias_errors.(%{token: "NHL", context: "stock", case: "sensitive"})

    many = Enum.map(1..51, &%{token: "T#{&1}", case: "sensitive"})

    assert %{news_aliases: ["should have at most 50 item(s)"]} =
             errors(security, %{news_aliases: many})

    assert %{news_aliases: ["lists the token \"NHL\" twice"]} =
             errors(security, %{
               news_aliases: [
                 %{token: "NHL", case: "sensitive"},
                 %{token: "NHL", context: ["stock"], case: "insensitive"}
               ]
             })

    assert %{} == errors(security, %{news_aliases: Enum.take(many, 50)})

    for cik <- ["12345678901", "CIK123", "12 34", "-1"] do
      assert %{news_cik: ["is not a CIK (1 to 10 digits)"]} = errors(security, %{news_cik: cik}),
             cik
    end

    assert %{news_watch: ["is invalid"]} = errors(security, %{news_watch: "often"})
  end

  # User story (ADR-0056 §2; ADR-0052 as the precedent for master data in
  # columns):
  # As the maintainer of the catalog,
  # I want the database itself to hold a CIK's shape, the aliases' JSON
  # form and the watch flag,
  # so that a writer past the changeset cannot store an alias list the
  # matcher cannot read.
  #
  # Acceptance criteria:
  # - A CIK not of 10 digits, aliases that are not a JSON array or longer
  #   than 50, and a missing watch flag are refused by the database.
  test "the database holds the CIK's shape, the aliases' form and the watch flag" do
    security = security!()

    # Past the changeset and its journal entry: the guard trigger on
    # `securities` wants an actor, which a raw write names itself.
    Repo.query!("SELECT set_config('portfolixir.journal_actor', 'synthetic-raw-write', true)")

    refusal = fn sql, params ->
      case Repo.query(sql, [security.id | params], mode: :savepoint) do
        {:ok, _} ->
          :updated

        {:error, %Postgrex.Error{postgres: %{constraint: constraint}}}
        when is_binary(constraint) ->
          constraint

        {:error, %Postgrex.Error{postgres: %{code: code}}} ->
          code
      end
    end

    assert refusal.("UPDATE securities SET news_cik = $2 WHERE id = $1", ["320193"]) ==
             "securities_news_cik_check"

    assert refusal.("UPDATE securities SET news_cik = $2 WHERE id = $1", ["0000320193"]) ==
             :updated

    assert refusal.("UPDATE securities SET news_aliases = '{}'::jsonb WHERE id = $1", []) ==
             "securities_news_aliases_check"

    many = Jason.encode!(Enum.map(1..51, &%{token: "T#{&1}", case: "sensitive", context: []}))

    assert refusal.("UPDATE securities SET news_aliases = $2::jsonb WHERE id = $1", [many]) ==
             "securities_news_aliases_check"

    assert refusal.("UPDATE securities SET news_watch = NULL WHERE id = $1", []) ==
             :not_null_violation
  end
end
