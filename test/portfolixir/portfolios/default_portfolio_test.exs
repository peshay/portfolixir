defmodule Portfolixir.Portfolios.DefaultPortfolioTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios

  # User story (ADR-0024):
  # As a local portfolio maintainer,
  # I want depot and cash-account creation to bind to one deterministic
  # internal default portfolio without ever asking me,
  # so that grouping happens exclusively through buckets and views while the
  # compatibility record stays consistent.
  #
  # Acceptance criteria:
  # - With no portfolio on file, the default is created once, named "Default"
  #   with the EUR base currency, and journaled under the requesting actor.
  # - With portfolios on file, the default is the earliest record (stable id
  #   order) and no new portfolio is created.
  # - Repeated calls return the same record (deterministic, idempotent).
  test "resolves the default portfolio deterministically, creating it only when none exists" do
    assert Portfolios.count_portfolios() == 0

    default = Portfolios.default_portfolio(Actor.owner_ui())
    assert default.name == "Default"
    assert default.base_currency_code == "EUR"
    assert Portfolios.count_portfolios() == 1

    # Idempotent: a second call finds the same record.
    assert Portfolios.default_portfolio(Actor.owner_ui()).id == default.id
    assert Portfolios.count_portfolios() == 1

    # The internal create is journaled like any sanctioned portfolio write.
    assert [entry | _] =
             Journal.list_entries(
               resource_type: "portfolio",
               resource_id: to_string(default.id),
               operation: :create
             )

    assert entry.actor_type == :owner_ui
  end

  test "an existing installation keeps binding to its earliest portfolio" do
    {:ok, first} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Alpha",
        base_currency_code: "EUR"
      })

    {:ok, _second} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Beta",
        base_currency_code: "EUR"
      })

    assert Portfolios.default_portfolio(Actor.owner_ui()).id == first.id
    assert Portfolios.count_portfolios() == 2
  end

  # User story (ADR-0024 modification 1):
  # As a local portfolio maintainer using the API/MCP surface,
  # I want every portfolio record — however it was created — listed with its
  # origin and bindings,
  # so that an LLM-first product never carries an invisible writable resource.
  #
  # Acceptance criteria:
  # - Every portfolio row appears with name, creation date, source (derived
  #   from the audit journal's create entry) and the count of bound depots
  #   and cash accounts.
  # - A record without a journaled create (pre-ADR-0017 legacy) reports the
  #   :seeded source rather than being dropped.
  test "portfolio_admin_list surfaces every record with source and bindings" do
    {:ok, ui} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Mine", base_currency_code: "EUR"})

    {:ok, api} =
      Portfolios.create_portfolio(Actor.api_token_rw("mcp"), %{
        name: "Ghost",
        base_currency_code: "USD"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: ui.id,
        name: "Cash EUR",
        currency_code: "EUR"
      })

    {:ok, _depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: ui.id,
        cash_account_id: cash.id,
        name: "Depot"
      })

    rows = Portfolios.portfolio_admin_list()
    assert length(rows) == 2

    ui_row = Enum.find(rows, &(&1.id == ui.id))
    api_row = Enum.find(rows, &(&1.id == api.id))

    assert ui_row.name == "Mine"
    assert ui_row.source == :ui
    assert ui_row.depot_count == 1
    assert ui_row.cash_account_count == 1
    assert %NaiveDateTime{} = ui_row.inserted_at

    assert api_row.source == :api
    assert api_row.depot_count == 0
    assert api_row.cash_account_count == 0
  end

  test "portfolio_admin_list reports :seeded for system-job (migration/seed) creates" do
    {:ok, _portfolio} =
      Portfolios.create_portfolio(Actor.system_job("pp-import-seed"), %{
        name: "Seeded",
        base_currency_code: "EUR"
      })

    assert [%{source: :seeded}] = Portfolios.portfolio_admin_list()
  end
end
