defmodule PortfolixirWeb.SecurityEventLabel do
  @moduledoc """
  The one localized label per security-event `kind` and `timing` (ADR-0048 §6;
  EXPERIENCE.md → Amendment 2026-09-12 → Voice and Tone: a raw enum value never
  reaches a user-facing string).

  Every element of `Portfolixir.Knowledge.SecurityEvent.kinds/0` and
  `timings/0` has a clause and there is deliberately **no fallback**: an
  unknown value fails loudly in `security_event_label_test.exs`, which pins the
  coverage against the enum, instead of printing its slug on a page. The rule
  applies here from the first commit rather than being added after a review
  found a slug on a screen.
  """
  use Gettext, backend: PortfolixirWeb.Gettext

  @spec kind(String.t() | atom()) :: String.t()
  def kind(value) when is_atom(value) and not is_nil(value), do: kind(Atom.to_string(value))

  def kind("earnings"), do: gettext("Earnings report")
  def kind("ex_dividend"), do: gettext("Ex-dividend date")
  def kind("dividend_payment"), do: gettext("Dividend payment")
  def kind("lockup_expiry"), do: gettext("Lockup expiry")
  def kind("index_review"), do: gettext("Index review")
  def kind("shareholder_meeting"), do: gettext("Shareholder meeting")
  def kind("regulatory_decision"), do: gettext("Regulatory decision")
  def kind("guidance_update"), do: gettext("Guidance update")

  @doc """
  How well the date is known (§3). The wording is the point: an estimate must
  not read like a filing.

  `exact` reads "Announced" rather than "Confirmed date", which is what the
  closing-act walkthrough found it saying beside the `confirmed` badge. The
  two are different facts — `exact` is *a source set this day*, `confirmed`
  is *it happened* (§5.3's "did it actually happen?" queue) — and a row
  reading "Confirmed date" on an event nobody has ticked off says the
  opposite of what it means. ADR-0048 §3 draws the same contrast itself:
  `estimated` is "from an estimate rather than an announcement".
  """
  @spec timing(String.t() | atom()) :: String.t()
  def timing(value) when is_atom(value) and not is_nil(value), do: timing(Atom.to_string(value))

  def timing("exact"), do: gettext("Announced")
  def timing("estimated"), do: gettext("Estimated")
  def timing("window"), do: gettext("Within a period")
  def timing("month"), do: gettext("Month known, day not")
end
