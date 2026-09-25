defmodule PortfolixirWeb.ApiV1TextBoundsTest do
  # E25 S4, G17 and G24 (#889): a name longer than its column, counted the way
  # the database counts it (code points), and text carrying a character the
  # database refuses passed the changesets and failed in the database with a
  # 500 instead of a field error. Every writer now meets one text rule
  # (`Portfolixir.Input.Text`).
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Repo

  # One grapheme, three code points: 100 of them are 300 code points, past a
  # varchar(255) column however short they look.
  @combining String.duplicate("é́", 100)
  @long String.duplicate("a", 256)
  @nul "Depot\u0000A"

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    world = base_world(name: "Text bounds")
    security = create_security!(name: "Helios Solar Systems SE", ticker: "HSS")

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    %{conn: conn, world: world, security: security, classification: classification}
  end

  defp writes(world, security, classification, value) do
    pid = world.portfolio.id

    [
      {:post, "/api/v1/portfolios",
       %{"portfolio" => %{"name" => value, "base_currency_code" => "EUR"}}, "name"},
      {:post, "/api/v1/cash_accounts",
       %{"cash_account" => %{"portfolio_id" => pid, "name" => value, "currency_code" => "EUR"}},
       "name"},
      {:post, "/api/v1/securities_accounts",
       %{
         "securities_account" => %{
           "portfolio_id" => pid,
           "cash_account_id" => world.cash.id,
           "name" => value
         }
       }, "name"},
      {:post, "/api/v1/securities", %{"security" => %{"name" => value, "currency_code" => "EUR"}},
       "name"},
      {:patch, "/api/v1/securities/#{security.id}", %{"security" => %{"wkn" => value}}, "wkn"},
      {:patch, "/api/v1/securities/#{security.id}", %{"security" => %{"exchange_code" => value}},
       "exchange_code"},
      {:patch, "/api/v1/securities/#{security.id}", %{"security" => %{"isin" => value}}, "isin"},
      {:post, "/api/v1/classifications", %{"classification" => %{"name" => value}}, "name"},
      {:post, "/api/v1/classifications/#{classification.id}/categories",
       %{"category" => %{"name" => value}}, "name"},
      {:post, "/api/v1/buckets", %{"bucket" => %{"name" => value, "dimension" => "purpose"}},
       "name"},
      {:post, "/api/v1/views", %{"view" => %{"name" => value}}, "name"},
      {:post, "/api/v1/snapshots", %{"name" => value, "as_of" => "2026-01-02"}, "name"},
      {:post, "/api/v1/portfolios/#{pid}/policy_rules",
       %{
         "rule" => %{
           "name" => value,
           "version" => %{
             "subject_type" => "security",
             "security_id" => security.id,
             "measure" => "weight",
             "kind" => "cap",
             "threshold" => "10",
             "severity" => "hard"
           }
         }
       }, "name"},
      {:post, "/api/v1/tax/profiles",
       %{
         "profile" => %{
           "holder" => value,
           "valid_from" => "2026-01-01",
           "assessment_type" => "single"
         }
       }, "holder"},
      {:post, "/api/v1/tax/statement_snapshots",
       %{
         "statement_snapshot" => %{
           "institution" => value,
           "holder" => "Owner",
           "tax_year" => 2025,
           "as_of" => "2025-12-31"
         }
       }, "institution"},
      {:put, "/api/v1/tax/allowance_orders",
       %{
         "allowance_order" => %{
           "holder" => value,
           "institution" => "Example Bank",
           "tax_year" => 2026,
           "amount_granted" => "1000"
         }
       }, "holder"}
    ]
  end

  # User story:
  # As the operator's agent naming a record over the API,
  # I want a name the database cannot store refused as a field error,
  # so that an over-long or garbled name costs me one round trip and never a
  # server error.
  #
  # Acceptance criteria:
  # - A name over its column's width, counted in code points, answers 422
  #   naming the field on every writer of a name, and stores nothing.
  # - A name carrying a NUL or another control character answers 422 naming
  #   the field.
  test "an over-long or control-character name answers 422 with a field error",
       %{conn: conn, world: world, security: security, classification: classification} do
    portfolios_before = Repo.aggregate(Portfolio, :count)

    for value <- [@long, @combining, @nul],
        {verb, path, body, field} <- writes(world, security, classification, value) do
      conn = Phoenix.ConnTest.dispatch(conn, @endpoint, verb, path, body)

      assert conn.status == 422,
             "#{verb} #{path} #{field} (#{String.length(value)} graphemes): #{conn.status}"

      assert Map.has_key?(Jason.decode!(conn.resp_body)["errors"], field),
             "#{verb} #{path}: #{conn.resp_body}"
    end

    assert Repo.aggregate(Portfolio, :count) == portfolios_before
    assert Catalog.get_security(security.id).name == "Helios Solar Systems SE"
  end

  # Acceptance criteria:
  # - Free text (a booking's notes, a research-log entry, an event's note)
  #   keeps its line breaks and tabs but refuses a NUL with a 422 naming the
  #   field.
  test "free text keeps line breaks and refuses a NUL",
       %{conn: conn, world: world, security: security} do
    deposit = fn notes ->
      %{
        "transaction" => %{
          "portfolio_id" => world.portfolio.id,
          "cash_account_id" => world.cash.id,
          "type" => "deposit",
          "date" => "2026-01-02",
          "gross_amount" => "100",
          "currency_code" => "EUR",
          "notes" => notes
        }
      }
    end

    assert conn
           |> post("/api/v1/transactions", deposit.("line one\nline two\ttab"))
           |> json_response(201)

    body =
      conn |> post("/api/v1/transactions", deposit.("broken\u0000note")) |> json_response(422)

    assert Map.has_key?(body["errors"], "notes")

    body =
      conn
      |> post("/api/v1/securities/#{security.id}/notes", %{
        "note" => %{
          "kind" => "evidence",
          "body" => "Order book\u0000grew.",
          "source_quality" => "primary",
          "source_url" => "https://example.com/report",
          "as_of" => "2026-01-02"
        }
      })
      |> json_response(422)

    assert Map.has_key?(body["errors"], "body")
  end

  # User story:
  # As the operator's agent keeping free-form attributes on a security,
  # I want an attribute the database cannot store refused as a field error,
  # so that a garbled key or value costs me one round trip and never a server
  # error.
  #
  # Acceptance criteria:
  # - An attributes map whose key or string value carries a NUL or another
  #   control character, at any depth, or whose key is longer than 255 code
  #   points, answers 422 on attributes on create and update, and stores
  #   nothing.
  # - A value keeps its tabs and line breaks.
  test "an attributes map carrying text the database refuses answers 422",
       %{conn: conn, security: security} do
    for attributes <- [
          %{"sector" => "Tech\u0000"},
          %{"a\u0000b" => "Tech"},
          %{"segments" => %{"nested" => ["ok", "bad\u0000"]}},
          %{"line\nbreak" => "Tech"},
          %{@long => "Tech"}
        ] do
      body =
        conn
        |> post("/api/v1/securities", %{
          "security" => %{
            "name" => "Garbled Attributes Co",
            "currency_code" => "EUR",
            "attributes" => attributes
          }
        })
        |> json_response(422)

      assert Map.has_key?(body["errors"], "attributes"), inspect(attributes)

      body =
        conn
        |> patch("/api/v1/securities/#{security.id}", %{
          "security" => %{"attributes" => attributes}
        })
        |> json_response(422)

      assert Map.has_key?(body["errors"], "attributes"), inspect(attributes)
    end

    refute Repo.get_by(Portfolixir.Catalog.Security, name: "Garbled Attributes Co")
    assert Catalog.get_security(security.id).attributes == %{}

    assert %{"data" => %{"attributes" => %{"summary" => "line one\nline two\ttab"}}} =
             conn
             |> patch("/api/v1/securities/#{security.id}", %{
               "security" => %{"attributes" => %{"summary" => "line one\nline two\ttab"}}
             })
             |> json_response(200)
  end

  # User story:
  # As the operator's agent recording a corporate action's ISIN change,
  # I want a new ISIN that is not twelve characters of the ISIN shape refused,
  # so that an identifier that can never resolve an import is not stored.
  #
  # Acceptance criteria:
  # - A new ISIN longer than twelve characters, or not of the shape two
  #   letters, nine letters or digits and a digit, answers 422 naming
  #   new_isin and changes nothing.
  # - An over-long alias note answers 422 naming note.
  test "the new ISIN of an ISIN change is length- and shape-checked", %{conn: conn} do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Kestrel Industrial Group NV",
        currency_code: "EUR",
        isin: "NL0000000016"
      })

    path = "/api/v1/securities/#{security.id}/isin-change"

    for new_isin <- [
          @long,
          "NL00000000261",
          "NL000000002",
          "NL000000002X",
          "1L0000000026",
          "NL00000\u000026"
        ] do
      body =
        conn |> post(path, %{"isin_change" => %{"new_isin" => new_isin}}) |> json_response(422)

      assert Map.has_key?(body["errors"], "new_isin"), inspect(new_isin)
    end

    body =
      conn
      |> post(path, %{"isin_change" => %{"new_isin" => "NL0000000024", "note" => @long}})
      |> json_response(422)

    assert Map.has_key?(body["errors"], "note")
    assert Catalog.get_security(security.id).isin == "NL0000000016"

    assert conn
           |> post(path, %{"isin_change" => %{"new_isin" => " nl0000000024 "}})
           |> json_response(200)
  end
end
