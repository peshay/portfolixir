defmodule PortfolixirWeb.PortfolioAccounts.RenameDialog do
  @moduledoc """
  The rename dialog of a cash account or a depot on Accounts & depots
  (ADR-0050 §4, #328; board 01-accounts-lifecycle, pick G1-A: one dialog per
  action of the row menu).

  Only the name is editable: the currency and the portfolio freeze once the
  account is referenced (§11), and the liquidity role, the balance and the
  buckets stay in the row. The dialog says which case of the rename rule
  applies before it writes — the current name stays a former name of this
  account, or, while another account of the kind carries it as its live
  name, it is not kept and an import naming it books to that account (the
  MCP rename tool's two cases) — and refuses a name another account answers
  to at the field, naming that account.

  The account's former names are listed and removable, each with a
  confirmation that says what removing costs; a name that arrived by a merge
  carries its origin (board 13, G13.1-A). Removing takes effect at once and
  the dialog stays open with a typed name kept. The row changing in place is
  the confirmation of a rename; no banner follows.

  The parent hears `{:dialog, id, :close}`, `{:dialog, id, :renamed}` and
  `{:dialog, id, :changed}` (a former name removed; reload, stay open).
  """
  use Phoenix.LiveComponent
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Actor
  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.AccountNames
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.LiveEventGuard
  alias PortfolixirWeb.LiveParam

  @impl true
  def mount(socket) do
    {:ok, socket |> LiveEventGuard.attach() |> assign(error: nil, account: nil, name: "")}
  end

  @impl true
  def update(%{kind: kind, account_id: account_id} = assigns, socket) do
    socket = assign(socket, id: assigns.id, kind: kind)

    if socket.assigns.account && socket.assigns.account.id == account_id do
      {:ok, socket}
    else
      case fetch(kind, account_id) do
        nil ->
          notify(socket, :close)
          {:ok, socket}

        account ->
          {:ok, socket |> assign(name: account.name, error: nil) |> load(account)}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <dialog
      id={@id}
      class="modal rename-dialog"
      phx-hook="ModalDialog"
      data-close-event="close"
      aria-labelledby={"#{@id}-title"}
    >
      <header class="modal-head">
        <h2 id={"#{@id}-title"}><%= gettext("Rename — %{name}", name: @account.name) %></h2>
        <button
          type="button"
          class="icon-button"
          aria-label={gettext("Close")}
          phx-click="close"
          phx-target={@myself}
        >
          <AppShell.icon name={:x} />
        </button>
      </header>
      <div class="modal-body">
        <form id="rename-form" phx-change="change" phx-submit="save" phx-target={@myself}>
          <div class="form-grid">
            <label>
              <span><%= gettext("Name") %></span>
              <input
                type="text"
                name="rename[name]"
                value={@name}
                required
                maxlength="255"
                autocomplete="off"
                aria-invalid={@error && "true"}
                aria-describedby={@error && "rename-error"}
              />
              <span :if={@error} id="rename-error" class="field-error" role="alert">
                <%= @error %>
              </span>
            </label>
          </div>
        </form>
        <p class="hint" data-role="rename-former-case"><%= former_case(@kind, @account, @outcome) %></p>
        <details :if={@former != []} class="perf-table-disclosure" open>
          <summary class="disclosure-summary">
            <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
            <%= gettext("Former names") %>
          </summary>
          <ul class="former-names" data-role="former-names">
            <li :for={entry <- @former}>
              <span>
                <span data-role="former-name"><%= entry.name %></span>
                <small :if={entry.merged_on} class="former-names__origin">
                  <%= gettext("merged on %{date}", date: Format.date(entry.merged_on)) %>
                </small>
              </span>
              <button
                type="button"
                class="button-ghost"
                data-role="remove-former-name"
                phx-click="remove_former_name"
                phx-value-name={entry.name}
                phx-target={@myself}
                aria-label={gettext("Remove “%{name}”", name: entry.name)}
                data-confirm={removal_confirmation(@kind, entry.name)}
              >
                <%= gettext("Remove") %>
              </button>
            </li>
          </ul>
        </details>
        <div class="modal-footer">
          <button type="button" class="button-ghost" phx-click="close" phx-target={@myself}>
            <%= gettext("Cancel") %>
          </button>
          <button type="submit" form="rename-form" class="button-primary">
            <%= gettext("Rename") %>
          </button>
        </div>
      </div>
    </dialog>
    """
  end

  # -- events ---------------------------------------------------------------

  @impl true
  def handle_event("close", _params, socket) do
    notify(socket, :close)
    {:noreply, socket}
  end

  def handle_event("change", %{"rename" => params}, socket) do
    case LiveParam.map(params) do
      %{"name" => name} when is_binary(name) -> {:noreply, assign(socket, :name, name)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("save", %{"rename" => params}, socket) do
    case LiveParam.map(params) do
      %{"name" => name} when is_binary(name) -> save(socket, String.trim(name))
      _ -> {:noreply, socket}
    end
  end

  def handle_event("remove_former_name", %{"name" => name}, socket) when is_binary(name) do
    case remove_former_name(socket.assigns.account, name) do
      {:ok, account} ->
        notify(socket, :changed)
        {:noreply, load(socket, account)}

      {:error, _reason} ->
        {:noreply, reload(socket)}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # -- the write --------------------------------------------------------------

  defp save(socket, name) do
    account = socket.assigns.account

    cond do
      name == "" ->
        {:noreply, assign(socket, name: name, error: gettext("Enter a name."))}

      name == account.name ->
        notify(socket, :close)
        {:noreply, socket}

      message = conflict_message(socket.assigns.kind, account, name) ->
        {:noreply, assign(socket, name: name, error: message)}

      true ->
        case rename(account, name) do
          {:ok, _renamed} ->
            notify(socket, :renamed)
            {:noreply, socket}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply,
             assign(socket,
               name: name,
               error:
                 conflict_message(socket.assigns.kind, account, name) ||
                   changeset_error(changeset)
             )}

          {:error, _reason} ->
            {:noreply,
             assign(socket, name: name, error: gettext("That account no longer exists."))}
        end
    end
  end

  defp rename(%CashAccount{} = account, name),
    do: Portfolios.update_cash_account(Actor.owner_ui(), account, %{name: name})

  defp rename(%SecuritiesAccount{} = account, name),
    do: Portfolios.update_securities_account(Actor.owner_ui(), account, %{name: name})

  defp remove_former_name(%CashAccount{} = account, name),
    do: Portfolios.remove_cash_account_former_name(Actor.owner_ui(), account, name)

  defp remove_former_name(%SecuritiesAccount{} = account, name),
    do: Portfolios.remove_securities_account_former_name(Actor.owner_ui(), account, name)

  # -- reads ------------------------------------------------------------------

  defp fetch("cash", id), do: Portfolios.get_cash_account(id)
  defp fetch("depot", id), do: Portfolios.get_securities_account(id)

  defp reload(socket) do
    case fetch(socket.assigns.kind, socket.assigns.account.id) do
      nil ->
        notify(socket, :close)
        socket

      account ->
        load(socket, account)
    end
  end

  # The former names, each with the date of the merge it arrived by, if it
  # did (board 13, G13.1-A).
  defp load(socket, %schema{} = account) do
    merged =
      schema
      |> merge_kind()
      |> Lifecycle.merged_from([account.id])
      |> Map.get(account.id, [])
      |> Map.new(&{&1.source_name, &1.merged_on})

    assign(socket,
      account: account,
      outcome: AccountNames.previous_name_outcome(account),
      former: Enum.map(account.former_names, &%{name: &1, merged_on: Map.get(merged, &1)})
    )
  end

  defp merge_kind(CashAccount), do: :cash_account
  defp merge_kind(SecuritiesAccount), do: :securities_account

  # -- copy -------------------------------------------------------------------

  defp former_case("cash", account, :kept) do
    gettext(
      "The current name “%{name}” stays a former name: an import that still names it keeps booking to this account.",
      name: account.name
    )
  end

  defp former_case("depot", account, :kept) do
    gettext(
      "The current name “%{name}” stays a former name: an import that still names it keeps booking to this depot.",
      name: account.name
    )
  end

  defp former_case("cash", account, {:not_kept, _holder}) do
    gettext(
      "Another cash account is also named “%{name}”, so the current name is not kept: an import that names it books to that account. Merge or rename that account to change this.",
      name: account.name
    )
  end

  defp former_case("depot", account, {:not_kept, _holder}) do
    gettext(
      "Another depot is also named “%{name}”, so the current name is not kept: an import that names it books to that depot. Merge or rename that depot to change this.",
      name: account.name
    )
  end

  defp removal_confirmation("cash", name) do
    gettext(
      "Remove “%{name}” as a former name? An import that still names '%{name}' will then create a new account.",
      name: name
    )
  end

  defp removal_confirmation("depot", name) do
    gettext(
      "Remove “%{name}” as a former name? An import that still names '%{name}' will then create a new depot.",
      name: name
    )
  end

  defp conflict_message(kind, %schema{} = account, name) do
    case AccountNames.conflict(schema, account.portfolio_id, name, account.id) do
      nil -> nil
      {:former, holder} -> former_conflict(name, holder.name)
      {:live, _holder} -> live_conflict(kind, name)
    end
  end

  defp former_conflict(name, holder) do
    gettext(
      "“%{name}” is a former name of “%{holder}”: an import under this name books there. Choose another name or remove it from “%{holder}”.",
      name: name,
      holder: holder
    )
  end

  defp live_conflict("cash", name),
    do: gettext("“%{name}” is already the name of another cash account.", name: name)

  defp live_conflict("depot", name),
    do: gettext("“%{name}” is already the name of another depot.", name: name)

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {_field, {message, opts}} ->
      Gettext.dgettext(PortfolixirWeb.Gettext, "errors", message, opts)
    end)
    |> Enum.join(" ")
  end

  defp notify(socket, message), do: send(self(), {:dialog, socket.assigns.id, message})
end
