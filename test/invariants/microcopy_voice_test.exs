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
end
