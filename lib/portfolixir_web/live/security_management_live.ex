defmodule PortfolixirWeb.SecurityManagementLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog

  @security_form_defaults %{
    "name" => "",
    "symbol" => "",
    "currency_code" => "",
    "isin" => "",
    "wkn" => "",
    "exchange_code" => "",
    "provider_symbol" => "",
    "notes" => ""
  }

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:security_form, @security_form_defaults)
      |> assign(:security_error, nil)
      |> load_securities()

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-gradient-to-br from-slate-50 to-slate-100 p-6">
      <section class="mx-auto max-w-6xl rounded-lg bg-white p-6 shadow-sm ring-1 ring-slate-200">
        <h1 class="text-2xl font-semibold tracking-tight text-slate-900">Securities</h1>
        <p class="mt-1 text-sm text-slate-600">
          Manage securities and inspect existing entries.
        </p>

        <section id="security-create" class="mt-6">
          <h2 class="text-lg font-medium text-slate-800">Create security</h2>

          <%= if @security_error do %>
            <p id="security-form-error" class="mt-2 rounded border border-red-200 bg-red-50 p-3 text-sm text-red-700">
              <%= @security_error %>
            </p>
          <% end %>

          <form id="security-form" class="mt-3 grid gap-3 md:grid-cols-2" phx-submit="create_security">
            <label class="flex flex-col text-sm text-slate-700">
              Name
              <input
                id="security-name"
                class="mt-1 rounded border border-slate-300 p-2"
                name="security[name]"
                value={@security_form["name"]}
              />
            </label>

            <label class="flex flex-col text-sm text-slate-700">
              Symbol
              <input
                id="security-symbol"
                class="mt-1 rounded border border-slate-300 p-2"
                name="security[symbol]"
                value={@security_form["symbol"]}
              />
            </label>

            <label class="flex flex-col text-sm text-slate-700">
              Currency code
              <input
                id="security-currency-code"
                class="mt-1 rounded border border-slate-300 p-2"
                name="security[currency_code]"
                value={@security_form["currency_code"]}
              />
            </label>

            <label class="flex flex-col text-sm text-slate-700">
              ISIN (optional)
              <input
                id="security-isin"
                class="mt-1 rounded border border-slate-300 p-2"
                name="security[isin]"
                value={@security_form["isin"]}
              />
            </label>

            <label class="flex flex-col text-sm text-slate-700">
              WKN (optional)
              <input
                id="security-wkn"
                class="mt-1 rounded border border-slate-300 p-2"
                name="security[wkn]"
                value={@security_form["wkn"]}
              />
            </label>

            <label class="flex flex-col text-sm text-slate-700">
              Exchange code (optional)
              <input
                id="security-exchange-code"
                class="mt-1 rounded border border-slate-300 p-2"
                name="security[exchange_code]"
                value={@security_form["exchange_code"]}
              />
            </label>

            <label class="flex flex-col text-sm text-slate-700">
              Provider symbol (optional)
              <input
                id="security-provider-symbol"
                class="mt-1 rounded border border-slate-300 p-2"
                name="security[provider_symbol]"
                value={@security_form["provider_symbol"]}
              />
            </label>

            <label class="flex flex-col text-sm text-slate-700 md:col-span-2">
              Notes (optional)
              <textarea
                id="security-notes"
                class="mt-1 rounded border border-slate-300 p-2"
                rows="2"
                name="security[notes]"
              ><%= @security_form["notes"] %></textarea>
            </label>

            <button
              type="submit"
              class="md:col-span-2 inline-flex w-fit rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white"
            >
              Add security
            </button>
          </form>
        </section>

        <section id="security-listing" class="mt-10">
          <h2 class="text-lg font-medium text-slate-800">Existing securities</h2>

          <%= if Enum.empty?(@securities) do %>
            <p id="no-securities" class="mt-3 text-sm text-slate-500">No securities yet.</p>
          <% else %>
            <table id="security-list" class="mt-3 w-full border-collapse overflow-hidden rounded bg-white text-sm">
              <thead>
                <tr class="bg-slate-50 text-left text-slate-600">
                  <th class="border px-3 py-2">Name</th>
                  <th class="border px-3 py-2">Symbol</th>
                  <th class="border px-3 py-2">Currency</th>
                  <th class="border px-3 py-2">ISIN</th>
                  <th class="border px-3 py-2">WKN</th>
                  <th class="border px-3 py-2">Provider symbol</th>
                  <th class="border px-3 py-2">Exchange</th>
                </tr>
              </thead>
              <tbody>
                <%= for security <- @securities do %>
                  <tr>
                    <td class="border px-3 py-2 font-medium text-slate-800"><%= security.name %></td>
                    <td class="border px-3 py-2"><%= security.symbol %></td>
                    <td class="border px-3 py-2"><%= security.currency_code %></td>
                    <td class="border px-3 py-2"><%= security.isin || "—" %></td>
                    <td class="border px-3 py-2"><%= security.wkn || "—" %></td>
                    <td class="border px-3 py-2"><%= security.provider_symbol || "—" %></td>
                    <td class="border px-3 py-2"><%= security.exchange_code || "—" %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </section>
      </section>
    </main>
    """
  end

  def handle_event("create_security", %{"security" => params}, socket) do
    case Catalog.create_security(sanitize_security_params(params)) do
      {:ok, _security} ->
        {:noreply,
         socket
         |> assign(:security_form, @security_form_defaults)
         |> assign(:security_error, nil)
         |> load_securities()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(
           :security_form,
           @security_form_defaults |> Map.merge(sanitize_security_params(params))
         )
         |> assign(:security_error, format_errors(changeset))
         |> load_securities()}
    end
  end

  defp load_securities(socket) do
    socket
    |> assign(:securities, Catalog.list_securities())
  end

  defp sanitize_security_params(params) when is_map(params) do
    params
    |> Map.new(fn {key, value} -> {key, value} end)
    |> maybe_remove_empty_string("isin")
    |> maybe_remove_empty_string("wkn")
    |> maybe_remove_empty_string("exchange_code")
    |> maybe_remove_empty_string("provider_symbol")
    |> maybe_remove_empty_string("notes")
  end

  defp sanitize_security_params(_), do: %{}

  defp maybe_remove_empty_string(params, key) do
    case Map.get(params, key) do
      "" -> Map.put(params, key, nil)
      _ -> params
    end
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, _opts}} ->
      "#{field} #{message}"
    end)
  end
end
