defmodule PortfolixirWeb.LiveEventGuard do
  @moduledoc """
  The pages' event boundary (E25 S4, F17): an event a page cannot read never
  reaches its `handle_event/3`.

  A page's own markup and hooks send every event with an object payload, so a
  pushed event whose payload is anything else — a string, a number, a list,
  `null` — is dropped here. So is an event whose payload carries, at any
  depth, an id no `bigint` column can hold: the rule is the JSON API's own
  (`PortfolixirWeb.Api.V1.IdRangeGuard.out_of_range_key/1`), which answers
  such a body with a 422 before a controller runs. A page simply stays as it
  was.

  What this hook cannot see is a page's own reading of a well-shaped payload:
  each handler parses ids and nested form maps through
  `PortfolixirWeb.LiveParam`, and each page ends its `handle_event/3` with a
  clause that ignores an event it does not know. A LiveComponent's events do
  not pass the page's hooks at all, so each component attaches this guard in
  its own `mount/1` (`attach/1`) and carries the same clauses itself.
  """
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias PortfolixirWeb.Api.V1.IdRangeGuard

  def on_mount(:default, _params, _session, socket), do: {:cont, attach(socket)}

  @doc """
  Attaches the guard to a socket. A LiveComponent calls this from its
  `mount/1`: its events reach it directly, past the page's hooks.
  """
  @spec attach(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def attach(socket), do: attach_hook(socket, :event_payload, :handle_event, &guard/3)

  @doc false
  def guard(_event, params, socket) do
    if readable?(params), do: {:cont, socket}, else: {:halt, socket}
  end

  @doc "Whether an event payload is one a page may read: a map with no out-of-range id."
  @spec readable?(term()) :: boolean()
  def readable?(params) when is_map(params) and not is_struct(params),
    do: is_nil(IdRangeGuard.out_of_range_key(params))

  def readable?(_params), do: false
end
