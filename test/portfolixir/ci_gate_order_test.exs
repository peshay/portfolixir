defmodule Portfolixir.CIGateOrderTest do
  # The CI workflow parsed and run through a model of GitHub Actions' status
  # rules: a step without a status function in its `if:` runs only while no
  # earlier step of its job failed (an implicit `success() &&`); `always()`
  # and `!cancelled()` run regardless; `failure()` runs only after a failure;
  # `continue-on-error: true` keeps the job green; a job runs only when every
  # job it `needs:` succeeded. Non-status operands (`steps.x.outputs.y ==
  # 'true'`, `github.event_name == ...`) are taken as true, the worst case for
  # the claim being tested.
  use ExUnit.Case, async: true

  defp workflow_path, do: ".github/workflows/ci.yml"

  # Red with nobody pushing: they read a live advisory or retirement feed.
  @live_feed_audits ["mix hex.audit", "mix deps.audit", "npm audit"]

  # Red only for something a change did.
  @deterministic_gates [
    "mix credo --strict",
    "mix sobelow --skip --exit",
    "mix dialyzer --format short",
    "npm test --prefix mcp-server",
    "npm run build --prefix mcp-server"
  ]

  @nothing_fails "\0 no step runs this \0"

  # The model is checked against this workflow's own `if: always()`,
  # `if: failure()` and `needs:` steps before it is trusted.
  describe "the model of GitHub Actions' status rules" do
    test "with every step green, every audit and every gate runs" do
      ran = workflow() |> simulate(@nothing_fails) |> ran_scripts()

      for command <- @live_feed_audits ++ @deterministic_gates do
        assert Enum.any?(ran, &String.contains?(&1, command)), "#{command} did not run"
      end
    end

    test "a failed step skips the later default steps but not `if: always()` / `if: failure()`" do
      # test job: "Run test suite with coverage" fails -> the always() upload
      # runs, the default Codecov upload after it does not.
      jobs = simulate(workflow(), "mix coveralls.json")
      test_job = jobs["test"]

      assert test_job.result == :failure
      assert "Upload test output artifact" in test_job.ran_names
      refute "Upload coverage to Codecov" in test_job.ran_names

      # compose-smoke: the stack fails to start -> the failure() and always()
      # steps run, the default probes after it do not.
      jobs = simulate(workflow(), "docker compose up --build -d")
      smoke = jobs["compose-smoke"]

      assert smoke.result == :failure
      assert "Print the stack's state and logs" in smoke.ran_names
      assert "Tear the stack down" in smoke.ran_names
      refute "The page answers" in smoke.ran_names
    end

    test "a job whose `needs:` failed is skipped" do
      jobs = simulate(workflow(), "pre-commit run --all-files")

      assert jobs["pre-commit"].result == :failure
      assert jobs["quality"].result == :skipped
      assert jobs["test"].result == :skipped
    end
  end

  describe "a red live-feed audit does not switch the deterministic gates off" do
    # User story (security review 2026-10-12, H63):
    # As the owner whose merge rests on green gates instead of a read of the code,
    # I want a new advisory or retirement in a live feed to turn one check red
    # while every deterministic gate keeps running,
    # so that Credo, Sobelow, Dialyzer and the companion's tests and build still
    # judge every change while the feed is red.
    #
    # Acceptance criteria:
    # - With any one live-feed audit (`mix hex.audit`, `mix deps.audit`,
    #   `npm audit`) red, every deterministic gate still runs.
    # - The red audit still fails the run: no `continue-on-error`.
    # - One red live-feed audit does not hide the other two.
    test "every deterministic gate still runs while a live-feed audit is red, and the audit stays blocking" do
      wf = workflow()

      scripts = all_scripts(wf)

      present =
        Enum.filter(@live_feed_audits, fn audit ->
          Enum.any?(scripts, &String.contains?(&1, audit))
        end)

      assert present == @live_feed_audits, "the workflow no longer runs every live-feed audit"

      outcome =
        for audit <- @live_feed_audits, into: %{} do
          jobs = simulate(wf, audit)
          ran = ran_scripts(jobs)

          skipped =
            Enum.reject(@deterministic_gates, fn gate ->
              Enum.any?(ran, &String.contains?(&1, gate))
            end)

          # The audit itself must stay a blocking gate: some job ends red.
          blocking? = Enum.any?(jobs, fn {_name, job} -> job.result == :failure end)

          {audit, %{skipped_gates: skipped, audit_still_blocking: blocking?}}
        end

      for {audit, %{audit_still_blocking: blocking?}} <- outcome do
        assert blocking?, "#{audit} no longer fails the run (continue-on-error is not a fix)"
      end

      skipped =
        for {audit, %{skipped_gates: [_ | _] = gates}} <- outcome, into: %{}, do: {audit, gates}

      assert skipped == %{},
             "a red live-feed audit skips deterministic gates (H63):\n" <>
               Enum.map_join(skipped, "\n", fn {audit, gates} ->
                 "  #{audit} red -> never run: #{Enum.join(gates, ", ")}"
               end)
    end

    test "one red live-feed audit does not hide the other live-feed audits" do
      wf = workflow()

      hidden =
        Enum.reduce(@live_feed_audits, %{}, fn audit, acc ->
          ran = wf |> simulate(audit) |> ran_scripts()

          missing =
            Enum.reject(@live_feed_audits -- [audit], fn other ->
              Enum.any?(ran, &String.contains?(&1, other))
            end)

          if missing == [], do: acc, else: Map.put(acc, audit, missing)
        end)

      assert hidden == %{},
             "a red live-feed audit hides the other audits (H63):\n" <>
               Enum.map_join(hidden, "\n", fn {audit, others} ->
                 "  #{audit} red -> never run: #{Enum.join(others, ", ")}"
               end)
    end
  end

  # --- the model --------------------------------------------------------------

  defp workflow, do: YamlElixir.read_from_file!(workflow_path())

  defp all_scripts(wf) do
    for {_name, job} <- wf["jobs"],
        step <- job["steps"] || [],
        is_binary(step["run"]),
        do: step["run"]
  end

  defp ran_scripts(jobs) do
    for {_name, job} <- jobs, {_step_name, script} <- job.ran, is_binary(script), do: script
  end

  # Every job of the workflow under GitHub Actions' status rules, with every
  # step green except those whose run script contains `failing`.
  defp simulate(wf, failing) do
    jobs = wf["jobs"]
    Enum.reduce(Map.keys(jobs), %{}, &run_job(&1, jobs, failing, &2))
  end

  defp run_job(name, jobs, failing, acc) do
    if Map.has_key?(acc, name) do
      acc
    else
      job = jobs[name]
      needs = List.wrap(job["needs"])
      acc = Enum.reduce(needs, acc, &run_job(&1, jobs, failing, &2))
      needs_failed? = not Enum.all?(needs, &(acc[&1].result == :success))

      if holds?(job["if"], needs_failed?) do
        {ran, failed?} = run_steps(job["steps"] || [], failing)
        result = if failed?, do: :failure, else: :success
        Map.put(acc, name, %{ran: ran, ran_names: Enum.map(ran, &elem(&1, 0)), result: result})
      else
        Map.put(acc, name, %{ran: [], ran_names: [], result: :skipped})
      end
    end
  end

  defp run_steps(steps, failing) do
    {ran, failed?} =
      Enum.reduce(steps, {[], false}, fn step, {ran, failed?} ->
        if holds?(step["if"], failed?) do
          script = step["run"]
          fails? = is_binary(script) and String.contains?(script, failing)
          continue? = step["continue-on-error"] in [true, "true"]
          {[{step["name"], script} | ran], failed? or (fails? and not continue?)}
        else
          {ran, failed?}
        end
      end)

    {Enum.reverse(ran), failed?}
  end

  # An `if:` without a status function is `success() && (...)`.
  defp holds?(nil, failed?), do: not failed?
  defp holds?(expr, failed?) when is_boolean(expr), do: expr and not failed?

  defp holds?(expr, failed?) do
    e = expr |> to_string() |> String.replace(["${{", "}}", " "], "")

    cond do
      String.contains?(e, "always()") -> true
      String.contains?(e, "!cancelled()") -> true
      String.contains?(e, "cancelled()") -> false
      String.contains?(e, "failure()") -> failed?
      true -> not failed?
    end
  end
end
