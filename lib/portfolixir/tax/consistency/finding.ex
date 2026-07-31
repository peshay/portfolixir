defmodule Portfolixir.Tax.Consistency.Finding do
  @moduledoc """
  One advisory finding from `Portfolixir.Tax.Consistency` (ADR-0031 §4).

  A finding states **which two numbers disagree and by how much** — nothing
  else. It deliberately carries no message text and no suggested replacement:

  - no prose, because the engine is pure and locale-free; the display layer
    renders the code (story 19.6), and the API serialises the numbers (19.5);
  - no corrected value, because the checks are a transcription-error detector,
    not a tax authority. The recorded statement stays the authority.

  `severity` is `:advisory` for every finding this module produces. The two
  hard rules (C1, C2) are changeset errors on the snapshot itself — they never
  reach a finding, because the row must not be saved at all.
  """

  @type code :: :c3 | :c4 | :c5 | :c6 | :c7 | :c8

  @type t :: %__MODULE__{
          code: code(),
          severity: :advisory,
          field: atom(),
          recorded: Decimal.t(),
          expected: Decimal.t(),
          gap: Decimal.t()
        }

  @enforce_keys [:code, :severity, :field, :recorded, :expected, :gap]
  defstruct [:code, :severity, :field, :recorded, :expected, :gap]

  @doc "Builds an advisory finding; `gap` is the absolute difference."
  @spec new(code(), atom(), Decimal.t(), Decimal.t()) :: t()
  def new(code, field, recorded, expected) do
    %__MODULE__{
      code: code,
      severity: :advisory,
      field: field,
      recorded: recorded,
      expected: expected,
      gap: recorded |> Decimal.sub(expected) |> Decimal.abs()
    }
  end
end
