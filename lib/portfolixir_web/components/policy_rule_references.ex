defmodule PortfolixirWeb.PolicyRuleReferences do
  @moduledoc """
  The rules a refused delete names, each one **reachable** (#871, pick G6-A,
  board `ux-design-2026-09-24/06-view-rule-reach`).

  A rule belongs to the view it applies in — its context (ADR-0049 §1) — and
  Wealth → Risk shows only the active view's rules, with no view switcher. So
  a refusal that names a rule links the rule's **name** to
  `/risk?view=<its context>` (`view=total` for a portfolio-wide rule), and
  says in the parenthesis which view that is. The link is a plain `href`, like
  the view switcher's chips: a full navigation, so `PortfolixirWeb.ViewScope`
  takes the choice.

  One formulation for every refusal that names rules (the message band on
  `/buckets` and `/classifications`, the list in the securities
  delete-blocked dialog). The rules arrive as data, never as a finished
  sentence, and a rule's name or a view's name is only ever rendered as text:
  the translated templates are split around their placeholders before any
  stored text is put in.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Buckets
  alias Portfolixir.Portfolios.PolicyRule
  alias PortfolixirWeb.PolicyRuleLabel

  @enforce_keys [:rules]
  defstruct [:rules]

  @typedoc "One named rule: its id, name, status and the view it applies in."
  @type rule_reference :: %{
          id: integer(),
          name: String.t(),
          status: atom(),
          view_id: integer() | nil,
          view_name: String.t() | nil
        }

  @type t :: %__MODULE__{rules: [rule_reference()]}

  @doc """
  The refusal a delete answers when rules read the object (ADR-0049 §8), as
  data for `message/1`: every rule with the name of the view it applies in.
  """
  @spec refusal([PolicyRule.t()]) :: t()
  def refusal(rules), do: %__MODULE__{rules: references(rules)}

  @doc "The rules as references, each with the name of its context view."
  @spec references([PolicyRule.t()]) :: [rule_reference()]
  def references(rules) do
    names =
      if Enum.any?(rules, &(not is_nil(&1.view_id))),
        do: Map.new(Buckets.list_views(), &{&1.id, &1.name}),
        else: %{}

    Enum.map(rules, fn %PolicyRule{} = rule ->
      %{
        id: rule.id,
        name: rule.name,
        status: rule.status,
        view_id: rule.view_id,
        view_name: Map.get(names, rule.view_id)
      }
    end)
  end

  @doc """
  A message band's text: a plain message as it is, a refusal as the sentence
  naming the rules with their links (board 06's second sentence unchanged).
  """
  attr(:message, :any, required: true)

  def message(%{message: %__MODULE__{}} = assigns) do
    assigns =
      assign(
        assigns,
        :segments,
        segments(
          gettext(
            "Read by policy rules: %{names}. A rule that has been in force keeps its subject as part of its history; retiring it on Wealth → Risk stops its evaluation.",
            names: marker(:names)
          )
        )
      )

    ~H"""
    <%= for segment <- @segments do %><%= if segment == :names do %><%= for {reference, index} <- Enum.with_index(@message.rules) do %><%= if index > 0 do %>, <% end %><.rule reference={reference} /><% end %><% else %><%= segment %><% end %><% end %>
    """
  end

  def message(assigns) do
    ~H"<%= @message %>"
  end

  @doc """
  One named rule: “name” (status, view “View”), the name a link to Wealth →
  Risk in the view the rule applies in.
  """
  attr(:reference, :map, required: true)

  def rule(assigns) do
    assigns =
      assign(
        assigns,
        :segments,
        segments(
          gettext("“%{name}” (%{status}, view “%{view}”)",
            name: marker(:name),
            status: marker(:status),
            view: marker(:view)
          )
        )
      )

    ~H"""
    <%= for segment <- @segments do %><%= case segment do %><% :name -> %><a href={risk_href(@reference)} data-role="policy-rule-link" data-rule-id={@reference.id}><%= @reference.name %></a><% :status -> %><%= PolicyRuleLabel.status(@reference.status) %><% :view -> %><%= view_name(@reference) %><% text -> %><%= text %><% end %><% end %>
    """
  end

  @doc "Wealth → Risk in the view a rule applies in."
  @spec risk_href(rule_reference()) :: String.t()
  def risk_href(%{view_id: nil}), do: "/risk?view=total"
  def risk_href(%{view_id: view_id}), do: "/risk?view=#{view_id}"

  defp view_name(%{view_id: nil}), do: gettext("Everything")
  defp view_name(%{view_name: name}) when is_binary(name), do: name
  # A view a rule applies in cannot be deleted (ADR-0049 §8), so its name is
  # always found; this only keeps the band from failing on a race.
  defp view_name(%{view_id: view_id}), do: to_string(view_id)

  # A placeholder no translation can carry: the template is split on it, so
  # no stored name ever takes part in the split or reaches the page as markup.
  @marker "\u0000"

  defp marker(key), do: @marker <> Atom.to_string(key) <> @marker

  defp segments(text) do
    ~r/\x{0}(names|name|status|view)\x{0}/u
    |> Regex.split(text, include_captures: true, trim: true)
    |> Enum.map(fn
      @marker <> "names" <> @marker -> :names
      @marker <> "name" <> @marker -> :name
      @marker <> "status" <> @marker -> :status
      @marker <> "view" <> @marker -> :view
      text -> text
    end)
  end
end
