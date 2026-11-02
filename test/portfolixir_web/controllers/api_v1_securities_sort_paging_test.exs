defmodule PortfolixirWeb.ApiV1SecuritiesSortPagingTest do
  use PortfolixirWeb.ConnCase, async: true

  alias Portfolixir.WorldFixtures

  @count 12

  defp api_conn do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp page_ids(query) do
    conn = get(api_conn(), "/api/v1/securities?" <> URI.encode_query(query))
    conn |> json_response(200) |> Map.fetch!("data") |> Enum.map(& &1["id"])
  end

  # The documented walk: limit 1, offsets 0..n-1, one row per page.
  defp walk(sort_query) do
    Enum.flat_map(0..(@count - 1), fn offset ->
      page_ids(Map.merge(sort_query, %{"limit" => "1", "offset" => Integer.to_string(offset)}))
    end)
  end

  # User story (#1294, Sprint 22 A2):
  # As the agent walking the securities list page by page,
  # I want every sort to break its ties by id,
  # so that a limit/offset walk over rows sharing a sort value returns each
  # security exactly once, and in the same order on every read.
  #
  # Acceptance criteria:
  # - Over a set where every row ties on the sort key (a column, an
  #   attribute nobody set, a quote metric nobody has, the default name
  #   sort), a walk with limit 1 and offsets 0..n-1 returns every id exactly
  #   once.
  # - The tied rows come in ascending id, whichever the sort's direction.
  test "every securities sort breaks its ties by id, so an offset walk neither skips nor repeats" do
    ids =
      for _n <- 1..@count do
        WorldFixtures.create_security!(name: "Tied Security", ticker: nil).id
      end

    expected = Enum.sort(ids)

    sorts = [
      %{},
      %{"sort" => "name"},
      %{"sort" => "name", "direction" => "desc"},
      %{"sort" => "currency_code"},
      %{"sort" => "currency_code", "direction" => "desc"},
      %{"sort" => "asset_class", "direction" => "desc"},
      %{"sort" => "attr_market_cap_rank"},
      %{"sort" => "attr_market_cap_rank", "direction" => "desc"},
      %{"sort" => "latest_price"},
      %{"sort" => "latest_price", "direction" => "desc"}
    ]

    for sort <- sorts do
      walked = walk(sort)
      assert walked == expected, "sort #{inspect(sort)} walked #{inspect(walked)}"
      assert page_ids(sort) == expected, "sort #{inspect(sort)} read out of id order"
    end
  end
end
