defmodule PortfolixirWeb.Api.V1.CrashBenchmarkControllerTest do
  # Sprint 29 C1 (FR-54, #1421; ADR-0058 §1, §9): PUT
  # /api/v1/settings/crash_benchmark. Every name and figure is synthetic.
  # group: :crash_benchmark -- the async modules that choose the crash
  # benchmark never run at the same time (the closing act of Sprint 29). The
  # choice is one settings row for the instance (settings_key_index), taken
  # under an advisory lock on its key, and a sandboxed test never commits: a
  # module choosing beside another one waited on the other's lock and row
  # until that test ended, into the 15 s query timeout under load. The key
  # is the setting's, so no fixture of a test's own avoids it.
  use PortfolixirWeb.ConnCase, async: true, group: :crash_benchmark

  import Portfolixir.WorldFixtures, only: [create_security!: 1, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Journal
  alias Portfolixir.Lifecycle
  alias Portfolixir.Settings

  @path "/api/v1/settings/crash_benchmark"

  defp authed(conn, token \\ "test-api-token") do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer " <> token)
  end

  defp put_benchmark(conn, body), do: conn |> authed() |> put(@path, Jason.encode!(body))

  defp bare!(name) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{name: name, currency_code: "EUR"})

    security
  end

  # User story (ADR-0058 §1, §9):
  # As the agent the operator runs,
  # I want to set the crash benchmark over the API with my own token,
  # so that the operator's choice of "the market" is scriptable and every
  # agent then reads the same windows.
  #
  # Acceptance criteria:
  # - PUT {"security_id": <id>} with a security that has a stored quote,
  #   flagged or not, answers 200 with the id and the security's id, name,
  #   is_benchmark and benchmark_security (flagged, held or unheld).
  # - PUT {"security_id": null} clears it and answers both as null.
  # - The write is journaled under the request's token.
  test "sets and clears the crash benchmark, journaled under the token", %{conn: conn} do
    fund = create_security!(name: "Synthetic Watched Fund", ticker: "SWF")
    put_quote!(fund, ~D[2025-03-03], "10")

    assert %{
             "data" => %{
               "security_id" => id,
               "security" => %{
                 "id" => id,
                 "name" => "Synthetic Watched Fund",
                 "is_benchmark" => false,
                 "benchmark_security" => "unheld"
               }
             }
           } = conn |> put_benchmark(%{security_id: fund.id}) |> json_response(200)

    assert id == fund.id
    assert Settings.crash_benchmark_security_id() == fund.id

    assert [%{operation: :upsert, actor_type: :api_token_rw}] =
             Journal.list_entries(resource_type: "setting")

    assert %{"data" => %{"security_id" => nil, "security" => nil}} =
             conn |> put_benchmark(%{security_id: nil}) |> json_response(200)

    assert Settings.crash_benchmark_security_id() == nil
  end

  # Acceptance criteria (ADR-0058 §1, §9):
  # - A security without a stored quote answers 422 errors.security_id
  #   ["has no stored quote"]; an unknown id 422 ["is not a benchmark
  #   security"]; a merged-away one the same, naming merged_into {kind, id}.
  # - A malformed or missing security_id answers 422 naming it.
  # - A field the write does not take answers 422 naming it.
  # - None of them writes the setting.
  test "refuses an unquoted, unknown, merged-away or malformed id and an unknown field",
       %{conn: conn} do
    unquoted = create_security!(name: "Synthetic Unquoted Fund", ticker: "SUF")

    target = bare!("Synthetic Harbour Fund")
    source = bare!("Synthetic Harbour Fund")
    put_quote!(target, ~D[2025-03-03], "20")
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    {:ok, _record, :applied} =
      Lifecycle.merge_security(Actor.owner_ui(), source.id, target.id, %{
        plan_digest: preview.plan_digest
      })

    assert %{"errors" => %{"security_id" => ["has no stored quote"]}} =
             conn |> put_benchmark(%{security_id: unquoted.id}) |> json_response(422)

    assert %{"errors" => %{"security_id" => ["is not a benchmark security"]} = errors} =
             conn |> put_benchmark(%{security_id: 999_999_999}) |> json_response(422)

    refute Map.has_key?(errors, "merged_into")

    target_id = target.id

    assert %{
             "errors" => %{
               "security_id" => ["is not a benchmark security"],
               "merged_into" => %{"kind" => "security", "id" => ^target_id}
             }
           } = conn |> put_benchmark(%{security_id: source.id}) |> json_response(422)

    for bad <- ["abc", "1.5", 0, -3, "99999999999999999999", 1.0] do
      assert %{"errors" => %{"security_id" => ["is invalid"]}} =
               conn |> put_benchmark(%{security_id: bad}) |> json_response(422),
             "security_id=#{inspect(bad)}"
    end

    assert %{"errors" => %{"security_id" => ["can't be blank"]}} =
             conn |> put_benchmark(%{}) |> json_response(422)

    assert %{"errors" => %{"threshold" => ["is unknown: this write takes only security_id"]}} =
             conn
             |> put_benchmark(%{security_id: target.id, threshold: "0.2"})
             |> json_response(422)

    assert Settings.crash_benchmark_security_id() == nil
    assert Journal.list_entries(resource_type: "setting") == []
  end

  test "requires a read-write token", %{conn: conn} do
    assert conn
           |> put_req_header("accept", "application/json")
           |> put(@path, %{security_id: nil})
           |> json_response(401)
  end
end
