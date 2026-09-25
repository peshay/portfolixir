defmodule PortfolixirWeb.Api.V1.ReferencedConflict do
  @moduledoc """
  The one answer a lifecycle delete gives when the row is still referenced
  (ADR-0050 §11): **409**, naming what references it, counted, and what to do
  instead.

      {"errors": {
         "detail": "cash account is referenced by existing records (…); …",
         "referenced_by": {"transactions": 12, "securities_accounts": 1},
         "remedy": "merge",
         "remedy_route": "GET /api/v1/cash_accounts/5/merge_preview?target_id="}}

  `referenced_by` keys are the referencing tables. The remedy is `merge` — the
  route is the merge preview, completed with the id of the row to keep — or,
  for a security that research notes or policy-rule versions reference (a
  merge refuses such a source, ADR-0050 §9), `retire`, whose route is the
  security's PATCH with `is_retired`. The detail says the same in words,
  because a consumer reads the error, not the record.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Lifecycle.Delete
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount

  @labels %{
    "transactions" => {"transaction", "transactions"},
    "securities_accounts" => {"securities account", "securities accounts"},
    "security_quotes" => {"quote", "quotes"},
    "security_notes" => {"research note", "research notes"},
    "security_events" => {"security event", "security events"},
    "policy_rule_versions" => {"policy-rule version", "policy-rule versions"}
  }

  @doc "Renders the 409 for `record`, referenced as `referenced_by` counts."
  @spec render(Plug.Conn.t(), Delete.record(), Delete.referenced_by()) :: Plug.Conn.t()
  def render(conn, record, referenced_by) when is_map(referenced_by) do
    remedy = Delete.remedy(record, referenced_by)
    {noun, path} = resource(record)
    route = remedy_route(remedy, path, record.id)

    conn
    |> put_status(:conflict)
    |> json(%{
      errors: %{
        detail:
          "#{noun} is referenced by existing records (#{counts(referenced_by)}); " <>
            remedy_sentence(remedy, noun, route),
        referenced_by: referenced_by,
        remedy: Atom.to_string(remedy),
        remedy_route: route
      }
    })
  end

  defp resource(%CashAccount{}), do: {"cash account", "cash_accounts"}
  defp resource(%SecuritiesAccount{}), do: {"securities account", "securities_accounts"}
  defp resource(%Security{}), do: {"security", "securities"}

  defp remedy_route(:merge, path, id), do: "GET /api/v1/#{path}/#{id}/merge_preview?target_id="
  defp remedy_route(:retire, path, id), do: "PATCH /api/v1/#{path}/#{id}"

  defp remedy_sentence(:merge, noun, route) do
    "merge it into the #{noun} to keep instead, which moves what references it: preview " <>
      "the merge with #{route}<id of the #{noun} to keep>"
  end

  defp remedy_sentence(:retire, noun, route) do
    "research notes and policy-rule versions can neither move nor vanish, so the #{noun} " <>
      "cannot be merged away: retire it instead with #{route} and " <>
      ~s({"security": {"is_retired": true}})
  end

  defp counts(referenced_by) when map_size(referenced_by) == 0,
    do: "a reference that has gone again; retry the delete"

  defp counts(referenced_by) do
    referenced_by
    |> Enum.map(fn {table, count} -> {label(table, count), count} end)
    |> Enum.sort()
    |> Enum.map_join(", ", fn {label, count} -> "#{count} #{label}" end)
  end

  defp label(table, count) do
    {one, many} = Map.get(@labels, table, {table, table})
    if count == 1, do: one, else: many
  end
end
