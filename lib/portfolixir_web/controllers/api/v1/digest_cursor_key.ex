defmodule PortfolixirWeb.Api.V1.DigestCursorKey do
  @moduledoc """
  The key the digest's consumer cursors are signed with (ADR-0056 §9;
  Sprint 28, N3): derived from `SECRET_KEY_BASE` for this one purpose, as
  the session's signing keys and the UI password's fingerprint are
  (`PortfolixirWeb.UiAuth`), never the raw secret, and cached like theirs.
  Nothing secret is stored; see `Portfolixir.News.DigestCursor`.
  """

  alias Plug.Crypto.KeyGenerator

  @doc "The 32-byte cursor key of this instance."
  @spec key() :: binary()
  def key do
    PortfolixirWeb.Endpoint.config(:secret_key_base)
    |> KeyGenerator.generate("portfolixir.news.digest_cursor", cache: Plug.Keys)
  end
end
