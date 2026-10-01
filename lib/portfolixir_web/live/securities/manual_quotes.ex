defmodule PortfolixirWeb.Securities.ManualQuotes do
  @moduledoc """
  The Quotes tab's words about a security's manual quotes (T-9; Sprint 17 V2;
  board `ux-design-2026-10-01/03-quote-release`, pick G3-A).

  `note/1` is the data note above the quote table: how many manual quotes the
  **whole stored history** holds and from when to when (the table below shows
  only the chart's range), that a manual quote wins over the provider's until
  it is released, and "Release…" as its remedy (UX-DR17: the remedy is a child
  of the note). With no manual quote there is no note and no control: an
  all-clear is not a finding (A7).

  `release_message/2` is the result the tab reports after a release (A5), in
  the numbers of the write's answer, not of the dialog.

  Dates are `<time datetime>` elements, which `app.css` keeps whole inside a
  note, so a 390 px line never breaks an ISO date at its hyphen.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias PortfolixirWeb.AppShell

  # A placeholder no translation can carry: the translated sentence is split
  # on it before the dates go in.
  @marker "\u0000"

  attr(:manual, :map, required: true)

  @doc "The data note above the quote table, or nothing without a manual quote."
  def note(assigns) do
    ~H"""
    <AppShell.data_note :if={@manual.count > 0} severity={:note} data-role="manual-quotes-note">
      <.dated segments={count_sentence(@manual)} />
      <%= gettext(
        "A manual quote has precedence: the quote sync leaves it standing until it is released."
      ) %>
      <button
        type="button"
        class="link-button"
        phx-click="open_quote_release"
        data-role="release-manual-quotes"
      >
        <%= gettext("Release…") %>
      </button>
    </AppShell.data_note>
    """
  end

  attr(:segments, :list, required: true)

  defp dated(assigns) do
    ~H"""
    <%= for segment <- @segments do %><%= case segment do %><% {:date, date} -> %><time datetime={Date.to_iso8601(date)}><%= Date.to_iso8601(date) %></time><% text -> %><%= text %><% end %><% end %>
    """
  end

  defp count_sentence(%{count: 1, first: date, stored_count: 1}),
    do:
      segments(
        gettext(
          "One manual quote in the stored history, on %{date}; it is the only stored quote.",
          date: marker("date")
        ),
        date: date
      )

  defp count_sentence(%{count: 1, first: date}),
    do:
      segments(
        gettext("One manual quote in the stored history, on %{date}.", date: marker("date")),
        date: date
      )

  defp count_sentence(%{count: count, stored_count: count} = manual),
    do:
      segments(
        ngettext(
          "%{count} manual quote in the stored history, from %{first} to %{last}; every stored quote is manual.",
          "%{count} manual quotes in the stored history, from %{first} to %{last}; every stored quote is manual.",
          count,
          first: marker("first"),
          last: marker("last")
        ),
        first: manual.first,
        last: manual.last
      )

  defp count_sentence(manual),
    do:
      segments(
        ngettext(
          "%{count} manual quote in the stored history, from %{first} to %{last}.",
          "%{count} manual quotes in the stored history, from %{first} to %{last}.",
          manual.count,
          first: marker("first"),
          last: marker("last")
        ),
        first: manual.first,
        last: manual.last
      )

  @doc """
  The result of a release, as safe markup for `AppShell.inline_result/1`:
  how many manual quotes were released from when to when, and what follows —
  the next sync's close, or, without an adapter for the provider, no quote.
  """
  @spec release_message([Date.t()], boolean()) :: Phoenix.HTML.safe()
  def release_message([], _adapter?) do
    Phoenix.HTML.html_escape(
      gettext("No manual quote was left in the range; nothing was released.")
    )
  end

  def release_message(released, adapter?) do
    first = Enum.min(released, Date)
    last = Enum.max(released, Date)

    released_sentence =
      case length(released) do
        1 ->
          segments(gettext("One manual quote released, on %{date}.", date: marker("date")),
            date: first
          )

        count ->
          segments(
            ngettext(
              "%{count} manual quote released, from %{first} to %{last}.",
              "%{count} manual quotes released, from %{first} to %{last}.",
              count,
              first: marker("first"),
              last: marker("last")
            ),
            first: first,
            last: last
          )
      end

    follow = follow_sentence(length(released), adapter?)

    {:safe, [Enum.map(released_sentence, &safe_segment/1), " ", escape(follow)]}
  end

  # One day or several (closing act, γ n6); without a sync that can fetch the
  # security — no adapter for its provider, or none that can ask for it (γ
  # D7) — the days stay empty.
  defp follow_sentence(count, true) do
    ngettext(
      "The next quote sync stores the provider's close for this day.",
      "The next quote sync stores the provider's close for these days.",
      count
    )
  end

  defp follow_sentence(count, false) do
    ngettext(
      "The quote sync fetches no quotes for this security: this day stays without a quote.",
      "The quote sync fetches no quotes for this security: these days stay without a quote.",
      count
    )
  end

  defp safe_segment({:date, date}) do
    iso = Date.to_iso8601(date)
    [~s(<time datetime="), iso, ~s(">), iso, "</time>"]
  end

  defp safe_segment(text), do: escape(text)

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp marker(key), do: @marker <> key <> @marker

  # The translated sentence split on its date placeholders: text stays text,
  # each placeholder becomes {:date, date}.
  defp segments(text, dates) do
    ~r/\x{0}(date|first|last)\x{0}/u
    |> Regex.split(text, include_captures: true, trim: true)
    |> Enum.map(fn
      @marker <> rest ->
        {:date, Keyword.fetch!(dates, key_atom(String.trim_trailing(rest, @marker)))}

      text ->
        text
    end)
  end

  defp key_atom("date"), do: :date
  defp key_atom("first"), do: :first
  defp key_atom("last"), do: :last
end
