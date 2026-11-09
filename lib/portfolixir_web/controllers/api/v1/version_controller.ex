defmodule PortfolixirWeb.Api.V1.VersionController do
  @moduledoc """
  `GET /api/v1/version` (FR-55, #1429): the version this instance was built
  from, as `Portfolixir.BuildVersion` read it when the code compiled — its
  kind (`release`, `build` or `unknown`), its value, the link that explains
  it and the parts it is made of. A read of a compiled constant: it touches
  no database and requests nothing.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.BuildVersion

  def show(conn, _params) do
    json(conn, %{data: BuildVersion.json(BuildVersion.current())})
  end
end
