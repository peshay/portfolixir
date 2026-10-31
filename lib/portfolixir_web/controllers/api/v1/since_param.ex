defmodule PortfolixirWeb.Api.V1.SinceParam do
  @moduledoc """
  `?since=` delta reads (FR-38, issue #666), pull-only by design.

  Parses the `since` parameter into the naive-UTC cut the timestamp columns
  compare against. Accepted forms: an ISO8601 datetime with offset
  (converted to UTC), a naive ISO8601 datetime (taken as UTC), or a plain
  ISO date (start of that day, UTC). Anything else is a validation error.

  The delta covers creates and updates (`updated_at` strictly after the
  cut). Deletions are not represented — a caller that must detect deletions
  performs a full read. Push delivery stays gated (B3.7); this module is
  deliberately the whole of FR-38's change-propagation surface.

  **The family (#830, Sprint 14 D-5).** `since` is a *row-delta* parameter and
  fits only reads whose answer is a collection of rows with a change stamp:
  securities, transactions, a security's research log (by `inserted_at` — the
  log is append-only), a security's events, and the category and position
  target reads (a row counts as changed when it or its plan did). Two shapes
  deliberately do not carry it: derived projections (valuation, allocation,
  performance, risk — no rows, so "changed since" is a basis-version question
  this module cannot answer), and the time-derived queues (`/notes/unreviewed`,
  `/notes/expiring`, `/notes/uncorroborated`, `/events/upcoming`,
  `/events/stale`, `/events/unconfirmed`), whose membership changes because
  time passes with no row changing — a cut there would drop exactly the rows
  a poller needs. Those reads ignore `since` like any undefined parameter.

  **A capped read is a page (K17).** The delta reads bounded by `limit`
  (transactions, securities, a security's research log and events, a
  portfolio's policy rules) parse `since` with `parse_page/1` and answer
  with `put_page_envelope/4`: rows oldest change first, `has_more` true when
  more rows matched than the page holds (the read fetches one row past the
  limit), and then an `as_of` that is a cursor at the page's last row,
  `<ISO8601 instant>~<id>`, which the next read of the same kind takes as its
  `since`. A cursor belongs to the read that answered it: it carries that
  read's row id, so another read would skip its own rows on the cursor's
  second; and a delta read pages by `as_of` alone, never by `offset`.
  Rows sharing one stamp (an import writes thousands within a second) are
  told apart by the id, so a page boundary inside them skips none and
  repeats none. A cursor never lies past the read's own bound (see
  `Portfolixir.DeltaCursor`): when the page's last row is newer than that
  bound, `as_of` is the bound (no `~<id>`) with `has_more` still true, and
  the note tells the agent to poll again later: until the write holding the
  bound ends, a read at once returns the same page.
  """

  alias Portfolixir.DeltaCursor
  alias PortfolixirWeb.Api.V1.IdParam

  @delta_note "Rows created or updated strictly after `since` (UTC), by " <>
                "their updated_at. Deletions are not represented - a caller " <>
                "that must detect deletions performs a full read. Use this " <>
                "response's `as_of` as the next `since`: it lies no later " <>
                "than the start of the oldest write still in flight, so the " <>
                "next read may re-deliver a row but never skips one."

  @page_rule "Use this response's `as_of` as the next `since`. When `has_more` is true the " <>
               "page held `limit` rows and more are waiting: an `as_of` ending in `~<id>` is a " <>
               "cursor at the page's last row, so read again with it at once; an `as_of` " <>
               "without `~<id>` means the rest waits behind a write still in flight, so poll " <>
               "again later, not at once. `as_of` never lies later than the start of the " <>
               "oldest write still in flight, so the next read may re-deliver a row but never " <>
               "skips one. A cursor belongs to the read that answered it: pass it to no other " <>
               "read. With `since`, page by `as_of`, never by `offset`."

  @paged_delta_note "Rows created or updated strictly after `since` (UTC), by their " <>
                      "updated_at, oldest change first. Deletions are not represented - a " <>
                      "caller that must detect deletions performs a full read. " <> @page_rule

  @doc "The paging sentence every paged delta note ends with (K17)."
  @spec page_rule() :: String.t()
  def page_rule, do: @page_rule

  @doc "Parses `since`; `{:ok, nil}` when absent, `{:error, :since}` when invalid."
  def parse(params) do
    case Map.get(params, "since") do
      nil -> {:ok, nil}
      "" -> {:ok, nil}
      value when is_binary(value) -> parse_value(value)
      _other -> {:error, :since}
    end
  end

  @doc """
  As `parse/1`, for a paged read (K17): `since` may also be the cursor a
  full page answered as `as_of`, `<ISO8601 instant>~<id>`. The parsed cut
  carries `after_id` (nil for a plain instant or date).
  """
  def parse_page(params) do
    case Map.get(params, "since") do
      value when is_binary(value) and value != "" -> parse_cursor(String.split(value, "~"))
      _absent_or_other -> parse(params)
    end
  end

  defp parse_cursor([instant]), do: with_after_id(parse_value(instant), nil)

  defp parse_cursor([instant, id]) when instant != "" do
    case IdParam.parse(id) do
      {:ok, after_id} -> with_after_id(parse_value(instant), after_id)
      :error -> {:error, :since}
    end
  end

  defp parse_cursor(_parts), do: {:error, :since}

  defp with_after_id({:ok, since}, after_id), do: {:ok, Map.put(since, :after_id, after_id)}
  defp with_after_id(error, _after_id), do: error

  @doc "The `Portfolixir.DeltaCursor` cursor of a parsed `parse_page/1` cut."
  def cursor(%{cut: cut} = since), do: %{cut: cut, after_id: Map.get(since, :after_id)}

  defp parse_value(value) do
    with :error <- parse_datetime(value),
         :error <- parse_naive(value),
         :error <- parse_date(value) do
      {:error, :since}
    else
      # `as_of` is captured here, BEFORE the controller runs its query, and
      # it is no later than one second before the start of the oldest
      # transaction that has written and is still open (E25 S6, G06;
      # `Portfolixir.DeltaCursor`). A row's `updated_at` is stamped when its
      # transaction writes it, not when that transaction commits: an `as_of`
      # of "now" lost every row a transaction open during the read stamped
      # before now and committed after, and the second's margin alone only
      # covered transactions that commit within it. `updated_at` carries
      # second precision, so the margin also keeps a row stamped inside the
      # cursor's own second in the next poll's window. Both give a harmless
      # overlap — the next poll re-delivers a row rather than losing one.
      # A cut the database cannot encode (a year before 1) is not a cut:
      # the timestamp encoder raises on it, so it is refused here as the
      # 422 the contract promises (closing-act finding).
      {:ok, %NaiveDateTime{year: year}} when year < 1 ->
        {:error, :since}

      {:ok, naive} ->
        {:ok, %{raw: value, cut: naive, as_of: DeltaCursor.as_of()}}
    end
  end

  defp parse_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, DateTime.to_naive(datetime)}
      _other -> :error
    end
  end

  defp parse_naive(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> {:ok, naive}
      _other -> :error
    end
  end

  defp parse_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, NaiveDateTime.new!(date, ~T[00:00:00])}
      _other -> :error
    end
  end

  @doc """
  Adds the delta envelope (`since`, `as_of`, `delta_note`) to a `%{data: _}`
  response when a delta cut is active; leaves the plain read untouched.
  """
  def put_envelope(response, since), do: put_envelope(response, since, @delta_note)

  @doc """
  As `put_envelope/2`, with a read-specific `delta_note` for a read whose
  change stamp is not a plain `updated_at` (the append-only research log, the
  plan-scoped targets). The note must still state what the cut compares and
  what the delta cannot represent.
  """
  def put_envelope(response, nil, _note), do: response

  def put_envelope(response, %{raw: raw, as_of: as_of}, note) when is_binary(note) do
    Map.merge(response, %{
      since: raw,
      as_of: DateTime.to_iso8601(as_of),
      delta_note: note
    })
  end

  @doc """
  The delta envelope of a paged read (K17): `since`, `as_of`, `has_more`
  and the note. `page` is `%{has_more: boolean, last: {stamp, id} | nil}`,
  the page's flag and its last row. A full page's `as_of` is the cursor at
  that row, unless the row is newer than the read's bound; a page that is
  not full answers the bound, as before.
  """
  def put_page_envelope(response, since, note \\ @paged_delta_note, page)

  def put_page_envelope(response, nil, _note, _page), do: response

  def put_page_envelope(response, %{raw: raw, as_of: as_of}, note, %{has_more: more?} = page)
      when is_binary(note) and is_boolean(more?) do
    Map.merge(response, %{
      since: raw,
      as_of: next_cursor(as_of, more?, page[:last]),
      has_more: more?,
      delta_note: note
    })
  end

  defp next_cursor(as_of, true, {%NaiveDateTime{} = stamp, id}) when is_integer(id) do
    stamp = DateTime.from_naive!(stamp, "Etc/UTC")

    if DateTime.compare(stamp, as_of) == :gt,
      do: DateTime.to_iso8601(as_of),
      else: DateTime.to_iso8601(stamp) <> "~" <> Integer.to_string(id)
  end

  defp next_cursor(as_of, _more?, _last), do: DateTime.to_iso8601(as_of)
end
