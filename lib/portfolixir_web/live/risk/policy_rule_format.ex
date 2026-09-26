defmodule PortfolixirWeb.Risk.PolicyRuleFormat do
  @moduledoc """
  How a policy rule and its finding read on the Risk tab (ADR-0049, board
  `01-policy-rules-surface`): the measured value, the line and the distance on
  the measure's own scale, and the rule's words.

  | Measure | Value | Distance |
  |---|---|---|
  | weight, volatility | `12.4 %` | `+2.4 pp` |
  | max_drawdown | `−12.0 %` | `+3.0 pp` |
  | drift | `−1.2 pp` | `+0.5 pp` |
  | hhi | `6,800` | `+300` |

  The distance is the finding's own arithmetic (value − the nearest line) —
  never a recommendation. A value and its unit are joined by a non-breaking
  space, so a narrow cell breaks a band only at "…", never between a figure
  and its unit (board 07 F29). Negative figures carry the app's hyphen-minus,
  as every other figure in the app does.
  """
  use Gettext, backend: PortfolixirWeb.Gettext

  alias PortfolixirWeb.Format
  alias PortfolixirWeb.PolicyRuleLabel

  @percent ~w(weight volatility max_drawdown)

  @doc "The unit a measure's thresholds are typed in, for the dialog's labels."
  @spec unit(String.t() | atom()) :: String.t()
  def unit(measure) when is_atom(measure), do: unit(Atom.to_string(measure))
  def unit(measure) when measure in @percent, do: "%"
  def unit("drift"), do: gettext("pp")
  def unit(_hhi), do: ""

  @doc "A measured value on its measure's scale."
  @spec value(String.t() | atom(), Decimal.t() | nil) :: String.t()
  def value(_measure, nil), do: "—"
  def value(measure, value) when is_atom(measure), do: value(Atom.to_string(measure), value)
  def value("max_drawdown", value), do: "#{Format.signed_decimal(value, 1)}\u00A0%"
  def value(measure, value) when measure in @percent, do: "#{Format.decimal(value, 1)}\u00A0%"
  def value("drift", value), do: "#{Format.signed_decimal(value, 1)}\u00A0#{gettext("pp")}"
  def value(_hhi, value), do: Format.decimal(value, 0)

  @doc "The signed distance to the nearest line."
  @spec distance(String.t() | atom(), Decimal.t() | nil) :: String.t() | nil
  def distance(_measure, nil), do: nil
  def distance(measure, value) when is_atom(measure), do: distance(Atom.to_string(measure), value)
  def distance("hhi", value), do: Format.signed_decimal(value, 0)
  def distance(_measure, value), do: "#{Format.signed_decimal(value, 1)}\u00A0#{gettext("pp")}"

  @doc "A version's line: its threshold, or its band `lower … upper`."
  @spec line(map()) :: String.t()
  def line(%{kind: :band, measure: measure, lower: lower, upper: upper}),
    do: "#{value(measure, lower)} … #{value(measure, upper)}"

  def line(%{measure: measure, threshold: threshold}), do: value(measure, threshold)

  @doc "A version's period, `from – until` or `from –` while open."
  @spec period(map()) :: String.t()
  def period(%{valid_from: from, valid_until: nil}),
    do: gettext("from %{date}", date: Format.date(from))

  def period(%{valid_from: from, valid_until: until}),
    do: "#{Format.date(from)} – #{Format.date(until)}"

  @doc """
  The rule's words: measure (and window) · subject · kind · severity. `names`
  resolves the subject's ids: `%{securities: %{id => name}, categories: ...,
  views: ...}`.
  """
  @spec words(map(), map()) :: String.t()
  def words(version_or_finding, names) do
    [
      PolicyRuleLabel.measure(version_or_finding.measure),
      version_or_finding.window && PolicyRuleLabel.window(version_or_finding.window),
      subject(version_or_finding, names),
      PolicyRuleLabel.kind(version_or_finding.kind),
      PolicyRuleLabel.severity(version_or_finding.severity)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  @doc """
  `words/2` as parts, for a line that renders them (E25 S7, G20; pick G12.2
  = B): `{:stored, text}` for the subject when it is a stored name (a
  security's, a category's, a view's), which the line isolates in `<bdi>`, so
  a direction control a legacy name still carries reorders at most the name;
  `{:text, text}` for every other part. Joined by " · ", the parts read
  exactly as `words/2`.
  """
  @spec word_parts(map(), map()) :: [{:text | :stored, String.t()}]
  def word_parts(version_or_finding, names) do
    [
      {:text, PolicyRuleLabel.measure(version_or_finding.measure)},
      {:text, version_or_finding.window && PolicyRuleLabel.window(version_or_finding.window)},
      subject_part(version_or_finding, names),
      {:text, PolicyRuleLabel.kind(version_or_finding.kind)},
      {:text, PolicyRuleLabel.severity(version_or_finding.severity)}
    ]
    |> Enum.reject(fn {_kind, text} -> is_nil(text) end)
  end

  defp subject_part(%{subject_type: type} = version, names)
       when type in [:security, :category, :view] do
    fallback = PolicyRuleLabel.subject_type(type)

    case subject(version, names) do
      ^fallback -> {:text, fallback}
      stored -> {:stored, stored}
    end
  end

  defp subject_part(version, names), do: {:text, subject(version, names)}

  defp subject(%{subject_type: :basis}, _names), do: nil
  defp subject(%{subject_type: :cash}, _names), do: PolicyRuleLabel.subject_type(:cash)

  defp subject(%{subject_type: :security, security_id: id}, names),
    do: Map.get(names.securities, id) || PolicyRuleLabel.subject_type(:security)

  defp subject(%{subject_type: :category, category_id: id}, names),
    do: Map.get(names.categories, id) || PolicyRuleLabel.subject_type(:category)

  defp subject(%{subject_type: :view, subject_view_id: id}, names) do
    case Map.get(names.views, id) do
      nil -> PolicyRuleLabel.subject_type(:view)
      name -> gettext("View “%{name}”", name: name)
    end
  end
end
