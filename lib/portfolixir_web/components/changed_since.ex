defmodule PortfolixirWeb.ChangedSince do
  @moduledoc """
  The human view of the `?since=` delta read (FR-38, issue #731).

  One control, two surfaces (transactions and securities): the URL parameter
  mirrors the API parameter — same name, same accepted forms via
  `SinceParam`, same strictly-after-`updated_at` semantics — so a link an
  agent hands over opens the exact slice it read. The presets write concrete
  ISO dates into the URL rather than relative windows, which keeps a shared
  link meaning what it meant when it was shared.

  Unlike the API (where an invalid `since` is a 422), a garbled URL value
  degrades to the unfiltered list with no delta note: a stale bookmark must
  never silently narrow what the operator sees.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias PortfolixirWeb.Api.V1.SinceParam

  @doc """
  Parses the LiveView `since` URL param through the API's own parser.
  Returns the `%{raw: _, cut: _}` cut map, or `nil` (absent or garbled).
  """
  def parse(params) do
    case SinceParam.parse(params) do
      {:ok, since} -> since
      {:error, :since} -> nil
    end
  end

  @doc """
  The one-tap presets, as `{key, label, iso_date}`. Day-granular on purpose:
  a plain ISO date is an accepted API form (start of that day, UTC), and the
  chip's active state stays a plain string comparison for the whole UTC day.
  """
  def presets do
    today = Date.utc_today()

    [
      {"today", gettext("Today"), Date.to_iso8601(today)},
      {"7d", gettext("7 days"), Date.to_iso8601(Date.add(today, -7))},
      {"30d", gettext("30 days"), Date.to_iso8601(Date.add(today, -30))}
    ]
  end

  @doc "The URL value the active chip would toggle to, or nil to clear."
  def toggle_value(since, preset_key) do
    {_key, _label, iso} = List.keyfind!(presets(), preset_key, 0)
    if since && since.raw == iso, do: nil, else: iso
  end

  attr(:id, :string, required: true)
  attr(:since, :map, default: nil, doc: "the parsed cut map, or nil")

  @doc """
  The changed-since chip group. Clicks emit `set_changed_since` with the
  preset key; the LiveView answers with a URL patch, so the cut is state the
  reader can share, not state the socket holds.
  """
  def chips(assigns) do
    assigns = assign(assigns, :presets, presets())

    ~H"""
    <div id={@id} class="filter-chips" role="group" aria-label={gettext("Changed since")}>
      <span class="filter-chips__family"><%= gettext("Changed since") %></span>
      <%= for {key, label, iso} <- @presets do %>
        <button
          type="button"
          id={"#{@id}-#{key}"}
          class={["filter-chip", @since && @since.raw == iso && "is-active"]}
          aria-pressed={to_string(@since != nil && @since.raw == iso)}
          phx-click="set_changed_since"
          phx-value-preset={key}
        >
          <%= label %>
        </button>
      <% end %>
    </div>
    """
  end
end
