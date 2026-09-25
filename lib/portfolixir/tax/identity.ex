defmodule Portfolixir.Tax.Identity do
  @moduledoc """
  Normalisation for the free-text identity columns of the tax context —
  `holder` and `institution` (ADR-0031 §3, story 19.2 §5a).

  Portfolixir has no institution entity, so three tables key off these strings:
  `tax_profiles`, `allowance_orders` and (story 19.3)
  `tax_statement_snapshots`. Story 19.4 joins across them. If `"comdirect"` and
  `"Comdirect"` landed as two rows, the consistency engine would report a
  missing Freistellungsauftrag that is not missing — a wrong advisory that looks
  like a real finding.

  The rule is therefore fixed here once: normalise on write (compose, drop
  invisible format characters, collapse every run of Unicode spaces, reject
  empty), store **case-preserving** because the operator's capitalisation is
  theirs, and match **case-folded by the database** — the unique indexes are
  on `lower(...)`, and every lookup, roll-up and enumeration folds with that
  same `lower()` on both sides (`folded/1`), never with an Elixir fold that
  can disagree with it (E25 S6, G21, G22).
  """

  alias Portfolixir.Input.Text

  # Every Unicode space separator (Zs: the no-break, figure, narrow and
  # ideographic spaces among them) and every other white-space character.
  @spaces ~r/[\s\p{Zs}]+/u

  @doc """
  Composes to NFC, removes Unicode format characters (zero-width spaces and
  joiners, the byte-order mark, the soft hyphen, bidi marks), and collapses
  every run of Unicode spaces to a single space, trimmed. A value that was
  only such characters becomes `""`, which the changesets' required check
  refuses as blank.

  Only ever called from `update_change/3`, which runs after a successful cast —
  a non-string never reaches here, it is already a changeset type error. A
  string that is not valid UTF-8 is returned unchanged for the text check to
  refuse.
  """
  @spec normalize(String.t()) :: String.t()
  def normalize(value) when is_binary(value) do
    if String.valid?(value) do
      value
      |> Text.strip_format_characters()
      |> :unicode.characters_to_nfc_binary()
      |> String.split(@spaces, trim: true)
      |> Enum.join(" ")
    else
      value
    end
  end

  @doc """
  The database's fold of an identity column or value inside an Ecto query:
  the `lower(...)` the unique indexes are built on. Both sides of a match,
  and every grouping key, are folded here, so the database's case rule is
  the only one.
  """
  defmacro folded(expr) do
    quote do
      fragment("lower(?)", unquote(expr))
    end
  end
end
