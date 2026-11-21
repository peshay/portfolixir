defmodule PortfolixirWeb.Browser.LaunchCheckTest do
  # Which browser the walks launch (Sprint 31 M2, the Sprint 30
  # retrospective's carry-forward 1). CI's browser job runs every walk in
  # the chromium-headless-shell of the Playwright release
  # test/browser/package-lock.json pins; a machine that launched a full
  # Chrome laid the shipped Inter out 3 px wider, and a walk passed there
  # that failed in CI. The launcher's choice is checked here through
  # `launch_check.js`, with no server and no database.
  #
  # Excluded from the test job (test/test_helper.exs): it needs Node, the
  # pinned Playwright and its headless shell, which CI's `browser` job
  # installs. Run it with
  #
  #     mix test test/browser --only browser
  use ExUnit.Case, async: true

  @moduletag :browser
  @moduletag timeout: 120_000

  @script Path.expand("launch_check.js", __DIR__)

  # User story (Sprint 31 M2):
  # As the owner who reads a green browser job instead of the pages,
  # I want every walk to run in the browser CI runs it in, unless a
  # machine names another one, and to say which one it ran in,
  # so that a walk green here is green in CI, and a run in another browser
  # says so.
  #
  # Acceptance criteria:
  # - Without PLAYWRIGHT_CHROMIUM_EXECUTABLE the launcher asks Playwright
  #   for the pinned release's chromium-headless-shell, headless.
  # - With it, the launcher launches that executable, headless, and no
  #   channel.
  # - The launcher logs one line naming what it launched and the browser's
  #   version, once however often a walk launches.
  test "the walks launch the pinned headless shell unless a machine names another browser" do
    {output, status} = System.cmd("node", [@script], stderr_to_stdout: true)
    assert status == 0, "the browser run failed:\n" <> output

    lines = String.split(output, "\n", trim: true)
    result = lines |> List.last() |> Jason.decode!()
    refute result["error"], "the browser run failed: #{result["error"]}"

    assert result["bare"]["options"] == %{
             "headless" => true,
             "channel" => "chromium-headless-shell"
           },
           "without a named browser the launcher does not ask for the headless shell: " <>
             inspect(result["bare"])

    assert result["bare"]["browser"] =~ ~r/^chromium-headless-shell of Playwright \d+\.\d+\.\d+$/

    assert result["named"]["options"] == %{
             "headless" => true,
             "executablePath" => "/opt/another/chrome"
           },
           "a named browser is not what the launcher launches: #{inspect(result["named"])}"

    assert result["named"]["browser"] =~ "PLAYWRIGHT_CHROMIUM_EXECUTABLE=/opt/another/chrome"

    [version | _] = result["versions"]
    assert length(result["versions"]) == 2

    logged = Enum.filter(lines, &String.starts_with?(&1, "launch.js: "))

    assert logged == ["launch.js: launched #{result["here"]["browser"]}, Chromium #{version}"],
           "the launcher did not say once what it launched:\n" <> output
  end
end
