defmodule PortfolixirWeb.Api.V1.SecurityDossierController do
  @moduledoc """
  The position dossier read (FR-49; Sprint 24 plan D-2):
  `GET /api/v1/securities/:id/dossier`, mirrored by the
  `portfolixir.securities.dossier` MCP tool. Read-only. The parts and the
  read each one mirrors are `PortfolixirWeb.Api.V1.SecurityDossier`'s.

  A merged-away id answers 404 with `errors.merged_into`, as
  `GET /api/v1/securities/:id` does (ADR-0050 §12).
  """
  use PortfolixirWeb, :controller

  alias PortfolixirWeb.Api.V1.MergedAway
  alias PortfolixirWeb.Api.V1.SecurityDossier

  def show(conn, %{"id" => id}) do
    case SecurityDossier.build(id) do
      {:ok, dossier} -> json(conn, %{data: dossier})
      :error -> MergedAway.not_found(conn, :security, id)
    end
  end
end
