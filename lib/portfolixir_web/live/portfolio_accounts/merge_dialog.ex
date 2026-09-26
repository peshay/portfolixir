defmodule PortfolixirWeb.PortfolioAccounts.MergeDialog do
  @moduledoc """
  The merge of a cash account or a depot into another, on Accounts & depots
  (ADR-0050 §7, §8, §10, #328; board 02-merge-preview, pick G2-B: two steps).

  **Step 1** lists every other account of the kind. One that cannot take the
  history — another currency, liquidity role or bucket set for a cash
  account, another default bucket set for a depot, another portfolio record
  for either — is disabled and names each reason, so every reason is
  readable without opening anything. The only legal target is chosen.

  **Step 2** is the preview of exactly that pair, and so of exactly one plan
  digest (`Portfolixir.Lifecycle.preview_cash_merge/2`,
  `preview_depot_merge/2`): nothing above it can change the plan while it is
  read. The equal bookings' choice (§8) is never preselected and the confirm
  waits for it. Confirming applies under the preview's digest and the
  choice; a plan that changed meanwhile answers with the fresh preview, an
  attention note saying what changed, and the choice cleared (a changed plan
  is a new question, design pass Part 2). A refusal the preview finds names
  its reason and its remedy, with "Check again" and no confirm.

  The step-2 anatomy is `PortfolixirWeb.PortfolioAccounts.MergePreview`.
  The parent hears `{:dialog, id, :close}` and `{:dialog, id, {:merged,
  message}}`.
  """
  use Phoenix.LiveComponent
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Ledger
  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.Delete
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.LiveEventGuard
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.PortfolioAccounts.MergePreview

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> LiveEventGuard.attach()
     |> assign(source: nil, step: :target, preview: nil, refused: nil, collapse: nil)
     |> assign(stale: nil, problem: nil, target_id: nil)}
  end

  @impl true
  def update(%{kind: kind, source_id: source_id} = assigns, socket) do
    socket = assign(socket, id: assigns.id, kind: kind)

    if socket.assigns.source && socket.assigns.source.id == source_id do
      {:ok, socket}
    else
      case fetch(kind, source_id) do
        nil ->
          notify(socket, :close)
          {:ok, socket}

        source ->
          {:ok, start(socket, source)}
      end
    end
  end

  defp start(socket, source) do
    buckets = Map.new(Buckets.list_buckets(), &{&1.id, &1.name})
    balances = Ledger.cash_balances()
    candidates = candidates(socket.assigns.kind, source)
    legal = Enum.filter(candidates, &(&1.reasons == []))

    assign(socket,
      source: source,
      bucket_names: buckets,
      balances: balances,
      source_bucket_ids: bucket_ids(source),
      source_bookings: Map.get(Delete.referenced_by(source), "transactions", 0),
      candidates: candidates,
      target_id: if(match?([_], legal), do: hd(legal).account.id),
      step: :target,
      preview: nil,
      refused: nil,
      collapse: nil,
      stale: nil,
      problem: nil
    )
  end

  # -- render -------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <dialog
      id={@id}
      class={["modal", "merge-dialog", @step == :target && "merge-dialog--target"]}
      phx-hook="ModalDialog"
      data-close-event="close"
      aria-labelledby={"#{@id}-title"}
    >
      <header class="modal-head">
        <h2 id={"#{@id}-title"}>
          <%= gettext("Merge %{name}", name: @source.name) %>
          <span class="modal-head__step"><%= step_label(@step) %></span>
        </h2>
        <button
          type="button"
          class="icon-button"
          aria-label={gettext("Close")}
          data-role="merge-dismiss"
          phx-click="close"
          phx-target={@myself}
        >
          <AppShell.icon name={:x} />
        </button>
      </header>
      <%= if @step == :target do %>
        <%= render_target_step(assigns) %>
      <% else %>
        <MergePreview.step
          kind={@kind}
          source={@source}
          target={target(@candidates, @target_id)}
          preview={@preview}
          refused={@refused}
          collapse={@collapse}
          stale={@stale}
          problem={@problem}
          bucket_names={@bucket_names}
          myself={@myself}
        />
      <% end %>
    </dialog>
    """
  end

  defp render_target_step(assigns) do
    {legal, illegal} = Enum.split_with(assigns.candidates, &(&1.reasons == []))
    assigns = assign(assigns, legal: legal, illegal: illegal)

    ~H"""
    <div class="modal-body">
      <div class="merge-route" data-role="merge-route">
        <b><%= @source.name %></b>
        <span class="merge-route__meta"><%= source_meta(assigns) %></span>
      </div>
      <p :if={@legal == []} class="merge-empty"><%= no_target_text(@kind) %></p>
      <form id="merge-target-form" data-role="merge-target-form" phx-change="pick_target" phx-target={@myself}>
        <fieldset class="merge-targets">
          <legend :if={@legal != []}><%= target_legend(@kind) %></legend>
          <label
            :for={candidate <- @legal}
            class={["merge-target", candidate.account.id == @target_id && "is-on"]}
            data-role="merge-target"
            data-id={candidate.account.id}
          >
            <input
              type="radio"
              id={"merge-target-#{candidate.account.id}"}
              name="merge[target_id]"
              value={candidate.account.id}
              checked={candidate.account.id == @target_id}
            />
            <span class="merge-target__name">
              <b><%= candidate.account.name %></b>
              <small><%= candidate_meta(@kind, candidate, @bucket_names) %></small>
            </span>
            <span class="merge-target__balance num"><%= candidate_figure(assigns, candidate) %></span>
          </label>
          <p :if={@illegal != []} class="merge-sub-caps">
            <%= ngettext("Not selectable (%{count})", "Not selectable (%{count})", length(@illegal)) %>
          </p>
          <label
            :for={candidate <- @illegal}
            class="merge-target is-off"
            data-role="merge-target"
            data-id={candidate.account.id}
          >
            <input
              type="radio"
              id={"merge-target-#{candidate.account.id}"}
              name="merge[target_id]"
              value={candidate.account.id}
              disabled
            />
            <span class="merge-target__name">
              <b><%= candidate.account.name %></b>
              <small><%= candidate_meta(@kind, candidate, @bucket_names) %></small>
            </span>
            <span class="merge-target__balance num"><%= candidate_figure(assigns, candidate) %></span>
            <span class="merge-target__why"><%= Enum.map_join(candidate.reasons, ", ", &reason/1) %></span>
          </label>
        </fieldset>
      </form>
      <p class="merge-basis"><%= selectable_basis(@kind) %></p>
    </div>
    <div class="modal-footer modal-footer--band">
      <button type="button" class="button-ghost" data-role="merge-close" phx-click="close" phx-target={@myself}>
        <%= if @legal == [], do: gettext("Close"), else: gettext("Cancel") %>
      </button>
      <span class="modal-footer__spacer"></span>
      <button
        :if={@legal != []}
        type="button"
        class="button-primary"
        data-role="merge-continue"
        phx-click="continue"
        phx-target={@myself}
        disabled={is_nil(@target_id)}
      >
        <%= gettext("Continue to preview") %>
      </button>
    </div>
    """
  end

  # -- events ---------------------------------------------------------------------

  @impl true
  def handle_event("close", _params, socket) do
    notify(socket, :close)
    {:noreply, socket}
  end

  def handle_event("pick_target", %{"merge" => params}, socket) do
    with %{"target_id" => raw} <- LiveParam.map(params),
         {:ok, id} <- LiveParam.fetch_id(raw),
         %{reasons: []} <- Enum.find(socket.assigns.candidates, &(&1.account.id == id)) do
      {:noreply, assign(socket, :target_id, id)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("continue", _params, %{assigns: %{target_id: id}} = socket)
      when is_integer(id) do
    {:noreply, socket |> assign(step: :preview, stale: nil, problem: nil) |> load_preview()}
  end

  def handle_event("recheck", _params, %{assigns: %{step: :preview}} = socket) do
    {:noreply, socket |> assign(stale: nil, problem: nil) |> load_preview()}
  end

  def handle_event("back", _params, socket) do
    {:noreply,
     assign(socket, step: :target, preview: nil, refused: nil, stale: nil, problem: nil)}
  end

  def handle_event("choose", %{"merge" => params}, %{assigns: %{preview: %{}}} = socket) do
    case LiveParam.map(params) do
      %{"collapse" => "true"} -> {:noreply, assign(socket, :collapse, true)}
      %{"collapse" => "false"} -> {:noreply, assign(socket, :collapse, false)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("confirm", _params, %{assigns: %{preview: %{} = preview}} = socket) do
    if preview.choice_required and is_nil(socket.assigns.collapse) do
      {:noreply, socket}
    else
      apply_merge(socket, preview)
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # -- the preview and the apply ---------------------------------------------------

  defp load_preview(socket) do
    %{kind: kind, source: source, target_id: target_id} = socket.assigns

    case preview(kind, source.id, target_id) do
      {:ok, preview} ->
        assign(socket, preview: preview, refused: nil, collapse: nil)

      {:error, {:refused, guards}} ->
        assign(socket, preview: nil, refused: guards, collapse: nil)

      {:error, refusal} ->
        assign(socket, preview: nil, refused: nil, problem: problem(refusal))
    end
  end

  defp apply_merge(socket, preview) do
    %{kind: kind, source: source, target_id: target_id, collapse: collapse} = socket.assigns
    consent = %{plan_digest: preview.plan_digest, collapse_key_equal: collapse}

    case merge(kind, source.id, target_id, consent) do
      {:ok, record, _outcome} ->
        notify(socket, {:merged, result_message(source, target(socket.assigns), record)})
        {:noreply, socket}

      {:error, {:plan_changed, fresh}} ->
        {:noreply,
         assign(socket,
           preview: fresh,
           refused: nil,
           collapse: nil,
           stale: MergePreview.changes(kind, preview, fresh)
         )}

      {:error, {:refused, guards}} ->
        {:noreply, assign(socket, preview: nil, refused: guards, collapse: nil)}

      {:error, refusal} ->
        {:noreply, assign(socket, problem: problem(refusal))}
    end
  end

  defp preview("cash", source_id, target_id),
    do: Lifecycle.preview_cash_merge(source_id, target_id)

  defp preview("depot", source_id, target_id),
    do: Lifecycle.preview_depot_merge(source_id, target_id)

  defp merge("cash", source_id, target_id, consent),
    do: Lifecycle.merge_cash_account(Actor.owner_ui(), source_id, target_id, consent)

  defp merge("depot", source_id, target_id, consent),
    do: Lifecycle.merge_depot(Actor.owner_ui(), source_id, target_id, consent)

  defp problem(:not_found), do: gettext("The account no longer exists. Nothing was merged.")

  defp problem({:already_merged, _record}),
    do: gettext("The account was merged into another one meanwhile. Nothing was merged now.")

  defp problem({:choice_required, _choice, count}),
    do:
      ngettext(
        "Choose what to do with the equal booking.",
        "Choose what to do with the %{count} equal bookings.",
        count
      )

  defp problem(_refusal) do
    gettext(
      "Nothing was merged: the check of the merged figures did not hold, so the merge was rolled back. Check again; if it recurs, the audit journal shows both accounts' bookings."
    )
  end

  defp result_message(source, target, record) do
    transactions = Map.get(record.manifest, "transactions", %{})
    moved = length(Map.get(transactions, "moved", []))
    removed = length(Map.get(transactions, "deleted", []))

    gettext("Merged %{source} into %{target}: %{moved}, %{removed}.",
      source: source.name,
      target: target.name,
      moved: ngettext("%{count} booking moved", "%{count} bookings moved", moved),
      removed: ngettext("%{count} removed", "%{count} removed", removed)
    )
  end

  # -- candidates (step 1) ----------------------------------------------------------

  defp fetch("cash", id), do: Portfolios.get_cash_account(id)
  defp fetch("depot", id), do: Portfolios.get_securities_account(id)

  defp candidates("cash", %CashAccount{} = source) do
    source_buckets = bucket_ids(source)

    for account <- Portfolios.list_cash_accounts(), account.id != source.id do
      buckets = bucket_ids(account)

      reasons =
        [
          account.portfolio_id != source.portfolio_id && :portfolio,
          account.currency_code != source.currency_code && :currency,
          account.liquidity_role != source.liquidity_role && :liquidity_role,
          buckets != source_buckets && :buckets
        ]
        |> Enum.filter(& &1)

      %{account: account, bucket_ids: buckets, reasons: reasons}
    end
  end

  defp candidates("depot", %SecuritiesAccount{} = source) do
    source_buckets = bucket_ids(source)

    for account <- Portfolios.list_securities_accounts(), account.id != source.id do
      buckets = bucket_ids(account)

      reasons =
        [
          account.portfolio_id != source.portfolio_id && :portfolio,
          buckets != source_buckets && :buckets
        ]
        |> Enum.filter(& &1)

      %{account: account, bucket_ids: buckets, reasons: reasons}
    end
  end

  defp bucket_ids(%CashAccount{id: id}), do: Enum.sort(Buckets.cash_account_bucket_ids(id))
  defp bucket_ids(%SecuritiesAccount{id: id}), do: Enum.sort(Buckets.depot_default_bucket_ids(id))

  defp target(%{candidates: candidates, target_id: id}), do: target(candidates, id)

  defp target(candidates, id) do
    case Enum.find(candidates, &(&1.account.id == id)) do
      nil -> nil
      candidate -> candidate.account
    end
  end

  # -- copy -------------------------------------------------------------------------

  defp step_label(:target), do: gettext("Step 1 of 2 · Target")
  defp step_label(:preview), do: gettext("Step 2 of 2 · Preview")

  defp target_legend("cash"), do: gettext("Target — receives every booking")
  defp target_legend("depot"), do: gettext("Target — receives every booking")

  defp no_target_text("cash"), do: gettext("No account meets the conditions.")
  defp no_target_text("depot"), do: gettext("No depot meets the conditions.")

  defp selectable_basis("cash"),
    do: gettext("Selectable: same currency, same liquidity role, same buckets.")

  defp selectable_basis("depot"), do: gettext("Selectable: same default buckets.")

  defp reason(:portfolio), do: gettext("different portfolio record")
  defp reason(:currency), do: gettext("different currency")
  defp reason(:liquidity_role), do: gettext("different liquidity role")
  defp reason(:buckets), do: gettext("different buckets")

  defp source_meta(%{kind: "cash", source: source} = assigns) do
    [
      source.currency_code,
      MergePreview.role_label(source.liquidity_role),
      gettext("Buckets: %{names}",
        names: bucket_list(assigns.source_bucket_ids, assigns.bucket_names, gettext("none"))
      ),
      bookings(assigns.source_bookings),
      "#{Format.money(Map.get(assigns.balances, source.id, Decimal.new(0)))} #{source.currency_code}"
    ]
    |> Enum.join(" · ")
  end

  defp source_meta(%{kind: "depot"} = assigns) do
    [
      gettext("Buckets: %{names}",
        names: bucket_list(assigns.source_bucket_ids, assigns.bucket_names, gettext("none"))
      ),
      bookings(assigns.source_bookings)
    ]
    |> Enum.join(" · ")
  end

  defp bookings(count), do: ngettext("%{count} booking", "%{count} bookings", count)

  defp candidate_meta("cash", candidate, names) do
    Enum.join(
      [
        candidate.account.currency_code,
        MergePreview.role_label(candidate.account.liquidity_role),
        bucket_list(candidate.bucket_ids, names, gettext("no buckets"))
      ],
      " · "
    )
  end

  defp candidate_meta("depot", candidate, names) do
    gettext("Buckets: %{names}", names: bucket_list(candidate.bucket_ids, names, gettext("none")))
  end

  defp candidate_figure(%{kind: "cash", balances: balances}, %{account: account}) do
    "#{Format.money(Map.get(balances, account.id, Decimal.new(0)))} #{account.currency_code}"
  end

  defp candidate_figure(%{kind: "depot"}, _candidate), do: ""

  defp bucket_list([], _names, empty), do: empty

  defp bucket_list(ids, names, _empty),
    do: ids |> Enum.map(&Map.get(names, &1, "##{&1}")) |> Enum.sort() |> Enum.join(", ")

  defp notify(socket, message), do: send(self(), {:dialog, socket.assigns.id, message})
end
