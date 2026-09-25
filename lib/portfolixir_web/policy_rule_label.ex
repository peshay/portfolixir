defmodule PortfolixirWeb.PolicyRuleLabel do
  @moduledoc """
  The one localized label per policy-rule enum value (ADR-0049 §1;
  EXPERIENCE.md → Amendment 2026-09-12 → Voice and Tone: a raw enum value
  never reaches a user-facing string).

  Every member of `Portfolixir.Portfolios.PolicyRuleVersion`'s closed sets —
  and of the finding states, their reasons and the rule statuses — has a
  clause, and there is deliberately **no fallback**: an unknown value fails
  loudly in `transaction_kind_label_test.exs`, which pins the coverage against
  the enums, instead of printing its slug on a page. The rule applies here
  from the first commit, as ADR-0049 §1 requires.
  """
  use Gettext, backend: PortfolixirWeb.Gettext

  @spec measure(String.t() | atom()) :: String.t()
  def measure(value) when is_atom(value), do: measure(Atom.to_string(value))
  def measure("weight"), do: gettext("Weight")
  def measure("drift"), do: gettext("Drift")
  def measure("hhi"), do: gettext("Concentration (HHI)")
  def measure("volatility"), do: gettext("Volatility")
  def measure("max_drawdown"), do: gettext("Maximum drawdown")

  @spec subject_type(String.t() | atom()) :: String.t()
  def subject_type(value) when is_atom(value), do: subject_type(Atom.to_string(value))
  def subject_type("basis"), do: gettext("Whole basis")
  def subject_type("security"), do: gettext("Security")
  def subject_type("category"), do: gettext("Category")
  def subject_type("view"), do: gettext("View")
  def subject_type("cash"), do: gettext("Cash")

  @spec kind(String.t() | atom()) :: String.t()
  def kind(value) when is_atom(value), do: kind(Atom.to_string(value))
  def kind("cap"), do: gettext("Cap")
  def kind("floor"), do: gettext("Floor")
  def kind("band"), do: gettext("Band")

  @spec severity(String.t() | atom()) :: String.t()
  def severity(value) when is_atom(value), do: severity(Atom.to_string(value))
  def severity("warn"), do: gettext("Warning")
  def severity("hard"), do: gettext("Hard")

  @spec window(String.t() | atom()) :: String.t()
  def window(value) when is_atom(value), do: window(Atom.to_string(value))
  def window("30d"), do: gettext("30 days")
  def window("90d"), do: gettext("90 days")
  def window("365d"), do: gettext("365 days")

  @doc "A finding's state (ADR-0049 §3)."
  @spec state(String.t() | atom()) :: String.t()
  def state(value) when is_atom(value), do: state(Atom.to_string(value))
  def state("breached"), do: gettext("breached")
  def state("undetermined"), do: gettext("undetermined")
  def state("ok"), do: gettext("met")

  @doc "Why a finding is undetermined (ADR-0049 §3)."
  @spec reason(String.t() | atom()) :: String.t()
  def reason(value) when is_atom(value), do: reason(Atom.to_string(value))
  def reason("insufficient_data"), do: gettext("too little history")
  def reason("undefined"), do: gettext("the figure is undefined")
  def reason("no_active_plan"), do: gettext("no active plan")
  def reason("no_target"), do: gettext("no target in the plan")
  def reason("empty_basis"), do: gettext("nothing to weigh")
  def reason("subject_not_found"), do: gettext("the subject no longer exists")
  def reason("not_measured"), do: gettext("not measured")
  def reason("unvalued"), do: gettext("held, but not valued")

  @doc "A rule's status relative to today (in force, scheduled, retired)."
  @spec status(String.t() | atom()) :: String.t()
  def status(value) when is_atom(value), do: status(Atom.to_string(value))
  def status("in_force"), do: gettext("in force")
  def status("scheduled"), do: gettext("scheduled")
  def status("retired"), do: gettext("retired")

  # The refusal a delete gives when rules read the object (ADR-0049 §8) names
  # each rule as a link to Risk in its view: `PortfolixirWeb.PolicyRuleReferences`
  # (#871, G6-A).
end
