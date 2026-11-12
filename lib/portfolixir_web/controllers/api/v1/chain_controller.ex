defmodule PortfolixirWeb.Api.V1.ChainController do
  @moduledoc """
  The registered block chains and the on-demand chain read (FR-58,
  [ADR-0059](../../../../../docs/decisions/0059-chain-source-block-heights-and-times-for-halvings.md)
  §8, §11), mirrored by `portfolixir.chains.list` and
  `portfolixir.chains.refresh`.

    * `GET /api/v1/chains` — every registered chain with its constants and,
      for a chain with a source, its health, the inputs of the next
      halving's estimate and when the next refresh is allowed
      (`Portfolixir.Chains.list/1`).
    * `POST /api/v1/chains/:chain/refresh` — one run of the chain reader,
      synchronous, answering the chain's entry with `run`, its outcome
      (`ok` with the host, the tip and the securities written; `unbound`,
      no security bound, no host asked; `failed` with the stored error).
      Once per 10 minutes per chain: sooner answers **429** with
      `errors.retry_after` in seconds and the `Retry-After` header; a chain
      without a source **422** `errors.code` `no_source`; a name the
      registry does not hold 404.

  Both take no parameter and no body field: one is refused with 422 naming
  it (`ClosedBody`), before anything runs. Times are ISO 8601 UTC, the mean
  block time a decimal string.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Chains
  alias PortfolixirWeb.Api.V1.ClosedBody
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, _params) do
    case ClosedBody.check(conn, nil, []) do
      :ok -> json(conn, %{data: Enum.map(Chains.list(), &JSON.chain/1)})
      {:error, errors} -> ClosedBody.refuse(conn, errors)
    end
  end

  def refresh(conn, %{"chain" => chain}) do
    with :ok <- ClosedBody.check(conn, nil, []),
         {:ok, entry} <- Chains.refresh(chain) do
      json(conn, %{data: JSON.chain(entry)})
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{errors: %{detail: "not found"}})

      {:error, :no_source} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          errors: %{
            code: "no_source",
            chain: chain,
            detail:
              "#{chain} has no source: the app reads no chain but bitcoin (ADR-0059 §3); " <>
                "its halvings are written by hand"
          }
        })

      {:error, {:too_soon, seconds}} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(seconds))
        |> put_status(:too_many_requests)
        |> json(%{
          errors: %{
            retry_after: seconds,
            detail:
              "#{chain} was read less than 10 minutes ago: a chain is read on demand at " <>
                "most once per 10 minutes (ADR-0059 §11); retry after #{seconds} seconds"
          }
        })

      {:error, errors} when is_map(errors) ->
        ClosedBody.refuse(conn, errors)
    end
  end
end
