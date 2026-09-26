defmodule PortfolixirWeb.Securities.MergePreview do
  @moduledoc """
  Step 2 of the security merge (ADR-0050 §8, §9, §10; board
  03-security-merge, pick G3-A): the preview of exactly one pair, rendered
  from `Portfolixir.Lifecycle.preview_security_merge/2` and nothing else, so
  what the operator reads is what the plan digest covers.

  Top to bottom (board 03, "Die Vorschau, von oben nach unten"): the source
  and the target as two cards — the names may be equal, so each names its
  ISIN, bookings and creation date, and the source's role says it is
  deleted; the ISIN choice as two option cards, one consequence line each,
  nothing preselected, the date of the ISIN change inside "Adopt"; holdings
  as a sum with the figure if the equal bookings go; the counts; the equal
  bookings with their unpreselected choice; the colliding manual quotes;
  the source's settings with what becomes of each; the events that stand
  the same in the target; the master data that differ; a note and the
  deletion warning.

  A refusal names each reason in the operator's words and its remedy, with
  "Merge the other way" only where that merge passes, and where it does not
  either, both reasons and no remedy the version does not have.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Buckets
  alias Portfolixir.Catalog.AssetClasses
  alias Portfolixir.Catalog.Feeds
  alias Portfolixir.Clock
  alias Portfolixir.Knowledge
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.PolicyRules
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.PolicyRuleReferences
  alias PortfolixirWeb.PortfolioAccounts.MergePreview, as: AccountMergePreview
  alias PortfolixirWeb.SecuritiesLive
  alias PortfolixirWeb.SecurityEventLabel
  alias PortfolixirWeb.TransactionKindLabel

  @visible_pairs 3

  attr(:source, :map, required: true)
  attr(:target, :map, default: nil)
  attr(:preview, :map, default: nil)
  attr(:refused, :list, default: nil)
  attr(:reverse, :list, default: nil)
  attr(:choices, :map, required: true)
  attr(:field_error, :string, default: nil)
  attr(:stale, :list, default: nil)
  attr(:problem, :string, default: nil)
  attr(:totals, :map, default: %{})
  attr(:myself, :any, required: true)

  def step(assigns) do
    ~H"""
    <div class="modal-body">
      <%!-- One live region each (UX-DR17): the fresh preview after a changed
           plan is status, a refusal of the confirm just pressed an alert. --%>
      <div role="status" class="merge-region"><AppShell.data_note
          :if={@stale}
          severity={:attention}
          data-role="merge-stale"
        >
          <%= gettext(
            "The securities changed while the preview was open. Nothing was merged; the preview now shows the new state."
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
      <.pair :if={@target} source={@source} target={@target} preview={@preview} totals={@totals} />
      <%= cond do %>
        <% @refused -> %>
          <.refusal guards={@refused} reverse={@reverse} source={@source} target={@target} myself={@myself} />
        <% @preview -> %>
          <.body
            source={@source}
            preview={@preview}
            choices={@choices}
            field_error={@field_error}
            totals={@totals}
            myself={@myself}
          />
        <% true -> %>
      <% end %>
    </div>
    <div class="modal-footer modal-footer--band">
      <button type="button" class="button-ghost" data-role="merge-back" phx-click="back" phx-target={@myself}>
        <%= gettext("Back") %>
      </button>
      <span class="modal-footer__spacer"></span>
      <%= if @preview && is_nil(@refused) do %>
        <% missing = missing_choices(@preview, @choices) %>
        <p :if={missing != []} class="merge-footer__why" data-role="merge-why">
          <%= Enum.map_join(missing, " · ", &missing_label(&1, @preview)) %>
        </p>
        <button
          type="button"
          class="button-danger"
          data-role="merge-confirm"
          phx-click="confirm"
          phx-target={@myself}
          disabled={missing != []}
        >
          <%= gettext("Merge into %{name}", name: @preview.target.name) %>
        </button>
      <% else %>
        <button type="button" class="button-ghost" data-role="merge-close" phx-click="close" phx-target={@myself}>
          <%= gettext("Close") %>
        </button>
      <% end %>
    </div>
    """
  end

  # -- the pair -------------------------------------------------------------------

  attr(:source, :map, required: true)
  attr(:target, :map, required: true)
  attr(:preview, :map, default: nil)
  attr(:totals, :map, default: %{})

  # Two cards, because the names can be equal: the ISIN, the bookings and
  # the creation date tell the two apart (board 03, ①).
  defp pair(assigns) do
    ~H"""
    <div class="merge-pair" data-role="merge-pair">
      <div class="merge-pair__side">
        <span class="merge-pair__role merge-pair__role--gone"><%= gettext("Source · deleted") %></span>
        <b><%= @source.name %></b>
        <span :if={@source.isin} class="mono"><%= @source.isin %></span>
        <small><%= side_meta(@source, Map.get(@totals, :source_bookings)) %></small>
      </div>
      <span class="merge-pair__arrow" aria-hidden="true">→</span>
      <span class="visually-hidden"><%= gettext("into") %></span>
      <div class="merge-pair__side">
        <span class="merge-pair__role"><%= gettext("Target · stays") %></span>
        <b><%= @target.name %></b>
        <span :if={@target.isin} class="mono"><%= @target.isin %></span>
        <small><%= side_meta(@target, Map.get(@totals, :target_bookings)) %></small>
      </div>
    </div>
    """
  end

  defp side_meta(security, bookings) do
    [
      bookings && ngettext("%{count} booking", "%{count} bookings", bookings),
      gettext("created %{date}", date: created_on(security))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  @doc "The calendar date a security was created on, ISO 8601, where the instance runs."
  @spec created_on(map()) :: String.t()
  def created_on(%{inserted_at: %NaiveDateTime{} = at}),
    do: at |> DateTime.from_naive!("Etc/UTC") |> Clock.local_date() |> Date.to_iso8601()

  def created_on(_security), do: "—"

  @doc "A security's asset class as the catalog labels it, or nil."
  @spec asset_class_label(map()) :: String.t() | nil
  def asset_class_label(%{asset_class: nil}), do: nil
  def asset_class_label(%{asset_class: code}), do: AssetClasses.label(code)

  # -- the preview's body ----------------------------------------------------------

  attr(:source, :map, required: true)
  attr(:preview, :map, required: true)
  attr(:choices, :map, required: true)
  attr(:field_error, :string, default: nil)
  attr(:totals, :map, default: %{})
  attr(:myself, :any, required: true)

  defp body(assigns) do
    preview = assigns.preview
    collapse? = assigns.choices.collapse == true

    assigns =
      assign(assigns,
        outcome: Map.fetch!(preview.outcomes, collapse?),
        keep: Map.fetch!(preview.outcomes, false),
        collapsed: Map.fetch!(preview.outcomes, true),
        pairs: preview.key_equal_pairs,
        holdings: holdings(preview, assigns.totals),
        names: account_names(preview),
        bucket_names: Map.new(Buckets.list_buckets(), &{&1.id, &1.name}),
        settings: settings(preview)
      )

    ~H"""
    <%!-- One form for every choice of the dialog (board 03, why A). --%>
    <form id="security-merge-choice-form" data-role="merge-choice-form" phx-change="choose" phx-target={@myself}>
      <.identity_choice
        :if={@preview.identifiers.choice_required}
        preview={@preview}
        choices={@choices}
        field_error={@field_error}
      />
      <%!-- pgettext: a bare "Target" is the allocation column ("Soll"). --%>
      <div class="merge-identity" data-role="merge-identity">
        <div class="merge-identity__term">
          <i><%= pgettext("merge side", "Source") %></i>
          <b class="num"><%= Format.exact(@holdings.source) %><small><%= gettext("shares") %></small></b>
        </div>
        <span class="merge-identity__op" aria-hidden="true">+</span>
        <div class="merge-identity__term">
          <i><%= pgettext("merge side", "Target") %></i>
          <b class="num"><%= Format.exact(@holdings.target) %><small><%= gettext("shares") %></small></b>
        </div>
        <span class="merge-identity__op" aria-hidden="true">=</span>
        <div class="merge-identity__term merge-identity__result">
          <i><%= gettext("Holdings afterwards") %></i>
          <b class="num"><%= Format.exact(@holdings.keep) %><small><%= gettext("shares") %></small></b>
        </div>
        <p :if={@pairs != []} class="merge-identity__alt">
          <%= ngettext(
            "%{quantity} shares if the equal booking is removed (%{difference})",
            "%{quantity} shares if the %{count} equal bookings are removed (%{difference})",
            length(@pairs),
            quantity: Format.exact(@holdings.collapsed),
            difference: signed(Decimal.sub(@holdings.collapsed, @holdings.keep))
          ) %>
        </p>
      </div>
      <p class="merge-basis">
        <%= gettext(
          "Holdings in every depot as of %{date}, computed from the bookings. The sum holds per depot on every day and is checked before anything is saved.",
          date: Date.to_iso8601(Clock.today())
        ) %>
      </p>
      <.counts preview={@preview} outcome={@outcome} settings={@settings} />
      <.pair_choice
        :if={@pairs != []}
        pairs={@pairs}
        choices={@choices}
        keep={@keep}
        collapsed={@collapsed}
        holdings={@holdings}
        names={@names}
        currency={@preview.target.currency_code}
      />
    </form>
    <.quote_collisions preview={@preview} />
    <.settings_table :if={@settings != []} settings={@settings} bucket_names={@bucket_names} />
    <.events_table :if={@preview.events.possible_duplicates != []} preview={@preview} />
    <.master_data preview={@preview} />
    <.notes preview={@preview} source={@source} />
    """
  end

  # Holdings in every depot: the target's elsewhere plus, per depot the
  # source holds, the position after either answer to the duplicates.
  defp holdings(preview, totals) do
    source = Map.get(totals, :source, sum(preview.outcomes[false].positions, :source))
    target_total = Map.get(totals, :target, sum(preview.outcomes[false].positions, :target))
    target_in_source_depots = sum(preview.outcomes[false].positions, :target)
    elsewhere = Decimal.sub(target_total, target_in_source_depots)

    %{
      source: source,
      target: target_total,
      keep: Decimal.add(elsewhere, sum(preview.outcomes[false].positions, :after)),
      collapsed: Decimal.add(elsewhere, sum(preview.outcomes[true].positions, :after))
    }
  end

  defp sum(positions, side) do
    Enum.reduce(positions, Decimal.new(0), fn position, acc ->
      case Map.get(position, side) do
        %{quantity: %Decimal{} = quantity} -> Decimal.add(acc, quantity)
        _none -> acc
      end
    end)
  end

  defp signed(%Decimal{} = value) do
    formatted = Format.exact(value)
    if Decimal.compare(value, 0) == :gt, do: "+" <> formatted, else: formatted
  end

  # -- the ISIN choice (G3-A) --------------------------------------------------------

  attr(:preview, :map, required: true)
  attr(:choices, :map, required: true)
  attr(:field_error, :string, default: nil)

  defp identity_choice(assigns) do
    ~H"""
    <fieldset class="merge-choice" data-role="merge-identity-choice">
      <legend><%= gettext("ISIN afterwards") %></legend>
      <label class={["merge-option", @choices.identity == :keep_target_isin && "is-on"]} data-role="identity-keep">
        <input type="radio" name="merge[identity]" value="keep_target_isin" checked={@choices.identity == :keep_target_isin} />
        <span>
          <span class="merge-option__title">
            <%= gettext("Keep %{isin}", isin: @preview.target.isin) %>
            <span class="merge-option__tag"><%= gettext("the target's ISIN") %></span>
          </span>
          <small>
            <%= gettext("%{isin} becomes a former ISIN of this security.", isin: @preview.source.isin) %>
          </small>
        </span>
      </label>
      <label class={["merge-option", @choices.identity == :adopt_source_isin && "is-on"]} data-role="identity-adopt">
        <input type="radio" name="merge[identity]" value="adopt_source_isin" checked={@choices.identity == :adopt_source_isin} />
        <span>
          <span class="merge-option__title">
            <%= gettext("Adopt %{isin}", isin: @preview.source.isin) %>
            <span class="merge-option__tag"><%= gettext("the source's ISIN") %></span>
          </span>
          <small>
            <%= gettext("%{target} becomes a former ISIN; the target carries %{source} afterwards.",
              target: @preview.target.isin,
              source: @preview.source.isin
            ) %>
          </small>
        </span>
      </label>
      <%!-- The date of the ISIN change belongs to "Adopt", so it follows that
           card, only when it is chosen (board 03); a field of its own, not
           inside the radio's label. --%>
      <div :if={@choices.identity == :adopt_source_isin} class="merge-option-field">
        <label for="security-merge-isin-changed-on"><%= gettext("ISIN change on") %></label>
        <input
          type="text"
          id="security-merge-isin-changed-on"
          name="merge[isin_changed_on]"
          value={@choices.isin_changed_on}
          inputmode="numeric"
          autocomplete="off"
          maxlength="10"
          placeholder="YYYY-MM-DD"
          aria-invalid={@field_error && "true"}
          aria-describedby={@field_error && "security-merge-isin-changed-on-error"}
        />
        <span :if={@field_error} id="security-merge-isin-changed-on-error" class="field-error">
          <%= @field_error %>
        </span>
      </div>
    </fieldset>
    """
  end

  # -- counts -----------------------------------------------------------------------

  attr(:preview, :map, required: true)
  attr(:outcome, :map, required: true)
  attr(:settings, :list, required: true)

  defp counts(assigns) do
    assigns =
      assign(assigns,
        moved: length(assigns.outcome.moved_transaction_ids),
        pairs: length(assigns.preview.key_equal_pairs),
        splits: length(assigns.preview.splits.collapsed),
        quotes: assigns.preview.quotes,
        manual: length(assigns.preview.quotes.manual_collisions),
        moving_settings: Enum.count(assigns.settings, &(&1.outcome == :moves)),
        dropped_settings: Enum.count(assigns.settings, &(&1.outcome != :moves)),
        events: length(assigns.preview.events.moved),
        event_twins: length(assigns.preview.events.possible_duplicates)
      )

    ~H"""
    <dl class="merge-counts" data-role="merge-counts">
      <dt><%= @moved %></dt>
      <dd><%= ngettext("booking moves to the target", "bookings move to the target", @moved) %></dd>
      <%= if @pairs > 0 do %>
        <dt><%= @pairs %></dt>
        <dd>
          <%= ngettext("booking is equal in both securities", "bookings are equal in both securities", @pairs) %>
          <small><%= gettext("— choice below") %></small>
        </dd>
      <% end %>
      <%= if @splits > 0 do %>
        <dt><%= @splits %></dt>
        <dd>
          <%= ngettext(
            "split stands the same in both — the target's stays",
            "splits stand the same in both — the target's stay",
            @splits
          ) %>
        </dd>
      <% end %>
      <%= if @quotes.moved_count > 0 do %>
        <dt><%= @quotes.moved_count %></dt>
        <dd>
          <%= ngettext(
            "quote of the source fills a gap in the target",
            "quotes of the source fill gaps in the target",
            @quotes.moved_count
          ) %>
        </dd>
      <% end %>
      <%= if @quotes.collision_count > 0 do %>
        <dt><%= @quotes.collision_count %></dt>
        <dd>
          <%= ngettext(
            "day with a quote in both — the target's applies",
            "days with a quote in both — the target's applies",
            @quotes.collision_count
          ) %>
          <small :if={@manual > 0}>
            <%= ngettext("— %{count} of them manual, table", "— %{count} of them manual, table", @manual) %>
          </small>
        </dd>
      <% end %>
      <%= if @settings != [] do %>
        <dt><%= length(@settings) %></dt>
        <dd>
          <%= ngettext("setting of the source", "settings of the source", length(@settings)) %>:
          <%= [
            @moving_settings > 0 && ngettext("%{count} moves", "%{count} move", @moving_settings),
            @dropped_settings > 0 &&
              ngettext("%{count} is dropped", "%{count} are dropped", @dropped_settings)
          ]
          |> Enum.filter(& &1)
          |> Enum.join(", ") %>
          <small><%= gettext("— table") %></small>
        </dd>
      <% end %>
      <%= if @events > 0 do %>
        <dt><%= @events %></dt>
        <dd>
          <%= ngettext("event moves", "events move", @events) %>
          <small :if={@event_twins > 0}>
            <%= ngettext(
              "— %{count} of them stands the same in the target, table",
              "— %{count} of them stand the same in the target, table",
              @event_twins
            ) %>
          </small>
        </dd>
      <% end %>
    </dl>
    """
  end

  # -- the equal bookings (§8) -------------------------------------------------------

  attr(:pairs, :list, required: true)
  attr(:choices, :map, required: true)
  attr(:keep, :map, required: true)
  attr(:collapsed, :map, required: true)
  attr(:holdings, :map, required: true)
  attr(:names, :map, required: true)
  attr(:currency, :string, required: true)

  defp pair_choice(assigns) do
    {visible, rest} = Enum.split(assigns.pairs, @visible_pairs)
    assigns = assign(assigns, visible: visible, rest: rest)

    ~H"""
    <fieldset class="merge-choice" data-role="merge-pairs">
      <legend>
        <%= ngettext(
          "%{count} equal booking in both securities",
          "%{count} equal bookings in both securities",
          length(@pairs)
        ) %>
      </legend>
      <.pair_table pairs={@visible} names={@names} currency={@currency} />
      <details :if={@rest != []} class="merge-more">
        <summary class="disclosure-summary">
          <AppShell.icon name={:chevron_right} size={14} class="disclosure-chevron" />
          <%= ngettext("Show the other pair", "Show the other %{count} pairs", length(@rest)) %>
        </summary>
        <.pair_table pairs={@rest} names={@names} currency={@currency} />
      </details>
      <label class={["merge-option", @choices.collapse == true && "is-on"]} data-role="collapse-true">
        <input type="radio" name="merge[collapse]" value="true" checked={@choices.collapse == true} />
        <span>
          <%= gettext("remove as duplicates") %>
          <small>
            <%= ngettext(
              "The booking of the source is deleted.",
              "The %{count} bookings of the source are deleted.",
              length(@pairs)
            ) %>
            <%= gettext("Holdings afterwards") %> <b><%= gettext("%{quantity} shares", quantity: Format.exact(@holdings.collapsed)) %></b>.
          </small>
          <small :if={@collapsed.cash_accounts != []} class="merge-option__extra">
            <%= gettext("Also changes: %{changes}", changes: Enum.join(collapse_effects(@collapsed), " · ")) %>
          </small>
        </span>
      </label>
      <label class={["merge-option", @choices.collapse == false && "is-on"]} data-role="collapse-false">
        <input type="radio" name="merge[collapse]" value="false" checked={@choices.collapse == false} />
        <span>
          <%= gettext("keep both") %>
          <small>
            <%= ngettext(
              "The booking stands at the target afterwards.",
              "All %{count} bookings stand at the target afterwards.",
              @keep.transaction_count
            ) %>
            <%= gettext("Holdings afterwards") %> <b><%= gettext("%{quantity} shares", quantity: Format.exact(@holdings.keep)) %></b>.
          </small>
        </span>
      </label>
      <p class="merge-basis">
        <%= gettext("Equal means: same day, same kind, same depot and account, same quantity and amounts.") %>
      </p>
    </fieldset>
    """
  end

  attr(:pairs, :list, required: true)
  attr(:names, :map, required: true)
  attr(:currency, :string, required: true)

  # What removing the duplicates changes outside the pair (§16 invariant 9,
  # board 13): each cash account's balance, and a flow a later set balance
  # of it absorbs.
  defp collapse_effects(outcome) do
    names = Map.new(outcome.cash_accounts, &{&1.id, &1.name})

    Enum.map(outcome.cash_accounts, fn account ->
      "#{account.name} #{Format.money(account.balance_before)} → #{Format.money(account.balance_after)}"
    end) ++
      AccountMergePreview.absorbed_lines(
        outcome.flow_changes,
        &Map.get(names, &1, "##{&1}")
      )
  end

  defp pair_table(assigns) do
    ~H"""
    <div class="data-table-wrapper">
      <table class="data-table merge-table">
        <thead>
          <tr>
            <th><%= gettext("Date") %></th>
            <th><%= gettext("Kind") %></th>
            <th class="num"><%= gettext("Quantity") %></th>
            <th class="num"><%= gettext("Amount") %></th>
            <th><%= gettext("Depot / account") %></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={pair <- @pairs}>
            <td><%= Date.to_iso8601(pair.date) %></td>
            <td><%= TransactionKindLabel.label(pair.type) %></td>
            <td class="num"><%= if pair.quantity, do: Format.exact(pair.quantity), else: "—" %></td>
            <td class="num"><%= pair_amount(pair, @currency) %></td>
            <td><%= pair_place(pair, @names) %></td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp pair_amount(%{gross_amount: %Decimal{} = amount}, currency),
    do: "#{Format.money(amount)} #{currency}"

  defp pair_amount(%{quantity: %Decimal{} = quantity, price: %Decimal{} = price}, currency),
    do: "#{Format.money(Decimal.mult(quantity, price))} #{currency}"

  defp pair_amount(_pair, _currency), do: "—"

  defp pair_place(pair, names) do
    [
      Map.get(names.depots, pair.securities_account_id),
      Map.get(names.cash, pair.cash_account_id)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp account_names(preview) do
    if preview.key_equal_pairs == [] do
      %{depots: %{}, cash: %{}}
    else
      %{
        depots: Map.new(Portfolios.list_securities_accounts(), &{&1.id, &1.name}),
        cash: Map.new(Portfolios.list_cash_accounts(), &{&1.id, &1.name})
      }
    end
  end

  # -- quotes on days with both (§9) ---------------------------------------------------

  attr(:preview, :map, required: true)

  defp quote_collisions(assigns) do
    ~H"""
    <%= if @preview.quotes.manual_collisions != [] do %>
      <h3 class="merge-block-head">
        <%= gettext("Quotes on days with both values") %>
        <small><%= gettext("only days with a manual quote") %></small>
      </h3>
      <div class="data-table-wrapper" data-role="merge-quote-collisions">
        <table class="data-table merge-table">
          <thead>
            <tr>
              <th><%= gettext("Date") %></th>
              <th class="num"><%= gettext("Target · applies") %></th>
              <th class="num"><%= gettext("Source · dropped") %></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={collision <- @preview.quotes.manual_collisions}>
              <td><%= Date.to_iso8601(collision.date) %></td>
              <td class="num merge-table__keep">
                <%= Format.money(collision.target_close) %>
                <span class="badge quote-source"><%= SecuritiesLive.quote_source_label(collision.target_source) %></span>
              </td>
              <td class="num merge-table__drop">
                <s><%= Format.money(collision.source_close) %></s>
                <span class="badge quote-source"><%= SecuritiesLive.quote_source_label("manual") %></span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    <% end %>
    <p :if={@preview.quotes.collision_count > 0 or @preview.quotes.moved_count > 0} class="merge-basis">
      <%= ngettext(
        "Every dropped quote stands in the merge's record with its date, value and source. The quote that moves keeps its source and so its price basis.",
        "Every dropped quote stands in the merge's record with its date, value and source. The %{count} quotes that move keep their source and so their price basis.",
        @preview.quotes.moved_count
      ) %>
    </p>
    """
  end

  # -- the source's settings (§9 configuration) ---------------------------------------

  # One row per setting of the source the merge carries or drops, each with
  # its outcome and its reason — never silent.
  defp settings(preview) do
    assignments =
      for row <- preview.configuration.category_assignments do
        %{
          what: gettext("Category"),
          where: gettext("tree “%{name}”", name: row.classification_name),
          value: {:text, row.source_category_name},
          outcome: if(row.action == :move, do: :moves, else: :dropped),
          reason:
            if(row.action == :move,
              do: gettext("The target has none in this tree."),
              else:
                gettext("The target stands in “%{name}” there.", name: row.target_category_name)
            )
        }
      end

    targets =
      for row <- preview.configuration.position_targets do
        %{
          what: gettext("Position target"),
          where: "“#{row.plan_name}”, #{plan_status(row.plan_status)}",
          value:
            {:text,
             gettext("%{weight} % in “%{category}”",
               weight: Format.percent(row.target_weight),
               category: row.category_name
             )},
          outcome: if(row.action == :move, do: :moves, else: :dropped),
          reason: position_target_reason(row)
        }
      end

    buckets =
      for entry <- preview.position_buckets,
          entry.action in [:carry, :drop_redundant, :drop_unheld, :clear_target] do
        %{
          what: gettext("Position buckets"),
          where: entry.securities_account_name,
          value: {:buckets, entry.source_buckets},
          outcome: if(entry.action == :carry, do: :moves, else: :dropped),
          reason: bucket_reason(entry.action)
        }
      end

    assignments ++ targets ++ buckets
  end

  defp plan_status(:active), do: gettext("active")
  defp plan_status(:draft), do: gettext("draft")
  defp plan_status(:archived), do: gettext("archived")
  defp plan_status(other), do: to_string(other)

  defp position_target_reason(%{action: :move}),
    do: gettext("The target takes it over in its category.")

  defp position_target_reason(%{reason: :collides}),
    do: gettext("The target already has a position target in this plan.")

  defp position_target_reason(%{reason: :stale, category_name: category}),
    do:
      gettext("The target does not stand in “%{name}”; the target would be stale.",
        name: category
      )

  defp bucket_reason(:carry),
    do: gettext("The target holds nothing there; the views stay the same.")

  defp bucket_reason(:drop_redundant), do: gettext("The target's position has the same buckets.")
  defp bucket_reason(:drop_unheld), do: gettext("The source holds nothing there.")

  defp bucket_reason(:clear_target),
    do: gettext("The target's own buckets there are cleared: the source's position inherits.")

  attr(:settings, :list, required: true)
  attr(:bucket_names, :map, required: true)

  defp settings_table(assigns) do
    ~H"""
    <h3 class="merge-block-head">
      <%= gettext("Settings of the source") %>
      <small><%= gettext("in active, draft and archived plans") %></small>
    </h3>
    <div class="data-table-wrapper" data-role="merge-settings">
      <table class="data-table merge-table">
        <thead>
          <tr>
            <th><%= gettext("What") %></th>
            <th><%= pgettext("merge side", "Source") %></th>
            <th><%= gettext("Consequence") %></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={setting <- @settings}>
            <td><%= setting.what %><small><%= setting.where %></small></td>
            <td><%= setting_value(setting.value, @bucket_names) %></td>
            <td>
              <span class={["merge-outcome", "merge-outcome--#{setting.outcome}"]}>
                <%= if setting.outcome == :moves, do: gettext("moves"), else: gettext("is dropped") %>
              </span>
              <small><%= setting.reason %></small>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp setting_value({:text, text}, _names), do: text
  defp setting_value({:buckets, []}, _names), do: gettext("no buckets")

  defp setting_value({:buckets, ids}, names),
    do: ids |> Enum.map(&Map.get(names, &1, "##{&1}")) |> Enum.sort() |> Enum.join(", ")

  # -- events --------------------------------------------------------------------------

  attr(:preview, :map, required: true)

  defp events_table(assigns) do
    ~H"""
    <h3 class="merge-block-head">
      <%= gettext("Events that stand the same in the target") %>
      <small><%= gettext("the same kind on the same day") %></small>
    </h3>
    <div class="data-table-wrapper" data-role="merge-events">
      <table class="data-table merge-table">
        <thead>
          <tr>
            <th><%= gettext("Date") %></th>
            <th><%= gettext("Kind") %></th>
            <th><%= gettext("Consequence") %></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={twin <- @preview.events.possible_duplicates}>
            <td><%= Date.to_iso8601(twin.date) %></td>
            <td><%= SecurityEventLabel.kind(twin.kind) %></td>
            <td><%= gettext("both stay") %></td>
          </tr>
        </tbody>
      </table>
    </div>
    <p class="merge-basis">
      <%= gettext("An event books nothing. A duplicate can be deleted afterwards in the Events tab.") %>
    </p>
    """
  end

  # -- master data ---------------------------------------------------------------------

  attr(:preview, :map, required: true)

  # Only the fields that differ, with what holds afterwards (board 03: a
  # check that holds is not a finding).
  defp master_data(assigns) do
    identifiers = assigns.preview.identifiers

    rows =
      Enum.map(identifiers.adopted, fn %{field: field, value: value} ->
        %{
          field: field,
          source: value,
          target: nil,
          after: value,
          why: gettext("adopted: the target had none.")
        }
      end) ++
        Enum.map(identifiers.differences, fn %{field: field, source: source, target: target} ->
          %{
            field: field,
            source: source,
            target: target,
            after: target,
            why: gettext("The target's value applies.")
          }
        end)

    assigns = assign(assigns, rows: rows)

    ~H"""
    <%= if @rows != [] do %>
      <h3 class="merge-block-head"><%= gettext("Master data that differ") %></h3>
      <div class="data-table-wrapper" data-role="merge-master-data">
        <table class="data-table merge-table">
          <thead>
            <tr>
              <th><%= gettext("Field") %></th>
              <th><%= pgettext("merge side", "Source") %></th>
              <th><%= pgettext("merge side", "Target") %></th>
              <th><%= gettext("Afterwards") %></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows}>
              <td><%= field_label(row.field) %></td>
              <td><%= field_value(row.field, row.source) %></td>
              <td><%= field_value(row.field, row.target) %></td>
              <td class="merge-table__keep"><%= field_value(row.field, row.after) %><small><%= row.why %></small></td>
            </tr>
          </tbody>
        </table>
      </div>
      <p class="merge-basis">
        <%= gettext(
          "Name, asset class and logo follow the target; WKN, ticker and quote source are adopted only where the target has none."
        ) %>
      </p>
    <% end %>
    """
  end

  defp field_label(:isin), do: gettext("ISIN")
  defp field_label(:wkn), do: gettext("WKN")
  defp field_label(:ticker_symbol), do: gettext("Ticker")
  defp field_label(:feed), do: gettext("Quote source")
  defp field_label(:feed_url), do: gettext("Quote source address")
  defp field_label(:name), do: gettext("Name")
  defp field_label(:asset_class), do: gettext("Asset class")
  defp field_label(:logo), do: gettext("Logo")

  defp field_value(_field, nil), do: "—"
  defp field_value(:asset_class, code), do: AssetClasses.label(code)
  defp field_value(:feed, feed), do: Feeds.label(feed)
  defp field_value(:logo, _path), do: gettext("a logo")
  defp field_value(_field, value), do: to_string(value)

  # -- the notes -----------------------------------------------------------------------

  attr(:preview, :map, required: true)
  attr(:source, :map, required: true)

  defp notes(assigns) do
    isins =
      assigns.preview.identifiers.outcomes
      |> Map.values()
      |> Enum.flat_map(&[&1.isin | &1.former_isins])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    assigns = assign(assigns, isins: isins)

    ~H"""
    <AppShell.data_note severity={:note} data-role="merge-note">
      <%= if @isins == [] do %>
        <%= gettext("An import that names the source books to the target afterwards.") %>
      <% else %>
        <%= ngettext(
          "After the merge, %{isins} leads to this security; an import that names it books here.",
          "After the merge, %{isins} lead to this security; an import that names any of them books here.",
          length(@isins),
          isins: Enum.join(@isins, ", ")
        ) %>
      <% end %>
    </AppShell.data_note>
    <AppShell.data_note severity={:attention} data-role="merge-warning">
      <%= gettext(
        "The source (created %{date}) is deleted afterwards — the entry, not its ISIN. This cannot be undone; every changed row is journaled.",
        date: created_on(@source)
      ) %>
    </AppShell.data_note>
    """
  end

  # -- the refusal ---------------------------------------------------------------------

  attr(:guards, :list, required: true)
  attr(:reverse, :list, default: nil)
  attr(:source, :map, required: true)
  attr(:target, :map, default: nil)
  attr(:myself, :any, required: true)

  defp refusal(assigns) do
    failed = Enum.reject(assigns.guards, & &1.passed)
    other_way? = Enum.any?(failed, &(Map.get(&1, :remedy) == :merge_other_way))
    keep_both? = Enum.any?(failed, &(Map.get(&1, :remedy) == :keep_both))

    remedies =
      failed |> remedy_guards() |> Enum.map(&remedy/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    assigns =
      assign(assigns,
        failed: failed,
        other_way?: other_way?,
        keep_both?: keep_both? and (assigns.reverse || []) != [],
        remedies: remedies,
        recheck?: Enum.any?(failed, &(&1.code in recheckable()))
      )

    ~H"""
    <AppShell.data_note severity={:problem} data-role="merge-refused">
      <%= for {guard, index} <- Enum.with_index(@failed) do %>
        <p class="merge-refusal__lead">
          <%= if index == 0,
            do: gettext("Merging is not possible: %{reason}", reason: reason(guard, @source, @target, :direct)),
            else: gettext("Also: %{reason}", reason: reason(guard, @source, @target, :direct)) %>
        </p>
        <.rule_list :if={guard.code == :policy_rules} security={@source} />
        <p :for={line <- detail_lines(guard)} class="merge-refusal__position"><%= line %></p>
      <% end %>
      <%= if @keep_both? do %>
        <p :for={guard <- @reverse} class="merge-refusal__lead">
          <%= gettext("The other way is refused too: %{reason}", reason: reason(guard, @target, @source, :reverse)) %>
        </p>
        <p :if={not Enum.any?(@failed, &(&1.code == :identity_unresolvable))} class="merge-refusal__remedy">
          <%= gettext("No direction is possible; both securities stay unchanged.") %>
        </p>
      <% end %>
      <p :for={remedy <- @remedies} class="merge-refusal__remedy"><%= remedy %></p>
      <p :if={@other_way?} class="merge-refusal__remedy">
        <%= gettext("Remedy: merge the other way — %{target} into this security.",
          target: (@target && (@target.isin || @target.name)) || ""
        ) %>
      </p>
      <span class="merge-refusal__actions">
        <button :if={@other_way?} type="button" class="button" data-role="merge-other-way" phx-click="other_way" phx-target={@myself}>
          <%= gettext("Merge the other way") %>
        </button>
        <button :if={@recheck?} type="button" class="button" data-role="merge-recheck" phx-click="recheck" phx-target={@myself}>
          <%= gettext("Check again") %>
        </button>
      </span>
    </AppShell.data_note>
    """
  end

  # Two ratios on one day also fail the split-event rule for that day; its
  # remedy ("book the split on that side first") cannot apply while both
  # sides carry a split, so the ratio conflict's own remedy speaks alone.
  defp remedy_guards(failed) do
    if Enum.any?(failed, &(&1.code == :split_ratio_mismatch)),
      do: Enum.reject(failed, &(&1.code in [:split_event_mismatch, :split_linearity])),
      else: failed
  end

  defp recheckable,
    do: [
      :benchmark_mismatch,
      :retired_target,
      :quote_basis_mismatch,
      :position_buckets_mismatch,
      :split_ratio_mismatch,
      :split_event_mismatch,
      :split_linearity,
      :legacy_hashed_split
    ]

  attr(:security, :map, required: true)

  # ADR-0049 §8: the rules that read the security, each reachable (G6-A).
  defp rule_list(assigns) do
    assigns =
      assign(
        assigns,
        :rules,
        PolicyRuleReferences.references(PolicyRules.referencing(:security, assigns.security.id))
      )

    ~H"""
    <ul class="merge-refusal__rules">
      <li :for={reference <- @rules}><PolicyRuleReferences.rule reference={reference} /></li>
    </ul>
    <p class="merge-refusal__position">
      <%= gettext("A rule that has been in force keeps its subject as part of its history.") %>
    </p>
    """
  end

  # The reason in the operator's words. `subject` is the security the guard
  # speaks of as its source, `other` its target; on the reverse direction the
  # two roles swap, and so do the words.
  defp reason(%{code: :currency_mismatch}, subject, other, _direction) do
    gettext(
      "the securities trade in %{source} and %{target}, and a merge never converts a booked amount.",
      source: subject.currency_code,
      target: other && other.currency_code
    )
  end

  defp reason(%{code: :benchmark_mismatch}, _subject, _other, _direction),
    do: gettext("only one of the two is marked as a benchmark.")

  defp reason(%{code: :retired_target}, _subject, _other, :direct),
    do: gettext("the target is retired while the source is live.")

  defp reason(%{code: :retired_target}, _subject, _other, :reverse),
    do: gettext("the source is retired while the target is live.")

  defp reason(%{code: :quote_basis_mismatch}, _subject, _other, _direction),
    do:
      gettext(
        "the quotes would change their basis: only one of the two treats its synced quotes as raw."
      )

  defp reason(%{code: :research_notes}, subject, _other, direction) do
    notes = Knowledge.list_notes(subject.id)
    last = notes |> Enum.map(& &1.as_of) |> Enum.max(Date, fn -> nil end)
    date = last && Date.to_iso8601(last)

    case direction do
      :direct ->
        ngettext(
          "the source has %{count} research entry, the last of %{date}. Research entries are never moved or deleted; a security with entries can only be the target.",
          "the source has %{count} research entries, the last of %{date}. Research entries are never moved or deleted; a security with entries can only be the target.",
          length(notes),
          date: date
        )

      :reverse ->
        ngettext(
          "the target has %{count} research entry, the last of %{date}, and research entries are never moved or deleted.",
          "the target has %{count} research entries, the last of %{date}, and research entries are never moved or deleted.",
          length(notes),
          date: date
        )
    end
  end

  defp reason(%{code: :policy_rules}, _subject, _other, :direct),
    do: gettext("the source is read by policy rules:")

  defp reason(%{code: :policy_rules} = guard, _subject, _other, :reverse) do
    gettext("the target is read by policy rules: %{names}.",
      names: Enum.map_join(Map.get(guard, :policy_rules, []), ", ", &"“#{&1.name}”")
    )
  end

  defp reason(%{code: :position_buckets_mismatch} = guard, _subject, _other, _direction) do
    ngettext(
      "for %{count} position the buckets differ, so the views would change retroactively.",
      "for %{count} positions the buckets differ, so the views would change retroactively.",
      length(Map.get(guard, :positions, []))
    )
  end

  defp reason(%{code: :split_ratio_mismatch} = guard, _subject, _other, _direction) do
    guard
    |> Map.get(:conflicts, [])
    |> Enum.map_join(" ", fn conflict ->
      gettext(
        "on %{date} in %{portfolio} the source splits %{source} and the target %{target}; one split cannot carry two ratios.",
        date: Date.to_iso8601(conflict.date),
        portfolio: conflict.portfolio_name,
        source: ratio(conflict.source_ratio),
        target: ratio(conflict.target_ratio)
      )
    end)
  end

  defp reason(%{code: :split_event_mismatch} = guard, _subject, _other, direction) do
    guard
    |> Map.get(:issues, [])
    |> Enum.map_join(" ", &issue(&1, direction))
  end

  defp reason(%{code: :split_linearity} = guard, _subject, _other, _direction) do
    case Map.get(guard, :failure) do
      %{date: date, securities_account_name: depot} ->
        gettext(
          "the split of %{date} would rescale bookings in %{depot} it did not scale before.",
          date: Date.to_iso8601(date),
          depot: depot
        )

      _unknown ->
        gettext("a split would rescale bookings it did not scale before.")
    end
  end

  defp reason(%{code: :identity_unresolvable} = guard, _subject, _other, _direction) do
    identifiers =
      guard
      |> Map.get(:unresolvable, [])
      |> Enum.map(& &1.ref)
      |> Enum.uniq()
      |> Enum.map_join("; ", &identifier/1)

    gettext(
      "after the merge, an identifier of the two would no longer lead to the target: %{identifiers}.",
      identifiers: identifiers
    )
  end

  defp reason(%{code: :legacy_hashed_split}, _subject, _other, _direction),
    do:
      gettext(
        "a split of the source still carries an import hash from before the import-hash check and cannot be moved."
      )

  defp reason(%{code: :same_security}, _subject, _other, _direction),
    do: gettext("a security cannot be merged into itself.")

  defp reason(%{code: :not_live}, _subject, _other, _direction),
    do: gettext("the target no longer exists.")

  defp reason(_guard, _subject, _other, _direction),
    do: gettext("a check of the merge did not hold.")

  # On the reverse direction the sides swap: its source is this target.
  defp issue(%{kind: :two_ratios, date: date, ratios: ratios}, direction) do
    gettext("on %{date} the securities split %{ratios}; one event cannot carry two ratios.",
      date: Date.to_iso8601(date),
      ratios:
        Enum.map_join(ratios, " · ", fn %{ratio: r, sides: sides} ->
          "#{ratio(r)} (#{Enum.map_join(sides, ", ", &side_word(&1, direction))})"
        end)
    )
  end

  defp issue(%{kind: :lacking, side: side, date: date, ratio: r, earlier: earlier}, direction) do
    params = [date: Date.to_iso8601(date), ratio: ratio(r), earlier: earlier_text(earlier)]

    case swap(side, direction) do
      :target ->
        gettext(
          "the source's split of %{date} (%{ratio}) is not a split of the target, which has %{earlier} before it.",
          params
        )

      :source ->
        gettext(
          "the target's split of %{date} (%{ratio}) is not a split of the source, which has %{earlier} before it.",
          params
        )
    end
  end

  defp swap(side, :direct), do: side
  defp swap(:source, :reverse), do: :target
  defp swap(:target, :reverse), do: :source

  defp side_word(side, direction) do
    case swap(side, direction) do
      :source -> gettext("source")
      :target -> gettext("target")
    end
  end

  defp earlier_text(%{kind: :booking, date: date}),
    do: gettext("a booking of %{date}", date: Date.to_iso8601(date))

  defp earlier_text(%{kind: :quote, date: date}),
    do: gettext("a quote of %{date}", date: Date.to_iso8601(date))

  defp ratio(%{numerator: p, denominator: q}), do: "#{p}:#{q}"

  defp identifier(%{isin: isin}) when is_binary(isin), do: gettext("ISIN %{isin}", isin: isin)
  defp identifier(%{wkn: wkn}) when is_binary(wkn), do: gettext("WKN %{wkn}", wkn: wkn)

  defp identifier(%{ticker: ticker} = ref) when is_binary(ticker),
    do: gettext("ticker %{ticker} (%{currency})", ticker: ticker, currency: ref.currency)

  defp identifier(ref),
    do: gettext("name “%{name}” (%{currency})", name: ref.name, currency: ref.currency)

  # The facts a reason lists line by line: the positions whose buckets
  # differ.
  defp detail_lines(%{code: :position_buckets_mismatch} = guard) do
    names = Map.new(Buckets.list_buckets(), &{&1.id, &1.name})

    for position <- Map.get(guard, :positions, []) do
      gettext("%{depot} — source: %{source} · target: %{target}",
        depot: position.securities_account_name,
        source: bucket_list(position.source_buckets, names),
        target: bucket_list(position.target_buckets, names)
      )
    end
  end

  # Board 14 ③: the split a refusal means, by its date and number.
  defp detail_lines(%{code: :legacy_hashed_split} = guard) do
    for split <- Map.get(guard, :splits, []) do
      gettext("Split on %{date} · no. %{id}", date: Date.to_iso8601(split.date), id: split.id)
    end
  end

  defp detail_lines(_guard), do: []

  defp bucket_list([], _names), do: gettext("no buckets")

  defp bucket_list(ids, names),
    do: ids |> Enum.map(&Map.get(names, &1, "##{&1}")) |> Enum.sort() |> Enum.join(", ")

  defp remedy(%{code: :currency_mismatch}),
    do: gettext("Remedy: go back and choose a target in the same currency.")

  defp remedy(%{code: :benchmark_mismatch}),
    do: gettext("Remedy: mark both the same, then check again.")

  defp remedy(%{code: :retired_target}),
    do: gettext("Remedy: reactivate the target, then check again.")

  defp remedy(%{code: :quote_basis_mismatch}),
    do: gettext("Remedy: set “treat synced quotes as raw” the same on both, then check again.")

  defp remedy(%{code: :position_buckets_mismatch}),
    do: gettext("Remedy: give the position the same buckets in both, then check again.")

  # Board 03 and 14 ④: both sides carry a split that day, so the remedy is
  # to delete the wrong one, never to book one.
  defp remedy(%{code: :split_ratio_mismatch}),
    do:
      gettext(
        "Remedy: delete the split with the wrong ratio in the Transactions tab, then check again."
      )

  defp remedy(%{code: code}) when code in [:split_event_mismatch, :split_linearity],
    do:
      gettext(
        "Remedy: book the split on that side first, or delete the wrong split, then check again."
      )

  defp remedy(%{code: :legacy_hashed_split}),
    do:
      gettext(
        "Remedy: change its kind back to the one it was imported as, or delete it, then check again."
      )

  defp remedy(%{code: :identity_unresolvable}),
    do: gettext("This version has no way around it; both securities stay unchanged.")

  defp remedy(%{code: :not_live}), do: gettext("Remedy: go back and choose another target.")
  defp remedy(_guard), do: nil

  # -- shared --------------------------------------------------------------------------

  @doc "The operator's choices the preview still needs: `:identity`, `:collapse`."
  @spec missing_choices(map(), map()) :: [:identity | :collapse]
  def missing_choices(preview, choices) do
    [
      (preview.identifiers.choice_required and is_nil(choices.identity)) && :identity,
      (preview.key_equal_pairs != [] and is_nil(choices.collapse)) && :collapse
    ]
    |> Enum.filter(& &1)
  end

  defp missing_label(:identity, _preview), do: gettext("Choice for the ISIN missing")

  defp missing_label(:collapse, preview) do
    ngettext(
      "Choice for the equal booking missing",
      "Choice for %{count} equal bookings missing",
      length(preview.key_equal_pairs)
    )
  end

  @doc """
  The inline result of an applied merge, from the preview whose digest it
  matched and the choices it applied (board 03, "Danach").
  """
  @spec result_message(map(), map()) :: String.t()
  def result_message(preview, choices) do
    outcome = Map.fetch!(preview.outcomes, choices.collapse == true)
    moved = length(outcome.moved_transaction_ids)
    removed = Enum.count(outcome.deleted, &(&1.reason == :collapsed_duplicate))
    quotes = preview.quotes.moved_count

    dropped =
      preview |> settings() |> Enum.count(&(&1.outcome != :moves))

    parts =
      [
        ngettext("%{count} booking moved", "%{count} bookings moved", moved),
        removed > 0 &&
          ngettext("%{count} duplicate removed", "%{count} duplicates removed", removed),
        quotes > 0 && ngettext("%{count} quote added", "%{count} quotes added", quotes),
        dropped > 0 && ngettext("%{count} setting dropped", "%{count} settings dropped", dropped)
      ]
      |> Enum.filter(& &1)
      |> Enum.join(", ")

    isin =
      preview.identifiers.outcomes
      |> Map.get(choices.identity || :no_choice, %{isin: nil})
      |> Map.get(:isin)

    message =
      gettext("Merged into %{target}: %{parts}.", target: preview.target.name, parts: parts)

    if isin, do: message <> " " <> gettext("ISIN now %{isin}.", isin: isin), else: message
  end

  @doc """
  What changed between the preview the operator read and the fresh one a
  changed plan answered with: each side's booking count, and the quotes of
  the source, as short phrases.
  """
  @spec changes(map(), map()) :: [String.t()]
  def changes(before, fresh) do
    bookings =
      for {side, label} <- [
            {:source, gettext("bookings of the source")},
            {:target, gettext("bookings of the target")}
          ],
          b = Map.fetch!(before, side).transaction_count,
          f = Map.fetch!(fresh, side).transaction_count,
          b != f,
          do: "#{label} #{b} → #{f}"

    quotes =
      if before.quotes.source_count != fresh.quotes.source_count,
        do: [
          "#{gettext("quotes of the source")} #{before.quotes.source_count} → #{fresh.quotes.source_count}"
        ],
        else: []

    bookings ++ quotes
  end
end
