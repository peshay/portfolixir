defmodule PortfolixirWeb.Securities.MergeDialog do
  @moduledoc """
  The merge of one security into another, on the securities page (ADR-0050
  §8, §9, §10, #608; board 03-security-merge, pick G3-A; the two steps of
  G2-B, as on Accounts & depots).

  **Step 1** searches the target — the catalog holds hundreds of securities,
  so the list stays empty until a search and suggests nothing (ADR-0050 §14
  excludes merge suggestions). It never lists the source. A candidate the
  master data already rules out — another currency, one of the two a
  benchmark, a retired target of a live source, another "treat synced quotes
  as raw" while the source has quotes — is disabled and names each reason;
  the rest the preview checks. The only legal candidate is chosen.

  **Step 2** is the preview of exactly that pair, and so of exactly one plan
  digest (`Portfolixir.Lifecycle.preview_security_merge/2`); its anatomy is
  `PortfolixirWeb.Securities.MergePreview`. Both of the operator's choices —
  which ISIN stays when both carry one, and what becomes of the equal
  bookings — are never preselected, and the confirm waits for each. A plan
  that changed meanwhile answers with the fresh preview, a note saying so,
  and the choices cleared (a changed plan is a new question, as on Accounts
  & depots). A refusal names each reason and its remedy; where the merge the
  other way passes, "Merge the other way" swaps the pair, and where it does
  not either, the refusal says so and offers nothing it cannot keep.

  The parent hears `{:dialog, id, :close}` and `{:dialog, id, {:merged,
  message, target_id}}`.
  """
  use Phoenix.LiveComponent
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Clock
  alias Portfolixir.Ledger
  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.Delete
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.LiveEventGuard
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.Securities.MergePreview

  @max_candidates 25
  @max_query 100
  @identity_choices %{
    "keep_target_isin" => :keep_target_isin,
    "adopt_source_isin" => :adopt_source_isin
  }

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> LiveEventGuard.attach()
     |> assign(source: nil, step: :target, query: "", candidates: [], target_id: nil)
     |> assign(target: nil, totals: %{})
     |> assign(preview: nil, refused: nil, reverse: nil, stale: nil, problem: nil)
     |> assign(choices: blank_choices(), field_error: nil)}
  end

  @impl true
  def update(%{source_id: source_id} = assigns, socket) do
    socket = assign(socket, :id, assigns.id)

    if socket.assigns.source && socket.assigns.source.id == source_id do
      {:ok, socket}
    else
      case Catalog.get_security(source_id) do
        %Security{} = source -> {:ok, start(socket, source)}
        nil -> {:ok, notify(socket, :close)}
      end
    end
  end

  defp start(socket, %Security{} = source) do
    references = Delete.referenced_by(source)

    assign(socket,
      source: source,
      source_bookings: Map.get(references, "transactions", 0),
      source_quotes: Map.get(references, "security_quotes", 0),
      step: :target,
      query: "",
      candidates: [],
      target_id: nil,
      preview: nil,
      refused: nil,
      reverse: nil,
      stale: nil,
      problem: nil,
      choices: blank_choices(),
      field_error: nil
    )
  end

  defp blank_choices,
    do: %{collapse: nil, identity: nil, isin_changed_on: Date.to_iso8601(Clock.today())}

  # -- render -------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <dialog
      id={@id}
      class={["modal", "merge-dialog", "security-merge-dialog", @step == :target && "merge-dialog--target"]}
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
          source={@source}
          target={@target}
          preview={@preview}
          refused={@refused}
          reverse={@reverse}
          choices={@choices}
          field_error={@field_error}
          totals={@totals}
          stale={@stale}
          problem={@problem}
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
        <span class="merge-route__meta"><%= source_meta(@source, @source_bookings) %></span>
      </div>
      <form
        id={"#{@id}-search"}
        data-role="merge-search"
        phx-change="search"
        phx-submit="search"
        phx-target={@myself}
      >
        <label class="search-field">
          <AppShell.icon name={:search} />
          <input
            type="search"
            name="merge[q]"
            value={@query}
            maxlength="100"
            autocomplete="off"
            phx-debounce="250"
            aria-label={gettext("Search the target: name, ISIN, WKN or ticker")}
            placeholder={gettext("Name, ISIN, WKN or ticker")}
          />
        </label>
      </form>
      <p :if={@query != "" and @candidates == []} class="merge-empty">
        <%= gettext("No other security matches.") %>
      </p>
      <form
        :if={@candidates != []}
        id={"#{@id}-targets"}
        data-role="merge-target-form"
        phx-change="pick_target"
        phx-target={@myself}
      >
        <fieldset class="merge-targets">
          <legend :if={@legal != []}>
            <%= gettext("Target — receives bookings, quotes and settings") %>
          </legend>
          <label
            :for={candidate <- @legal}
            class={["merge-target", candidate.security.id == @target_id && "is-on"]}
            data-role="merge-target"
            data-id={candidate.security.id}
          >
            <input
              type="radio"
              id={"merge-target-#{candidate.security.id}"}
              name="merge[target_id]"
              value={candidate.security.id}
              checked={candidate.security.id == @target_id}
            />
            <span class="merge-target__name">
              <b><%= candidate.security.name %></b>
              <small><%= candidate_meta(candidate.security) %></small>
            </span>
            <span class="merge-target__balance num"><%= bookings(candidate.bookings) %></span>
          </label>
          <p :if={@illegal != []} class="merge-sub-caps">
            <%= ngettext("Not selectable (%{count})", "Not selectable (%{count})", length(@illegal)) %>
          </p>
          <label
            :for={candidate <- @illegal}
            class="merge-target is-off"
            data-role="merge-target"
            data-id={candidate.security.id}
          >
            <input
              type="radio"
              id={"merge-target-#{candidate.security.id}"}
              name="merge[target_id]"
              value={candidate.security.id}
              disabled
            />
            <span class="merge-target__name">
              <b><%= candidate.security.name %></b>
              <small><%= candidate_meta(candidate.security) %></small>
            </span>
            <span class="merge-target__balance num"><%= bookings(candidate.bookings) %></span>
            <span class="merge-target__why"><%= Enum.map_join(candidate.reasons, ", ", &reason/1) %></span>
          </label>
        </fieldset>
      </form>
      <p class="merge-basis">
        <%= gettext(
          "Selectable: the same currency, both or neither a benchmark, the target not retired; with quotes also the same “treat synced quotes as raw”. The preview checks everything else."
        ) %>
      </p>
    </div>
    <div class="modal-footer modal-footer--band">
      <button type="button" class="button-ghost" data-role="merge-close" phx-click="close" phx-target={@myself}>
        <%= gettext("Cancel") %>
      </button>
      <span class="modal-footer__spacer"></span>
      <button
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
  def handle_event("close", _params, socket), do: {:noreply, notify(socket, :close)}

  def handle_event("search", %{"merge" => params}, %{assigns: %{step: :target}} = socket) do
    query =
      case LiveParam.map(params) do
        %{"q" => q} when is_binary(q) -> q |> String.slice(0, @max_query) |> String.trim()
        _other -> ""
      end

    {:noreply, search(socket, query)}
  end

  def handle_event("pick_target", %{"merge" => params}, socket) do
    with %{"target_id" => raw} <- LiveParam.map(params),
         {:ok, id} <- LiveParam.fetch_id(raw),
         %{reasons: []} <- Enum.find(socket.assigns.candidates, &(&1.security.id == id)) do
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
     socket
     |> assign(step: :target, preview: nil, refused: nil, reverse: nil)
     |> assign(stale: nil, problem: nil, field_error: nil)
     |> search(socket.assigns.query)}
  end

  # ADR-0050 §9, the reverse direction: the pair swaps roles, and the
  # preview of the other way is read (a read costs nothing, §10).
  def handle_event("other_way", _params, %{assigns: %{step: :preview}} = socket) do
    %{source: source, target_id: target_id} = socket.assigns

    case Catalog.get_security(target_id) do
      %Security{} = new_source ->
        query = socket.assigns.query

        {:noreply,
         socket
         |> start(new_source)
         |> assign(query: query, target_id: source.id, step: :preview)
         |> load_preview()}

      nil ->
        {:noreply, socket |> assign(step: :preview) |> load_preview()}
    end
  end

  def handle_event("choose", %{"merge" => params}, %{assigns: %{preview: %{}}} = socket) do
    params = LiveParam.map(params)
    choices = socket.assigns.choices

    choices = %{
      choices
      | identity: Map.get(@identity_choices, params["identity"], choices.identity),
        collapse: collapse_param(params["collapse"], choices.collapse),
        isin_changed_on: date_param(params["isin_changed_on"], choices.isin_changed_on)
    }

    {:noreply, assign(socket, choices: choices, field_error: nil)}
  end

  def handle_event("confirm", _params, %{assigns: %{preview: %{} = preview}} = socket) do
    if MergePreview.missing_choices(preview, socket.assigns.choices) == [] do
      apply_merge(socket, preview)
    else
      {:noreply, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp collapse_param("true", _current), do: true
  defp collapse_param("false", _current), do: false
  defp collapse_param(_other, current), do: current

  # The date field is text (UX-DR19): kept as typed, bounded, and parsed by
  # the merge itself, which names a date it cannot read at the field.
  defp date_param(value, _current) when is_binary(value), do: String.slice(value, 0, 32)
  defp date_param(_other, current), do: current

  # -- step 1: the candidates ----------------------------------------------------

  defp search(socket, "") do
    assign(socket, query: "", candidates: [], target_id: nil)
  end

  defp search(socket, query) do
    %{source: source, source_quotes: quotes} = socket.assigns

    found =
      [query: query, limit: @max_candidates + 1]
      |> Catalog.list_securities()
      |> Enum.reject(&(&1.id == source.id))
      |> Enum.take(@max_candidates)

    counts = Ledger.count_transactions_by_security(Enum.map(found, & &1.id))

    candidates =
      Enum.map(found, fn security ->
        %{
          security: security,
          bookings: Map.get(counts, security.id, 0),
          reasons: reasons(source, security, quotes)
        }
      end)

    legal = Enum.filter(candidates, &(&1.reasons == []))

    target_id =
      cond do
        Enum.any?(legal, &(&1.security.id == socket.assigns.target_id)) ->
          socket.assigns.target_id

        match?([_], legal) ->
          hd(legal).security.id

        true ->
          nil
      end

    assign(socket, query: query, candidates: candidates, target_id: target_id)
  end

  # The guards the master data already decides (ADR-0050 §9); the preview
  # checks the ones that need the pair and its bookings.
  defp reasons(source, candidate, source_quotes) do
    [
      candidate.currency_code != source.currency_code && :currency,
      candidate.is_benchmark != source.is_benchmark && :benchmark,
      (candidate.is_retired and not source.is_retired) && :retired,
      (source_quotes > 0 and candidate.treat_quotes_as_raw != source.treat_quotes_as_raw) &&
        :quote_basis
    ]
    |> Enum.filter(& &1)
  end

  # -- step 2: the preview and the apply ----------------------------------------

  defp load_preview(socket) do
    %{source: source, target_id: target_id} = socket.assigns

    socket =
      assign(socket,
        target: Catalog.get_security(target_id),
        totals: totals(source.id, target_id)
      )

    case Lifecycle.preview_security_merge(source.id, target_id) do
      {:ok, preview} ->
        assign(socket,
          preview: preview,
          refused: nil,
          reverse: nil,
          choices: blank_choices(),
          field_error: nil
        )

      {:error, {:refused, guards}} ->
        assign(socket,
          preview: nil,
          refused: guards,
          reverse: reverse_refusal(guards, source.id, target_id)
        )

      {:error, refusal} ->
        assign(socket, preview: nil, refused: nil, reverse: nil, problem: problem(refusal))
    end
  end

  # What the pair's cards and the holdings sum read beside the preview: each
  # security's bookings and its holdings in every depot, from the ledger.
  defp totals(source_id, target_id) do
    counts = Ledger.count_transactions_by_security([source_id, target_id])

    %{
      source: holdings(source_id),
      target: holdings(target_id),
      source_bookings: Map.get(counts, source_id, 0),
      target_bookings: Map.get(counts, target_id, 0)
    }
  end

  defp holdings(security_id) do
    security_id
    |> Ledger.holdings_for_security()
    |> Enum.reduce(Decimal.new(0), &Decimal.add(&2, &1.quantity))
  end

  # Where a one-sided refusal says the other way is refused too, what refuses
  # it — read from the reverse preview, so the reasons are named, not coded.
  defp reverse_refusal(guards, source_id, target_id) do
    if Enum.any?(guards, &(Map.get(&1, :remedy) == :keep_both)) do
      case Lifecycle.preview_security_merge(target_id, source_id) do
        {:error, {:refused, reverse_guards}} -> Enum.reject(reverse_guards, & &1.passed)
        _passes_or_gone -> []
      end
    end
  end

  defp apply_merge(socket, preview) do
    %{source: source, target_id: target_id, choices: choices} = socket.assigns

    params = %{
      plan_digest: preview.plan_digest,
      collapse_key_equal: choices.collapse,
      identity_choice: choices.identity,
      isin_changed_on:
        if(choices.identity == :adopt_source_isin, do: blank_to_nil(choices.isin_changed_on))
    }

    case Lifecycle.merge_security(Actor.owner_ui(), source.id, target_id, params) do
      {:ok, _record, _outcome} ->
        {:noreply,
         notify(socket, {:merged, MergePreview.result_message(preview, choices), target_id})}

      {:error, {:plan_changed, fresh}} ->
        {:noreply,
         assign(socket,
           totals: totals(source.id, target_id),
           preview: fresh,
           refused: nil,
           reverse: nil,
           choices: blank_choices(),
           field_error: nil,
           stale: MergePreview.changes(preview, fresh)
         )}

      {:error, {:refused, guards}} ->
        {:noreply,
         assign(socket,
           preview: nil,
           refused: guards,
           reverse: reverse_refusal(guards, source.id, target_id)
         )}

      {:error, {:invalid, :isin_changed_on, _message}} ->
        {:noreply,
         assign(socket,
           field_error: gettext("is not a date in the range the app accepts (YYYY-MM-DD)")
         )}

      {:error, refusal} ->
        {:noreply, assign(socket, problem: problem(refusal))}
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  defp problem(:not_found), do: gettext("The security no longer exists. Nothing was merged.")

  defp problem({:already_merged, _record}),
    do: gettext("The security was merged into another one meanwhile. Nothing was merged now.")

  defp problem({:choice_required, :collapse_key_equal, count}),
    do:
      ngettext(
        "Choose what to do with the equal booking.",
        "Choose what to do with the %{count} equal bookings.",
        count
      )

  defp problem({:choice_required, :identity_choice, _isins}),
    do: gettext("Choose which ISIN the security carries afterwards.")

  defp problem({:identity_unresolvable, _failures}),
    do:
      gettext(
        "Nothing was merged: after the merge an identifier of the two would no longer have led to the target, so the merge was rolled back. Check again."
      )

  defp problem({:write_refused, _resource, _id, %Ecto.Changeset{} = changeset}) do
    gettext("Nothing was merged: a row could not be written (%{errors}). Check again.",
      errors: changeset_errors(changeset)
    )
  end

  defp problem(_refusal) do
    gettext(
      "Nothing was merged: the check of the merged figures did not hold, so the merge was rolled back. Check again; if it recurs, the audit journal shows both securities' bookings."
    )
  end

  defp changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  # -- copy -------------------------------------------------------------------------

  defp step_label(:target), do: gettext("Step 1 of 2 · Target")
  defp step_label(:preview), do: gettext("Step 2 of 2 · Preview")

  defp reason(:currency), do: gettext("different currency")
  defp reason(:benchmark), do: gettext("only one of the two is a benchmark")
  defp reason(:retired), do: gettext("retired")
  defp reason(:quote_basis), do: gettext("other quote basis")

  defp source_meta(source, count) do
    [
      source.isin,
      source.currency_code,
      bookings(count),
      gettext("created %{date}", date: MergePreview.created_on(source))
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp candidate_meta(security) do
    [
      security.isin,
      security.currency_code,
      MergePreview.asset_class_label(security),
      security.is_benchmark && gettext("Benchmark"),
      security.is_retired && gettext("Retired")
    ]
    |> Enum.reject(&(&1 in [nil, "", false]))
    |> Enum.join(" · ")
  end

  defp bookings(count), do: ngettext("%{count} booking", "%{count} bookings", count)

  defp notify(socket, message) do
    send(self(), {:dialog, socket.assigns.id, message})
    socket
  end
end
