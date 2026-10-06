defmodule Portfolixir.Invariants.RawJournalWritersTest do
  # #1042, review pass 1. `Portfolixir.Journal` writes `audit_journal`
  # through its schema, and two frozen migration seeds write it as plain SQL
  # naming the journal's columns at their own version (#1015, #1042). This
  # test reads lib/ for every raw insert into the journal, so a third one
  # fails here until someone decides it is a frozen migration seed too.
  use ExUnit.Case, async: true

  # `path => reason`.
  @raw_writers %{
    "lib/portfolixir/tax/builtin_seed.ex" =>
      "the statutory tax history, frozen to 20260725140000_seed_tax_parameters (#1015)",
    "lib/portfolixir/buckets/scope_seed.ex" =>
      "the portfolio scope seed and its rollback, frozen to " <>
        "20260712130000_seed_portfolio_scope_buckets (#1042)"
  }

  @raw_insert ~r/insert\s+into\s+"?audit_journal"?\b/i

  # User story:
  # As the maintainer of the audit journal,
  # I want every module that writes journal entries as raw SQL to be listed
  # by name with its reason,
  # so that no write bypasses `Portfolixir.Journal` unseen, and the only
  # ones that do are code an immutable migration calls at its own version.
  #
  # Acceptance criteria:
  # - Exactly the two frozen migration seeds insert into `audit_journal`
  #   with raw SQL; a new one fails, naming its file, and a listed one that
  #   no longer does fails as stale.
  # - The matcher sees the SQL in its usual shapes, so a clean tree cannot
  #   pass vacuously.
  test "only the two frozen migration seeds insert into the journal with raw SQL" do
    found =
      for path <- Path.wildcard("lib/**/*.ex"),
          File.read!(path) =~ @raw_insert,
          into: MapSet.new(),
          do: path

    assert MapSet.difference(found, MapSet.new(Map.keys(@raw_writers))) |> Enum.sort() == [],
           "a module inserts into audit_journal with raw SQL; route it through " <>
             "Portfolixir.Journal, or list it here if it is a frozen migration seed"

    assert MapSet.difference(MapSet.new(Map.keys(@raw_writers)), found) |> Enum.sort() == [],
           "a listed raw journal writer no longer writes the journal; remove it from the list"
  end

  test "the matcher sees a raw journal insert in its usual shapes" do
    for sql <- [
          "INSERT INTO audit_journal (actor_type) VALUES ($1)",
          "insert into audit_journal (actor_type) values ($1)",
          ~s|INSERT INTO "audit_journal" (actor_type) VALUES ($1)|,
          "INSERT INTO\n  audit_journal\n  (actor_type) VALUES ($1)"
        ] do
      assert sql =~ @raw_insert, sql
    end

    refute "INSERT INTO audit_journal_archive (id) VALUES ($1)" =~ @raw_insert
    refute "SELECT id FROM audit_journal" =~ @raw_insert
  end
end
