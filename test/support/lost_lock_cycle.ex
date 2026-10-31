defmodule Portfolixir.LostLockCycle do
  @moduledoc """
  The database's answer to a lost lock cycle (SQLSTATE 40P01), on demand, for
  the tests of what a writer answers then (#1214). A real cycle needs two
  connections, which the lock-order harness (`Portfolixir.LockRace`) races;
  inside the SQL sandbox, `install!/1` adds a trigger that aborts every
  update of a booking whose note becomes `marker` with 40P01, as PostgreSQL
  aborts the losing side of a cycle.

  The trigger is created inside the test's sandbox transaction and rolled
  back with it. Its DDL locks the `transactions` table until then, so a
  module that installs it runs with `async: false`.
  """

  alias Portfolixir.Repo

  @doc "Installs the trigger for `marker`, a note no other test writes."
  @spec install!(String.t()) :: :ok
  def install!(marker) when is_binary(marker) do
    Repo.query!("""
    CREATE FUNCTION test_lose_lock_cycle() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF NEW.notes = #{quote_literal(marker)} THEN
        RAISE EXCEPTION 'deadlock detected' USING ERRCODE = '40P01';
      END IF;
      RETURN NEW;
    END
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER test_lose_lock_cycle BEFORE UPDATE ON transactions
      FOR EACH ROW EXECUTE FUNCTION test_lose_lock_cycle()
    """)

    :ok
  end

  defp quote_literal(text), do: "'" <> String.replace(text, "'", "''") <> "'"
end
