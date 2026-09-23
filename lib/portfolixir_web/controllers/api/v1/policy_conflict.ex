defmodule PortfolixirWeb.Api.V1.PolicyConflict do
  @moduledoc """
  The one answer a delete gives when a policy rule reads the object
  (ADR-0049 §8): **409**, naming the rules and the remedy.

  A version that has been in force keeps its subject as part of the record of
  what the standard was, so retiring a rule stops its evaluation without
  freeing the reference; only a rule none of whose versions was ever in force
  can be deleted, which does. The detail says both, because a consumer reads
  the error, not the record.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Portfolixir.Portfolios.PolicyRule

  @doc "Renders the 409 for `rules` reading `object` (e.g. \"security\")."
  @spec render(Plug.Conn.t(), [PolicyRule.t()], String.t()) :: Plug.Conn.t()
  def render(conn, rules, object) when is_list(rules) and is_binary(object) do
    names = Enum.map_join(rules, ", ", &"\"#{&1.name}\" (#{&1.status})")

    conn
    |> put_status(:conflict)
    |> json(%{
      errors: %{
        detail:
          "this #{object} is read by #{length(rules)} policy rule(s): #{names}. A rule's " <>
            "versions keep their subject as the record of what the standard was: retire a " <>
            "rule to stop its evaluation (POST /api/v1/policy_rules/:id/retire); only a rule " <>
            "none of whose versions was ever in force can be deleted, which frees the " <>
            "reference.",
        policy_rules:
          Enum.map(rules, fn %PolicyRule{} = rule ->
            %{id: rule.id, name: rule.name, status: to_string(rule.status)}
          end)
      }
    })
  end
end
