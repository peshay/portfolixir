defmodule PortfolixirWeb.Browser.PrivacyLeakSettleTest do
  # The privacy walk's wait (the Sprint 28 closing act, browser job):
  # `settle/2` in privacy_leak.js waited at most 8 s for a page's busy marks
  # to go and then went on silently, so on CI's slower runner the walk read
  # Wealth's stacked chart before its bands had landed and left the page
  # while the bands' task was mid-query; the killed task took the test's
  # one shared database connection with it, and every later page answered
  # 500 (DBConnection.OwnershipError). The wait is checked here on pages
  # the browser draws itself, through `privacy_leak_settle.js`, with no
  # server and no database.
  #
  # Excluded from the test job (test/test_helper.exs): it needs Node, the
  # Playwright test/browser/package-lock.json pins and its Chromium, which
  # CI's `browser` job installs. Run it with
  #
  #     mix test test/browser --only browser
  use ExUnit.Case, async: true

  @moduletag :browser
  @moduletag timeout: 120_000

  @script Path.expand("privacy_leak_settle.js", __DIR__)

  # User story (the Sprint 28 closing act, browser job):
  # As the owner who trusts the privacy walk instead of reading every page,
  # I want the walk to read a page only once every load it started has
  # landed, and to fail on a page whose loads never land,
  # so that a green walk has read every figure and has killed no load
  # mid-query.
  #
  # Acceptance criteria:
  # - A page whose busy mark never goes is answered as connected and not
  #   settled, naming what it still waits for, once the wait's time is up.
  # - A load that starts a moment after the first one landed (as Wealth's
  #   remembered period asks for one once the page is connected) is waited
  #   for too: the wait returns only after it has landed.
  # - A page that never connects is answered at once as not connected and
  #   is not waited on for its loads.
  test "the walk's wait answers when every load has landed, and names a page that never settles" do
    {output, status} = System.cmd("node", [@script], stderr_to_stdout: true)
    assert status == 0, "the browser run failed:\n" <> output

    result = output |> String.split("\n", trim: true) |> List.last() |> Jason.decode!()
    refute result["error"], "the browser run failed: #{result["error"]}"

    stuck = result["stuck"]

    assert match?(%{"connected" => true, "settled" => false}, stuck["answer"]),
           "a page that never settles is not named: #{inspect(stuck)}"

    assert Enum.any?(stuck["answer"]["pending"], &(&1 =~ "stuck-load")),
           "the wait does not name what the page still waits for: #{inspect(stuck)}"

    second = result["second"]

    assert match?(%{"connected" => true, "settled" => true}, second["answer"]) and
             second["landed"] == true,
           "the wait returned before the second load landed: #{inspect(second)}"

    unconnected = result["unconnected"]

    assert match?(%{"connected" => false}, unconnected["answer"]) and unconnected["ms"] < 5000,
           "a page that never connects is waited on: #{inspect(unconnected)}"
  end
end
