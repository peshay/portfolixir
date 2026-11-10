defmodule PortfolixirWeb.EventTypeLabel do
  @moduledoc """
  The one localized label per event type of a story's label (ADR-0056 §7)
  and of a research entry (ADR-0044's amendment of 2026-11-06), and per
  tone (Sprint 28, N8, N9; EXPERIENCE.md → Voice and Tone: a raw enum value
  never reaches a user-facing string).

  Every element of `Portfolixir.News.Label.event_types/0` (the entry's set
  and `noise`) has a clause and there is deliberately **no fallback**, as
  `PortfolixirWeb.SecurityEventLabel` has none: an unknown value fails
  loudly in `event_type_label_test.exs`, which pins the coverage against
  the enum, instead of printing its code on a page. The news page's digest,
  the security's tab „Nachrichten“ and the chart's note markers read their
  words here.
  """
  use Gettext, backend: PortfolixirWeb.Gettext

  @spec event_type(String.t() | atom()) :: String.t()
  def event_type(value) when is_atom(value) and not is_nil(value),
    do: event_type(Atom.to_string(value))

  def event_type("earnings"), do: pgettext("event type", "Earnings")
  def event_type("guidance"), do: pgettext("event type", "Guidance")
  def event_type("capital_measure"), do: pgettext("event type", "Capital measure")
  def event_type("legal"), do: pgettext("event type", "Legal")
  def event_type("m_and_a"), do: pgettext("event type", "M&A")
  def event_type("product"), do: pgettext("event type", "Product")
  def event_type("regulatory"), do: pgettext("event type", "Regulatory")
  def event_type("macro"), do: pgettext("event type", "Macro")
  def event_type("noise"), do: pgettext("event type", "Noise")

  @doc "The tone's word (−1, 0, +1): a stored reading, never a signal (ADR-0044)."
  @spec tone(-1 | 0 | 1) :: String.t()
  def tone(1), do: pgettext("tone", "positive")
  def tone(0), do: pgettext("tone", "neutral")
  def tone(-1), do: pgettext("tone", "negative")
end
