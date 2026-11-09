defmodule Portfolixir.News.DigestCursor do
  @moduledoc """
  The digest's consumer cursor (ADR-0056 §9; Sprint 28, N3): at least once.

  A **consumer** is a named reader of the digest (an agent's scheduled run).
  The server keeps its **confirmed position** (`Portfolixir.News.DigestConsumer`),
  and the digest of a consumer reads the stories that entered their scope
  after it, or whose label of the read's prompt version was written after
  it (closing act, AT6: a story hidden as unlabelled when the consumer
  confirmed is not lost once a label shows it; `Portfolixir.News.Reads.digest/5`). Every answer carries a **cursor**, the position the next read
  may start from; the consumer confirms it with `ack_cursor` on its next
  call, and only then does the position move. *Why not on read:* a run that
  fails after the read would never see those stories again. So:

    * **a call without a confirmation reads again** from the confirmed
      position: a run that broke off loses nothing (overlap, never loss,
      `Portfolixir.DeltaCursor`'s rule);
    * **the position only moves forward:** a confirmation is one
      `UPDATE … SET position = GREATEST(position, cursor)`, so a cursor
      older than the stored position is a no-op, and of two confirmations
      that race the newer stays, whichever commits last;
    * **a cursor is the consumer's own:** `<unix seconds>~<tag>`, the tag an
      HMAC-SHA-256 over the consumer's row id, its name and the position,
      cut to 16 bytes. A forged or altered cursor, and one issued to
      another consumer, fails the check (`{:error, :not_issued}`, the API's
      422), and nothing moves. **The key is the caller's** (`key`, at least
      32 bytes): the API derives it from `SECRET_KEY_BASE` for this one
      purpose (`PortfolixirWeb.Api.V1.DigestCursorKey`), so the context reads
      no web configuration (ADR-0001) and nothing secret is stored: a
      stored key would be a credential-shaped column the stored-credentials
      backstop (B1) exists to refuse. A changed `SECRET_KEY_BASE` refuses
      every cursor issued before it; the consumer then reads once without
      `ack_cursor`, from its confirmed position, and loses nothing.
      `Portfolixir.DeltaCursor` signs nothing — its cursors are instants a
      caller may choose freely, because they keep no state — so there was
      no signing rule to follow;
    * **a truncated answer is paged** (closing act, AT5): it carries a
      page token (`issue_page/4`) in place of the cursor, and only its last
      page carries the cursor, the first page's moment, so a confirmation
      never passes a row an answer left out. A page token names the
      consumer's position, that moment and the place of the last row
      answered, signed like a cursor but under a key of its own purpose
      (`PortfolixirWeb.Api.V1.DigestCursorKey.page_key/0`) and with more
      parts, so neither passes for the other. Paging moves nothing; a page
      of a position the consumer has confirmed past is the caller's to
      restart;
    * **a new consumer starts 24 hours back**, the stateless digest's
      default window, and its start counts as confirmed;
    * **at most 32 consumers** (`cap/0`): each is a row kept until the
      daily retention removes it, 90 days after its last confirmation or,
      never confirmed, its creation (`Portfolixir.News.Retention`; S28 N3's
      open question 2), written by a read; an agent that names a fresh
      consumer each run would grow the table without bound and read the
      stateless 24 hours in disguise. A new consumer beyond the cap is
      refused (`{:error, {:cap, 32}}`), and a stored one keeps reading.

  **A consumer is not journaled** (`Portfolixir.Journal.Allowlist`, its
  non-journaled tables): its position is a reader's bookmark that every
  confirmed read moves, not a record of the operator's data, and nothing in
  it changes what any read answers to anyone but that consumer. Journaling
  it would write an entry per agent run and record no decision.
  """
  import Ecto.Query

  alias Portfolixir.News.DigestConsumer
  alias Portfolixir.News.Label
  alias Portfolixir.Repo

  @cap 32
  @start_seconds 24 * 60 * 60
  @key_min_bytes 32
  @tag_bytes 16
  # The consumers' creation lock (one at a time, so the cap holds), distinct
  # from the app's other advisory locks.
  @create_lock 727_228_003

  @doc "The most consumers the server keeps."
  @spec cap() :: pos_integer()
  def cap, do: @cap

  @doc "Whether `name` is a consumer's name: a label's identifier shape."
  @spec name?(term()) :: boolean()
  def name?(name), do: Label.identifier?(name)

  @doc """
  The consumer `name` after confirming `ack_cursor` (or none, `nil`), at the
  server's clock `now`: `{:ok, consumer}` with its confirmed position,
  `{:error, :not_issued}` for a cursor the server did not issue to `name`
  (a consumer that does not exist was issued none), `{:error, {:cap, n}}`
  for a new consumer beyond the cap.
  """
  @spec consumer(String.t(), String.t() | nil, DateTime.t(), binary()) ::
          {:ok, DigestConsumer.t()} | {:error, :not_issued | {:cap, pos_integer()}}
  def consumer(name, ack_cursor, now, key)

  def consumer(name, nil, %DateTime{} = now, key) when is_binary(name) and is_binary(key) do
    case Repo.get_by(DigestConsumer, name: name) do
      %DigestConsumer{} = consumer -> {:ok, consumer}
      nil -> create(name, now)
    end
  end

  def consumer(name, ack_cursor, %DateTime{} = now, key)
      when is_binary(name) and is_binary(ack_cursor) and byte_size(key) >= @key_min_bytes do
    with %DigestConsumer{} = consumer <- Repo.get_by(DigestConsumer, name: name),
         {:ok, position} <- verify(consumer, ack_cursor, key) do
      {:ok, confirm(consumer, position, now)}
    else
      _not_issued -> {:error, :not_issued}
    end
  end

  @doc """
  The cursor of `consumer` at `position`, truncated to the second, signed
  with `key`.
  """
  @spec issue(DigestConsumer.t(), DateTime.t(), binary()) :: String.t()
  def issue(%DigestConsumer{} = consumer, %DateTime{} = position, key)
      when byte_size(key) >= @key_min_bytes do
    seconds = Integer.to_string(DateTime.to_unix(position))
    seconds <> "~" <> tag(consumer, seconds, key)
  end

  # --- closing act, AT5 begin ---

  @doc """
  The page token of `consumer`'s truncated answer (closing act, AT5): the
  consumer's confirmed position, `until` (the first page's `as_of`, the
  cursor its last page carries), and `keys` (the page keys of the rows
  already answered, `Portfolixir.News.Reads.encode_page_key/1`), signed
  with `key`: `<position>~<until>~<key>…~<tag>`. Never a cursor: it has
  more parts, and its tag is an HMAC under another purpose, so neither
  verifies as the other.
  """
  @spec issue_page(DigestConsumer.t(), DateTime.t(), [String.t()], binary()) :: String.t()
  def issue_page(%DigestConsumer{} = consumer, %DateTime{} = until, keys, key)
      when is_list(keys) and byte_size(key) >= @key_min_bytes do
    parts = [unix(consumer.position), unix(until) | keys]
    Enum.join(parts ++ [page_tag(consumer, parts, key)], "~")
  end

  @doc """
  The page token `token` checked for `consumer`: `{:ok, %{position:,
  until:, keys:}}` when the server signed it for that consumer row with
  `key`, else `:error`. The position it names may be older than the
  consumer's now; the caller decides what a stale page reads.
  """
  @spec verify_page(DigestConsumer.t(), String.t(), binary()) ::
          {:ok, %{position: DateTime.t(), until: DateTime.t(), keys: [String.t()]}} | :error
  def verify_page(%DigestConsumer{} = consumer, token, key)
      when is_binary(token) and byte_size(key) >= @key_min_bytes do
    with [_, _, _ | _] = all <- String.split(token, "~"),
         {parts, [tag]} = Enum.split(all, -1),
         expected = page_tag(consumer, parts, key),
         true <- byte_size(tag) == byte_size(expected),
         true <- Plug.Crypto.secure_compare(tag, expected),
         [position, until | keys] <- parts,
         {:ok, position} <- from_unix(position),
         {:ok, until} <- from_unix(until) do
      {:ok, %{position: position, until: until, keys: keys}}
    else
      _other -> :error
    end
  end

  defp page_tag(%DigestConsumer{id: id, name: name}, parts, key) do
    message = Enum.join(["portfolixir.news.digest_page", id, name | parts], <<0>>)

    :hmac
    |> :crypto.mac(:sha256, key, message)
    |> binary_part(0, @tag_bytes)
    |> Base.url_encode64(padding: false)
  end

  defp unix(%DateTime{} = at), do: Integer.to_string(DateTime.to_unix(at))

  defp from_unix(seconds) do
    with {unix, ""} when unix >= 0 <- Integer.parse(seconds),
         {:ok, at} <- DateTime.from_unix(unix) do
      {:ok, usec(at)}
    else
      _other -> :error
    end
  end

  # --- closing act, AT5 end ---

  defp verify(consumer, cursor, key) do
    with [seconds, tag] <- String.split(cursor, "~"),
         {unix, ""} when unix >= 0 <- Integer.parse(seconds),
         expected = tag(consumer, seconds, key),
         true <- byte_size(tag) == byte_size(expected),
         true <- Plug.Crypto.secure_compare(tag, expected),
         {:ok, position} <- DateTime.from_unix(unix) do
      {:ok, usec(position)}
    else
      _other -> :error
    end
  end

  defp tag(%DigestConsumer{id: id, name: name}, seconds, key) do
    message = Enum.join(["portfolixir.news.digest_cursor", id, name, seconds], <<0>>)

    :hmac
    |> :crypto.mac(:sha256, key, message)
    |> binary_part(0, @tag_bytes)
    |> Base.url_encode64(padding: false)
  end

  # One statement under the row's lock, compared in the database: the
  # position read with the consumer may be stale by now (another
  # confirmation committed since), so it decides nothing here.
  defp confirm(consumer, position, now) do
    {1, [confirmed]} =
      Repo.update_all(
        from(c in DigestConsumer,
          where: c.id == ^consumer.id,
          select: c,
          update: [
            set: [
              position: fragment("GREATEST(?, ?)", c.position, type(^position, c.position)),
              updated_at: ^usec_now(now)
            ]
          ]
        ),
        []
      )

    confirmed
  end

  defp usec_now(%DateTime{} = now), do: DateTime.add(now, 0, :microsecond)

  # A whole second, at the column's precision.
  defp usec(%DateTime{} = at), do: %{DateTime.truncate(at, :second) | microsecond: {0, 6}}

  defp create(name, now) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock($1)", [@create_lock])

      cond do
        consumer = Repo.get_by(DigestConsumer, name: name) ->
          consumer

        Repo.aggregate(DigestConsumer, :count) >= @cap ->
          Repo.rollback({:cap, @cap})

        true ->
          %DigestConsumer{}
          |> DigestConsumer.changeset(%{
            name: name,
            position: now |> DateTime.add(-@start_seconds, :second) |> usec()
          })
          |> Repo.insert!()
      end
    end)
  end
end
