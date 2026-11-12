defmodule Portfolixir.Invariants.BrowserWalksSettleTest do
  use ExUnit.Case, async: true

  # Sprint 29 M2 (Sprint 28 retrospective, carry-forward 1): a browser walk
  # that leaves a page while one of its loads runs stops the page's LiveView
  # and kills the load's task mid-query, which takes the test's one shared
  # database connection with it; every later request answers 500, or the
  # sandbox logs a dropped connection and the log noise rule fails the run.
  # The privacy walk failed CI's browser job for it in Sprint 28, then
  # `PeriodMemoryTest`, then the level switch walk (`9114ffb`): the wait
  # lived in each script that had learned it, and nothing made the next
  # walk use it. The wait is now one helper, `test/browser/settle.js`, and
  # this test reads every walk's source: each leaves a page only through
  # the helper.
  #
  # What leaves a page, and what the helper offers for it:
  # - `goto`, `reload`, `goBack`, `goForward` and `setContent` replace the
  #   page's document: `visit(page, url)` waits, then goes, and
  #   `draw(page, html)` waits, then writes (the helper offers no reload or
  #   history step; a walk that needs one adds it to the helper);
  # - `close` on a page, a context or the browser ends every page in it,
  #   the end of a walk included: `leave(target)` waits for each, then
  #   closes;
  # - a click or a tap on a link (an `a` element, a `data-phx-link`, an
  #   `href`, the sidebar's `#nav-…` links, the privacy switch) loads
  #   another page: `follow(page, () => page.click(…))` waits, then clicks.
  #
  # The check is lexical, so its limits are named: a click on a control
  # whose server answer navigates (a button that pushes a navigation) is
  # not told apart by its selector, nor is a link pressed with the
  # keyboard; a walk wraps those in `follow` by the same rule, and this
  # test cannot hold it. A patch inside one LiveView (a tab, a facet) leaves
  # no page and stops no load.
  #
  # Runs in the test job: it reads files and needs no browser.

  @dir "test/browser"

  # The helpers themselves: the launcher, and the wait every walk uses.
  @helpers ~w(launch.js settle.js)

  @leaving ~w(goto reload goBack goForward setContent close)

  # A selector that names a link to another page.
  @link ~r/(^|[\s>+~,(])a(?=[\[.#:\s]|$)|data-phx-link|\[href|#nav-|#privacy-mode/

  # The busy selector's parts: the helper's alone.
  @own_wait ~r/\.phx-loading|\.value-slot-pending/

  # Registered exceptions: %{file, rule, reason}, `rule` as `rule/1` names
  # it ({:direct, "close"}, :no_leave, ...). One that no longer matches a
  # violation fails as stale. None is needed today: even the helper's own
  # check (settle_check.js) draws its pages through `draw` and leaves them
  # through `leave`.
  @exceptions []

  # User story (Sprint 29 M2):
  # As the owner who trusts CI's browser job instead of reading every walk,
  # I want every browser walk to leave a page only once its loads have
  # landed, through one shared wait,
  # so that no walk kills a load mid-query and fails the job for a cause
  # found three times already.
  #
  # Acceptance criteria:
  # - Every walk script in test/browser/ requires `./settle`.
  # - No walk calls `goto`, `reload`, `goBack`, `goForward`, `setContent` or
  #   `close` itself; it calls the helper's `visit`, `draw` and `leave`.
  # - A walk that launches a browser leaves it through `leave`.
  # - A click or tap on a link runs inside the helper's `follow`.
  # - No walk carries a busy-marker wait of its own.
  # - Each exception is registered with its reason and is not stale.
  test "every walk leaves a page only through the settle helper" do
    walks = walk_files()
    assert walks != [], "no walk found in #{@dir}"

    found =
      for file <- walks,
          violation <- violations(File.read!(file)),
          do: {Path.basename(file), violation}

    {refused, stale} = judge(found, @exceptions)

    assert refused == [],
           "a walk leaves a page without the settle helper (test/browser/settle.js):\n" <>
             Enum.map_join(refused, "\n", &describe/1)

    assert stale == [], "a registered exception no longer matches: #{inspect(stale)}"

    assert Enum.all?(@exceptions, &(String.length(Map.get(&1, :reason, "")) > 20)),
           "an exception without its reason"
  end

  # The attack cases: the check refuses each way of leaving a page without
  # the helper, so a clean tree cannot pass vacuously.
  test "the check refuses a walk that navigates without the helper" do
    clean = """
    "use strict";
    const { launchChromium } = require("./launch");
    const { visit, leave, follow } = require("./settle");
    // page.goto(url) in a comment leaves nothing.
    (async () => {
      const browser = await launchChromium();
      const page = await browser.newPage();
      await visit(page, base + "/portfolio");
      await page.click("#detail-tab-chart");
      await follow(page, () => page.click("#nav-securities"));
      await leave(browser);
    })();
    """

    assert violations(clean) == []

    no_helper =
      String.replace(clean, ~s|const { visit, leave, follow } = require("./settle");\n|, "")

    assert :no_helper in violations(no_helper)

    goto =
      String.replace(
        clean,
        "await visit(page, base + \"/portfolio\");",
        "await page.goto(base + \"/portfolio\");"
      )

    assert {:direct, "goto", 8} in violations(goto)

    for call <- ["reload()", "goBack()", "goForward()", "setContent(\"<p></p>\")", "close()"] do
      source =
        String.replace(clean, "await page.click(\"#detail-tab-chart\");", "await page.#{call};")

      [name | _] = String.split(call, "(")
      assert {:direct, name} in Enum.map(violations(source), &rule/1), "#{call} is not refused"
    end

    closed = String.replace(clean, "await leave(browser);", "await browser.close();")
    assert {:direct, "close"} in Enum.map(violations(closed), &rule/1)
    assert :no_leave in violations(closed)

    for selector <-
          ~w(#nav-securities #privacy-mode a[href='/x'] a.nav-link) ++
            ["main a", "[data-phx-link='redirect']"] do
      source =
        String.replace(
          clean,
          "await follow(page, () => page.click(\"#nav-securities\"));",
          "await page.tap(\"#{selector}\");"
        )

      assert Enum.any?(violations(source), &match?({:unfollowed_link, _}, &1)),
             "a tap on #{selector} outside follow is not refused"
    end

    # A registered exception excuses its own violation only, and one that
    # matches nothing is stale.
    found = [{"a.js", {:direct, "goto", 3}}, {"b.js", :no_helper}]
    exception = %{file: "a.js", rule: {:direct, "goto"}, reason: "a reason"}
    stale = %{file: "c.js", rule: :no_leave, reason: "a reason"}
    assert judge(found, [exception, stale]) == {[{"b.js", :no_helper}], [stale]}

    own_wait =
      String.replace(
        clean,
        "// page.goto",
        "const BUSY = \"[aria-busy='true'], .phx-loading\";\n//"
      )

    assert :own_wait in violations(own_wait)
  end

  defp walk_files do
    "#{@dir}/*.js"
    |> Path.wildcard()
    |> Enum.reject(&(Path.basename(&1) in @helpers))
  end

  # Each way the source leaves a page without the helper.
  defp violations(source) do
    code = strip_comments(source)
    lines = String.split(code, "\n")

    helper = if code =~ ~r/require\(\s*["']\.\/settle["']\s*\)/, do: [], else: [:no_helper]

    direct =
      for {line, n} <- Enum.with_index(lines, 1),
          [_, call] <- Regex.scan(~r/\.(#{Enum.join(@leaving, "|")})\(/, line),
          do: {:direct, call, n}

    leave =
      if code =~ ~r/\blaunchChromium\(/ and not (code =~ ~r/\bleave\(/), do: [:no_leave], else: []

    links =
      for {line, n} <- Enum.with_index(lines, 1),
          line =~ ~r/\.(click|tap|dblclick)\(/,
          Enum.any?(string_literals(line), &(&1 =~ @link)),
          not (line =~ ~r/\bfollow\(/),
          do: {:unfollowed_link, n}

    own_wait = if code =~ @own_wait, do: [:own_wait], else: []

    helper ++ direct ++ leave ++ links ++ own_wait
  end

  defp rule({:direct, call, _line}), do: {:direct, call}
  defp rule(other), do: other

  # The violations no exception excuses, and the exceptions that excuse
  # none.
  defp judge(found, exceptions) do
    excuses? = fn ex, {file, violation} -> ex.file == file and ex.rule == rule(violation) end
    refused = Enum.reject(found, fn f -> Enum.any?(exceptions, &excuses?.(&1, f)) end)
    stale = Enum.reject(exceptions, fn ex -> Enum.any?(found, &excuses?.(ex, &1)) end)
    {refused, stale}
  end

  defp string_literals(line) do
    ~r/"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'|`((?:[^`\\]|\\.)*)`/
    |> Regex.scan(line, capture: :all_but_first)
    |> Enum.map(&Enum.join/1)
  end

  # Block comments and whole-line comments: a walk's prose names the calls
  # it explains.
  defp strip_comments(source) do
    source
    |> String.replace(~r{/\*.*?\*/}s, &String.replace(&1, ~r/[^\n]/, ""))
    |> String.replace(~r{^\s*//.*$}m, "")
  end

  defp describe({file, :no_helper}), do: "#{file}: does not require ./settle"

  defp describe({file, :no_leave}),
    do: "#{file}: launches a browser and never leaves it through leave()"

  defp describe({file, :own_wait}), do: "#{file}: carries a busy-marker wait of its own"

  defp describe({file, {:direct, call, line}}),
    do: "#{file}:#{line}: calls .#{call}( itself (use the helper's visit, draw or leave)"

  defp describe({file, {:unfollowed_link, line}}),
    do: "#{file}:#{line}: clicks or taps a link outside follow()"
end
