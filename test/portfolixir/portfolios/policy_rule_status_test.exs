defmodule Portfolixir.Portfolios.PolicyRuleStatusTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Portfolios.PolicyRuleStatus
  alias Portfolixir.Portfolios.PolicyRuleVersion

  @today ~D[2026-11-09]

  defp version(from, until \\ nil) do
    %PolicyRuleVersion{
      valid_from: Date.add(@today, from),
      valid_until: until && Date.add(@today, until)
    }
  end

  # User story (ADR-0059 §1, §2; ADR-0049 §4, §8):
  # As the agent deciding what to do with a stored rule,
  # I want the rule's status and the writes it accepts today named by one
  # module in the context, the same one its write guards consult,
  # so that I read "retire" or "delete" off the payload instead of learning
  # it from a 409, and the screen's buttons can never disagree with it.
  #
  # Acceptance criteria:
  # - The closed sets are named once: statuses in_force, scheduled, retired;
  #   actions add_version, rename, retire, delete.
  # - The status is derived from the versions relative to a date: in force
  #   when a version covers it, scheduled when none does but one starts
  #   later, retired otherwise; the version in force and the next version
  #   come from the same read.
  # - add_version and rename are always permitted; retire while a version
  #   is in force or a restart is scheduled (which it cancels); delete only
  #   while no version has ever been in force.
  # - A refused action names its reason: delete → in_force, retire →
  #   never_in_force or already_retired; a permitted one has none.
  # - The basis is stated once, as a sentence.
  describe "the closed sets" do
    test "are named once" do
      assert PolicyRuleStatus.statuses() == [:in_force, :scheduled, :retired]
      assert PolicyRuleStatus.actions() == [:add_version, :rename, :retire, :delete]
      assert PolicyRuleStatus.basis() =~ "never stored"
    end
  end

  describe "read/2" do
    test "a version covering the date is in force, with the next version named" do
      versions = [version(-20, -1), version(0), version(5)]

      assert %{status: :in_force, version_in_force: in_force, next_version: next} =
               PolicyRuleStatus.read(versions, @today)

      assert in_force.valid_from == @today
      assert next.valid_from == Date.add(@today, 5)
      assert PolicyRuleStatus.status(versions, @today) == :in_force
    end

    test "a version that starts later, with none in force, is scheduled" do
      assert %{status: :scheduled, version_in_force: nil, next_version: %{} = next} =
               PolicyRuleStatus.read([version(5)], @today)

      assert next.valid_from == Date.add(@today, 5)
    end

    test "every version ended is retired, and a day in the past reads its own standard" do
      versions = [version(-20, -1)]

      assert %{status: :retired, version_in_force: nil, next_version: nil} =
               PolicyRuleStatus.read(versions, @today)

      assert %{status: :in_force} = PolicyRuleStatus.read(versions, Date.add(@today, -10))
    end
  end

  describe "permits/2 and refusal/3" do
    test "a rule in force may be edited, renamed or retired, never deleted" do
      versions = [version(-20)]

      assert PolicyRuleStatus.permits(versions, @today) == [:add_version, :rename, :retire]
      assert PolicyRuleStatus.refusal(versions, @today, :delete) == :in_force
      assert PolicyRuleStatus.refusal(versions, @today, :retire) == nil
    end

    test "a rule that never started may be deleted, not retired" do
      versions = [version(5)]

      assert PolicyRuleStatus.permits(versions, @today) == [:add_version, :rename, :delete]
      assert PolicyRuleStatus.refusal(versions, @today, :retire) == :never_in_force
      assert PolicyRuleStatus.refusal(versions, @today, :delete) == nil
    end

    test "a retired rule may only be edited (taken up again) or renamed" do
      versions = [version(-20, -1)]

      assert PolicyRuleStatus.permits(versions, @today) == [:add_version, :rename]
      assert PolicyRuleStatus.refusal(versions, @today, :retire) == :already_retired
      assert PolicyRuleStatus.refusal(versions, @today, :delete) == :in_force
    end

    test "a retired rule scheduled to restart may be retired again, which cancels the restart" do
      versions = [version(-20, -1), version(5)]

      assert PolicyRuleStatus.status(versions, @today) == :scheduled
      assert PolicyRuleStatus.permits(versions, @today) == [:add_version, :rename, :retire]
      assert PolicyRuleStatus.refusal(versions, @today, :delete) == :in_force
    end

    test "a version that only started today is in force, so retire, not delete" do
      assert PolicyRuleStatus.permits([version(0)], @today) == [:add_version, :rename, :retire]
    end
  end
end
