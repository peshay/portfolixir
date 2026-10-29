defmodule PortfolixirWeb.ApiV1ClassificationPositionBoundsTest do
  # Synchronous (shared sandbox) so the page case's process can use the
  # test's connection.
  use PortfolixirWeb.ConnCase, async: false

  import ExUnit.CaptureLog, only: [with_log: 1]
  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Classifications.Category
  alias Portfolixir.Classifications.Classification
  alias Portfolixir.Repo

  @int4_max 2_147_483_647
  @int4_min -2_147_483_648
  @past_bounds [@int4_max + 1, @int4_min - 1, 3_000_000_000]

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, category} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Core"
      })

    %{conn: conn, tree: tree, category: category}
  end

  # The status and body the client is actually sent. When the action raises,
  # Phoenix's RenderErrors sends the error page through the test adapter (a
  # {ref, {status, headers, body}} message) and then re-raises; the raise is
  # turned into that sent status plus the exception banner.
  defp outcome(conn, method, path, body) do
    flush_sent()

    {result, _log} =
      with_log(fn ->
        try do
          sent = dispatch(conn, @endpoint, method, path, body)
          {sent.status, Jason.decode!(sent.resp_body)}
        rescue
          exception ->
            reason = unwrap(exception)

            status =
              receive do
                {ref, {status, _headers, _body}} when is_reference(ref) -> status
              after
                0 -> {:no_response, Plug.Exception.status(reason)}
              end

            {status, {:raised, Exception.format_banner(:error, reason)}}
        end
      end)

    result
  end

  defp unwrap(%Plug.Conn.WrapperError{reason: reason}), do: unwrap(reason)
  defp unwrap(reason), do: reason

  defp flush_sent do
    receive do
      {ref, {_status, _headers, _body}} when is_reference(ref) -> flush_sent()
      {:plug_conn, :sent} -> flush_sent()
    after
      0 -> :ok
    end
  end

  defp counts, do: {Repo.aggregate(Classification, :count), Repo.aggregate(Category, :count)}

  defp stored_positions(tree, category) do
    {Repo.get!(Classification, tree.id).position, Repo.get!(Category, category.id).position}
  end

  defp writes(tree, category, position) do
    base = "/api/v1/classifications"
    cats = "#{base}/#{tree.id}/categories"

    [
      {:post, base, %{"classification" => %{"name" => "Satellite", "position" => position}}},
      {:patch, "#{base}/#{tree.id}", %{"classification" => %{"position" => position}}},
      {:post, cats, %{"category" => %{"name" => "Edge", "position" => position}}},
      {:patch, "#{cats}/#{category.id}", %{"category" => %{"position" => position}}}
    ]
  end

  # User story (security review 2026-10-12, H31):
  # As the agent ordering classifications and categories over the API,
  # I want a position the database cannot hold answered with a field error,
  # so that I learn the bound instead of meeting a server error.
  #
  # Acceptance criteria:
  # - POST and PATCH of a classification and of a category with a position
  #   past either int4 bound answer 422 naming position and write nothing.
  # - The int4 edges themselves are accepted.
  # - A page event carrying such a position leaves the page alive.
  test "a position past the int4 range answers 422 naming position and writes nothing",
       %{conn: conn, tree: tree, category: category} do
    before_counts = counts()
    before_positions = stored_positions(tree, category)

    failures =
      @past_bounds
      |> Enum.flat_map(fn position ->
        Enum.map(writes(tree, category, position), fn {method, path, body} ->
          {method, path, position, outcome(conn, method, path, body)}
        end)
      end)
      |> Enum.reject(fn {_method, _path, _position, result} ->
        match?({422, %{"errors" => %{"position" => [_ | _]}}}, result)
      end)
      |> Enum.map(fn {method, path, position, result} ->
        "#{method |> to_string() |> String.upcase()} #{path} position=#{position} -> #{inspect(result)}"
      end)

    assert counts() == before_counts
    assert stored_positions(tree, category) == before_positions

    assert failures == [],
           "expected 422 with errors.position for every out-of-range write, got:\n" <>
             Enum.join(failures, "\n")
  end

  test "a crafted page event with an out-of-range position leaves the page alive",
       %{tree: tree} do
    Process.flag(:trap_exit, true)
    {:ok, view, _html} = live(build_conn(), "/classifications/#{tree.id}")
    render_async(view)
    before_counts = counts()

    {result, _log} =
      with_log(fn ->
        try do
          render_hook(view, "create_category", %{
            "category" => %{
              "classification_id" => to_string(tree.id),
              "name" => "Edge",
              "position" => "3000000000"
            }
          })

          :alive
        catch
          :exit, {{exception, _stack}, _} when is_exception(exception) ->
            {:crashed, Exception.format_banner(:error, exception)}

          :exit, reason ->
            {:crashed, inspect(reason)}
        end
      end)

    assert counts() == before_counts
    assert result == :alive, "the page process died: #{inspect(result)}"
  end

  test "the int4 edges themselves are accepted", %{conn: conn, tree: tree, category: category} do
    for position <- [@int4_max, @int4_min] do
      for {method, path, body} <- writes(tree, category, position) do
        {status, _body} = outcome(conn, method, path, body)

        assert status in [200, 201],
               "#{method} #{path} position=#{position} answered #{status}"
      end
    end
  end
end
