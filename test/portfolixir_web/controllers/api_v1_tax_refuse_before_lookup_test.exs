defmodule PortfolixirWeb.ApiV1TaxRefuseBeforeLookupTest do
  use PortfolixirWeb.ConnCase, async: true

  import ExUnit.CaptureLog, only: [with_log: 1]

  alias Portfolixir.Repo
  alias Portfolixir.Tax.Parameters
  alias Portfolixir.Tax.StatementSnapshot

  @parameters %{
    "capital_gains_tax_rate" => "0.25",
    "solidarity_surcharge_rate" => "0.055",
    "saver_allowance_single" => "1000",
    "saver_allowance_joint" => "2000"
  }

  defp api_conn do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  # What a client gets. `{:answered, status, body}` when the controller
  # answered; `{:raised, sent_status, exception, message}` when the request
  # raised and the endpoint's render_errors sent the error page instead. The
  # sent status is read from the test adapter's message, the way
  # Phoenix.ConnTest.assert_error_sent/2 reads it.
  defp outcome(verb, path, body) do
    discard_sent()

    {result, _log} =
      with_log(fn ->
        try do
          conn =
            Phoenix.ConnTest.dispatch(api_conn(), @endpoint, verb, path, Jason.encode!(body))

          {:answered, conn.status, Jason.decode!(conn.resp_body)}
        rescue
          exception ->
            {:raised, sent_response(), exception.__struct__,
             exception |> Exception.message() |> String.slice(0, 120)}
        end
      end)

    discard_sent()
    result
  end

  defp sent_response do
    receive do
      {ref, {status, _headers, body}} when is_reference(ref) -> {status, body}
    after
      0 -> :nothing_sent
    end
  end

  defp discard_sent do
    receive do
      {ref, {_status, _headers, _body}} when is_reference(ref) -> discard_sent()
      {:plug_conn, :sent} -> discard_sent()
    after
      0 -> :ok
    end
  end

  defp snapshot(holder) do
    %{
      "statement_snapshot" => %{
        "institution" => "Example Bank",
        "holder" => holder,
        "tax_year" => 2025,
        "as_of" => "2025-12-31"
      }
    }
  end

  # User story (security review 2026-10-12, H36):
  # As the agent recording tax parameters and statement snapshots,
  # I want a value the database cannot hold answered with a field error,
  # so that a bad holder, jurisdiction or year costs me a 422 naming it,
  # never a server error.
  #
  # Acceptance criteria:
  # - A tax year past the int4 range and a NUL in the jurisdiction answer
  #   422 naming the field on PUT /tax/parameters, and nothing is stored.
  # - A NUL in a statement snapshot's holder answers 422 naming holder, and
  #   nothing is stored.
  # - The neighbouring guards keep their answers, and a plain snapshot is
  #   recorded.
  test "PUT /tax/parameters with a tax_year past int4 answers 422 naming tax_year" do
    before = Repo.aggregate(Parameters, :count)
    body = %{"parameters" => Map.put(@parameters, "tax_year", 99_999_999_999)}

    assert {:answered, 422, %{"errors" => %{"tax_year" => _}}} =
             outcome(:put, "/api/v1/tax/parameters", body)

    assert Repo.aggregate(Parameters, :count) == before
  end

  # With an ordinary year, so a lookup would run.
  test "PUT /tax/parameters with a NUL jurisdiction answers 422 naming jurisdiction" do
    before = Repo.aggregate(Parameters, :count)

    body = %{
      "parameters" => Map.merge(@parameters, %{"jurisdiction" => "\u0000", "tax_year" => 2031})
    }

    assert {:answered, 422, %{"errors" => %{"jurisdiction" => _}}} =
             outcome(:put, "/api/v1/tax/parameters", body)

    assert Repo.aggregate(Parameters, :count) == before
  end

  # No church_tax_rate, so a profile lookup would run.
  test "POST /tax/statement_snapshots with a NUL in holder answers 422 naming holder" do
    before = Repo.aggregate(StatementSnapshot, :count)

    assert {:answered, 422, %{"errors" => %{"holder" => _}}} =
             outcome(:post, "/api/v1/tax/statement_snapshots", snapshot("Guest\u0000"))

    assert Repo.aggregate(StatementSnapshot, :count) == before
  end

  test "control: the sibling guards answer 422 and a plain snapshot is recorded" do
    order = fn attrs ->
      %{
        "allowance_order" =>
          Map.merge(
            %{
              "holder" => "Guest",
              "institution" => "Example Bank",
              "tax_year" => 2026,
              "amount_granted" => "100"
            },
            attrs
          )
      }
    end

    # G24: the allowance order never looks up with an invalid changeset.
    assert {:answered, 422, %{"errors" => %{"institution" => _}}} =
             outcome(:put, "/api/v1/tax/allowance_orders", order.(%{"institution" => "\u0000"}))

    assert {:answered, 422, %{"errors" => %{"tax_year" => _}}} =
             outcome(
               :put,
               "/api/v1/tax/allowance_orders",
               order.(%{"tax_year" => 99_999_999_999})
             )

    # A control character PostgreSQL stores passes the lookup harmlessly; the
    # probe's own error answers.
    assert {:answered, 422, %{"errors" => %{"holder" => _}}} =
             outcome(:post, "/api/v1/tax/statement_snapshots", snapshot("Guest\u0007"))

    # An out-of-range year inside int4 is looked up harmlessly, then refused.
    assert {:answered, 422, %{"errors" => %{"tax_year" => _}}} =
             outcome(:put, "/api/v1/tax/parameters", %{
               "parameters" => Map.put(@parameters, "tax_year", 3000)
             })

    # A plain holder is recorded.
    assert {:answered, 201, %{"data" => %{"holder" => "Guest"}}} =
             outcome(:post, "/api/v1/tax/statement_snapshots", snapshot("Guest"))
  end
end
