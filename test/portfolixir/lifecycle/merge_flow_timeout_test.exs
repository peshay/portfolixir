defmodule Portfolixir.Lifecycle.MergeFlowTimeoutTest do
  # The closing act, EH-2: a merge writes one journal entry per moved row in
  # one transaction, and DBConnection's default 15 s checkout capped it at a
  # few thousand bookings — an account or security with more could not be
  # merged at all (the API answered 500, the dialog crashed). Measured on
  # PostgreSQL 18: 8,000 deposits raised at 15 s before, and applied in about
  # 19 s with the timeout. A test that waits 15 s is not one to run on every
  # change, so this pins that the merge's transaction carries the timeout.
  use ExUnit.Case, async: true

  alias Portfolixir.Imports.Applier
  alias Portfolixir.Lifecycle.MergeFlow

  defmodule RecordingRepo do
    @moduledoc false
    def transaction(fun, opts) do
      send(self(), {:transaction_opts, opts})
      {:ok, fun.()}
    end
  end

  # User story:
  # As the operator merging an account with years of bookings,
  # I want the merge to run to its end instead of failing at 15 seconds,
  # so that no account is too large to merge.
  #
  # Acceptance criteria:
  # - The merge's transaction is opened with a timeout of at least ten
  #   minutes, and so are the import's apply and its dry run.
  test "a merge's transaction, and an import's, outlive the 15 s default" do
    assert {:ok, :done} = MergeFlow.transaction(fn -> :done end, RecordingRepo)
    assert_received {:transaction_opts, opts}
    assert Keyword.fetch!(opts, :timeout) == MergeFlow.transaction_timeout()
    assert MergeFlow.transaction_timeout() >= :timer.minutes(10)
    assert Applier.transaction_timeout() >= :timer.minutes(10)
  end
end
