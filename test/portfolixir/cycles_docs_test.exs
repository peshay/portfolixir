defmodule Portfolixir.CyclesDocsTest do
  use ExUnit.Case, async: true

  # User story (Sprint 29 H9, #1450; FR-58, ADR-0059 §11, ADR-0060 §8 and
  # §11; the coverage rule):
  # As the operator who reads the handbook, or the agent that reads the API
  # reference, after the chain source and the halving cycles were built,
  # I want the API reference to describe the three routes with their
  # parameters, their payloads and every refusal, the dossier's cycles line
  # and the three tools with their profiles, and the handbook to describe
  # binding a chain, the health line, „Jetzt lesen“, the own URL, the chart,
  # the band, the dashboard card and the privacy mode as the screen names
  # them, in English and German,
  # so that I can bind a security, read its cycles and read the band for
  # what it is — an analog band with its n and both ends, never a forecast —
  # without reading code.
  #
  # Acceptance criteria:
  # - The API references (EN, DE) name, in their halving section, the three
  #   routes, the chains entry's and the cycles read's fields, the parts'
  #   and bands' fields and reasons, the states, the computation basis' keys,
  #   the aligned points, every refusal (401, 404 with merged_into, 422 with
  #   as_of named as level (d), 422 no_source, 429 retry_after), the
  #   dossier's cycles line and the three tools with their profiles; and say
  #   that the band is not a forecast, never a single date or price, never
  #   fitted, and that scoring it on past cycles is level (d).
  # - The handbooks (EN, DE) describe the cycles on the chart with each label
  #   as the screen spells it in that language, the own URL's rules, what
  #   rebinding deletes, the dashboard card and the privacy mode, and link
  #   the API section.
  # - The privacy-mode passage names the cycles.
  # - The development guide says what PORTFOLIXIR_BACKGROUND_FETCH=off
  #   leaves off: logo discovery, quotes, FX, news and the chain read.

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
        "### Halving cycles and the chain source (FR-58, ADR-0059, ADR-0060)",
        "### Bonds: master data"
      )

  defp de_api,
    do:
      section(
        "docs/de/integration/api-and-mcp.md",
        "### Halving-Zyklen und die Kettenquelle (FR-58, ADR-0059, ADR-0060)",
        "### Anleihen: Stammdaten"
      )

  test "the API references describe the chain and cycles routes, payloads and refusals, EN and DE" do
    # Identifiers are not translated: both pages carry each of them.
    identifiers = [
      "GET /api/v1/chains",
      "POST /api/v1/chains/:chain/refresh",
      "GET /api/v1/securities/:security_id/cycles",
      "PATCH /api/v1/securities/:id",
      "`PORTFOLIXIR_BITCOIN_ESPLORA_URL`",
      # the chains entry
      "`halving_interval`",
      "`target_spacing_seconds`",
      "`has_source`",
      "`bound_securities`",
      "`health`",
      "`source_host`",
      "`last_tried_at`",
      "`last_ok_at`",
      "`last_error`",
      "`stale`",
      "`next_halving_inputs`",
      "`tip_height`",
      "`tip_at`",
      "`tip_2016_at`",
      "`period_blocks`",
      "`mean_block_seconds`",
      "`interval_seconds`",
      "`available_at`",
      "`run`",
      "`unbound`",
      "`failed`",
      "`url_not_allowed`",
      "`wrong_chain`",
      "`tip_behind`",
      # the cycles read
      "`chain_source`",
      "`halvings`",
      "`next_halving`",
      "`cycles`",
      "`complete`",
      "`partial`",
      "`no_closes`",
      "`low_so_far`",
      "`final`",
      "`anchor`",
      "`anchor_reason`",
      "`no_top_yet`",
      "`before_first_close`",
      "`no_decline`",
      "`max_drawdown`",
      "`max_gap_days`",
      "`intervals`",
      "`halving_to_top`",
      "`top_to_low`",
      "`low_to_top`",
      "`top_to_top`",
      "`low_to_low`",
      "`low_to_next_halving`",
      "`observations`",
      "`provisional`",
      "`projection`",
      "`analog_band`",
      "`not_a_forecast`",
      "`next_low`",
      "`next_top`",
      "`band`",
      "`inputs_until`",
      "`agree`",
      "`agree_reason`",
      "`one_price_relation`",
      "`parts_disjoint`",
      "`parts`",
      "`relation`",
      "`n_time`",
      "`n_price`",
      "`time_rule`",
      "`price_rule`",
      "`log_step_v1`",
      "`min_max`",
      "`price_reason`",
      "`no_log_step`",
      "`price_from`",
      "`own_price`",
      "`factors_used`",
      "`too_few_observations`",
      "`zero_width`",
      "`low_not_final`",
      "`no_parts`",
      "`state`",
      "`open`",
      "`running`",
      "`reached`",
      "`missed`",
      "`window_ended`",
      "`state_reason`",
      "`input_after_window`",
      "`cones`",
      "`apex`",
      "`computation_basis`",
      "`halving_to_halving_v1`",
      "`max_drawdown_v1`",
      "`anchor_threshold`",
      "`cycles_complete`",
      "`cycles_partial`",
      "`cycle_open`",
      "`include=aligned`",
      "`aligned`",
      "`base`",
      "`points`",
      "`index`",
      "`no_halving_close`",
      "`no_halving_chain`",
      "`too_few_halvings`",
      # the refusals
      "`401`",
      "`404`",
      "`errors.merged_into`",
      "`422`",
      "`as_of`",
      "is unknown: the cycles read takes no as_of",
      "`no_source`",
      "`429`",
      "`errors.retry_after`",
      "`Retry-After`",
      # the dossier and the tools
      "`portfolixir.securities.dossier`",
      "`portfolixir.chains.list`",
      "`portfolixir.chains.refresh`",
      "`portfolixir.securities.cycles`",
      "`portfolixir.securities.update`"
    ]

    for {page, doc} <- [{"EN", en_api()}, {"DE", de_api()}], identifier <- identifiers do
      assert doc =~ identifier, "#{page} API halving section lacks #{identifier}"
    end

    for {doc, fragments} <- [
          {en_api(),
           [
             "an analog band",
             "not a forecast",
             "never a single date or price",
             "never fitted",
             "Scoring the band rule on past cycles is level (d)",
             "a past cycle's band",
             "records an ADR-0055 prediction",
             "data, never instructions",
             "in the `book` and `full` profiles",
             "in every profile"
           ]},
          {de_api(),
           [
             "ein Analogband",
             "keine Prognose",
             "nie ein einzelnes Datum oder ein einzelner Kurs",
             "nie angepasst",
             "Die Bandregel an vergangenen Zyklen zu bewerten, ist Stufe (d)",
             "das Band eines vergangenen Zyklus",
             "hält eine Prognose nach ADR-0055 fest",
             "Daten, nie Anweisungen",
             "in den Profilen `book` und `full`",
             "in jedem Profil"
           ]}
        ],
        fragment <- fragments do
      assert doc =~ fragment, "API halving section lacks: #{fragment}"
    end
  end

  test "the handbooks describe the cycles as the screen names them, EN and DE" do
    en =
      section(
        "docs/product-documentation.md",
        "### Halving cycles on the chart (ADR-0059, ADR-0060)",
        "### Bonds: master data"
      )

    de =
      section(
        "docs/de/product-documentation.md",
        "### Halving-Zyklen im Chart (ADR-0059, ADR-0060)",
        "### Anleihen: Stammdaten"
      )

    labels = [
      {"Edit", de("Edit")},
      {"Halving chain", de("Halving chain")},
      {"None", de("None")},
      {"Read now", de("Read now")},
      {"Cycles", de("Cycles")},
      {"Timeline", de("halving cycles", "Timeline")},
      {"Aligned", de("halving cycles", "Aligned")},
      {"Segments", de("Segments")},
      {"Top ↔ low", de("Top ↔ low")},
      {"Top – top", de("Top – top")},
      {"Low – low", de("Low – low")},
      {"Cycle", de("chart range", "Cycle")},
      {"both ways", de("both ways")},
      {"Bands and their parts", de("Bands and their parts")},
      {"Where the ways agree", de("Where the ways agree")},
      {"Next low", de("Next low")},
      {"Next top", de("Next top")},
      {"open", de("halving cycles", "open")},
      {"running", de("halving cycles", "running")},
      {"reached", de("halving cycles", "reached")},
      {"missed", de("halving cycles", "missed")},
      {"provisional", de("halving cycles", "provisional")},
      {"Open in chart", "Open in chart →" |> de() |> String.trim_trailing(" →")},
      {"Halving", de("Halving")}
    ]

    for {english, german} <- labels do
      assert en =~ "**#{english}**", "EN handbook lacks **#{english}**"
      assert de =~ "**#{german}**", "DE handbook lacks **#{german}** (#{english})"
    end

    for {doc, fragments} <- [
          {en,
           [
             "`PORTFOLIXIR_BITCOIN_ESPLORA_URL`",
             "`https`",
             "replaces both",
             "home network",
             "deletes its halving events",
             "The journal keeps every deleted row",
             "once per 10 minutes",
             "24 hours",
             "maximum drawdown",
             "not a forecast",
             "never a single date or price",
             "n and both ends",
             "‹Name› cycle",
             "**Privacy mode**",
             "integration/api-and-mcp.html#halving-cycles-and-the-chain-source-fr-58-adr-0059-adr-0060",
             "gives no advice"
           ]},
          {de,
           [
             "`PORTFOLIXIR_BITCOIN_ESPLORA_URL`",
             "`https`",
             "ersetzt sie beide",
             "Heimnetz",
             "löscht seine Halving-Termine",
             "Das Journal behält jede gelöschte Zeile",
             "einmal je 10 Minuten",
             "24 Stunden",
             "maximalen Drawdowns",
             "keine Prognose",
             "nie ein einzelnes Datum oder ein einzelner Kurs",
             "n und beiden Enden",
             "‹Name›-Zyklus",
             "**Privatsphäre-Modus**",
             "integration/api-and-mcp.html#halving-zyklen-und-die-kettenquelle-fr-58-adr-0059-adr-0060",
             "gibt keinen Rat"
           ]}
        ],
        fragment <- fragments do
      assert doc =~ fragment, "handbook halving section lacks: #{fragment}"
    end
  end

  test "the privacy-mode passage names the cycles, EN and DE" do
    en = section("docs/product-documentation.md", "### Privacy mode", "## Audit Journal")
    assert en =~ "halving cycles"

    de = section("docs/de/product-documentation.md", "### Privatsphäre-Modus", "## Audit-Journal")
    assert de =~ "Halving-Zyklen"
  end

  test "the development guide names everything the background-fetch switch leaves off" do
    guide = normalized("docs/development/guide.md")

    refute guide =~ "leaves all three off"

    assert guide =~
             "`PORTFOLIXIR_BACKGROUND_FETCH=off` leaves logo discovery, the quote and FX " <>
               "sync, the news feeds' fetch and the chain read off"
  end
end
