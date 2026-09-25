defmodule PortfolixirWeb.ApiV1FreeTextCapsTest do
  # E25 S6 (#891), G01: a research-log body and invalidation condition, an
  # event's note and a policy-rule version's note had no length bound, on
  # storage that is append-only or journaled whole on every change. Each now
  # has a code-point cap, in the changeset (a 422 naming the field) and in a
  # database CHECK behind it.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Input.Text
  alias Portfolixir.Knowledge
  alias Portfolixir.Repo

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{
      conn: conn,
      world: base_world(name: "Free text caps"),
      security: create_security!(name: "Coastal Ferry Lines", ticker: "CFL")
    }
  end

  # One code point short of and one past a cap, in a character that is one
  # code point but several bytes.
  defp text(count), do: String.duplicate("ö", count)

  defp writes(world, security, value_for) do
    [
      {"/api/v1/securities/#{security.id}/notes",
       %{
         "note" => %{
           "kind" => "evidence",
           "body" => value_for.(:body),
           "source_quality" => "primary",
           "as_of" => "2026-01-02"
         }
       }, "body"},
      {"/api/v1/securities/#{security.id}/notes",
       %{
         "note" => %{
           "kind" => "thesis",
           "body" => "Fleet renewal carries the margin.",
           "invalidation_condition" => value_for.(:note),
           "source_quality" => "primary",
           "as_of" => "2026-01-02"
         }
       }, "invalidation_condition"},
      {"/api/v1/securities/#{security.id}/events",
       %{
         "event" => %{
           "kind" => "earnings",
           "date" => "2026-11-20",
           "timing" => "estimated",
           "source_quality" => "awareness",
           "note" => value_for.(:note)
         }
       }, "note"},
      {"/api/v1/portfolios/#{world.portfolio.id}/policy_rules",
       %{
         "rule" => %{
           "name" => "Single-name cap",
           "version" => %{
             "subject_type" => "security",
             "security_id" => security.id,
             "measure" => "weight",
             "kind" => "cap",
             "threshold" => "10",
             "severity" => "hard",
             "note" => value_for.(:note)
           }
         }
       }, "note"}
    ]
  end

  defp field_errors(body, field) do
    errors = body["errors"]
    errors[field] || get_in(errors, ["version", field]) || []
  end

  # User story:
  # As the operator whose research log is never edited,
  # I want an entry body, an invalidation condition, an event note and a
  # rule-version note past their bound refused with the field named,
  # so that one oversized write cannot grow append-only storage without end.
  #
  # Acceptance criteria:
  # - A value one code point past its cap answers 422 naming the field and
  #   stores nothing; a value at the cap is stored.
  test "a free-text value past its cap answers 422 on every append-only writer",
       %{conn: conn, world: world, security: security} do
    over = fn
      :body -> text(Text.entry_body_max() + 1)
      :note -> text(Text.free_text_max() + 1)
    end

    at = fn
      :body -> text(Text.entry_body_max())
      :note -> text(Text.free_text_max())
    end

    for {path, body, field} <- writes(world, security, over) do
      response = conn |> post(path, body) |> json_response(422)

      assert [message] = field_errors(response, field), "#{path} #{field}: #{inspect(response)}"
      assert message =~ "at most"
    end

    assert Knowledge.list_notes(security.id) == []

    for {path, body, field} <- writes(world, security, at) do
      assert conn |> post(path, body) |> json_response(201), "#{path} #{field} at the cap"
    end
  end

  # Acceptance criteria:
  # - The database refuses an over-cap value on each of the four columns
  #   even from a writer that skips the changeset.
  test "the database refuses an over-cap value behind the changeset", %{security: security} do
    {:ok, event} =
      Portfolixir.Knowledge.Events.create_event(Portfolixir.Actor.owner_ui(), %{
        security_id: security.id,
        kind: "earnings",
        date: ~D[2026-11-20],
        timing: "estimated",
        source_quality: "awareness"
      })

    error =
      assert_raise Postgrex.Error, fn ->
        Repo.transaction(fn ->
          Repo.query!("SELECT set_config('portfolixir.journal_actor', 'owner_ui', true)")

          Repo.query!("UPDATE security_events SET note = repeat('x', $1) WHERE id = $2", [
            Text.free_text_max() + 1,
            event.id
          ])
        end)
      end

    assert error.postgres.code == :check_violation

    for {table, column} <- [
          {"security_notes", "body"},
          {"security_notes", "invalidation_condition"},
          {"security_events", "note"},
          {"policy_rule_versions", "note"}
        ] do
      %{rows: [[definition]]} =
        Repo.query!(
          """
          SELECT pg_get_constraintdef(c.oid)
          FROM pg_constraint c
          WHERE c.conrelid = $1::text::regclass AND c.conname = $2
          """,
          [table, "#{table}_#{column}_length_check"]
        )

      assert definition =~ "char_length(#{column})", "#{table}.#{column}: #{definition}"
    end
  end
end
