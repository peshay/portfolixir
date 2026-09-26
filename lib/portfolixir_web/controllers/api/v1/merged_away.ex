defmodule PortfolixirWeb.Api.V1.MergedAway do
  @moduledoc """
  What a read of a merged-away id answers (ADR-0050 §12): **404** — the row
  is gone — with `errors.merged_into {kind, id}`, the row its history lives
  on now, following every later merge of that row to the live end of the
  chain (`Portfolixir.Lifecycle.merged_into/2`), and a detail naming both. An
  id no merge names answers the plain `{"errors": {"detail": "not found"}}`.

  Used by the reads of one security, one cash account and one depot
  (`GET /api/v1/securities/:id`, `/cash_accounts/:id`,
  `/securities_accounts/:id`), and so by the MCP tools that read them.
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
    errors =
      with {:ok, parsed} <- IdParam.parse(id),
           survivor when is_integer(survivor) <- Lifecycle.merged_into(kind, parsed) do
        noun = Map.fetch!(@nouns, kind)

        %{
          detail:
            "#{noun} ##{parsed} was merged into #{noun} ##{survivor} and no longer exists; " <>
              "its history lives on #{noun} ##{survivor}",
          merged_into: %{kind: Atom.to_string(kind), id: survivor}
        }
      else
        _not_merged -> %{detail: "not found"}
      end

    conn
    |> put_status(:not_found)
    |> json(%{errors: errors})
  end
end
