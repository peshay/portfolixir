defmodule PortfolixirWeb.Api.V1.TaxControllerTest do
  use PortfolixirWeb.ConnCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Tax

  # User story (2026-07-25, ADR-0031, story 19.5):
  # As the operating LLM agent,
  # I want the recorded snapshots and the derived trim budget over the API,
  # so that I can size a trim without scraping PDFs.
  #
  # Acceptance criteria:
  # - Every financial decimal serialises as a string.
  # - The payload carries allowance_remaining, tax_free_trim_budget, the as_of
  #   basis and the consistency findings.
  # - Create/update/delete reach full parity for all four resources.
  # - Synthetic fixtures only; no network calls.

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp get_json(conn, path), do: conn |> api_conn() |> get(path)
  defp post_json(conn, path, body), do: conn |> api_conn() |> post(path, Jason.encode!(body))
  defp put_json(conn, path, body), do: conn |> api_conn() |> put(path, Jason.encode!(body))
  defp patch_json(conn, path, body), do: conn |> api_conn() |> patch(path, Jason.encode!(body))
  defp delete_json(conn, path), do: conn |> api_conn() |> delete(path)

  defp snapshot_params(overrides \\ %{}) do
    Map.merge(
      %{
        "institution" => "Example Bank",
        "holder" => "Owner",
        "tax_year" => 2025,
        "as_of" => "2025-12-31",
        "taxable_income" => "12000.00",
        "allowance_granted" => "1000.00",
        "allowance_used" => "1000.00",
        "loss_pot_equities" => "2500.00",
        "capital_gains_tax_withheld" => "2550.00",
        "solidarity_surcharge_withheld" => "140.25",
        "withholding_tax_credited" => "200.00"
      },
      overrides
    )
  end

  test "the seeded statutory parameters are readable, with rates as strings", %{conn: conn} do
    body = get_json(conn, "/api/v1/tax/parameters?jurisdiction=DE") |> json_response(200)

    year_2023 = Enum.find(body["data"], &(&1["tax_year"] == 2023))
    assert year_2023["saver_allowance_single"] == "1000"
    assert year_2023["capital_gains_tax_rate"] == "0.25"
    assert year_2023["built_in"] == true

    year_2022 = Enum.find(body["data"], &(&1["tax_year"] == 2022))
    assert year_2022["saver_allowance_single"] == "801"
  end

  test "parameters can be upserted", %{conn: conn} do
    params = %{
      "parameters" => %{
        "jurisdiction" => "DE",
        "tax_year" => 2027,
        "capital_gains_tax_rate" => "0.25",
        "solidarity_surcharge_rate" => "0.055",
        "saver_allowance_single" => "1100.00",
        "saver_allowance_joint" => "2200.00"
      }
    }

    body = conn |> put_json("/api/v1/tax/parameters", params) |> json_response(200)
    assert body["data"]["saver_allowance_single"] == "1100"
    assert body["data"]["built_in"] == false
  end

  test "an invalid rate is a 422 naming the field", %{conn: conn} do
    params = %{
      "parameters" => %{
        "jurisdiction" => "DE",
        "tax_year" => 2027,
        "capital_gains_tax_rate" => "25",
        "solidarity_surcharge_rate" => "0.055",
        "saver_allowance_single" => "1100.00",
        "saver_allowance_joint" => "2200.00"
      }
    }

    body = conn |> put_json("/api/v1/tax/parameters", params) |> json_response(422)
    assert body["errors"]["capital_gains_tax_rate"]
  end

  test "profiles reach create, list, update and delete parity", %{conn: conn} do
    created =
      conn
      |> post_json("/api/v1/tax/profiles", %{
        "profile" => %{"holder" => "Owner", "valid_from" => "2024-01-01"}
      })
      |> json_response(201)

    assert created["data"]["church_tax_liable"] == false
    assert created["data"]["church_tax_rate"] == "0"
    id = created["data"]["id"]

    listed = get_json(conn, "/api/v1/tax/profiles?holder=Owner") |> json_response(200)
    assert Enum.map(listed["data"], & &1["id"]) == [id]

    updated =
      conn
      |> patch_json("/api/v1/tax/profiles/#{id}", %{
        "profile" => %{"church_tax_liable" => true, "church_tax_rate" => "0.09"}
      })
      |> json_response(200)

    assert updated["data"]["church_tax_rate"] == "0.09"

    assert conn |> delete_json("/api/v1/tax/profiles/#{id}") |> json_response(200)

    assert get_json(conn, "/api/v1/tax/profiles?holder=Owner") |> json_response(200) == %{
             "data" => []
           }
  end

  test "listing profiles without a holder is a 422, not an unscoped dump", %{conn: conn} do
    body = get_json(conn, "/api/v1/tax/profiles") |> json_response(422)
    assert body["errors"]["holder"]
  end

  test "allowance orders reach put, list and delete parity", %{conn: conn} do
    created =
      conn
      |> put_json("/api/v1/tax/allowance_orders", %{
        "allowance_order" => %{
          "holder" => "Owner",
          "institution" => "Example Bank",
          "tax_year" => 2025,
          "amount_granted" => "1000.00"
        }
      })
      |> json_response(200)

    assert created["data"]["amount_granted"] == "1000"
    id = created["data"]["id"]

    listed =
      conn
      |> get_json("/api/v1/tax/allowance_orders?holder=Owner&tax_year=2025")
      |> json_response(200)

    assert Enum.map(listed["data"], & &1["id"]) == [id]

    assert conn |> delete_json("/api/v1/tax/allowance_orders/#{id}") |> json_response(200)
    assert get_json(conn, "/api/v1/tax/allowance_orders") |> json_response(200) == %{"data" => []}
  end

  test "a snapshot round-trips with its derived figures and as-of basis", %{conn: conn} do
    created =
      conn
      |> post_json("/api/v1/tax/statement_snapshots", %{"statement_snapshot" => snapshot_params()})
      |> json_response(201)

    data = created["data"]
    assert data["as_of"] == "2025-12-31"
    assert data["loss_pot_equities"] == "2500"
    assert data["allowance_remaining"] == "0"
    assert data["tax_free_trim_budget"] == "2500"
    assert data["expected_capital_gains_tax"] == "2550"
    assert data["findings"] == []
    assert is_boolean(data["stale"])

    # Every money value is a string, never a JSON number.
    for key <- ~w(taxable_income allowance_granted allowance_used loss_pot_equities
                  loss_pot_other loss_carryforward_prior_years withholding_tax_pot
                  withholding_tax_credited capital_gains_tax_withheld
                  solidarity_surcharge_withheld church_tax_withheld church_tax_rate) do
      assert is_binary(data[key]), "#{key} must serialize as a string"
    end

    id = data["id"]
    assert get_json(conn, "/api/v1/tax/statement_snapshots/#{id}") |> json_response(200)

    updated =
      conn
      |> patch_json("/api/v1/tax/statement_snapshots/#{id}", %{
        "statement_snapshot" => %{"note" => "page 4"}
      })
      |> json_response(200)

    assert updated["data"]["note"] == "page 4"

    assert conn |> delete_json("/api/v1/tax/statement_snapshots/#{id}") |> json_response(200)
    assert get_json(conn, "/api/v1/tax/statement_snapshots/#{id}") |> json_response(404)
  end

  test "a mis-transcribed figure comes back as an advisory finding, not a rejection", %{
    conn: conn
  } do
    body =
      conn
      |> post_json("/api/v1/tax/statement_snapshots", %{
        "statement_snapshot" =>
          snapshot_params(%{
            "capital_gains_tax_withheld" => "5250.00",
            "solidarity_surcharge_withheld" => "288.75"
          })
      })
      |> json_response(201)

    assert [finding] = body["data"]["findings"]
    assert finding["code"] == "c3"
    assert finding["severity"] == "advisory"
    assert finding["recorded"] == "5250"
    assert finding["expected"] == "2550"
    assert finding["gap"] == "2700"
    refute Map.has_key?(finding, "correction")
  end

  test "a magnitude violation is a 422 naming the convention", %{conn: conn} do
    body =
      conn
      |> post_json("/api/v1/tax/statement_snapshots", %{
        "statement_snapshot" => snapshot_params(%{"loss_pot_equities" => "-2500.00"})
      })
      |> json_response(422)

    assert [message] = body["errors"]["loss_pot_equities"]
    assert message =~ "magnitude"
  end

  test "the trim budget rolls up per holder and states its coverage", %{conn: conn} do
    {:ok, _} =
      Tax.create_snapshot(
        Actor.owner_ui(),
        %{
          institution: "Bank A",
          holder: "Owner",
          tax_year: 2025,
          as_of: ~D[2025-12-31],
          allowance_granted: Decimal.new("1000.00"),
          allowance_used: Decimal.new("400.00"),
          loss_pot_equities: Decimal.new("2500.00")
        },
        today: ~D[2026-01-15]
      )

    {:ok, _} =
      Tax.put_allowance_order(Actor.owner_ui(), %{
        holder: "Owner",
        institution: "Bank B",
        tax_year: 2025,
        amount_granted: Decimal.new("500.00")
      })

    body =
      get_json(conn, "/api/v1/tax/trim_budget?holder=Owner&tax_year=2025") |> json_response(200)

    assert body["data"]["tax_free_trim_budget"] == "3100"
    assert body["data"]["as_of"] == "2025-12-31"
    assert body["data"]["institutions"] == ["Bank A"]
    assert body["data"]["complete"] == false
    assert body["data"]["missing_institutions"] == ["Bank B"]
  end

  test "the trim budget requires a holder and a tax year", %{conn: conn} do
    assert get_json(conn, "/api/v1/tax/trim_budget") |> json_response(422)
    assert get_json(conn, "/api/v1/tax/trim_budget?holder=Owner") |> json_response(422)
  end

  test "the tax routes require a bearer token" do
    assert build_conn() |> get("/api/v1/tax/parameters") |> json_response(401)
  end
end
