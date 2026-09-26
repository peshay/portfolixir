defmodule PortfolixirWeb.Api.V1.MergedAway do
  @moduledoc """
  What a read of a merged-away id answers (ADR-0050 §12): **404** — the row
  is gone — with `errors.merged_into {kind, id}`, the row its history lives
  on now, following every later merge of that row to the live end of the
  chain (`Portfolixir.Lifecycle.merged_into/2`), and a detail naming both. An
  id no merge names answers the plain `{"errors": {"detail": "not found"}}`;
  one whose chain ends at a row deleted since (a survivor may be deleted
  once it holds nothing) answers without `merged_into`, its detail naming
  that row.

  Used by the reads of one security, one cash account and one depot
  (`GET /api/v1/securities/:id`, `/cash_accounts/:id`,
  `/securities_accounts/:id`) and by every route under
  `/api/v1/securities/:security_id/` whose security is not found (its
  quotes, trades, metrics, notes, events and logo, its ISIN change and the
  delete of an identifier alias, reads and writes), and so by the MCP tools
  that call them.
  """

  import Plug.Conn, only: [put_status: 2]
  import Phoenix.Controller, only: [json: 2]

  alias Portfolixir.Lifecycle
  alias PortfolixirWeb.Api.V1.IdParam

  @nouns %{
    cash_account: "cash account",
    securities_account: "securities account",
    security: "security"
  }

  @doc """
  Answers the 404 for `id` of `kind`: with `merged_into` when a merge took
  that row away, plain otherwise.
  """
  @spec not_found(Plug.Conn.t(), :cash_account | :securities_account | :security, term()) ::
          Plug.Conn.t()
  def not_found(conn, kind, id) when is_map_key(@nouns, kind) do
    noun = Map.fetch!(@nouns, kind)

    errors =
      with {:ok, parsed} <- IdParam.parse(id),
           {state, last} <- Lifecycle.merge_chain_end(kind, parsed) do
        chain_errors(state, noun, kind, parsed, last)
      else
        _not_merged -> %{detail: "not found"}
      end

    conn
    |> put_status(:not_found)
    |> json(%{errors: errors})
  end

  defp chain_errors(:live, noun, kind, id, survivor) do
    %{
      detail:
        "#{noun} ##{id} was merged into #{noun} ##{survivor} and no longer exists; " <>
          "its history lives on #{noun} ##{survivor}",
      merged_into: %{kind: Atom.to_string(kind), id: survivor}
    }
  end

  # The survivor at the chain's end was deleted after the merge (it held
  # nothing by then): no row to point at.
  defp chain_errors(:deleted, noun, _kind, id, last) do
    %{detail: "#{noun} ##{id} was merged into #{noun} ##{last}, which has since been deleted"}
  end
end
