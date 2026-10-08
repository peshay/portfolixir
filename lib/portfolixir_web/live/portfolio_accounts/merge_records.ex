defmodule PortfolixirWeb.PortfolioAccounts.MergeRecords do
  @moduledoc """
  The merge records on Accounts & depots (ADR-0050 §12; Sprint 17 V1; board
  `ux-design-2026-10-01/02-merge-records`, pick G2-A): the operator's view of
  `GET /api/v1/merges`, the capability the agent has read since Sprint 16.

  A section at the end of the page, after the accounts table and before the
  compatibility records: an h2 and Cash flow's `.section-disclosure`,
  collapsed under "N entries · latest <date>". One `.data-table` for all
  three kinds, newest first as the API orders it; each row the date, the
  kind, "source → target" (the source muted, never struck: its name lives on
  as a former name of the target), the result in the confirmation's own
  words, and who ran it ("Operator" or "Agent", G12.1-A's words). The result
  is a disclosure that opens the count per table, the choice made and the
  check the merge passed, each under a fixed label (`line_label/1`): a raw
  manifest key never reaches the screen, and `labelled_paths/0` is what the
  meta-test holds the three merge writers against. Under 560 px the rows are
  two-line rows (UX-DR27) with the date moved into the identifier line.

  Read-only: there is no unmerge (§12), so nothing here writes, and nothing
  suggests a merge can be taken back.

  The figures are `Portfolixir.Lifecycle.manifest_summary/1`'s, the same the
  API answers, so both users read one count.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Clock
  alias Portfolixir.Input.BoundedDate
  alias Portfolixir.Lifecycle
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format

  # The API's default page; at the limit the summary says "the newest 100"
  # (UX-DR26), which is why one more record is read than is shown.
  @limit 100

  # Every key path of a manifest summary the three merge writers emit, and the
  # disclosure line that reads it. A path missing here fails the meta-test in
  # `accounts_merge_records_live_test.exs`, so a new manifest key gets its
  # words before it can reach the screen.
  @paths %{
    ["transactions", "moved"] => :bookings,
    ["transactions", "deleted"] => :bookings,
    ["transactions", "deleted_by_reason"] => :bookings,
    ["transactions", "deleted_by_reason", "collapsed_duplicate"] => :bookings,
    ["transactions", "deleted_by_reason", "internal_transfer"] => :bookings,
    ["transactions", "deleted_by_reason", "folded_anchor"] => :bookings,
    ["transactions", "deleted_by_reason", "collapsed_split"] => :bookings,
    ["transactions", "restated"] => :set_balances,
    ["restated_anchors"] => :set_balances,
    ["securities_accounts", "repointed"] => :linked_depots,
    ["quotes", "moved"] => :quotes,
    ["quotes", "dropped"] => :quotes,
    ["category_assignments", "moved"] => :classifications,
    ["category_assignments", "dropped"] => :classifications,
    ["position_targets", "moved"] => :position_targets,
    ["position_targets", "deleted"] => :position_targets,
    ["security_events", "moved"] => :events,
    ["security_events", "possible_duplicates"] => :events,
    ["split_events", "source"] => :splits,
    ["split_events", "target"] => :splits,
    ["position_bucket_overrides", "carried"] => :position_buckets,
    ["position_bucket_overrides", "dropped"] => :position_buckets,
    ["position_bucket_overrides", "cleared"] => :position_buckets,
    ["cash_account_buckets", "removed"] => :buckets,
    ["securities_account_buckets", "removed"] => :buckets,
    ["former_names", "appended"] => :former_names,
    ["former_names", "not_kept"] => :former_names,
    ["identifier_aliases", "reassigned"] => :former_isins,
    ["identifiers", "adopted"] => :master_data,
    ["identifiers", "differences"] => :master_data,
    ["rounding_differences"] => :rounding,
    ["identifiers", "source_isin"] => :isin,
    ["identifiers", "target_isin"] => :isin,
    ["identifier_aliases", "created"] => :isin,
    ["identifier_aliases", "created", "former_isin"] => :isin,
    ["identifier_aliases", "created", "changed_on"] => :isin,
    ["choices", "identity_choice"] => :isin,
    ["choices", "isin_changed_on"] => :isin,
    ["choices", "collapse_key_equal"] => :choice,
    ["linearity", "dates_checked"] => :check,
    ["linearity", "securities_checked"] => :check,
    ["linearity", "depots_checked"] => :check
  }

  # The order the lines open in: what moved first, the choice and the check
  # last (board 02, ③).
  @lines [
    :bookings,
    :set_balances,
    :linked_depots,
    :quotes,
    :classifications,
    :position_targets,
    :events,
    :splits,
    :position_buckets,
    :buckets,
    :former_names,
    :former_isins,
    :master_data,
    :rounding,
    :isin,
    :choice,
    :check
  ]

  @reasons ~w(collapsed_duplicate internal_transfer folded_anchor collapsed_split)

  @doc "Every manifest-summary key path the list has words for."
  @spec labelled_paths() :: [[String.t()]]
  def labelled_paths, do: Map.keys(@paths)

  @doc "The disclosure line a manifest-summary key path feeds."
  @spec line_of([String.t()]) :: atom() | nil
  def line_of(path), do: Map.get(@paths, path)

  @doc "The fixed label of a disclosure line."
  @spec line_label(atom()) :: String.t()
  def line_label(:bookings), do: pgettext("merge record", "Bookings")
  def line_label(:set_balances), do: gettext("Set balances")
  def line_label(:linked_depots), do: pgettext("merge record", "Linked depots")
  def line_label(:quotes), do: gettext("Quotes")
  def line_label(:classifications), do: gettext("Classifications")
  def line_label(:position_targets), do: pgettext("merge record", "Position targets")
  def line_label(:events), do: pgettext("merge record", "Events")
  def line_label(:splits), do: pgettext("merge record", "Split events")
  def line_label(:position_buckets), do: gettext("Position buckets")
  def line_label(:buckets), do: pgettext("merge record", "Bucket assignments")
  def line_label(:former_names), do: gettext("Former names")
  def line_label(:former_isins), do: pgettext("merge record", "Former ISINs")
  def line_label(:master_data), do: pgettext("merge record", "Master data")
  def line_label(:rounding), do: pgettext("merge record", "Rounding at a split")
  def line_label(:isin), do: pgettext("merge record", "ISIN")
  def line_label(:choice), do: pgettext("merge record", "Choice")
  def line_label(:check), do: pgettext("merge record", "Check")

  # -- data -------------------------------------------------------------------------

  @doc """
  The records the section lists, newest first, and whether more exist than
  it shows. `places` maps `{kind, id}` of every live cash account and depot
  to `%{name, href}` — the page's own rows — so a target links to its band;
  a security target links to its page.
  """
  @spec load(map()) :: %{records: [map()], more?: boolean()}
  def load(places) when is_map(places) do
    listed = Lifecycle.list_merges(@limit + 1)
    shown = Enum.take(listed, @limit)
    places = Map.merge(places, security_places(shown))

    %{records: Enum.map(shown, &entry(&1, places)), more?: length(listed) > @limit}
  end

  defp security_places(listed) do
    listed
    |> Enum.filter(&(&1.record.kind == :security))
    |> Enum.flat_map(&[&1.record.target_id, &1.target_merged_into])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.flat_map(fn id ->
      case Catalog.get_security(id) do
        %Security{name: name} -> [{{:security, id}, %{name: name, href: "/securities/#{id}"}}]
        nil -> []
      end
    end)
    |> Map.new()
  end

  defp entry(listed, places) do
    record = listed.record

    %{
      id: record.id,
      kind: record.kind,
      date: Clock.local_date(record.inserted_at),
      source_name: listed.source_name,
      target: target(record.kind, record.target_id, listed, places),
      actor: actor(record.actor_type),
      summary: Lifecycle.manifest_summary(record.manifest)
    }
  end

  defp target(kind, id, listed, places) do
    case {Map.fetch(places, {kind, id}), listed.target_merged_into} do
      {{:ok, place}, _merged_into} ->
        {:live, place}

      {:error, end_id} when is_integer(end_id) ->
        case Map.fetch(places, {kind, end_id}) do
          {:ok, place} -> {:merged, listed.target_name, place}
          :error -> {:merged_gone, listed.target_name}
        end

      {:error, nil} when is_binary(listed.target_name) ->
        {:merged_gone, listed.target_name}

      {:error, nil} ->
        :deleted
    end
  end

  # G12.1-A's rule: a token writes as the agent, everything else as the
  # operator.
  defp actor(type) when type in [:api_token_rw, :api_token_ro], do: :agent
  defp actor(_type), do: :operator

  # -- the section ----------------------------------------------------------------

  attr(:records, :list, required: true)
  attr(:more?, :boolean, default: false)
  attr(:focus, :integer, default: nil)

  @doc "The section, placed by the page after its accounts table."
  def section(assigns) do
    ~H"""
    <section
      id="merge-records"
      class="workspace-section merge-records"
      aria-labelledby="merge-records-title"
      data-role="merge-records"
      phx-hook="MergeFocus"
      data-focus={@focus}
    >
      <h2 id="merge-records-title"><%= gettext("Merges") %></h2>
      <%= if @records == [] do %>
        <p class="empty-state" data-role="merge-records-empty">
          <%= gettext(
            "No merge yet — “Merge into…” is in the row menu of every account, depot and security."
          ) %>
        </p>
      <% else %>
        <details
          id="merge-records-disclosure"
          class="section-disclosure"
          open={focused?(@records, @focus) or past_cut?(@records, @more?, @focus)}
        >
          <summary class="disclosure-summary" data-role="merge-records-summary">
            <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
            <%= list_summary(@records, @more?) %>
          </summary>
          <p class="detail-tab-hint"><%= gettext("What each merge moved, the newest first.") %></p>
          <%!-- A link naming a merge the cut list does not carry (a
               survivor's date past the newest 100, closing act γ): said,
               not silently nothing. --%>
          <p
            :if={past_cut?(@records, @more?, @focus)}
            class="hint"
            data-role="merge-records-focus-missing"
          >
            <%= ngettext(
              "The merge the link names is not among the newest %{count} listed here.",
              "The merge the link names is not among the newest %{count} listed here.",
              length(@records)
            ) %>
          </p>

          <div class="data-table-wrapper merge-records__table">
            <table class="data-table merge-records-table" data-role="merge-records-table">
              <thead>
                <tr>
                  <th><%= gettext("Date") %></th>
                  <th><%= gettext("Kind") %></th>
                  <th><%= gettext("Source → target") %></th>
                  <th><%= gettext("Result") %></th>
                  <th><%= pgettext("merge record", "By") %></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={record <- @records} id={"merge-record-#{record.id}"} data-merge={record.id}>
                  <td class="cell-date"><%= Format.date(record.date) %></td>
                  <td class="cell-kind"><%= kind_label(record.kind) %></td>
                  <td class="merge-record__pair"><.pair record={record} /></td>
                  <td><.manifest record={record} open={record.id == @focus} /></td>
                  <td class="cell-actor"><%= actor_label(record.actor) %></td>
                </tr>
              </tbody>
            </table>
          </div>

          <ul class="phone-rows merge-records__rows" aria-label={gettext("Merges")}>
            <li :for={record <- @records} class="phone-row" data-merge={record.id}>
              <span class="phone-row__body">
                <span class="phone-row__name merge-record__pair"><.pair record={record} /></span>
                <span class="phone-row__ids">
                  <%= Enum.join(
                    [Format.date(record.date), kind_label(record.kind), actor_label(record.actor)],
                    " · "
                  ) %>
                </span>
              </span>
              <.manifest record={record} open={record.id == @focus} />
            </li>
          </ul>
        </details>
      <% end %>
    </section>
    """
  end

  attr(:record, :map, required: true)

  # Source → target, the preview's `.merge-route` order in one line; a reader
  # hears "in" for the arrow.
  defp pair(assigns) do
    ~H"""
    <span class="merge-record__source"><%= @record.source_name || "—" %></span><span
      class="merge-record__arrow"
      aria-hidden="true"
    >→</span><span class="visually-hidden"><%= gettext("into") %></span><%= case @record.target do %>
      <% {:live, place} -> %>
        <a class="merge-record__target" href={place.href}><%= place.name %></a>
      <% {:merged, name, place} -> %>
        <span class="merge-record__target merge-record__target--gone"><%= name %></span>
        <span class="merge-record__later">
          <%= gettext("now in") %> <a href={place.href}><%= place.name %></a>
        </span>
      <% {:merged_gone, name} -> %>
        <span class="merge-record__target merge-record__target--gone"><%= name %></span>
        <span class="merge-record__later"><%= later_deleted(@record.kind) %></span>
      <% :deleted -> %>
        <span class="merge-record__target merge-record__target--gone merge-record__target--deleted">
          <%= deleted_target(@record.kind) %>
        </span>
    <% end %>
    """
  end

  attr(:record, :map, required: true)
  attr(:open, :boolean, default: false)

  # The result: the confirmation's phrase is the summary; the counts per
  # table, the choice and the check open under it.
  defp manifest(assigns) do
    assigns = assign(assigns, :lines, lines(assigns.record.kind, assigns.record.summary))

    ~H"""
    <details class="merge-manifest" open={@open}>
      <summary class="disclosure-summary">
        <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
        <%= result_phrase(@record.kind, @record.summary) %>
      </summary>
      <dl class="merge-manifest__counts">
        <%= for {label, value} <- @lines do %>
          <dt><%= label %></dt>
          <dd><%= value %></dd>
        <% end %>
      </dl>
      <p class="merge-manifest__basis">
        <%= gettext("Counted from the merge's record; every single row is in the audit journal.") %>
      </p>
    </details>
    """
  end

  # -- words ----------------------------------------------------------------------

  defp focused?(records, focus), do: focus != nil and Enum.any?(records, &(&1.id == focus))

  # Only a cut list can leave out a merge a link names; in a whole list an id
  # it does not carry names no merge, and nothing is said.
  defp past_cut?(records, more?, focus),
    do: more? and focus != nil and not focused?(records, focus)

  defp list_summary(records, more?) do
    latest = records |> hd() |> Map.fetch!(:date) |> Format.date()

    if more?,
      do:
        ngettext(
          "the newest %{count} · latest %{date}",
          "the newest %{count} · latest %{date}",
          length(records),
          date: latest
        ),
      else:
        ngettext(
          "%{count} entry · latest %{date}",
          "%{count} entries · latest %{date}",
          length(records),
          date: latest
        )
  end

  defp kind_label(:cash_account), do: gettext("Cash account")
  defp kind_label(:securities_account), do: gettext("Depot")
  defp kind_label(:security), do: gettext("Security")

  defp actor_label(:agent), do: gettext("Agent")
  defp actor_label(:operator), do: gettext("Operator")

  defp deleted_target(:cash_account), do: gettext("a cash account deleted since")
  defp deleted_target(:securities_account), do: gettext("a depot deleted since")
  defp deleted_target(:security), do: gettext("a security deleted since")

  defp later_deleted(:cash_account), do: gettext("now in a cash account deleted since")
  defp later_deleted(:securities_account), do: gettext("now in a depot deleted since")
  defp later_deleted(:security), do: gettext("now in a security deleted since")

  @doc """
  The result in the words the confirmation used when the merge ran: for an
  account or a depot "N bookings moved, M removed", for a security the moved
  bookings, the duplicates removed, the splits collapsed with the target's
  (#1032, pick H8.7: in the open line's own word, no total that would mix the
  operator's choice with the automatic step), the quotes added and the
  settings dropped. A part that is zero is left out, the moved bookings
  never.
  """
  @spec result_phrase(atom(), map()) :: String.t()
  def result_phrase(:security, summary) do
    dropped =
      count(summary, ["category_assignments", "dropped"]) +
        count(summary, ["position_targets", "deleted"]) +
        count(summary, ["position_bucket_overrides", "dropped"]) +
        count(summary, ["position_bucket_overrides", "cleared"])

    [
      moved_phrase(summary),
      nonzero(
        count(summary, ["transactions", "deleted_by_reason", "collapsed_duplicate"]),
        fn n ->
          ngettext("%{count} duplicate removed", "%{count} duplicates removed", n)
        end
      ),
      nonzero(
        count(summary, ["transactions", "deleted_by_reason", "collapsed_split"]),
        &removed_for("collapsed_split", &1)
      ),
      nonzero(count(summary, ["quotes", "moved"]), fn n ->
        ngettext("%{count} quote added", "%{count} quotes added", n)
      end),
      nonzero(dropped, fn n ->
        ngettext("%{count} setting dropped", "%{count} settings dropped", n)
      end)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  def result_phrase(_account_kind, summary) do
    [
      moved_phrase(summary),
      nonzero(count(summary, ["transactions", "deleted"]), fn n ->
        ngettext("%{count} removed", "%{count} removed", n)
      end)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp moved_phrase(summary) do
    moved = count(summary, ["transactions", "moved"])
    ngettext("%{count} booking moved", "%{count} bookings moved", moved)
  end

  @doc """
  The disclosure's lines for a merge of `kind`: `{label, value}` per line
  with something to say, in the order of `@lines`.
  """
  @spec lines(atom(), map()) :: [{String.t(), String.t()}]
  def lines(kind, summary) do
    for line <- @lines,
        value = line_value(line, kind, summary),
        value not in [nil, ""],
        do: {line_label(line), value}
  end

  defp line_value(:bookings, _kind, summary) do
    reasons = get(summary, ["transactions", "deleted_by_reason"]) || %{}
    named = Enum.map(@reasons, &{&1, Map.get(reasons, &1, 0)})

    unnamed =
      count(summary, ["transactions", "deleted"]) - Enum.sum(Enum.map(named, &elem(&1, 1)))

    parts(
      [
        pngettext(
          "merge record",
          "%{count} moved",
          "%{count} moved",
          count(summary, ["transactions", "moved"])
        )
      ] ++
        Enum.map(named, fn {reason, n} -> nonzero(n, &removed_for(reason, &1)) end) ++
        [nonzero(unnamed, &ngettext("%{count} removed", "%{count} removed", &1))]
    )
  end

  defp line_value(:set_balances, _kind, summary) do
    parts([
      nonzero(count(summary, ["transactions", "restated"]), fn n ->
        pngettext("merge record", "%{count} adjusted", "%{count} adjusted", n)
      end),
      nonzero(count(summary, ["restated_anchors"]), fn n ->
        pngettext(
          "merge record",
          "%{count} now covers both accounts",
          "%{count} now cover both accounts",
          n
        )
      end)
    ])
  end

  defp line_value(:linked_depots, _kind, summary) do
    parts([
      nonzero(count(summary, ["securities_accounts", "repointed"]), fn n ->
        pngettext(
          "merge record",
          "%{count} moved to the target",
          "%{count} moved to the target",
          n
        )
      end)
    ])
  end

  defp line_value(:quotes, _kind, summary) do
    parts([
      nonzero(count(summary, ["quotes", "moved"]), fn n ->
        pngettext("merge record", "%{count} added", "%{count} added", n)
      end),
      nonzero(count(summary, ["quotes", "dropped"]), fn n ->
        pngettext(
          "merge record",
          "%{count} dropped, the target had one on that day",
          "%{count} dropped, the target had one on those days",
          n
        )
      end)
    ])
  end

  defp line_value(:classifications, _kind, summary) do
    parts([
      nonzero(count(summary, ["category_assignments", "moved"]), fn n ->
        pngettext("merge record", "%{count} assignment moved", "%{count} assignments moved", n)
      end),
      nonzero(count(summary, ["category_assignments", "dropped"]), &dropped/1)
    ])
  end

  defp line_value(:position_targets, _kind, summary) do
    parts([
      nonzero(count(summary, ["position_targets", "moved"]), &moved/1),
      nonzero(count(summary, ["position_targets", "deleted"]), &dropped/1)
    ])
  end

  defp line_value(:events, _kind, summary) do
    parts([
      nonzero(count(summary, ["security_events", "moved"]), &moved/1),
      nonzero(count(summary, ["security_events", "possible_duplicates"]), fn n ->
        pngettext(
          "merge record",
          "%{count} possibly twice now",
          "%{count} possibly twice now",
          n
        )
      end)
    ])
  end

  defp line_value(:splits, _kind, summary) do
    parts([
      nonzero(count(summary, ["split_events", "source"]), fn n ->
        pngettext("merge record", "%{count} of the source", "%{count} of the source", n)
      end),
      nonzero(count(summary, ["split_events", "target"]), fn n ->
        pngettext("merge record", "%{count} of the target", "%{count} of the target", n)
      end)
    ])
  end

  defp line_value(:position_buckets, _kind, summary) do
    parts([
      nonzero(count(summary, ["position_bucket_overrides", "carried"]), &carried/1),
      nonzero(count(summary, ["position_bucket_overrides", "dropped"]), &dropped/1),
      nonzero(count(summary, ["position_bucket_overrides", "cleared"]), fn n ->
        pngettext(
          "merge record",
          "%{count} cleared on the target",
          "%{count} cleared on the target",
          n
        )
      end)
    ])
  end

  defp line_value(:buckets, _kind, summary) do
    parts([
      nonzero(
        count(summary, ["cash_account_buckets", "removed"]) +
          count(summary, ["securities_account_buckets", "removed"]),
        &ngettext("%{count} removed", "%{count} removed", &1)
      )
    ])
  end

  defp line_value(:former_names, _kind, summary) do
    parts([
      nonzero(count(summary, ["former_names", "appended"]), &carried/1),
      nonzero(count(summary, ["former_names", "not_kept"]), fn n ->
        pngettext("merge record", "%{count} not kept", "%{count} not kept", n)
      end)
    ])
  end

  defp line_value(:former_isins, _kind, summary) do
    parts([nonzero(count(summary, ["identifier_aliases", "reassigned"]), &carried/1)])
  end

  # #1167: an ISIN adopted from the source is named on the ISIN line, so the
  # count here leaves it out. The record lists it among identifiers.adopted
  # exactly when the source alone carried an ISIN (ADR-0050 §9), the ISIN
  # line's own condition; the stored record keeps its shape.
  defp line_value(:master_data, _kind, summary) do
    adopted = count(summary, ["identifiers", "adopted"])

    parts([
      nonzero(if(source_isin_only?(summary), do: adopted - 1, else: adopted), fn n ->
        pngettext(
          "merge record",
          "%{count} field adopted, the target had none",
          "%{count} fields adopted, the target had none",
          n
        )
      end),
      nonzero(count(summary, ["identifiers", "differences"]), fn n ->
        pngettext(
          "merge record",
          "%{count} differs, the target's stands",
          "%{count} differ, the target's stand",
          n
        )
      end)
    ])
  end

  defp line_value(:rounding, _kind, summary) do
    parts([
      nonzero(count(summary, ["rounding_differences"]), fn n ->
        pngettext("merge record", "%{count} difference", "%{count} differences", n)
      end)
    ])
  end

  # #1067 (board 07.5): the line keys on the ISINs the record holds, not on
  # the choice it was given. An API or MCP merge recorded a choice as given
  # even when none was required (a record written before #1159 still holds
  # one), and keying on it printed "stays; is now a former ISIN" with an
  # empty slot. Neither side, or the target alone: no
  # line, nothing changed. The source alone: the target adopted it. Both: the
  # choice the merge required, as given.
  defp line_value(:isin, :security, summary) do
    source = isin(get(summary, ["identifiers", "source_isin"]))
    target = isin(get(summary, ["identifiers", "target_isin"]))
    changed_on = get(summary, ["identifier_aliases", "created", "changed_on"])

    case {source, target} do
      {nil, _target} ->
        nil

      {source, nil} ->
        gettext("%{isin} adopted from the source", isin: source)

      {source, target} ->
        both_isins(get(summary, ["choices", "identity_choice"]), source, target, changed_on)
    end
  end

  defp line_value(:isin, _kind, _summary), do: nil

  # The collapse choice the record holds. A merge records one only where it
  # had key-equal pairs to choose about (#1159's rule, for
  # collapse_key_equal), so a merge with nothing to choose has no line; a
  # record stored before holds the choice as sent and reads as it did.
  defp line_value(:choice, _kind, summary) do
    case get(summary, ["choices", "collapse_key_equal"]) do
      true -> gettext("equal bookings: removed as duplicates")
      false -> gettext("equal bookings: both kept")
      _none -> nil
    end
  end

  # The identity check the merge passed (§10). A merge whose source moved
  # nothing — no booking moved, none removed — had nothing to check, and says
  # so for every kind (#1032, pick H8.7): the cash writer checks today and
  # the target's own booking dates too, so its count alone would read "on 3
  # days" for an empty source. The record's payload is unchanged.
  defp line_value(:check, kind, summary) do
    dates = count(summary, ["linearity", "dates_checked"])
    days = pngettext("merge check", "on %{count} day", "on %{count} days", dates)
    empty? = moved_nothing?(summary)

    case {kind, dates} do
      {_kind, 0} ->
        gettext("nothing to check")

      _empty when empty? ->
        gettext("nothing to check")

      {:cash_account, _dates} ->
        gettext("Balance confirmed %{days}", days: days)

      {:securities_account, _dates} ->
        case count(summary, ["linearity", "securities_checked"]) do
          0 ->
            gettext("nothing to check")

          securities ->
            gettext("Quantity confirmed %{days} for %{securities}",
              days: days,
              securities:
                pngettext("merge check", "%{count} security", "%{count} securities", securities)
            )
        end

      {:security, _dates} ->
        case count(summary, ["linearity", "depots_checked"]) do
          0 ->
            gettext("nothing to check")

          depots ->
            gettext("Quantity confirmed %{days} in %{depots}",
              days: days,
              depots: pngettext("merge check", "%{count} depot", "%{count} depots", depots)
            )
        end
    end
  end

  # A day the record stores as ISO text, said in the page's language (Sprint
  # 19 U3); a text that does not read as a date is said as stored.
  defp stored_day(text) do
    case BoundedDate.parse(text) do
      {:ok, date} -> Format.date(date)
      {:error, _reason} -> text
    end
  end

  defp moved_nothing?(summary),
    do:
      count(summary, ["transactions", "moved"]) + count(summary, ["transactions", "deleted"]) == 0

  # The ISIN line when both securities carried one (#1067): the merge
  # required the choice, so the given choice is the one it made.
  defp both_isins("keep_target_isin", source, target, _changed_on),
    do: gettext("%{isin} stays; %{former} is now a former ISIN", isin: target, former: source)

  defp both_isins("adopt_source_isin", source, target, changed_on) do
    parts([
      gettext("%{isin} adopted; %{former} is now a former ISIN", isin: source, former: target),
      is_binary(changed_on) && gettext("change dated %{date}", date: stored_day(changed_on))
    ])
  end

  defp both_isins(_no_choice, _source, _target, _changed_on), do: nil

  # A recorded ISIN, or nil for none: a blank one is none.
  defp isin(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      isin -> isin
    end
  end

  defp isin(_none), do: nil

  # The source alone carried an ISIN: the one the target adopted from it.
  defp source_isin_only?(summary) do
    isin(get(summary, ["identifiers", "source_isin"])) != nil and
      isin(get(summary, ["identifiers", "target_isin"])) == nil
  end

  defp removed_for("collapsed_duplicate", n),
    do: ngettext("%{count} duplicate removed", "%{count} duplicates removed", n)

  defp removed_for("internal_transfer", n),
    do:
      pngettext(
        "merge record",
        "%{count} internal transfer dropped",
        "%{count} internal transfers dropped",
        n
      )

  defp removed_for("folded_anchor", n),
    do:
      pngettext(
        "merge record",
        "%{count} same-day set balance dropped",
        "%{count} same-day set balances dropped",
        n
      )

  defp removed_for("collapsed_split", n),
    do: pngettext("merge record", "%{count} split collapsed", "%{count} splits collapsed", n)

  defp moved(n), do: pngettext("merge record", "%{count} moved", "%{count} moved", n)
  defp dropped(n), do: pngettext("merge record", "%{count} dropped", "%{count} dropped", n)

  defp carried(n),
    do: pngettext("merge record", "%{count} carried over", "%{count} carried over", n)

  defp nonzero(n, fun) when is_integer(n) and n > 0, do: fun.(n)
  defp nonzero(_n, _fun), do: nil

  defp parts(list) do
    case Enum.filter(list, &is_binary/1) do
      [] -> nil
      present -> Enum.join(present, " · ")
    end
  end

  defp get(summary, path) do
    Enum.reduce_while(path, summary, fn
      key, %{} = map -> {:cont, Map.get(map, key)}
      _key, _leaf -> {:halt, nil}
    end)
  end

  defp count(summary, path) do
    case get(summary, path) do
      n when is_integer(n) -> n
      _other -> 0
    end
  end
end
