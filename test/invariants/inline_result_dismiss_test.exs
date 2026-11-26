defmodule Portfolixir.Invariants.InlineResultDismissTest do
  # Wealth's polish list #1366, line R-157 (Sprint 32 W5): the × on a
  # result note sends its dismiss event to the page that draws it
  # (`AppShell.inline_result/1`, `dismiss_event`, „dismiss_result“ by
  # default). A page without a clause for it lets the event fall to its
  # catch-all, and the × does nothing — as it did on Snapshots, the one of
  # nine hosts without one.
  use ExUnit.Case, async: true

  @root "lib/portfolixir_web"

  # User story (#1366, R-157):
  # As the operator closing a problem note,
  # I want its × to close it on every page that shows one,
  # so that no page keeps a note I dismissed.
  #
  # Acceptance criteria:
  # - Every file under lib/portfolixir_web/ that draws
  #   `<AppShell.inline_result` has a `handle_event` clause for each
  #   dismiss event its notes send (`dismiss_event`, else „dismiss_result“).
  # - The walk reaches all nine hosts (Buckets, Classifications, Imports,
  #   News, Accounts, Risk, Securities, Snapshots, Transactions).
  # - The check's own attack: a host drawing a note without the clause is
  #   named.
  test "every page that draws a result note answers its dismiss event" do
    hosts =
      for file <- Path.wildcard(Path.join(@root, "**/*.ex")),
          source = File.read!(file),
          events = dismiss_events(source),
          events != [],
          do: {Path.relative_to(file, @root), source, events}

    names = Enum.map(hosts, &elem(&1, 0))

    for host <-
          ~w(buckets_live classifications_live imports_live news_live portfolio_accounts_live
             risk_live securities_live snapshots_live transaction_management_live) do
      assert "live/#{host}.ex" in names, "the walk misses #{host}"
    end

    assert length(hosts) == 9, inspect(names)
    assert unanswered(hosts) == []
  end

  test "a host drawing a note without its clause is named" do
    source = """
    def render(assigns) do
      ~H\"\"\"
      <AppShell.inline_result id="x" result={@r} />
      <AppShell.inline_result id="y" result={@r} dismiss_event="dismiss_other" />
      \"\"\"
    end

    def handle_event("dismiss_other", _params, socket), do: {:noreply, socket}
    """

    assert unanswered([{"live/fake_live.ex", source, dismiss_events(source)}]) ==
             [{"live/fake_live.ex", "dismiss_result"}]
  end

  # The dismiss events a source's result notes send.
  defp dismiss_events(source) do
    ~r/<AppShell\.inline_result\b[^>]*?\/?>/s
    |> Regex.scan(source)
    |> Enum.map(fn [tag] ->
      case Regex.run(~r/dismiss_event="([^"]+)"/, tag) do
        [_, event] -> event
        nil -> "dismiss_result"
      end
    end)
    |> Enum.uniq()
  end

  defp unanswered(hosts) do
    for {file, source, events} <- hosts,
        event <- events,
        not String.contains?(source, ~s|def handle_event("#{event}"|),
        do: {file, event}
  end
end
