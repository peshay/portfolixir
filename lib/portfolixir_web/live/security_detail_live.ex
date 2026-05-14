defmodule PortfolixirWeb.SecurityDetailLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog
  alias PortfolixirWeb.AppShell

  @quote_form %{
    "date" => "",
    "source" => "manual",
    "currency_code" => "EUR",
    "open" => "",
    "high" => "",
    "low" => "",
    "close" => "",
    "volume" => ""
  }

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    security = Catalog.get_security!(id)

    {:ok,
     socket
     |> assign(:security, security)
     |> assign(:quote_form, Map.put(@quote_form, "currency_code", security.currency_code))
     |> assign(:error, nil)
     |> assign(:success, nil)
     |> load_quotes()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current_path={"/securities/#{@security.id}"}>
      <header class="page-header">
        <h1><%= @security.name %></h1>
        <p><%= @security.symbol %> · <%= @security.currency_code %></p>
      </header>

      <div class="stack">
        <section id="quote-create" class="panel">
          <h2><%= gettext("Add quote") %></h2>
          <%= if @error do %>
            <p class="alert-error" role="alert"><%= @error %></p>
          <% end %>
          <%= if @success do %>
            <p class="alert-success" role="status"><%= @success %></p>
          <% end %>
          <form id="quote-form" phx-submit="save_quote">
            <div class="form-grid">
              <label>
                <span><%= gettext("Date") %></span>
                <input type="date" name="quote[date]" value={@quote_form["date"]} required />
              </label>
              <label>
                <span><%= gettext("Close") %></span>
                <input name="quote[close]" value={@quote_form["close"]} inputmode="decimal" required />
              </label>
              <label>
                <span><%= gettext("Currency") %></span>
                <input name="quote[currency_code]" value={@quote_form["currency_code"]} maxlength="3" required />
              </label>
              <label>
                <span><%= gettext("Source") %></span>
                <input name="quote[source]" value={@quote_form["source"]} required />
              </label>
              <label>
                <span><%= gettext("Open") %></span>
                <input name="quote[open]" value={@quote_form["open"]} inputmode="decimal" />
              </label>
              <label>
                <span><%= gettext("High") %></span>
                <input name="quote[high]" value={@quote_form["high"]} inputmode="decimal" />
              </label>
              <label>
                <span><%= gettext("Low") %></span>
                <input name="quote[low]" value={@quote_form["low"]} inputmode="decimal" />
              </label>
              <label>
                <span><%= gettext("Volume") %></span>
                <input name="quote[volume]" value={@quote_form["volume"]} inputmode="decimal" />
              </label>
            </div>
            <button type="submit"><%= gettext("Store quote") %></button>
          </form>
        </section>

        <section id="security-price-history" class="panel">
          <h2><%= gettext("Price history") %></h2>
          <%= if Enum.empty?(@quotes) do %>
            <div id="security-price-chart-empty" class="empty-state" role="status">
              <%= gettext("No quotes yet") %>
            </div>
          <% else %>
            <svg
              id="security-price-chart"
              class="chart"
              viewBox="0 0 420 160"
              role="img"
              aria-label={gettext("Security price history chart")}
            >
              <rect x="0" y="0" width="420" height="160" fill="#ffffff" />
              <line x1="16" y1="140" x2="404" y2="140" stroke="#d8e1ea" />
              <line x1="16" y1="16" x2="16" y2="140" stroke="#d8e1ea" />
              <polyline points={chart_points(@quotes)} fill="none" stroke="#0f766e" stroke-width="3" />
              <%= for point <- chart_point_pairs(@quotes) do %>
                <circle cx={point.x} cy={point.y} r="3.5" fill="#0f766e" />
              <% end %>
            </svg>
          <% end %>
        </section>

        <section id="security-quote-history" class="panel">
          <h2><%= gettext("Quote history") %></h2>
          <%= if Enum.empty?(@quotes) do %>
            <div id="no-quotes" class="empty-state" role="status">
              <%= gettext("No quote history yet") %>
            </div>
          <% else %>
            <table>
              <thead>
                <tr>
                  <th><%= gettext("Date") %></th>
                  <th><%= gettext("Close") %></th>
                  <th><%= gettext("Currency") %></th>
                  <th><%= gettext("Source") %></th>
                </tr>
              </thead>
              <tbody>
                <%= for quote <- @quotes do %>
                  <tr>
                    <td><%= quote.date %></td>
                    <td><%= format_decimal(quote.close) %></td>
                    <td><%= quote.currency_code %></td>
                    <td><%= quote.source %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </section>
      </div>
    </AppShell.shell>
    """
  end

  @impl true
  def handle_event("save_quote", %{"quote" => params}, socket) do
    params = Map.put(params, "security_id", socket.assigns.security.id)

    case Catalog.create_security_quote(params) do
      {:ok, _quote} ->
        {:noreply,
         socket
         |> assign(
           :quote_form,
           Map.put(@quote_form, "currency_code", socket.assigns.security.currency_code)
         )
         |> assign(:success, gettext("Quote stored"))
         |> assign(:error, nil)
         |> load_quotes()}

      {:error, changeset} ->
        {:noreply,
         assign(socket, quote_form: params, error: changeset_error(changeset), success: nil)}
    end
  end

  defp load_quotes(socket) do
    assign(socket, :quotes, Catalog.list_security_quotes(socket.assigns.security.id))
  end

  defp chart_points(quotes) do
    quotes
    |> chart_point_pairs()
    |> Enum.map_join(" ", fn point -> "#{point.x},#{point.y}" end)
  end

  defp chart_point_pairs([]), do: []

  defp chart_point_pairs(quotes) do
    closes = Enum.map(quotes, & &1.close)
    min_close = decimal_min(closes)
    max_close = decimal_max(closes)
    range = Decimal.sub(max_close, min_close)
    range = if Decimal.equal?(range, Decimal.new("0")), do: Decimal.new("1"), else: range
    count = Enum.count(quotes)

    quotes
    |> Enum.with_index()
    |> Enum.map(fn {quote, index} ->
      x =
        if count == 1 do
          Decimal.new("210")
        else
          Decimal.add(
            Decimal.new("16"),
            Decimal.div(
              Decimal.mult(Decimal.new(index), Decimal.new("388")),
              Decimal.new(count - 1)
            )
          )
        end

      y =
        quote.close
        |> Decimal.sub(min_close)
        |> Decimal.div(range)
        |> Decimal.mult(Decimal.new("124"))
        |> then(&Decimal.sub(Decimal.new("140"), &1))

      %{x: format_coordinate(x), y: format_coordinate(y)}
    end)
  end

  defp decimal_min([first | rest]) do
    Enum.reduce(rest, first, fn value, min ->
      if Decimal.compare(value, min) == :lt, do: value, else: min
    end)
  end

  defp decimal_max([first | rest]) do
    Enum.reduce(rest, first, fn value, max ->
      if Decimal.compare(value, max) == :gt, do: value, else: max
    end)
  end

  defp format_coordinate(decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
  end

  defp format_decimal(nil), do: ""
  defp format_decimal(decimal), do: Decimal.to_string(decimal, :normal)

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field} #{message}" end)
    |> Enum.join(", ")
  end
end
