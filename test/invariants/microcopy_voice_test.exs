defmodule Portfolixir.Invariants.MicrocopyVoiceTest do
  use ExUnit.Case, async: true

  @de "priv/gettext/de/LC_MESSAGES/default.po"

  # User story (#791, the review's D11; EXPERIENCE.md → Voice and Tone,
  # UX-DR11; the impersonal-voice rule of 2026-07-23, review-blocking):
  # As the operator reading any surface,
  # I want no string to address me or coach me,
  # so that the interface states conditions and offers controls instead of
  # giving instructions.
  #
  # Acceptance criteria:
  # - The German catalog carries no translation that starts an instruction
  #   ("Tippe", "Wähle", "Lege", "Passe", "Klicke") or addresses the reader
  #   ("du", "dein"), outside quoted legal terms.
  # - The English source strings carry no "you" / "your".
  @second_person_de ~r/(Tippe |Wähle |Lege |Passe |Klicke |\bdu\b|\bdein)/
  @second_person_en ~r/\b([Yy]ou|[Yy]our)\b/

  test "no German translation addresses or coaches the reader" do
    offending =
      @de
      |> File.read!()
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "msgstr"))
      |> Enum.filter(&Regex.match?(@second_person_de, &1))

    assert offending == [], "second-person strings in #{@de}:\n" <> Enum.join(offending, "\n")
  end

  test "no English source string addresses the reader" do
    offending =
      @de
      |> File.read!()
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "msgid"))
      |> Enum.filter(&Regex.match?(@second_person_en, &1))

    assert offending == [], "second-person source strings:\n" <> Enum.join(offending, "\n")
  end

  # User story (Sprint 19 U6, board 08 "found while drawing"; EXPERIENCE.md
  # → Voice and Tone, the house infinitive; R10d):
  # As the operator reading the German interface,
  # I want a remedy said in the infinitive wherever it stands in a sentence,
  # and the journal named in plain words,
  # so that no message switches to "du" halfway through, and none says
  # "journalisiert".
  #
  # Acceptance criteria:
  # - No German translation in either catalog carries a "du" imperative,
  #   whether it opens the sentence or follows a dash or a semicolon
  #   ("— wähle einen", "Aktualisiere die Seite", "gib den Text … ein").
  # - No German translation says "journalisiert"; the journal "hält … fest".
  @du_imperative_de ~r/\b(erfasse|korrigiere|wähle|entferne|aktualisiere|versuche|importiere|synchronisiere|bearbeite|weise|gib|tippe|lege|passe|klicke|prüfe|öffne)\b|(^msgstr(\[\d\])? "|[.!?—:;] )(Erfasse|Korrigiere|Wähle|Entferne|Aktualisiere|Versuche|Importiere|Synchronisiere|Bearbeite|Gib|Tippe|Lege|Passe|Klicke|Prüfe|Öffne) /u

  test "no German translation gives a du imperative mid-sentence or says journalisiert" do
    offending =
      ["priv/gettext/de/LC_MESSAGES/default.po", "priv/gettext/de/LC_MESSAGES/errors.po"]
      |> Enum.flat_map(fn path -> path |> File.read!() |> String.split("\n") end)
      |> Enum.filter(&String.starts_with?(&1, "msgstr"))
      |> Enum.filter(&(Regex.match?(@du_imperative_de, &1) or &1 =~ "journalisiert"))

    assert offending == [], "du imperatives or \"journalisiert\":\n" <> Enum.join(offending, "\n")
  end

  # User story (the review of Sprint 19 U6; R10d, board 08 "found while
  # drawing" item 3):
  # As the operator reading the English interface,
  # I want the journal named in plain words there too,
  # so that the security delete confirmation does not say "journaled" where
  # every other surface says the journal records the change.
  #
  # Acceptance criteria:
  # - No English source string in either template says "journaled"
  #   (singular or plural form); the journal "records" it.
  @journaled_en ~r/\bjournal(l)?ed\b/i

  test "no English source string says journaled" do
    offending =
      ["priv/gettext/default.pot", "priv/gettext/errors.pot"]
      |> Enum.flat_map(fn path -> path |> File.read!() |> String.split("\n") end)
      |> Enum.filter(&String.starts_with?(&1, "msgid"))
      |> Enum.filter(&Regex.match?(@journaled_en, &1))

    assert offending == [], "\"journaled\" in source strings:\n" <> Enum.join(offending, "\n")
  end
end
