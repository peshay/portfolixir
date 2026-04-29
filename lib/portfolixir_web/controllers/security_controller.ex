defmodule PortfolixirWeb.SecurityController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.SecurityCsv

  def export(conn, _params) do
    csv = Catalog.list_securities(:all) |> SecurityCsv.render_csv()

    conn
    |> put_resp_content_type("text/csv", "utf-8")
    |> put_resp_header(
      "content-disposition",
      "attachment; filename=\"portfolixir-securities.csv\""
    )
    |> send_resp(200, csv)
  end
end
