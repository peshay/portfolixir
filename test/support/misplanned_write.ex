defmodule Portfolixir.MisplannedWrite do
  @moduledoc """
  A write that lands other than planned, for the tests of a merge's identity
  check (ADR-0050 §7 step 6 and §9, §16 invariants 9 and 10).

  Nothing in a correct merge makes that check fail, so the tests install a
  trigger on `transactions` that adds one to `figure` on every update that
  changes `column` — the row a merge re-points. The trigger and its function
  are created inside the test's own sandbox transaction and rolled back with
  it. Creating a trigger locks `transactions` against every concurrent
  writer until the test ends, so a test that installs one runs with
  `async: false`.
  """

  alias Portfolixir.Repo

  @columns ~w(cash_account_id securities_account_id security_id)
  @figures ~w(gross_amount quantity)

  @doc "Installs the trigger for the rest of the test's transaction."
  @spec install!(String.t(), String.t()) :: :ok
  def install!(column, figure), do: install!([{column, figure}])

  @doc """
  Installs one trigger for every `{column, figure}` rule, for a test that
  merges more than one kind.
  """
  @spec install!([{String.t(), String.t()}]) :: :ok
  def install!(rules) when is_list(rules) and rules != [] do
    body = Enum.map_join(rules, "\n", &rule_sql/1)

    Repo.query!("""
    CREATE FUNCTION synthetic_misplanned_write() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
    #{body}
      RETURN NEW;
    END
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER synthetic_misplanned_write BEFORE UPDATE ON transactions
    FOR EACH ROW EXECUTE FUNCTION synthetic_misplanned_write()
    """)

    :ok
  end

  defp rule_sql({column, figure}) when column in @columns and figure in @figures do
    """
      IF NEW.#{column} IS DISTINCT FROM OLD.#{column} THEN
        NEW.#{figure} := NEW.#{figure} + 1;
      END IF;
    """
  end
end
