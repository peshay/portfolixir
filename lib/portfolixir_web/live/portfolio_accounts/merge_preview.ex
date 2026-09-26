defmodule PortfolixirWeb.PortfolioAccounts.MergePreview do
  @moduledoc """
  Step 2 of the account merge (ADR-0050 §7, §8, §10; board 02-merge-preview,
  pick G2-B; the three lines board 13 adds): the preview of exactly one pair,
  rendered from `Portfolixir.Lifecycle.preview_cash_merge/2` or
  `preview_depot_merge/2` and nothing else, so what the operator reads is
  what the plan digest covers.

  A cash merge states the balances as a sum (source + target = after, and the
  balance if the equal bookings are removed), the counts, every restated
  balance anchor as "set + other account = after", the equal bookings with a
  choice nothing preselects — each option stating the balance it leads to,
  and "remove as duplicates" what it changes outside the two accounts — the
  former-name note and the deletion warning. A depot merge states each
  affected position's quantity, moving-average cost and realized result
  before and after, and the rounding a split leaves once two positions
  combine. The figures that depend on the choice follow it; with no choice
  made they read "keep both".

  A refusal names its reason in the operator's language and its remedy,
  with "Check again" and no confirm (board 02, "Abgelehnt · Depot"); a plan
  that changed while the preview was open is the fresh preview under an
  attention note saying what changed (board 02, "Veraltet").
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Catalog
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.TransactionKindLabel

  attr(:kind, :string, required: true)
  attr(:source, :map, required: true)
  attr(:target, :map, required: true)
  attr(:preview, :map, default: nil)
  attr(:refused, :list, default: nil)
  attr(:collapse, :any, default: nil)
  attr(:stale, :list, default: nil)
  attr(:problem, :string, default: nil)
  attr(:bucket_names, :map, required: true)
  attr(:myself, :any, required: true)

  def step(assigns) do
    ~H"""
    <div class="modal-body">
      <%!-- One live region each (UX-DR17: politeness per region, never per
           note): the fresh preview after a changed plan is status, a
           refusal of the confirm just pressed is an alert. --%>
      <div role="status" class="merge-region"><AppShell.data_note
          :if={@stale}
          severity={:attention}
          data-role="merge-stale"
        >
          <%= gettext(
            "The accounts changed while the preview was open. Nothing was merged; the preview now shows the new state."
          ) %>
          <span :if={@stale != []} class="merge-stale__changes">
            <%= gettext("Changed since opening: %{changes}", changes: Enum.join(@stale, "; ")) %>
          </span>
        </AppShell.data_note></div>
      <div role="alert" class="merge-region"><AppShell.data_note
          :if={@problem}
          severity={:problem}
          data-role="merge-problem"
        ><%= @problem %></AppShell.data_note></div>
      <div class="merge-route" data-role="merge-route">
        <b><%= @source.name %></b>
        <span class="merge-route__arrow" aria-hidden="true">→</span>
        <span class="visually-hidden"><%= gettext("into") %></span>
        <b><%= @target && @target.name %></b>
        <span :if={@kind == "cash" and @target} class="merge-route__meta">
          <%= @target.currency_code %> · <%= role_label(@target.liquidity_role) %>
        </span>
        <span :if={@kind == "depot" and @preview} class="merge-route__meta">
          <%= gettext("Buckets: %{names}", names: bucket_names(@preview.target.bucket_ids, @bucket_names)) %>
        </span>
      </div>
      <%= cond do %>
        <% @refused -> %>
          <.refusal kind={@kind} guards={@refused} source={@source} target={@target} bucket_names={@bucket_names} myself={@myself} />
        <% @preview && @kind == "cash" -> %>
          <.cash_preview preview={@preview} collapse={@collapse} myself={@myself} />
        <% @preview -> %>
          <.depot_preview preview={@preview} collapse={@collapse} myself={@myself} />
        <% true -> %>
      <% end %>
    </div>
    <div class="modal-footer modal-footer--band">
      <button type="button" class="button-ghost" data-role="merge-back" phx-click="back" phx-target={@myself}>
        <%= gettext("Back") %>
      </button>
      <span class="modal-footer__spacer"></span>
      <%= if @preview && is_nil(@refused) do %>
        <p :if={@preview.choice_required and is_nil(@collapse)} class="merge-footer__why" data-role="merge-why">
          <%= ngettext(
            "Choice for the equal booking missing",
            "Choice for %{count} equal bookings missing",
            length(@preview.key_equal_pairs)
          ) %>
        </p>
        <button
          type="button"
          class="button-danger"
          data-role="merge-confirm"
          phx-click="confirm"
          phx-target={@myself}
          disabled={@preview.choice_required and is_nil(@collapse)}
        >
          <%= gettext("Merge into %{name}", name: @target.name) %>
        </button>
      <% else %>
        <button type="button" class="button-ghost" data-role="merge-close" phx-click="close" phx-target={@myself}>
          <%= gettext("Close") %>
        </button>
      <% end %>
    </div>
    """
  end

  # -- cash -----------------------------------------------------------------------

  attr(:preview, :map, required: true)
  attr(:collapse, :any, default: nil)
  attr(:myself, :any, required: true)

  defp cash_preview(assigns) do
    preview = assigns.preview
    keep = Map.fetch!(preview.outcomes, false)
    collapsed = Map.fetch!(preview.outcomes, true)
    outcome = Map.fetch!(preview.outcomes, assigns.collapse == true)

    assigns =
      assign(assigns,
        currency: preview.target.currency_code,
        keep: keep,
        collapsed: collapsed,
        outcome: outcome,
        pairs: preview.key_equal_pairs,
        restated: Enum.filter(outcome.restated_anchors, &restated?/1),
        folded: Enum.count(outcome.deleted, &(&1.reason == :folded_anchor)),
        names: %{source: preview.source.name, target: preview.target.name}
      )

    ~H"""
    <div class="merge-identity" data-role="merge-identity">
      <div class="merge-identity__term">
        <i><%= @names.source %></i>
        <b class="num"><%= Format.money(@preview.source.balance) %><small><%= @currency %></small></b>
      </div>
      <span class="merge-identity__op" aria-hidden="true">+</span>
      <div class="merge-identity__term">
        <i><%= @names.target %></i>
        <b class="num"><%= Format.money(@preview.target.balance) %><small><%= @currency %></small></b>
      </div>
      <span class="merge-identity__op" aria-hidden="true">=</span>
      <div class="merge-identity__term merge-identity__result">
        <i><%= gettext("%{name} after", name: @names.target) %></i>
        <b class="num"><%= Format.money(@keep.balance) %><small><%= @currency %></small></b>
      </div>
      <p :if={@pairs != []} class="merge-identity__alt">
        <%= ngettext(
          "%{amount} %{currency} if the equal booking is removed (%{difference})",
          "%{amount} %{currency} if the %{count} equal bookings are removed (%{difference})",
          length(@pairs),
          amount: Format.money(@collapsed.balance),
          currency: @currency,
          difference: Format.signed_decimal(Decimal.sub(@collapsed.balance, @keep.balance), 2)
        ) %>
      </p>
    </div>
    <p class="merge-basis">
      <%= gettext(
        "Balances as of %{date}, computed from the bookings. The sum holds on every day either account has a booking and is checked before anything is saved.",
        date: Format.date(Portfolixir.Clock.today())
      ) %>
    </p>
    <dl class="merge-counts" data-role="merge-counts">
      <dt><%= length(@outcome.moved_transaction_ids) %></dt>
      <dd>
        <%= ngettext("booking moves to %{name}", "bookings move to %{name}", length(@outcome.moved_transaction_ids), name: @names.target) %>
      </dd>
      <%= if @preview.internal_transfers != [] do %>
        <dt><%= length(@preview.internal_transfers) %></dt>
        <dd>
          <%= ngettext(
            "transfer between the two accounts is dropped",
            "transfers between the two accounts are dropped",
            length(@preview.internal_transfers)
          ) %>
          <small><%= gettext("— they cancel out in the balance") %></small>
        </dd>
      <% end %>
      <%= if @restated != [] or @folded > 0 do %>
        <dt><%= length(@restated) %></dt>
        <dd>
          <%= ngettext("set balance is adjusted", "set balances are adjusted", length(@restated)) %><%= if @folded > 0,
            do: ngettext(", %{count} is dropped", ", %{count} are dropped", @folded) %>
          <small><%= gettext("— table") %></small>
        </dd>
      <% end %>
      <%= if @pairs != [] do %>
        <dt><%= length(@pairs) %></dt>
        <dd>
          <%= ngettext("booking is equal in both accounts", "bookings are equal in both accounts", length(@pairs)) %>
          <small><%= gettext("— choice below") %></small>
        </dd>
      <% end %>
      <%= if @preview.linked_depots != [] do %>
        <dt><%= length(@preview.linked_depots) %></dt>
        <dd>
          <%= ngettext("linked depot moves to %{name}", "linked depots move to %{name}", length(@preview.linked_depots), name: @names.target) %>
          <small>— <%= Enum.map_join(@preview.linked_depots, ", ", & &1.name) %></small>
        </dd>
      <% end %>
    </dl>
    <%= if @restated != [] do %>
      <h3 class="merge-block-head">
        <%= gettext("Set balances") %>
        <small><%= gettext("adjusted so the merged history holds") %></small>
      </h3>
      <div class="data-table-wrapper merge-wide">
        <table class="data-table merge-anchors">
          <thead>
            <tr>
              <th><%= gettext("Date") %></th>
              <th><%= gettext("Account") %></th>
              <th class="num"><%= gettext("Set") %></th>
              <th class="num"><%= gettext("+ other account") %></th>
              <th class="num"><%= gettext("After") %></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={anchor <- @restated} data-role="restated-anchor" data-id={anchor.id}>
              <td><%= Date.to_iso8601(anchor.date) %></td>
              <td>
                <%= Map.fetch!(@names, anchor.side) %>
                <small :if={anchor.folds != []}>
                  <%= gettext("the one of %{name} on this day is dropped", name: @names.source) %>
                </small>
              </td>
              <td class="num"><%= Format.money(anchor.stated) %></td>
              <td class="num"><%= Format.money(anchor.other_balance) %></td>
              <td class="num merge-anchors__after"><%= Format.money(anchor.after) %></td>
            </tr>
          </tbody>
        </table>
      </div>
      <%!-- Under 720 px the table becomes two-line rows with the sum
           "set + other account = after" (board 02 at 390 px). --%>
      <ul class="merge-lines merge-narrow">
        <li :for={anchor <- @restated}>
          <span class="merge-lines__head">
            <%= Date.to_iso8601(anchor.date) %> · <%= Map.fetch!(@names, anchor.side) %>
          </span>
          <span class="merge-lines__figure num">
            <%= Format.money(anchor.stated) %> + <%= Format.money(anchor.other_balance) %> =
            <b><%= Format.money(anchor.after) %></b>
            <small :if={anchor.folds != []}>
              <%= gettext("the one of %{name} on this day is dropped", name: @names.source) %>
            </small>
          </span>
        </li>
      </ul>
      <p class="merge-basis">
        <%= gettext(
          "“+ other account”: the other account's balance at the end of that day, from its bookings before the merge. On a day with two set balances, the target's carries the sum."
        ) %>
      </p>
    <% end %>
    <.pair_choice
      :if={@pairs != []}
      kind="cash"
      pairs={@pairs}
      collapse={@collapse}
      names={@names}
      currency={@currency}
      keep={@keep}
      collapsed={@collapsed}
      extra={collapse_effects(@collapsed, @names.source)}
      myself={@myself}
    />
    <.merge_notes kind="cash" preview={@preview} names={@names} />
    """
  end

  # A restated anchor is listed where the merge changes it: its amount, or
  # the anchors of its day it absorbs.
  defp restated?(anchor),
    do: anchor.folds != [] or not Decimal.equal?(anchor.stated, anchor.after)

  # -- depot ----------------------------------------------------------------------

  attr(:preview, :map, required: true)
  attr(:collapse, :any, default: nil)
  attr(:myself, :any, required: true)

  defp depot_preview(assigns) do
    preview = assigns.preview
    outcome = Map.fetch!(preview.outcomes, assigns.collapse == true)
    names = %{source: preview.source.name, target: preview.target.name}

    assigns =
      assign(assigns,
        outcome: outcome,
        names: names,
        pairs: preview.key_equal_pairs,
        security_names: security_names(preview),
        keep: Map.fetch!(preview.outcomes, false),
        collapsed: Map.fetch!(preview.outcomes, true)
      )

    ~H"""
    <dl class="merge-counts" data-role="merge-counts">
      <dt><%= length(@outcome.moved_transaction_ids) %></dt>
      <dd>
        <%= ngettext("booking moves to %{name}", "bookings move to %{name}", length(@outcome.moved_transaction_ids), name: @names.target) %>
      </dd>
      <%= if @preview.internal_transfers != [] do %>
        <dt><%= length(@preview.internal_transfers) %></dt>
        <dd>
          <%= ngettext(
            "security transfer between the two depots is dropped",
            "security transfers between the two depots are dropped",
            length(@preview.internal_transfers)
          ) %>
        </dd>
      <% end %>
      <dt><%= length(@pairs) %></dt>
      <dd><%= ngettext("equal booking", "equal bookings", length(@pairs)) %></dd>
    </dl>
    <%= if @outcome.positions != [] do %>
      <h3 class="merge-block-head"><%= gettext("Affected positions") %></h3>
      <div class="data-table-wrapper">
        <table class="data-table merge-positions">
          <thead>
            <tr>
              <th><%= gettext("Security") %></th>
              <th class="num"><%= gettext("Quantity") %></th>
              <th class="num"><%= gettext("Avg. cost") %></th>
              <th class="num"><%= gettext("Realized gain/loss") %></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={position <- @outcome.positions} data-role="merge-position" data-id={position.security_id}>
              <td><%= position.security_name %></td>
              <td class="num">
                <small><%= quantity(position.source) %> + <%= quantity(position.target) %> →</small>
                <b><%= quantity(position.after) %></b>
              </td>
              <td class="num">
                <small><%= money(position.source, :avg_cost) %> · <%= money(position.target, :avg_cost) %> →</small>
                <b><%= money(position.after, :avg_cost) %></b>
              </td>
              <td class="num">
                <small><%= money(position.source, :realized_result) %> · <%= money(position.target, :realized_result) %> →</small>
                <b><%= money(position.after, :realized_result) %></b>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p class="merge-basis">
        <%= gettext(
          "In each cell before above (%{source} + %{target}, or %{source} · %{target}), after below. Average cost and realized gain/loss in the security's currency, a moving average over both depots' buys, fees and taxes not included. Quantity per security = the sum of both depots, checked on every day; the market value of both depots together stays the same.",
          source: @names.source,
          target: @names.target
        ) %>
      </p>
      <ul :if={@outcome.rounding_differences != []} class="merge-rounding merge-basis" data-role="merge-rounding">
        <li :for={line <- @outcome.rounding_differences}>
          <%= gettext(
            "Rounding at a split: %{security} on %{date} (%{ratio}) — combined %{combined}, rounded apart %{separate} (%{difference}). Expected, not a refusal.",
            security: line.security_name,
            date: Date.to_iso8601(line.date),
            ratio: "#{line.ratio.numerator}:#{line.ratio.denominator}",
            combined: Format.exact(line.combined),
            separate: Format.exact(line.separate_sum),
            difference: signed_exact(line.difference)
          ) %>
        </li>
      </ul>
    <% end %>
    <.pair_choice
      :if={@pairs != []}
      kind="depot"
      pairs={@pairs}
      collapse={@collapse}
      names={@names}
      security_names={@security_names}
      keep={@keep}
      collapsed={@collapsed}
      extra={depot_collapse_effects(@collapsed)}
      myself={@myself}
    />
    <.merge_notes kind="depot" preview={@preview} names={@names} />
    """
  end

  defp quantity(nil), do: "0"
  defp quantity(figures), do: Format.exact(figures.quantity)

  defp money(nil, _field), do: "—"
  defp money(figures, field), do: Format.money(Map.get(figures, field))

  defp signed_exact(%Decimal{} = value) do
    formatted = Format.exact(value)
    if Decimal.compare(value, 0) == :gt, do: "+" <> formatted, else: formatted
  end

  defp security_names(preview) do
    ids = preview.key_equal_pairs |> Enum.map(& &1.security_id) |> Enum.reject(&is_nil/1)

    Map.new(ids, fn id ->
      {id, (Catalog.get_security(id) || %{name: "##{id}"}).name}
    end)
  end

  # -- the equal bookings' choice (§8) ----------------------------------------------

  attr(:kind, :string, required: true)
  attr(:pairs, :list, required: true)
  attr(:collapse, :any, required: true)
  attr(:names, :map, required: true)
  attr(:currency, :string, default: nil)
  attr(:security_names, :map, default: %{})
  attr(:keep, :map, required: true)
  attr(:collapsed, :map, required: true)
  attr(:extra, :list, default: [])
  attr(:myself, :any, required: true)

  defp pair_choice(assigns) do
    ~H"""
    <form id="merge-choice-form" data-role="merge-choice-form" phx-change="choose" phx-target={@myself}>
      <fieldset class="merge-choice" data-role="merge-pairs">
        <legend>
          <%= ngettext(
            "%{count} equal booking in both accounts",
            "%{count} equal bookings in both accounts",
            length(@pairs)
          ) %>
        </legend>
        <div class="data-table-wrapper merge-wide">
          <table class="data-table">
            <thead>
              <tr>
                <th><%= gettext("Date") %></th>
                <th><%= gettext("Kind") %></th>
                <th :if={@kind == "depot"}><%= gettext("Security") %></th>
                <th class="num"><%= gettext("Amount") %></th>
                <th><%= gettext("Stands in") %></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={pair <- @pairs}>
                <td><%= Date.to_iso8601(pair.date) %></td>
                <td><%= TransactionKindLabel.label(pair.type) %></td>
                <td :if={@kind == "depot"}><%= Map.get(@security_names, pair.security_id) %></td>
                <td class="num"><%= pair_amount(pair, @currency) %></td>
                <td><%= gettext("%{source} and %{target}", source: @names.source, target: @names.target) %></td>
              </tr>
            </tbody>
          </table>
        </div>
        <ul class="merge-lines merge-narrow">
          <li :for={pair <- @pairs}>
            <span class="merge-lines__head">
              <%= Date.to_iso8601(pair.date) %> · <%= TransactionKindLabel.label(pair.type) %>
              <%= if @kind == "depot", do: " · " <> (Map.get(@security_names, pair.security_id) || "") %>
            </span>
            <span class="merge-lines__figure num">
              <%= pair_amount(pair, @currency) %>
              <small><%= gettext("in %{source} and %{target}", source: @names.source, target: @names.target) %></small>
            </span>
          </li>
        </ul>
        <label class={["merge-option", @collapse == true && "is-on"]} data-role="collapse-true">
          <input type="radio" name="merge[collapse]" value="true" checked={@collapse == true} />
          <span>
            <%= gettext("remove as duplicates") %>
            <small>
              <%= ngettext(
                "The booking from %{source} is deleted.",
                "The %{count} bookings from %{source} are deleted.",
                length(@pairs),
                source: @names.source
              ) %>
              <%= if @kind == "cash" do %>
                <%= gettext("Balance after") %> <b><%= Format.money(@collapsed.balance) %> <%= @currency %></b>.
              <% end %>
            </small>
            <small :if={@extra != []} class="merge-option__extra">
              <%= gettext("Also changes: %{changes}", changes: Enum.join(@extra, " · ")) %>
            </small>
          </span>
        </label>
        <label class={["merge-option", @collapse == false && "is-on"]} data-role="collapse-false">
          <input type="radio" name="merge[collapse]" value="false" checked={@collapse == false} />
          <span>
            <%= gettext("keep both") %>
            <small>
              <%= gettext("Every booking stands in %{target} afterwards.", target: @names.target) %>
              <%= if @kind == "cash" do %>
                <%= gettext("Balance after") %> <b><%= Format.money(@keep.balance) %> <%= @currency %></b>.
              <% end %>
            </small>
          </span>
        </label>
        <p class="merge-basis"><%= gettext("Equal means: same day, same kind, same amounts.") %></p>
      </fieldset>
    </form>
    """
  end

  defp pair_amount(%{gross_amount: %Decimal{} = amount}, currency) when is_binary(currency),
    do: "#{Format.money(amount)} #{currency}"

  defp pair_amount(%{gross_amount: %Decimal{} = amount}, _currency), do: Format.money(amount)

  defp pair_amount(%{quantity: %Decimal{} = quantity}, _currency),
    do: gettext("%{quantity} shares", quantity: Format.exact(quantity))

  defp pair_amount(_pair, _currency), do: "—"

  # What removing the duplicates changes outside the two accounts (§16
  # invariant 9, board 13): a third account's balance, a position's
  # quantity, a flow one of the source's set balances absorbs.
  defp collapse_effects(outcome, source_name) do
    accounts =
      Enum.map(outcome.other_accounts, fn account ->
        "#{account.name} #{Format.money(account.balance_before)} → #{Format.money(account.balance_after)}"
      end)

    positions =
      Enum.map(outcome.positions, fn position ->
        security = Catalog.get_security(position.security_id)
        depot = Portfolios.get_securities_account(position.securities_account_id)

        gettext("%{security} in %{depot} %{change} shares",
          security: security && security.name,
          depot: depot && depot.name,
          change: signed_exact(position.quantity_change)
        )
      end)

    # The source's own set balances, and a third account's for a collapsed
    # transfer with it.
    names = Map.new(outcome.other_accounts, &{&1.id, &1.name})

    accounts ++
      positions ++ absorbed_lines(outcome.flow_changes, &Map.get(names, &1, source_name))
  end

  defp depot_collapse_effects(outcome) do
    names = Map.new(outcome.cash_accounts, &{&1.id, &1.name})

    accounts =
      Enum.map(outcome.cash_accounts, fn account ->
        "#{account.name} #{Format.money(account.balance_before)} → #{Format.money(account.balance_after)}"
      end)

    # A third depot a collapsed transfer names (board 13's position line).
    depots =
      Enum.map(outcome.other_depots, fn position ->
        gettext("%{security} in %{depot} %{change} shares",
          security: position.security_name,
          depot: position.securities_account_name,
          change: signed_exact(Decimal.sub(position.quantity_after, position.quantity_before))
        )
      end)

    accounts ++ depots ++ absorbed_lines(outcome.flow_changes, &Map.get(names, &1, "##{&1}"))
  end

  @doc """
  One phrase per flow a collapse moves into a set balance (§16 invariant 9):
  "a set balance of <account> on <date> absorbs <amount>", the account named
  by `name_of`.
  """
  @spec absorbed_lines([map()], (term() -> String.t())) :: [String.t()]
  def absorbed_lines(flow_changes, name_of) do
    for %{kind: :absorbed} = change <- flow_changes do
      gettext("a set balance of %{name} on %{date} absorbs %{amount}",
        name: name_of.(change.cash_account_id),
        date: Date.to_iso8601(change.date),
        amount: Format.money(change.change)
      )
    end
  end

  # -- the notes ------------------------------------------------------------------

  attr(:kind, :string, required: true)
  attr(:preview, :map, required: true)
  attr(:names, :map, required: true)

  defp merge_notes(assigns) do
    assigns =
      assign(assigns,
        appended: assigns.preview.former_names.appended,
        not_kept: assigns.preview.former_names.not_kept
      )

    ~H"""
    <AppShell.data_note severity={:note}>
      <%= former_names_sentence(@appended, @names.target) %>
      <%= for entry <- @not_kept do %>
        <%= gettext("“%{name}” is not kept: an import that names it already books to another account.",
          name: entry.name
        ) %>
      <% end %>
      <%= if @kind == "depot" do %>
        <%= gettext(
          "%{target} keeps its cash account; the cash account of %{source} stays an account of its own.",
          target: @names.target,
          source: @names.source
        ) %>
      <% end %>
    </AppShell.data_note>
    <AppShell.data_note severity={:attention}>
      <%= gettext(
        "%{source} is deleted afterwards. This cannot be undone; every changed booking is journaled.",
        source: @names.source
      ) %>
    </AppShell.data_note>
    """
  end

  defp former_names_sentence([], _target), do: nil

  defp former_names_sentence([name], target) do
    gettext(
      "“%{name}” becomes a former name of %{target}. An import that names this account books to %{target} afterwards.",
      name: name,
      target: target
    )
  end

  defp former_names_sentence(names, target) do
    gettext(
      "%{names} become former names of %{target}. An import that names them books to %{target} afterwards.",
      names: Enum.map_join(names, ", ", &"“#{&1}”"),
      target: target
    )
  end

  # -- the refusal ------------------------------------------------------------------

  attr(:kind, :string, required: true)
  attr(:guards, :list, required: true)
  attr(:source, :map, required: true)
  attr(:target, :map, default: nil)
  attr(:bucket_names, :map, required: true)
  attr(:myself, :any, required: true)

  defp refusal(assigns) do
    failed = Enum.find(assigns.guards, &(not &1.passed))
    assigns = assign(assigns, failed: failed)

    ~H"""
    <AppShell.data_note severity={:problem} data-role="merge-refused">
      <p class="merge-refusal__lead">
        <%= gettext("Merging is not possible: %{reason}", reason: refusal_reason(@failed, @kind)) %>
      </p>
      <p :for={position <- Map.get(@failed, :positions, [])} class="merge-refusal__position">
        <b><%= position.security_name %></b>
        — <%= @source.name %>: <%= bucket_names(position.source_buckets, @bucket_names) %>
        · <%= @target && @target.name %>: <%= bucket_names(position.target_buckets, @bucket_names) %>
      </p>
      <p class="merge-refusal__remedy"><%= refusal_remedy(@failed.code) %></p>
      <button type="button" class="button" data-role="merge-recheck" phx-click="recheck" phx-target={@myself}>
        <%= gettext("Check again") %>
      </button>
    </AppShell.data_note>
    """
  end

  defp bucket_names([], _names), do: gettext("no buckets")

  defp bucket_names(ids, names),
    do: ids |> Enum.map(&Map.get(names, &1, "##{&1}")) |> Enum.sort() |> Enum.join(", ")

  defp refusal_reason(%{code: :position_buckets_mismatch, positions: positions}, _kind) do
    ngettext(
      "for %{count} position the buckets differ, so the views would change retroactively.",
      "for %{count} positions the buckets differ, so the views would change retroactively.",
      length(positions)
    )
  end

  defp refusal_reason(%{code: :same_account}, "cash"),
    do: gettext("an account cannot be merged into itself.")

  defp refusal_reason(%{code: :same_account}, "depot"),
    do: gettext("a depot cannot be merged into itself.")

  defp refusal_reason(%{code: :not_live}, _kind), do: gettext("the target no longer exists.")

  defp refusal_reason(%{code: :portfolio_mismatch}, _kind),
    do: gettext("the two belong to different portfolio records.")

  defp refusal_reason(%{code: :currency_mismatch}, _kind),
    do: gettext("the accounts hold different currencies, and a merge never converts an amount.")

  defp refusal_reason(%{code: :liquidity_role_mismatch}, _kind),
    do: gettext("the accounts have different liquidity roles.")

  defp refusal_reason(%{code: :buckets_mismatch}, _kind),
    do: gettext("the two sit in different buckets, so the views would change retroactively.")

  defp refusal_reason(%{code: :legacy_hashed_anchor}, _kind),
    do:
      gettext(
        "a set balance still carries an import hash from before the import-hash check and cannot be adjusted."
      )

  defp refusal_reason(_guard, _kind), do: gettext("a check of the merge did not hold.")

  defp refusal_remedy(:position_buckets_mismatch),
    do: gettext("Remedy: give the position the same buckets in both depots, then check again.")

  defp refusal_remedy(:legacy_hashed_anchor),
    do:
      gettext(
        "Remedy: change that booking's kind back to the one it was imported as, or delete it, then check again."
      )

  defp refusal_remedy(:not_live), do: gettext("Remedy: go back and choose another target.")

  defp refusal_remedy(_code),
    do: gettext("Remedy: align the two, or go back and choose another target, then check again.")

  # -- shared ---------------------------------------------------------------------

  @doc "The liquidity role's label, as the accounts table names it."
  @spec role_label(String.t()) :: String.t()
  def role_label("free_cash"), do: gettext("Free cash")
  def role_label("credit_line"), do: gettext("Credit line")
  def role_label("reserve"), do: gettext("Reserve")
  def role_label(other), do: other

  @doc """
  What changed between the preview the operator read and the fresh one a
  changed plan answered with (board 02, "Veraltet"): each account's balance
  (a cash account) and booking count that moved, as short phrases. Empty when
  the difference is in a row's fields the lines do not name.
  """
  @spec changes(String.t(), map(), map()) :: [String.t()]
  def changes(kind, before, fresh) do
    for side <- [:source, :target],
        change <- side_changes(kind, Map.fetch!(before, side), Map.fetch!(fresh, side)),
        do: change
  end

  defp side_changes("cash", before, fresh) do
    balance =
      if Decimal.equal?(before.balance, fresh.balance),
        do: [],
        else: [
          gettext("balance of %{name} %{before} → %{after} %{currency}",
            name: fresh.name,
            before: Format.money(before.balance),
            after: Format.money(fresh.balance),
            currency: fresh.currency_code
          )
        ]

    balance ++ count_change(before, fresh, balance != [])
  end

  defp side_changes("depot", before, fresh), do: count_change(before, fresh, false)

  defp count_change(_before, _fresh, true), do: []

  defp count_change(%{transaction_count: same}, %{transaction_count: same}, _said), do: []

  defp count_change(before, fresh, _said) do
    [
      gettext("bookings of %{name} %{before} → %{after}",
        name: fresh.name,
        before: before.transaction_count,
        after: fresh.transaction_count
      )
    ]
  end
end
