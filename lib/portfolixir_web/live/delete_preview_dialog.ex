defmodule PortfolixirWeb.DeletePreviewDialog do
  @moduledoc """
  The three cascading deletes from the screen — a classification, a
  category, a view — confirmed in the app's own delete dialog, which says
  what the delete removes (Sprint 26 V4, F21, #894; board
  `ux-design-2026-11-06-sprint26-f21`, pick A "counts only"; DESIGN.md,
  "The cascading deletes say what they remove").

  The dialog is the booking delete's (`PortfolixirWeb.Transactions.
  BookingDeleteDialog`): a native dialog element (`.modal
  .booking-delete-dialog`) on the `ModalDialog` hook, the subject box, the
  band foot. What it lists is the delete's own **dry run**
  (`Classifications.dry_run_delete_classification/2`,
  `dry_run_delete_category/2`, `Buckets.dry_run_delete_view/2`, the
  functions `DELETE …?dry_run=true` answers with): one line per kind of row
  with its count, a kind with none left out, or — when a policy rule reads
  the subject — the refusal with the rules and only "Close".

  Opening runs the dry run and nothing else. The confirm runs the delete
  **held to the answer the dialog showed** (`held_to:`,
  `Portfolixir.DryRun.held_to/3`): it commits only when it removes exactly
  those ids, and otherwise deletes nothing and the dialog shows the new
  state. The page keeps the open dialog in its assigns; the confirm acts on
  that and on nothing the client sends, and `confirms?/3` lets a confirm
  through only when its kind and id name the open dialog's subject.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.View
  alias Portfolixir.Classifications
  alias Portfolixir.Classifications.Category
  alias Portfolixir.Classifications.Classification
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.PolicyRuleReferences
  alias PortfolixirWeb.StoredText

  @typedoc "What is deleted."
  @type kind :: :classification | :category | :view

  @typedoc """
  The subject box: the name, the line under it, and one or two figures on
  the right, each text or safe markup, built by the page from the row the
  operator chose.
  """
  @type subject :: %{
          required(:name) => String.t(),
          optional(:ids) => term(),
          optional(:figure) => term(),
          optional(:figure2) => term()
        }

  @typedoc """
  The open dialog. `state` is `:removes` (the dry run's answer, `removed`,
  listed), `:refused` (the policy rules that read the subject, `rules`) or
  `:concurrent` (the dry run met a concurrent change and answered nothing).
  `changed?` says that a confirm found the answer changed and deleted
  nothing.
  """
  @type t :: %{
          kind: kind(),
          id: integer(),
          name: String.t(),
          subject: subject(),
          state: :removes | :refused | :concurrent,
          removed: map() | nil,
          rules: [PolicyRuleReferences.rule_reference()],
          changed?: boolean()
        }

  @doc """
  Opens the dialog for deleting `record` (a `Classification`, a `Category`
  or a `View`): runs the delete's dry run as `actor` and nothing else.
  Answers `{:ok, dialog}`, or `{:error, reason}` for a refusal the dialog
  does not show (a built-in tree, a subject that is gone).
  """
  @spec open(Actor.t(), kind(), struct(), subject()) :: {:ok, t()} | {:error, term()}
  def open(%Actor{} = actor, kind, record, subject) do
    actor
    |> dry_run(kind, record)
    |> dialog_for(kind, record, subject, false)
  end

  @doc "The dry run again, for the dialog that met a concurrent change."
  @spec recheck(Actor.t(), t()) :: {:ok, t()} | {:error, term()}
  def recheck(%Actor{} = actor, %{kind: kind, id: id, subject: subject}) do
    case fetch(kind, id) do
      nil -> {:error, :not_found}
      record -> open(actor, kind, record, subject)
    end
  end

  @doc """
  Whether a confirm event's `kind` and `id` name the open dialog's subject,
  and the dialog lists what the delete removes. Anything else — no dialog,
  a refusal, another kind, another id, a value that is no id — is no
  confirm.
  """
  @spec confirms?(t() | nil, term(), term()) :: boolean()
  def confirms?(%{state: :removes, kind: kind, id: id}, kind_param, id_param)
      when is_binary(kind_param) do
    kind_param == Atom.to_string(kind) and LiveParam.fetch_id(id_param) == {:ok, id}
  end

  def confirms?(_dialog, _kind, _id), do: false

  @doc """
  Runs the delete the dialog listed, held to its list, as `actor`.
  Answers `:deleted`; `{:changed, dialog}` when the delete removes other
  rows now, is refused now, or met a concurrent change — nothing deleted,
  the dialog in its new state; `:gone` when the subject is no longer
  stored; or `{:error, reason}`.
  """
  @spec confirm(Actor.t(), t()) :: :deleted | {:changed, t()} | :gone | {:error, term()}
  def confirm(%Actor{} = actor, %{state: :removes, kind: kind, id: id} = dialog) do
    case fetch(kind, id) do
      nil -> :gone
      record -> answer_confirm(held_delete(actor, kind, record, dialog.removed), record, dialog)
    end
  end

  defp answer_confirm({:ok, _removed}, _record, _dialog), do: :deleted
  defp answer_confirm({:error, :not_found}, _record, _dialog), do: :gone

  defp answer_confirm({:error, {:changed, removed}}, record, dialog) do
    if subject_count(dialog.kind, removed) == 0,
      do: :gone,
      else: changed({:ok, removed}, record, dialog)
  end

  defp answer_confirm(other, record, dialog), do: changed(other, record, dialog)

  defp changed(answer, record, dialog) do
    case dialog_for(answer, dialog.kind, record, dialog.subject, true) do
      {:ok, fresh} -> {:changed, fresh}
      {:error, reason} -> {:error, reason}
    end
  end

  # -- the context calls the API makes --------------------------------------------

  defp dry_run(actor, :classification, %Classification{} = classification),
    do: Classifications.dry_run_delete_classification(actor, classification)

  defp dry_run(actor, :category, %Category{} = category),
    do: Classifications.dry_run_delete_category(actor, category)

  defp dry_run(actor, :view, %View{} = view), do: Buckets.dry_run_delete_view(actor, view)

  defp held_delete(actor, :classification, classification, removed),
    do: Classifications.delete_classification(actor, classification, held_to: removed)

  defp held_delete(actor, :category, category, removed),
    do: Classifications.delete_category(actor, category, held_to: removed)

  defp held_delete(actor, :view, view, removed),
    do: Buckets.delete_view(actor, view, held_to: removed)

  defp fetch(:classification, id), do: Classifications.get_classification(id)
  defp fetch(:category, id), do: Classifications.get_category(id)
  defp fetch(:view, id), do: Buckets.get_view(id)

  # The subject's own row among what the delete removes: none means the
  # subject was gone before the delete ran.
  defp subject_count(:classification, removed), do: count(removed, :classifications)
  defp subject_count(:category, removed), do: count(removed, :categories)
  defp subject_count(:view, removed), do: count(removed, :views)

  defp count(removed, kind) do
    case Map.get(removed, kind) do
      %{count: count} -> count
      nil -> 0
    end
  end

  # The dry run's answer as the dialog's state; a refusal the dialog does
  # not show stays the page's.
  defp dialog_for({:ok, removed}, kind, record, subject, changed?),
    do: {:ok, base(kind, record, subject, :removes, changed?) |> Map.put(:removed, removed)}

  defp dialog_for({:error, {:policy_rules, rules}}, kind, record, subject, changed?) do
    {:ok,
     kind
     |> base(record, subject, :refused, changed?)
     |> Map.put(:rules, PolicyRuleReferences.references(rules))}
  end

  # The concurrent note says itself that nothing was deleted.
  defp dialog_for({:error, :concurrent_change}, kind, record, subject, _changed?),
    do: {:ok, base(kind, record, subject, :concurrent, false)}

  defp dialog_for({:error, reason}, _kind, _record, _subject, _changed?), do: {:error, reason}

  defp base(kind, record, subject, state, changed?) do
    %{
      kind: kind,
      id: record.id,
      name: record.name,
      subject: subject,
      state: state,
      removed: nil,
      rules: [],
      changed?: changed?
    }
  end

  # -- the lines -----------------------------------------------------------------

  @doc """
  The lines under "The delete removes:", in a fixed order, one per kind
  with rows; the subject is in the box and gets no line, a category's own
  row is its line's name ("“Growth” and 1 category below it"), and a
  view's bucket sets are the view itself.
  """
  @spec lines(t()) :: [Phoenix.HTML.safe() | String.t()]
  def lines(%{state: :removes, kind: kind, removed: removed} = dialog) do
    [first_line(kind, removed, dialog.name) | common_lines(removed)]
    |> Enum.reject(&is_nil/1)
  end

  def lines(_dialog), do: []

  defp first_line(:classification, removed, _name) do
    case count(removed, :categories) do
      0 -> nil
      n -> ngettext("%{count} category", "%{count} categories", n)
    end
  end

  defp first_line(:category, removed, name) do
    case count(removed, :categories) - 1 do
      below when below > 0 ->
        StoredText.isolate(
          ngettext(
            "“%{name}” and %{count} category below it",
            "“%{name}” and %{count} categories below it",
            below,
            name: StoredText.slot(:name)
          ),
          name: name
        )

      _none ->
        nil
    end
  end

  defp first_line(:view, _removed, _name), do: nil

  defp common_lines(removed) do
    [
      line(count(removed, :assignments), fn n ->
        ngettext("%{count} security assignment", "%{count} security assignments", n)
      end),
      line(count(removed, :target_plans), fn n ->
        ngettext("%{count} target plan", "%{count} target plans", n)
      end),
      line(count(removed, :targets), fn n ->
        ngettext("%{count} target weight", "%{count} target weights", n)
      end),
      line(count(removed, :depot_snapshots), fn n ->
        ngettext("%{count} snapshot", "%{count} snapshots", n)
      end)
    ]
  end

  defp line(0, _text), do: nil
  defp line(n, text), do: text.(n)

  # -- the words -----------------------------------------------------------------

  defp title(%{state: :refused}), do: gettext("Cannot delete")
  defp title(%{kind: kind}), do: act(kind)

  defp act(:classification), do: gettext("Delete classification")
  defp act(:category), do: gettext("Delete category")
  defp act(:view), do: gettext("Delete view")

  defp kept(:classification),
    do: gettext("The securities themselves, their bookings and quotes stay.")

  defp kept(:category),
    do:
      gettext(
        "The securities themselves stay; in this classification they then sit under “Unassigned”."
      )

  defp kept(:view), do: gettext("The buckets and their assignments stay.")

  # -- the dialog ------------------------------------------------------------------

  attr(:dialog, :map, required: true)

  attr(:focus_fallback, :string,
    required: true,
    doc: "where the focus goes when the dialog closes and its opener is gone"
  )

  attr(:focus_result, :string,
    default: nil,
    doc: "the page's result slot, brought into view when the dialog closes"
  )

  @doc "The dialog for what `open/4` built."
  def dialog(assigns) do
    assigns = assign(assigns, :lines, lines(assigns.dialog))

    ~H"""
    <dialog
      id="delete-preview-dialog"
      class={[
        "modal booking-delete-dialog",
        @dialog.state == :refused && "confirm-delete-blocked"
      ]}
      phx-hook="ModalDialog"
      data-close-event="cancel_delete_preview"
      data-focus-fallback={@focus_fallback}
      data-focus-result={@focus_result}
      aria-labelledby="delete-preview-title"
      aria-describedby="delete-preview-subject"
    >
      <header class="modal-head">
        <h2 id="delete-preview-title"><%= title(@dialog) %></h2>
        <button
          type="button"
          class="icon-button"
          aria-label={gettext("Close")}
          phx-click="cancel_delete_preview"
        >
          <AppShell.icon name={:x} />
        </button>
      </header>
      <div class="modal-body">
        <%!-- The confirm found the answer changed: nothing was deleted and
             the dialog shows the new state, the split delete's shape. --%>
        <div role="status" class="booking-delete__region"><AppShell.data_note
            :if={@dialog.changed?}
            severity={:attention}
            data-role="delete-preview-changed"
          ><%= gettext(
              "What the delete removes changed while this dialog was open. Nothing was deleted; the dialog now shows the new state."
            ) %></AppShell.data_note><AppShell.data_note
            :if={@dialog.state == :concurrent}
            severity={:attention}
            data-role="delete-preview-concurrent"
          ><%= gettext(
              "Something changed while the check ran, and nothing was deleted. Check again to see what the delete removes now."
            ) %></AppShell.data_note></div>
        <p
          id="delete-preview-subject"
          class="booking-delete__subject"
          data-role="delete-preview-subject"
        >
          <span class="phone-row__body">
            <span class="phone-row__name"><bdi><%= @dialog.subject.name %></bdi></span>
            <span :if={@dialog.subject[:ids]} class="phone-row__ids"><span><%= @dialog.subject.ids %></span></span>
          </span>
          <span :if={@dialog.subject[:figure]} class="phone-row__figures">
            <span class="phone-row__figure"><%= @dialog.subject.figure %></span>
            <span :if={@dialog.subject[:figure2]} class="phone-row__figure2">
              <%= @dialog.subject.figure2 %>
            </span>
          </span>
        </p>
        <%= case @dialog.state do %>
          <% :refused -> %>
            <p>
              <%= StoredText.isolate(
                gettext("%{name} is read by policy rules:", name: StoredText.slot(:name)),
                name: @dialog.subject.name
              ) %>
            </p>
            <ul data-role="delete-preview-rules">
              <li :for={reference <- @dialog.rules}>
                <PolicyRuleReferences.rule reference={reference} />
              </li>
            </ul>
            <p class="muted" data-role="delete-preview-refusal-why">
              <%= gettext(
                "A rule that has been in force keeps its subject as part of its history, so the delete stays blocked; retiring the rule on Wealth → Risk stops its evaluation."
              ) %>
            </p>
          <% :concurrent -> %>
          <% :removes -> %>
            <div :if={@lines != []} class="delete-preview" data-role="delete-preview-removes">
              <p class="delete-preview__lead"><%= gettext("The delete removes:") %></p>
              <ul class="delete-preview__list">
                <li :for={line <- @lines}><%= line %></li>
              </ul>
            </div>
            <p
              :if={@lines == []}
              class="hint delete-preview__nothing"
              data-role="delete-preview-nothing"
            >
              <%= gettext("Nothing else is removed with it.") %>
            </p>
            <p class="hint" data-role="delete-preview-kept"><%= kept(@dialog.kind) %></p>
            <p class="hint" data-role="delete-preview-journal">
              <%= gettext(
                "The audit journal records each deletion with every value; none of it can be restored."
              ) %>
            </p>
        <% end %>
      </div>
      <div class="modal-footer modal-footer--band">
        <%= case @dialog.state do %>
          <% :refused -> %>
            <button
              type="button"
              class="button-ghost"
              data-role="delete-preview-cancel"
              phx-click="cancel_delete_preview"
              autofocus
            >
              <%= gettext("Close") %>
            </button>
          <% :concurrent -> %>
            <button
              type="button"
              class="button-ghost"
              data-role="delete-preview-cancel"
              phx-click="cancel_delete_preview"
              autofocus
            >
              <%= gettext("Cancel") %>
            </button>
            <span class="modal-footer__spacer"></span>
            <button
              type="button"
              class="button-primary"
              data-role="delete-preview-recheck"
              phx-click="recheck_delete_preview"
            >
              <%= gettext("Check again") %>
            </button>
          <% :removes -> %>
            <button
              type="button"
              class="button-ghost"
              data-role="delete-preview-cancel"
              phx-click="cancel_delete_preview"
              autofocus
            >
              <%= gettext("Cancel") %>
            </button>
            <span class="modal-footer__spacer"></span>
            <button
              type="button"
              id="delete-preview-confirm"
              class="button-danger"
              phx-click="confirm_delete_preview"
              phx-value-kind={@dialog.kind}
              phx-value-id={@dialog.id}
            >
              <%= act(@dialog.kind) %>
            </button>
        <% end %>
      </div>
    </dialog>
    """
  end
end
