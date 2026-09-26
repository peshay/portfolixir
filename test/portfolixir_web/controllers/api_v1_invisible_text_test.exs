defmodule PortfolixirWeb.ApiV1InvisibleTextTest do
  # E25 S7, G20: text an agent reads — research-log bodies and invalidation
  # conditions, event and rule-version notes, names — is refused over the API
  # when it carries a character the operator cannot see, with a field error
  # naming the character. The shared rule is Portfolixir.Input.Text's.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Knowledge

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{
      conn: conn,
      world: base_world(name: "Invisible text"),
      security: create_security!(name: "Coastal Ferry Lines", ticker: "CFL")
    }
  end

  defp c(code_point), do: <<code_point::utf8>>

  defp writes(world, security, hidden) do
    [
      {:post, "/api/v1/securities/#{security.id}/notes",
       %{
         "note" => %{
           "kind" => "evidence",
           "body" => "Fleet renewal on plan." <> hidden,
           "source_quality" => "primary",
           "as_of" => "2026-01-02"
         }
       }, "body"},
      {:post, "/api/v1/securities/#{security.id}/notes",
       %{
         "note" => %{
           "kind" => "thesis",
           "body" => "Fleet renewal carries the margin.",
           "invalidation_condition" => "Margin below 8 %" <> hidden,
           "source_quality" => "primary",
           "as_of" => "2026-01-02"
         }
       }, "invalidation_condition"},
      {:post, "/api/v1/securities/#{security.id}/events",
       %{
         "event" => %{
           "kind" => "earnings",
           "date" => "2026-11-20",
           "timing" => "estimated",
           "source_quality" => "awareness",
           "note" => "Q3 call" <> hidden
         }
       }, "note"},
      {:post, "/api/v1/portfolios/#{world.portfolio.id}/policy_rules",
       %{
         "rule" => %{
           "name" => "Single-name cap" <> hidden,
           "version" => %{
             "subject_type" => "cash",
             "measure" => "weight",
             "kind" => "floor",
             "threshold" => "5",
             "severity" => "warn"
           }
         }
       }, "name"},
      {:post, "/api/v1/portfolios/#{world.portfolio.id}/policy_rules",
       %{
         "rule" => %{
           "name" => "Cash floor",
           "version" => %{
             "subject_type" => "cash",
             "measure" => "weight",
             "kind" => "floor",
             "threshold" => "5",
             "severity" => "warn",
             "note" => "the operator's floor" <> hidden
           }
         }
       }, "note"},
      {:patch, "/api/v1/cash_accounts/#{world.cash.id}",
       %{"cash_account" => %{"name" => "Giro" <> hidden}}, "name"}
    ]
  end

  defp field_errors(body, field) do
    errors = body["errors"]
    errors[field] || get_in(errors, ["version", field]) || []
  end

  # User story (E25 S7, G20):
  # As an operator whose agent reads what is stored,
  # I want a write that carries a character I cannot see refused over the API
  # and MCP, naming the field and the character,
  # so that no hidden instruction lands in a record I review on screen.
  #
  # Acceptance criteria:
  # - A research-log body, an invalidation condition, an event note, a rule's
  #   name, a rule version's note and an account's name carrying a zero-width
  #   space, a bidirectional override or a tag character answer 422 naming
  #   the field and the code point, and store nothing.
  # - A security's name keeps losing its format characters as it is stored
  #   (E25 S5, G23) instead of being refused.
  test "a write carrying an invisible character answers 422 naming the field and the character",
       %{conn: conn, world: world, security: security} do
    for {hidden, named} <- [{c(0x200B), "U+200B"}, {c(0x202E), "U+202E"}, {c(0xE0041), "U+E0041"}],
        {method, path, body, field} <- writes(world, security, hidden) do
      response =
        conn
        |> dispatch(PortfolixirWeb.Endpoint, method, path, Jason.encode!(body))
        |> json_response(422)

      assert [message] = field_errors(response, field), "#{path} #{field}: #{inspect(response)}"
      assert message =~ "invisible characters", "#{path} #{field}"
      assert message =~ named, "#{path} #{field}"
    end

    assert Knowledge.list_notes(security.id) == []

    %{"data" => created} =
      conn
      |> post(
        "/api/v1/securities",
        Jason.encode!(%{
          security: %{name: "Harbour" <> c(0x200B) <> " Cranes", currency_code: "EUR"}
        })
      )
      |> json_response(201)

    assert created["name"] == "Harbour Cranes"
  end
end
