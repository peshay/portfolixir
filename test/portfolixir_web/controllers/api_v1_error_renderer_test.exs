defmodule PortfolixirWeb.ApiV1ErrorRendererTest do
  use PortfolixirWeb.ConnCase, async: false

  alias Portfolixir.Tax.Parameters
  alias PortfolixirWeb.Api.V1.JSON

  # A non-seeded year, so the upsert takes the insert path.
  @valid %{
    "jurisdiction" => "DE",
    "tax_year" => 2031,
    "capital_gains_tax_rate" => "0.25",
    "solidarity_surcharge_rate" => "0.055",
    "saver_allowance_single" => "1000.00",
    "saver_allowance_joint" => "2000.00"
  }

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  # Runs the request; a raise inside the endpoint is turned into a readable
  # outcome holding what the client actually received (the test adapter sends
  # the rendered error response to this process before the endpoint re-raises).
  defp put_parameters(conn, church_tax_rates) do
    body = Jason.encode!(%{"parameters" => Map.put(@valid, "church_tax_rates", church_tax_rates)})

    {outcome, _log} =
      ExUnit.CaptureLog.with_log(fn ->
        try do
          {:ok, conn |> api_conn() |> put("/api/v1/tax/parameters", body)}
        rescue
          error ->
            inner =
              case error do
                %Plug.Conn.WrapperError{reason: reason} -> reason
                other -> other
              end

            sent =
              receive do
                {ref, {status, _headers, sent_body}} when is_reference(ref) -> {status, sent_body}
              after
                0 -> :nothing_sent
              end

            {:raised, inner, sent}
        end
      end)

    outcome
  end

  defp assert_field_error(outcome, label) do
    case outcome do
      {:ok, conn} ->
        assert %{"errors" => %{"church_tax_rates" => [_ | _]}} = json_response(conn, 422)

      {:raised, inner, sent} ->
        flunk("""
        #{label}: expected a 422 naming church_tax_rates, but the request raised
          #{inspect(inner.__struct__)}: #{inner |> Exception.message() |> String.slice(0, 220)}
        and the client received #{inspect(sent)}
        """)
    end
  end

  # User story (security review 2026-10-12, H30):
  # As the agent writing tax parameters through the API or the companion,
  # I want a malformed value answered with a 422 that names the field,
  # so that I can correct my request instead of meeting a bare 500.
  #
  # Acceptance criteria:
  # - A church tax rate list whose element is no decimal, a value that is no
  #   list, a null element and a null answer 422 with the field named, on
  #   the insert and the update path.
  # - The API error renderer never raises on a changeset error: it fills in
  #   only the placeholders a message carries, and renders any value safely.
  # - A valid list still writes.
  describe "an array cast error answers 422" do
    test "a percentage string element answers 422 naming the field",
         %{conn: conn} do
      conn |> put_parameters(["8%"]) |> assert_field_error(~s(church_tax_rates ["8%"]))
    end

    test "a comma-decimal element (\"0,08\") answers 422 naming the field", %{conn: conn} do
      conn |> put_parameters(["0,08"]) |> assert_field_error(~s(church_tax_rates ["0,08"]))
    end

    test "a value that is not a list answers 422 naming the field", %{conn: conn} do
      conn
      |> put_parameters("not-a-list")
      |> assert_field_error(~s(church_tax_rates "not-a-list"))
    end

    test "the update path (a seeded year) answers 422 naming the field", %{conn: conn} do
      # A seeded year exists, so the upsert takes the update path and the
      # same changeset.
      body =
        Jason.encode!(%{
          "parameters" =>
            @valid |> Map.put("tax_year", 2023) |> Map.put("church_tax_rates", ["abc"])
        })

      {outcome, _log} =
        ExUnit.CaptureLog.with_log(fn ->
          try do
            {:ok, conn |> api_conn() |> put("/api/v1/tax/parameters", body)}
          rescue
            error ->
              inner =
                case error do
                  %Plug.Conn.WrapperError{reason: reason} -> reason
                  other -> other
                end

              sent =
                receive do
                  {ref, {status, _h, b}} when is_reference(ref) -> {status, b}
                after
                  0 -> :nothing_sent
                end

              {:raised, inner, sent}
          end
        end)

      assert_field_error(outcome, ~s(update path, church_tax_rates ["abc"]))
    end

    test "JSON.errors/1 renders an {:array, :decimal} cast error instead of raising" do
      changeset =
        Parameters.changeset(%Parameters{}, Map.put(@valid, "church_tax_rates", ["abc"]))

      # Precondition (Ecto 3.14): the cast error carries the type tuple as an opt.
      assert {"is invalid", opts} = changeset.errors[:church_tax_rates]
      assert opts[:type] == {:array, :decimal}

      rendered =
        try do
          JSON.errors(changeset)
        rescue
          error ->
            flunk(
              "JSON.errors/1 raised #{inspect(error.__struct__)}: " <>
                (error |> Exception.message() |> String.slice(0, 200))
            )
        end

      assert rendered[:church_tax_rates] == ["is invalid"]
    end
  end

  describe "the renderer is total" do
    test "an Ecto.Enum cast error, a list of atoms and a placeholder the opts lack render as text" do
      types = %{
        kind: Ecto.ParameterizedType.init(Ecto.Enum, values: [:alpha, :beta]),
        tags: {:array, :string},
        level: :integer
      }

      changeset =
        {%{}, types}
        |> Ecto.Changeset.cast(%{"kind" => "gamma", "level" => "7"}, [:kind, :level])
        |> Ecto.Changeset.add_error(:tags, "must be one of %{allowed}",
          allowed: [:alpha, :beta],
          shape: {:tuple, :value}
        )
        |> Ecto.Changeset.add_error(:level, "is %{missing} here", other: %{"a" => 1})

      rendered = JSON.errors(changeset)

      assert rendered[:kind] == ["is invalid"]
      assert rendered[:tags] == ["must be one of alpha, beta"]
      assert rendered[:level] == ["is %{missing} here"]
    end
  end

  describe "a null answers 422" do
    test "a null element ([null]) answers 422 naming the field", %{conn: conn} do
      conn |> put_parameters([nil]) |> assert_field_error("church_tax_rates [null]")
    end

    test "a null value answers 422 naming the field", %{conn: conn} do
      conn |> put_parameters(nil) |> assert_field_error("church_tax_rates null")
    end
  end

  describe "control: a valid list still writes" do
    test "decimal strings are accepted", %{conn: conn} do
      assert {:ok, conn} = put_parameters(conn, ["0.08", "0.09"])
      assert %{"data" => %{"church_tax_rates" => ["0.08", "0.09"]}} = json_response(conn, 200)
    end
  end
end
