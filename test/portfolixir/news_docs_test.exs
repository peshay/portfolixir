defmodule Portfolixir.NewsDocsTest do
  use ExUnit.Case, async: true

  # User story (Sprint 28 N10, #1420; ADR-0056 §7, §10, A2; plan D-3):
  # As the operator who reads the handbook, or the agent that reads the API
  # reference, after the news layer's second sprint,
  # I want the operator guide to describe the page, the security's tab, the
  # pins and the labeller as the screen names them, in English and German,
  # and the configuration I copy to name the labeller's profile,
  # so that I can find, use and set up what the second sprint built
  # without reading code, and nothing still says the news has no screen.
  #
  # Acceptance criteria:
  # - The EN and DE handbooks' news section no longer calls itself the
  #   agent's only, and names the page, its three tabs, „Zuordnen“, the
  #   security's tab, „Ins Research-Log“ and its save, the label's
  #   „maschinell“ and „ohne Einordnung“, „übernommen“ and „Notizen
  #   anzeigen“, each as the screen spells it in that language.
  # - Both say feeds and sources are registered through the API and the
  #   companion and only shown on the page (plan D-3), and how a labeller
  #   runs: its own named token in PORTFOLIXIR_API_TOKENS, the label
  #   profile, and that the model never holds the token (ADR-0056 §7).
  # - The detail pane's tab count reads eleven.
  # - "Connect an agent" and the deployment guide (EN, DE) list the label
  #   profile; .env.example and both Compose files name it in their comment.
  # - The API references (EN, DE) describe news.registry among the MCP
  #   tools and the label profile beside the three agent profiles.

  defp normalized(path), do: path |> File.read!() |> String.replace(~r/\s+/, " ")

  defp section(path, from, to) do
    text = normalized(path)
    [_, rest] = String.split(text, from, parts: 2)
    [body | _] = String.split(rest, to, parts: 2)
    body
  end

  defp de(msgid) do
    Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
      Gettext.gettext(PortfolixirWeb.Gettext, msgid)
    end)
  end

  defp de(context, msgid) do
    Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
      Gettext.pgettext(PortfolixirWeb.Gettext, context, msgid)
    end)
  end

  test "the handbooks describe the news page, the tab, the pins and the labeller, EN and DE" do
    en = section("docs/product-documentation.md", "## News ", "## Imports")
    de = section("docs/de/product-documentation.md", "## Nachrichten ", "## Imports")

    labels = [
      {"News", de("News")},
      {"Reports", de("Reports")},
      {"Feeds", de("Feeds")},
      {"Sources", de("Sources")},
      {"Assign", de("Assign")},
      {"To the research log", de("To the research log")},
      {"Save to the research log", de("Save to the research log")},
      {"machine-made", de("machine-made")},
      {"no label", de("no label")},
      {"kept", de("news story", "kept")},
      {"Show notes", de("Show notes")},
      {"Show transactions", de("Show transactions")}
    ]

    for {english, german} <- labels do
      assert en =~ "**#{english}**", "EN handbook lacks **#{english}**"
      assert de =~ "**#{german}**", "DE handbook lacks **#{german}** (#{english})"
    end

    for {doc, fragments} <- [
          {en,
           [
             "registered, changed and removed through the API and the companion",
             "the page shows them and edits neither",
             "`PORTFOLIXIR_API_TOKENS`",
             "`PORTFOLIXIR_MCP_PROFILE=label`",
             "the model never holds the token",
             "opening the page moves no agent's position"
           ]},
          {de,
           [
             "über die API und den Begleitdienst angelegt, geändert und entfernt",
             "die Seite zeigt sie und bearbeitet keins von beiden",
             "`PORTFOLIXIR_API_TOKENS`",
             "`PORTFOLIXIR_MCP_PROFILE=label`",
             "das Modell hält das Token nie",
             "das Öffnen der Seite verschiebt keine Leseposition eines Agenten"
           ]}
        ] do
      for fragment <- fragments, do: assert(doc =~ fragment, fragment)
    end

    for {path, stale} <- [
          {"docs/product-documentation.md", "Nothing is shown on screen yet"},
          {"docs/product-documentation.md", "News (for the agent, this sprint)"},
          {"docs/product-documentation.md", "the ten tabs"},
          {"docs/de/product-documentation.md", "Auf dem Bildschirm erscheint noch nichts"},
          {"docs/de/product-documentation.md", "News (für den Agenten, in diesem Sprint)"},
          {"docs/de/product-documentation.md", "die zehn Reiter"}
        ] do
      refute normalized(path) =~ stale, "#{path}: #{stale}"
    end

    assert normalized("docs/product-documentation.md") =~ "the eleven tabs"
    assert normalized("docs/de/product-documentation.md") =~ "die elf Reiter"
  end

  test "the configuration and the agent pages name the labeller's profile" do
    for {path, fragment} <- [
          {"docs/integration/connect-an-agent.md", "| `label` |"},
          {"docs/de/integration/connect-an-agent.md", "| `label` |"},
          {"docs/integration/connect-an-agent.md", "`read`, `book`, `full` or `label`"},
          {"docs/de/integration/connect-an-agent.md", "`read`, `book`, `full` oder `label`"},
          {"docs/home-deployment.md", "`label` (the news labeller's two tools"},
          {"docs/de/home-deployment.md", "`label` (die zwei Tools des News-Labellers"},
          {".env.example", "read, book, full or label"},
          {"docker-compose.yml", "read, book, full or label"},
          {"docker-compose.dev.yml", "read, book, full or label"},
          {"docs/integration/api-and-mcp.md", "A fourth profile, `label`"},
          {"docs/de/integration/api-and-mcp.md", "Ein viertes Profil, `label`"},
          {"docs/integration/api-and-mcp.md", "- `portfolixir.news.registry` —"},
          {"docs/de/integration/api-and-mcp.md", "- `portfolixir.news.registry` —"}
        ] do
      assert normalized(path) =~ fragment, "#{path}: #{fragment}"
    end
  end

  # User story (#1356; the lifecycle audit of 2026-11-09, #13):
  # As the owner who reviews decisions, not diffs,
  # I want ADR-0056 §5 to say what the fetcher does to a sec.gov feed
  # without the operator's user agent,
  # so that the record and the code agree and the health read is no
  # surprise.
  #
  # Acceptance criteria:
  # - §5 says the fetcher refuses every fetch of such a feed with
  #   `user_agent_missing`, the feed staying enabled, and no longer that the
  #   feed "stays disabled" (a wording fix, no rule changes).
  test "ADR-0056 §5 says a sec.gov feed without a user agent refuses every fetch" do
    adr = normalized("docs/decisions/0056-news-layer-fetched-matched-stored-labelled-outside.md")
    [_, section] = String.split(adr, "### 5. Fetching and failure", parts: 2)
    [section | _] = String.split(section, "### 6.", parts: 2)

    assert section =~ "refuses every fetch"
    assert section =~ "`user_agent_missing`"
    refute section =~ "stays disabled"
  end
end
