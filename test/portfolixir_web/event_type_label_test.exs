defmodule PortfolixirWeb.EventTypeLabelTest do
  # Sprint 28, N8 (EXPERIENCE.md → Voice and Tone): every event type a label
  # or a research entry can carry, and every tone, has its words, in English
  # and in German, and none reads as its code.
  use ExUnit.Case, async: true

  alias Portfolixir.Knowledge.SecurityNote
  alias Portfolixir.News.Label
  alias PortfolixirWeb.EventTypeLabel

  # User story (EXPERIENCE.md → Voice and Tone):
  # As the operator reading a story's label or a note's marker,
  # I want each event type and tone in words in my language,
  # so that I never read a code such as capital_measure.
  #
  # Acceptance criteria:
  # - Every event type of the label's set (the entry's set is part of it)
  #   and every tone has a label in English and German, none its code.
  test "every event type and tone has its words in both languages" do
    assert SecurityNote.event_types() -- Label.event_types() == []

    for locale <- ["en", "de"] do
      Gettext.with_locale(PortfolixirWeb.Gettext, locale, fn ->
        for type <- Label.event_types() do
          word = EventTypeLabel.event_type(type)
          refute word =~ "_", "#{locale}: #{type} reads #{word}"
          refute word == type, "#{locale}: #{type} reads as its code"
        end

        for tone <- [-1, 0, 1], do: assert(EventTypeLabel.tone(tone) =~ ~r/^\p{L}+$/u)
      end)
    end

    Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
      assert EventTypeLabel.event_type(:capital_measure) == "Kapitalmaßnahme"
      assert EventTypeLabel.tone(-1) == "negativ"
    end)
  end
end
