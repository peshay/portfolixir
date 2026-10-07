defmodule PortfolixirWeb.Securities.QuoteReleaseDialog do
  @moduledoc """
  The release of a security's manual quotes, from its Quotes tab (T-9;
  Sprint 17 V2; board `ux-design-2026-10-01/03-quote-release`, pick G3-A):
  the page's first quote write.

  A native dialog element (`.modal.quote-release-dialog`, on the
  `ModalDialog` hook) titled with the security. Its range is the custom
  range's ISO date pair, prefilled with the first and last manual date; one
  chip per stretch of manual quotes (the five newest, a hint naming the cut
  when there are more) plus "All" fills the pair, and the chip matching the
  pair is pressed. One sentence says what happens — the manual closes in the
  range are removed and kept in the journal with their values, the
  provider's stay, and the next quote sync fills the days, until then they
  have none — and an attention note says the days stay empty where the sync
  cannot fetch the security (`Portfolixir.Catalog.QuoteSync.adapter?/2`).
  The confirm is `.button-danger` naming how many manual quotes the range
  holds; a range with none disables it with its reason beside it
  (`.merge-footer__why`), and a "To" before its "From", or a field that is no
  date, is refused at the field — nothing is written.

  Only the confirm writes (closing act, γ D1): Enter in a field submits the
  form, which re-counts and checks the pair and writes nothing. The confirm
  carries the pair and the count it shows, and runs the journaled
  `Portfolixir.Catalog.Quotes.release_manual/4` as the operator, unchanged,
  once the range still holds that count; where it holds another by now,
  nothing is written and the dialog says the new count at the pair (γ CR-2).
  The parent hears `{:dialog, id, :close}` and
  `{:dialog, id, {:released, released_dates}}`, and reports the result in the
  tab (A5); where the release took the last manual quote and with it the
  "Release…" that opened the dialog, the focus goes to the result's dismiss
  (`data-focus-fallback`, γ D2).
  """
  use Phoenix.LiveComponent
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.QuoteSync
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Input.BoundedDate
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.LiveEventGuard
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.StoredText

  # Chips beside "All": the newest stretches (board 03, ④).
  @chips 5
  # The count the confirm carries back, as LiveParam reads an integer.
  @counts 1..2_147_483_647

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> LiveEventGuard.attach()
     |> assign(security: nil, summary: nil, adapter?: false)
     |> assign(from: "", to: "", count: nil, error: nil)}
  end

  @impl true
  def update(%{security_id: security_id} = assigns, socket) do
    socket = assign(socket, :id, assigns.id)

    if socket.assigns.security && socket.assigns.security.id == security_id do
      {:ok, socket}
    else
      case Catalog.get_security(security_id) do
        %Security{} = security -> {:ok, start(socket, security)}
        nil -> {:ok, notify(socket, :close)}
      end
    end
  end

  defp start(socket, %Security{} = security) do
    summary = Quotes.manual_summary(security.id, stretches: @chips)

    socket
    |> assign(security: security, summary: summary, adapter?: QuoteSync.adapter?(security))
    |> assign(error: nil)
    |> put_range(iso(summary.first), iso(summary.last))
  end

  # -- render -------------------------------------------------------------------

  # The security is gone (merged or deleted since the parent opened the
  # dialog): nothing to show while the parent hears :close.
  @impl true
  def render(%{security: nil} = assigns) do
    ~H"""
    <div id={@id} hidden></div>
    """
  end

  def render(assigns) do
    all = {iso(assigns.summary.first), iso(assigns.summary.last)}

    assigns =
      assign(assigns,
        all: all,
        # A stretch spanning every manual quote is "All" already.
        stretches: Enum.reject(assigns.summary.stretches, &(range(&1) == all)),
        chips: @chips,
        waits?: assigns.count == 0
      )

    ~H"""
    <dialog
      id={@id}
      class="modal quote-release-dialog"
      phx-hook="ModalDialog"
      data-close-event="close"
      data-focus-fallback="#quotes-release-result .inline-result__dismiss"
      aria-labelledby={"#{@id}-title"}
    >
      <header class="modal-head">
        <h2 id={"#{@id}-title"}>
          <%= StoredText.isolate(
            gettext("Release manual quotes — %{name}", name: StoredText.slot(:name)),
            name: @security.name
          ) %>
        </h2>
        <button
          type="button"
          class="icon-button"
          aria-label={gettext("Close")}
          data-role="quote-release-dismiss"
          phx-click="close"
          phx-target={@myself}
        >
          <AppShell.icon name={:x} />
        </button>
      </header>
      <div class="modal-body">
        <AppShell.data_note :if={not @adapter?} severity={:attention} data-role="release-no-adapter">
          <%= gettext(
            "The quote sync fetches no quotes for this security: the released days stay without a quote."
          ) %>
        </AppShell.data_note>
        <form
          id="quote-release-form"
          class="quote-release-form"
          phx-change="change"
          phx-submit="check"
          phx-target={@myself}
        >
          <div class="period-range__pair">
            <div class="period-range__field">
              <label for="quote-release-from"><%= gettext("From") %></label>
              <input
                type="text"
                id="quote-release-from"
                name="release[from]"
                value={@from}
                placeholder="YYYY-MM-DD"
                maxlength="10"
                autocomplete="off"
                aria-invalid={@error && elem(@error, 0) == :from && "true"}
                aria-describedby={@error && elem(@error, 0) == :from && "quote-release-error"}
              />
            </div>
            <span class="period-range__dash" aria-hidden="true">–</span>
            <div class="period-range__field">
              <label for="quote-release-to"><%= gettext("To") %></label>
              <input
                type="text"
                id="quote-release-to"
                name="release[to]"
                value={@to}
                placeholder="YYYY-MM-DD"
                maxlength="10"
                autocomplete="off"
                aria-invalid={@error && elem(@error, 0) == :to && "true"}
                aria-describedby={@error && elem(@error, 0) == :to && "quote-release-error"}
              />
            </div>
          </div>
          <p
            :if={@error}
            id="quote-release-error"
            class="field-error"
            data-role="quote-release-error"
            role="alert"
          >
            <%= elem(@error, 1) %>
          </p>
        </form>
        <div
          class="period-years"
          role="group"
          aria-label={gettext("Stretches of manual quotes")}
          data-role="release-stretches"
        >
          <.chip
            label={ngettext("All · %{count}", "All · %{count}", @summary.count)}
            range={@all}
            pressed={{@from, @to} == @all}
            myself={@myself}
          />
          <.chip
            :for={stretch <- @stretches}
            label={stretch_label(stretch)}
            range={range(stretch)}
            pressed={{@from, @to} == range(stretch)}
            myself={@myself}
          />
        </div>
        <p :if={@summary.stretch_count > @chips} class="hint" data-role="release-stretches-cut">
          <%= ngettext(
            "The %{shown} newest of %{count} stretches; “All” covers every one.",
            "The %{shown} newest of %{count} stretches; “All” covers every one.",
            @summary.stretch_count,
            shown: @chips
          ) %>
        </p>
        <p class="hint" data-role="release-consequence">
          <%= gettext(
            "The manual closes in the range are removed and kept in the journal with their values; the provider's quotes in the range stay as they are."
          ) %>
          <%= if @adapter? do %>
            <%= gettext(
              "The next quote sync stores the provider's close for the released days; until then they have no quote."
            ) %>
          <% end %>
        </p>
      </div>
      <div class="modal-footer modal-footer--band">
        <button
          type="button"
          class="button-ghost"
          data-role="quote-release-cancel"
          phx-click="close"
          phx-target={@myself}
        >
          <%= gettext("Cancel") %>
        </button>
        <span class="modal-footer__spacer"></span>
        <p :if={@waits?} id="quote-release-why" class="merge-footer__why" data-role="quote-release-why">
          <%= gettext("No manual quote in the range.") %>
        </p>
        <button
          type="button"
          class="button-danger"
          data-role="quote-release-confirm"
          disabled={@waits?}
          aria-describedby={@waits? && "quote-release-why"}
          phx-click="release"
          phx-value-from={@from}
          phx-value-to={@to}
          phx-value-shown={@count}
          phx-target={@myself}
        >
          <%= confirm_label(@count) %>
        </button>
      </div>
    </dialog>
    """
  end

  attr(:label, :string, required: true)
  attr(:range, :any, required: true)
  attr(:pressed, :boolean, required: true)
  attr(:myself, :any, required: true)

  defp chip(assigns) do
    ~H"""
    <button
      type="button"
      class={["filter-chip", @pressed && "is-active"]}
      aria-pressed={to_string(@pressed)}
      phx-click="pick"
      phx-value-from={elem(@range, 0)}
      phx-value-to={elem(@range, 1)}
      phx-target={@myself}
    >
      <%= @label %>
    </button>
    """
  end

  # A chip reads its days in the page's language (Sprint 19 U3); its
  # phx-values and the fields it fills keep ISO (`range/1`, `iso/1`).
  defp stretch_label(%{from: day, to: day, count: count}),
    do: ngettext("%{date} · %{count}", "%{date} · %{count}", count, date: Format.date(day))

  defp stretch_label(stretch) do
    ngettext("%{from} – %{to} · %{count}", "%{from} – %{to} · %{count}", stretch.count,
      from: Format.date(stretch.from),
      to: Format.date(stretch.to)
    )
  end

  defp range(stretch), do: {iso(stretch.from), iso(stretch.to)}

  defp confirm_label(count) when is_integer(count) and count > 0,
    do: ngettext("Release %{count} manual quote", "Release %{count} manual quotes", count)

  defp confirm_label(_count), do: gettext("Release")

  # -- events ---------------------------------------------------------------------

  @impl true
  def handle_event("close", _params, socket), do: {:noreply, notify(socket, :close)}

  def handle_event("change", %{"release" => params}, socket) do
    %{"from" => from, "to" => to} = fields(params)
    {:noreply, socket |> assign(error: nil) |> put_range(from, to)}
  end

  def handle_event("pick", params, socket) when is_map(params) do
    case fields(params) do
      %{"from" => from, "to" => to} when from != "" and to != "" ->
        {:noreply, socket |> assign(error: nil) |> put_range(from, to)}

      _incomplete ->
        {:noreply, socket}
    end
  end

  # Enter in a field: the pair re-counted and checked, never written.
  def handle_event("check", %{"release" => params}, socket) do
    %{"from" => from_text, "to" => to_text} = fields(params)
    socket = put_range(socket, from_text, to_text)

    case checked(from_text, to_text) do
      {:ok, _from, _to} -> {:noreply, assign(socket, :error, nil)}
      {:error, field, message} -> {:noreply, assign(socket, :error, {field, message})}
    end
  end

  # The confirm: the pair and the count it showed.
  def handle_event("release", params, socket) when is_map(params) do
    %{"from" => from_text, "to" => to_text} = fields(params)
    socket = put_range(socket, from_text, to_text)

    with {:ok, from, to} <- checked(from_text, to_text),
         count when count > 0 <- socket.assigns.count,
         :ok <- as_shown(count, params) do
      release(socket, from, to)
    else
      {:error, field, message} -> {:noreply, assign(socket, :error, {field, message})}
      _nothing_to_release -> {:noreply, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp release(socket, from, to) do
    security = socket.assigns.security

    case Catalog.release_manual_quotes(Actor.owner_ui(), security.id, from, to) do
      {:ok, %{released: released}} ->
        {:noreply, notify(socket, {:released, released})}

      {:error, :invalid_range} ->
        {:noreply, assign(socket, :error, {:to, order_message()})}

      {:error, _not_found} ->
        {:noreply, notify(socket, :close)}
    end
  end

  # -- the range ------------------------------------------------------------------

  defp fields(params) do
    params = LiveParam.map(params)

    %{
      "from" => text(Map.get(params, "from")),
      "to" => text(Map.get(params, "to")),
      "shown" => Map.get(params, "shown")
    }
  end

  defp checked(from_text, to_text) do
    with {:ok, from} <- date(from_text, :from),
         {:ok, to} <- date(to_text, :to),
         :ok <- ordered(from, to) do
      {:ok, from, to}
    end
  end

  defp text(value) when is_binary(value), do: value |> String.slice(0, 10) |> String.trim()
  defp text(_value), do: ""

  # The pair as typed, and — where it reads as a range — the count of manual
  # quotes it holds, which the confirm names (nil while it does not read).
  defp put_range(socket, from_text, to_text) do
    count =
      case checked(from_text, to_text) do
        {:ok, from, to} -> Quotes.manual_count(socket.assigns.security.id, from, to)
        _unreadable -> nil
      end

    assign(socket, from: from_text, to: to_text, count: count)
  end

  # The shared date rule (E25 S4), as the custom range reads it: an ISO date
  # inside the ledger's range, else the field's error.
  defp date(text, field) do
    case BoundedDate.parse(text) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, field, gettext("Not a date — use YYYY-MM-DD.")}
    end
  end

  # The confirm named a count; the write releases what the range holds when
  # it runs. Where the two differ — a manual close written or released since
  # the dialog counted — nothing is written and the confirm is asked again
  # with the new count (closing act, γ CR-2).
  defp as_shown(count, params) do
    case params |> fields() |> Map.get("shown") |> LiveParam.integer(@counts) do
      ^count ->
        :ok

      _other ->
        {:error, :count,
         ngettext(
           "The range now holds %{count} manual quote — check and confirm again.",
           "The range now holds %{count} manual quotes — check and confirm again.",
           count
         )}
    end
  end

  defp ordered(from, to) do
    if Date.compare(from, to) == :gt, do: {:error, :to, order_message()}, else: :ok
  end

  defp order_message, do: gettext("The end date is before the start date.")

  defp iso(nil), do: ""
  defp iso(%Date{} = date), do: Date.to_iso8601(date)

  defp notify(socket, message) do
    send(self(), {:dialog, socket.assigns.id, message})
    socket
  end
end
