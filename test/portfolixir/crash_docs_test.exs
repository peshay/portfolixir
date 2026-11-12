defmodule Portfolixir.CrashDocsTest do
  use ExUnit.Case, async: true

  # User story (Sprint 29 C7, #1421; FR-54, ADR-0058 §9 and its amendment's
  # F2 to F4; the coverage rule):
  # As the operator who reads the handbook, or the agent that reads the API
  # reference, after the crash windows were built,
  # I want the API reference to describe every crash route with its
  # parameters, its payload and every refusal, the five tools with their
  # profiles, and the handbook to describe the Crashes section on Wealth ›
  # Risk as the screen names it, in English and German,
  # so that I can read a crash window, its lists and the crash benchmark
  # without reading code, and know that the lists are data, never advice.
  #
  # Acceptance criteria:
  # - The API references (EN, DE) describe, in their crash section, the five
  #   routes; the rankings payload's fields (window, entries, reference,
  #   unanswered, computation_basis and its keys); `provisional`,
  #   `completes_on`, `not_yet`, `days_back` in calendar days; the lists
  #   without a crash benchmark (F2); every refusal (401, 404, 422 with what
  #   it names); survivorship; and that the answer is data, never advice.
  # - Both name the five tools with their profiles: crashes.delete admin,
  #   in `full` only.
  # - The handbooks (EN, DE) describe the Crashes section on the Risk tab:
  #   the rule (10 % from a high, recovery), names, manual windows, the
  #   crash benchmark chosen inline, „Im Depot ansehen“ and when it is
  #   missing (F4), the privacy mode, each label as the screen spells it in
  #   that language, and link the API section.

  defp normalized(path), do: path |> File.read!() |> String.replace(~r/\s+/, " ")

  defp section(path, from, to) do
    text = normalized(path)
    assert text =~ from, "#{path} has no #{from}"
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

  defp en_api,
    do:
      section(
        "docs/integration/api-and-mcp.md",
        "### Crash windows (ADR-0058)",
        "### The position dossier"
      )

  defp de_api,
    do:
      section(
        "docs/de/integration/api-and-mcp.md",
        "### Crash-Fenster (ADR-0058)",
        "### Das Positionsdossier"
      )

  test "the API references describe every crash route, its payload and its refusals, EN and DE" do
    # Identifiers are not translated: both pages carry each of them.
    identifiers = [
      "GET /api/v1/crashes",
      "GET /api/v1/crashes/:key/rankings",
      "PUT /api/v1/crashes/:key",
      "POST /api/v1/crashes",
      "DELETE /api/v1/crashes/:key",
      "`unmatched_names`",
      "`for_current_benchmark`",
      "`benchmark_name`",
      "`max_gap_days`",
      "`recovered_on`",
      "`window`",
      "`entries`",
      "`rank`",
      "`held`",
      "`low`",
      "`start_close`",
      "`back_on`",
      "`reference`",
      "`reference_reason`",
      "`no_benchmark_close`",
      "`answered`",
      "`unanswered`",
      "`unanswered_entries`",
      "`completes_on`",
      "`measured_to`",
      "`span_end`",
      "`not_yet`",
      "`days_back`",
      "`days_back_unit`",
      "`calendar_days`",
      "`vs_benchmark_pp`",
      "`benchmark_return`",
      "`computation_basis`",
      "`survivorship`",
      "`recovery_span_months`",
      "`staleness_days`",
      "`threshold`",
      "`peak_trough_v1`",
      "`no_crash_benchmark`",
      "`crash_benchmark_unavailable`",
      "`401`",
      "`404`",
      "`422`",
      "`201`",
      ~s(["is invalid: losers, winners or rebounders"]),
      ~s(["is invalid: catalogue or view:<id>"]),
      ~s(["is invalid: a positive integer, at most 50"]),
      ~s(["is invalid: true or false"]),
      ~s(["must be after start"]),
      ~s(["must not be in the future"]),
      "`from_name`",
      "`name_has_window`",
      "`portfolixir.crashes.list`",
      "`portfolixir.crashes.rankings`",
      "`portfolixir.crashes.put`",
      "`portfolixir.crashes.delete`",
      "`portfolixir.crashes.benchmark_put`"
    ]

    for {page, doc} <- [{"EN", en_api()}, {"DE", de_api()}], identifier <- identifiers do
      assert doc =~ identifier, "#{page} API crash section lacks #{identifier}"
    end

    for {doc, fragments} <- [
          {en_api(),
           [
             "data, never advice",
             "calendar days",
             "The ranking is unchanged",
             "a security that failed and was removed is in no list",
             "admin, in `full` only"
           ]},
          {de_api(),
           [
             "Daten, nie ein Rat",
             "Kalendertage",
             "Die Rangfolge bleibt dieselbe",
             "ein Wertpapier, das scheiterte und entfernt wurde, steht in keiner Liste",
             "Admin, nur in `full`"
           ]}
        ],
        fragment <- fragments do
      assert doc =~ fragment, "API crash section lacks: #{fragment}"
    end
  end

  test "the handbooks describe the Crashes section as the screen names it, EN and DE" do
    en = section("docs/product-documentation.md", "### Crashes", "## Predictions")
    de = section("docs/de/product-documentation.md", "### Crashes", "## Prognosen")

    labels = [
      {"Crashes", de("Crashes")},
      {"Window", de("crash", "Window")},
      {"List", de("crash", "List")},
      {"Losers", de("crash list", "Losers")},
      {"Winners", de("crash list", "Winners")},
      {"Rebounders", de("crash list", "Rebounders")},
      {"Securities", de("Securities")},
      {"In depot", de("crash universe", "In depot")},
      {"Whole catalogue", de("crash universe", "Whole catalogue")},
      {"in depot", de("crash", "in depot")},
      {"View in holdings", "View in holdings →" |> de() |> String.trim_trailing(" →")},
      {"Days to pre-crash close", de("Days to pre-crash close")},
      {"not yet", de("not yet")},
      {"provisional", de("crash", "provisional")},
      {"manual", de("crash kind", "manual")},
      {"detected", de("crash kind", "detected")},
      {"Crash windows", de("Crash windows")},
      {"Change", de("crash", "Change")},
      {"Choose crash benchmark", de("Choose crash benchmark")},
      {"Add window", de("Add window")},
      {"Rename", de("Rename")},
      {"Delete name", de("Delete name")},
      {"Make a manual window …", de("Make a manual window …")}
    ]

    for {english, german} <- labels do
      assert en =~ "**#{english}**", "EN handbook lacks **#{english}**"
      assert de =~ "**#{german}**", "DE handbook lacks **#{german}** (#{english})"
    end

    for {doc, fragments} <- [
          {en,
           [
             "10 % or more",
             "the last day at the high",
             "recovered",
             "three calendar months",
             "the first booking of this view",
             "**Privacy mode** changes nothing",
             "integration/api-and-mcp.html#crash-windows-adr-0058",
             "gives no advice"
           ]},
          {de,
           [
             "10 % oder mehr",
             "letzten Tag am Hoch",
             "erholt",
             "drei Kalendermonate",
             "der ersten Buchung dieser Ansicht",
             "**Privatsphäre-Modus** ändert in diesem Abschnitt nichts",
             "integration/api-and-mcp.html#crash-fenster-adr-0058",
             "gibt keinen Rat"
           ]}
        ],
        fragment <- fragments do
      assert doc =~ fragment, "handbook Crashes section lacks: #{fragment}"
    end
  end

  test "the privacy-mode passage names the Crashes section, EN and DE" do
    en = section("docs/product-documentation.md", "### Privacy mode", "## Audit Journal")
    assert en =~ "Crashes section"

    de = section("docs/de/product-documentation.md", "### Privatsphäre-Modus", "## Audit-Journal")
    assert de =~ "Abschnitt „Crashes“"
  end
end
