defmodule Portfolixir.Invariants.ScopeB5SystemWritersAndSchedulersTest do
  use Portfolixir.DataCase, async: true

  # NFR-9 backstop B5 (Sprint 16 Lane N, #885). The gates it backs, as
  # registered in scope_b7_gate_registry_test.exs:
  #   gate:nongoal.automated_trading_or_payment
  #   gate:gated.level_d_backtesting
  #   gate:gated.b3_3_data_acquisition
  #   gate:gated.b3_7_push_delivery
  #   gate:gated.phase3_readonly_sync
  #
  # User story:
  # As the operator whose instance prepares decisions and never acts,
  # I want every module that writes the books as the system itself, and every
  # process that wakes itself up, to be listed by name with its reason, the
  # dormant what-if marker of the audit journal to stay unwritten, and the
  # date line of a policy rule to be out of the web layer's reach,
  # so that automation (a sync, a push, a trading loop), a persisted what-if
  # scenario, or a rule backdated into the history it is judged against
  # cannot arrive without a reviewer reading its registry entry first.
  #
  # Acceptance criteria:
  # - Every `system_job` actor built in lib/ is registered by module and label
  #   with a reason; a new one fails until registered, and a registered one
  #   that no longer exists fails as stale.
  # - Every module in lib/ that schedules its own wake-up (a timer message, an
  #   interval, a sleep loop, a GenServer timeout, a `receive ... after`, a
  #   cron library) is registered with a reason, under the same two-way rule.
  # - The audit journal's `scenario_id` (ADR-0017's marker for persisted
  #   what-if writes, FR-27, level (d)) stays dormant: only the registered
  #   modules name it, no call passes it, no table is named for a scenario and
  #   nothing references the column.
  # - No web module moves a policy rule's as-of line: none passes options to a
  #   rules function that reads "today" from them, none passes `today:` at all,
  #   and none builds a rule version outside `Portfolixir.Portfolios.PolicyRules`.
  # - Each matcher catches a synthetic violation, so a clean tree cannot pass
  #   vacuously.

  # `{module, system_job label} => reason`.
  @system_writers %{
    {"Portfolixir.Catalog", "logo"} =>
      "logo bookkeeping on a security (#766): presentation metadata, journaled under " <>
        "the fixed logo actor; it books nothing",
    {"Portfolixir.Classifications", "builtin_seed"} =>
      "seeds the built-in asset-class and currency trees at boot (#529), derived " <>
        "from the catalog's own data",
    {"Mix.Tasks.Portfolixir.BackfillSettlementLegs", "settlement_backfill"} =>
      "an operator-run, one-shot repair of settlement legs from recorded transactions",
    {"Mix.Tasks.Portfolixir.SeedScopeBuckets", "portfolio_scope_seed"} =>
      "an operator-run seed turning portfolios into scope buckets and views (ADR-0024)"
  }

  # `module => reason`.
  @self_scheduling %{
    "Portfolixir.Catalog.QuoteSync" =>
      "the periodic quote sync — quotes sit inside the line B3.3 draws (ADR-0005)",
    "Portfolixir.Fx.RateSync" =>
      "the periodic ECB rate sync — FX sits inside the line B3.3 draws (ADR-0007)",
    "Portfolixir.Catalog.LogoDiscovery" =>
      "drains the missing-logo queue and rescans it periodically; fetches images, " <>
        "writes presentation metadata only",
    "Portfolixir.Derived.Refresher" =>
      "debounces the rebuild of durable derived values after a write (ADR-0039)",
    "Portfolixir.Portfolios.Performance.Warmup" =>
      "re-warms the performance basis at the local day rollover (ADR-0039 amendment)",
    "Portfolixir.Auth.Throttle" =>
      "sweeps expired login-throttle entries from its ETS table (ADR-0045)",
    "Portfolixir.Imports.PreviewStore" =>
      "sweeps expired import previews; the preview itself waits for a confirm",
    "PortfolixirWeb.PortfolioLive" =>
      "clears the FX-sync success flash three seconds after it shows; dies with the page"
  }

  # Modules allowed to name the journal's `scenario_id` at all: the writer
  # seam that stores it (defaulting to nil), the schema, the API read-out, and
  # a reader that filters on it to leave what-if entries out.
  @scenario_modules %{
    "Portfolixir.Journal" => "the journal's writer seam; nothing passes the option",
    "Portfolixir.Journal.Entry" => "the audit-journal schema carrying the dormant column",
    "PortfolixirWeb.Api.V1.JSON" => "serializes the column on the journal read (always nil)",
    "Portfolixir.Lifecycle.FormerNamesBackfill" =>
      "reads the column only in an is_nil filter, so the former-name backfill " <>
        "(ADR-0050 §4) never replays a what-if rename; it writes no scenario_id"
  }

  @scheduler_calls %{
    Process: ~w(send_after sleep)a,
    erlang: ~w(send_after start_timer)a,
    timer: ~w(send_after send_interval apply_after apply_interval apply_repeatedly sleep)a
  }

  @lib Path.wildcard("lib/**/*.ex")
  @web Path.wildcard("lib/portfolixir_web/**/*.ex")

  describe "the registries" do
    test "every system_job writer is registered with a reason" do
      found = @lib |> Enum.flat_map(&system_writers(File.read!(&1))) |> MapSet.new()

      assert MapSet.size(found) > 0, "the system-writer scan found nothing"

      assert_registry(found, @system_writers, "system_job writers")
    end

    test "every self-scheduling process is registered with a reason" do
      found = @lib |> Enum.flat_map(&self_scheduling(File.read!(&1))) |> MapSet.new()

      assert MapSet.size(found) > 0, "the scheduler scan found nothing"

      assert_registry(found, @self_scheduling, "self-scheduling modules")
    end
  end

  describe "the dormant scenario marker" do
    test "only the registered modules name scenario_id, and no call passes it" do
      named = @lib |> Enum.flat_map(&scenario_mentions(File.read!(&1))) |> MapSet.new()

      assert_registry(named, @scenario_modules, "modules naming scenario_id")

      passed = Enum.flat_map(@lib, &scenario_writes(File.read!(&1), &1))

      assert passed == [],
             "A persisted what-if write is FR-27, behind the level-(d) gate:\n" <>
               Enum.join(passed, "\n")
    end

    test "no table is named for a scenario and nothing references the column" do
      %{rows: tables} =
        Repo.query!("""
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = current_schema() AND table_name LIKE '%scenario%'
        """)

      assert tables == []

      %{rows: [[column]]} =
        Repo.query!("""
        SELECT count(*) FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'audit_journal' AND column_name = 'scenario_id'
        """)

      assert column == 1, "the scan did not find audit_journal.scenario_id"

      %{rows: [[foreign_keys]]} =
        Repo.query!("""
        SELECT count(*)
        FROM information_schema.key_column_usage k
        JOIN information_schema.table_constraints c
          ON c.constraint_name = k.constraint_name AND c.table_schema = k.table_schema
        WHERE k.table_schema = current_schema()
          AND k.table_name = 'audit_journal' AND k.column_name = 'scenario_id'
          AND c.constraint_type = 'FOREIGN KEY'
        """)

      assert foreign_keys == 0
    end
  end

  describe "the policy rules' as-of line" do
    test "no web module moves it" do
      line_movers = line_movers(File.read!("lib/portfolixir/portfolios/policy_rules.ex"))

      assert Map.has_key?(line_movers, :add_version),
             "the versioning edit no longer reads today from its options; the scan is broken"

      offenders = Enum.flat_map(@web, &as_of_violations(File.read!(&1), &1, line_movers))

      assert offenders == [],
             "The web layer must not move a policy rule's as-of line (NFR-9 B5, " <>
               "level (d)):\n" <> Enum.join(offenders, "\n")
    end
  end

  describe "the matchers (self-test: a clean tree cannot pass vacuously)" do
    test "a synthetic system writer is found and fails the registry" do
      source = """
      defmodule Portfolixir.SyntheticSync do
        alias Portfolixir.Actor

        def run, do: write(Actor.system_job("account_sync"))
        def other, do: write(Actor.new(:system_job, "night_run"))
        def raw, do: write(%Actor{type: :system_job})
        def owner, do: write(Actor.owner_ui())
      end
      """

      found = MapSet.new(system_writers(source))

      assert found ==
               MapSet.new([
                 {"Portfolixir.SyntheticSync", "account_sync"},
                 {"Portfolixir.SyntheticSync", "night_run"},
                 {"Portfolixir.SyntheticSync", nil}
               ])

      assert unregistered(found, @system_writers) == found
    end

    test "a synthetic self-scheduling process is found, a duration helper is not" do
      source = """
      defmodule Portfolixir.SyntheticPoller do
        use GenServer

        @interval :timer.hours(6)

        def init(state) do
          :timer.send_interval(@interval, :poll)
          {:ok, state}
        end

        def handle_info(:poll, state) do
          Process.send_after(self(), :poll, @interval)
          {:noreply, state}
        end

        defmodule Loop do
          def run, do: Process.sleep(1_000)
        end
      end

      defmodule Portfolixir.SyntheticPure do
        def window, do: :timer.minutes(5)
      end
      """

      assert MapSet.new(self_scheduling(source)) ==
               MapSet.new(["Portfolixir.SyntheticPoller", "Portfolixir.SyntheticPoller.Loop"])
    end

    test "a process that wakes itself by timeout, receive-after or a cron library is found" do
      source = """
      defmodule Portfolixir.SyntheticTimeout do
        use GenServer
        @interval 3_600_000
        def init(state), do: {:ok, state, 3_600_000}
        def handle_info(:timeout, state), do: {:noreply, state, @interval}
      end

      defmodule Portfolixir.SyntheticReplyTimeout do
        def handle_call(:x, _from, state), do: {:reply, :ok, state, :timer.hours(1)}
      end

      defmodule Portfolixir.SyntheticLoop do
        def loop do
          receive do
            :stop -> :ok
          after
            60_000 -> loop()
          end
        end
      end

      defmodule Portfolixir.SyntheticCron do
        use Quantum, otp_app: :portfolixir
      end

      defmodule Portfolixir.SyntheticObanCron do
        def plugins, do: [{Oban.Plugins.Cron, crontab: [{"@daily", Worker}]}]
      end

      defmodule Portfolixir.SyntheticDrain do
        def drain do
          receive do
            _message -> drain()
          after
            0 -> :ok
          end
        end
      end

      defmodule Portfolixir.SyntheticHibernate do
        def init(state), do: {:ok, state, :hibernate}
        def handle_info(:x, state), do: {:noreply, state, {:continue, :more}}
        def fetch(id), do: {:ok, id, "label"}
      end
      """

      assert MapSet.new(self_scheduling(source)) ==
               MapSet.new([
                 "Portfolixir.SyntheticTimeout",
                 "Portfolixir.SyntheticReplyTimeout",
                 "Portfolixir.SyntheticLoop",
                 "Portfolixir.SyntheticCron",
                 "Portfolixir.SyntheticObanCron"
               ])
    end

    test "a synthetic scenario write is caught" do
      source = """
      defmodule Portfolixir.SyntheticWhatIf do
        alias Portfolixir.Journal

        def record(multi, actor),
          do: Journal.record(multi, actor, resource_type: "transaction", scenario_id: 7)
      end
      """

      assert scenario_mentions(source) == ["Portfolixir.SyntheticWhatIf"]
      assert [hit] = scenario_writes(source, "synthetic.ex")
      assert hit =~ "Journal.record"
    end

    test "synthetic as-of moves from the web layer are caught, a plain call is not" do
      context = """
      defmodule Portfolixir.Portfolios.PolicyRules do
        def add_version(actor, rule, attrs, opts \\\\ []) do
          today = today(opts)
          {actor, rule, attrs, today}
        end

        def list_rules(portfolio_id, opts \\\\ []), do: {portfolio_id, opts}

        defp today(opts), do: Keyword.get(opts, :today)
      end
      """

      movers = line_movers(context)

      assert movers == %{add_version: 3}

      web = """
      defmodule PortfolixirWeb.SyntheticRuleLive do
        alias Portfolixir.Portfolios.PolicyRules
        alias Portfolixir.Portfolios.PolicyRules, as: Rules
        alias Portfolixir.Portfolios.PolicyRuleVersion

        def a(actor, rule, attrs), do: PolicyRules.add_version(actor, rule, attrs, today: ~D[2020-01-01])
        def b(actor, rule, attrs, opts), do: Rules.add_version(actor, rule, attrs, opts)
        def c(id), do: PolicyRules.list_rules(id, today: ~D[2020-01-01])
        def d(attrs), do: PolicyRuleVersion.changeset(%PolicyRuleVersion{}, attrs)
        def ok(actor, rule, attrs), do: PolicyRules.add_version(actor, rule, attrs)
        def read(id), do: PolicyRules.list_rules(id, as_of: ~D[2020-01-01])
      end
      """

      offenders = as_of_violations(web, "synthetic.ex", movers)

      assert length(offenders) == 4, Enum.join(offenders, "\n")
      assert Enum.any?(offenders, &(&1 =~ "PolicyRuleVersion.changeset"))
    end
  end

  # --- registry assertion --------------------------------------------------

  defp assert_registry(found, registry, label) do
    for {entry, reason} <- registry do
      assert is_binary(reason) and String.length(reason) > 20,
             "#{label}: #{inspect(entry)} needs a written reason"
    end

    missing = unregistered(found, registry)
    stale = registry |> Map.keys() |> MapSet.new() |> MapSet.difference(found)

    assert MapSet.size(missing) == 0,
           "Unregistered #{label} (NFR-9 B5) — register each with its reason:\n" <>
             Enum.map_join(missing, "\n", &inspect/1)

    assert MapSet.size(stale) == 0,
           "Stale #{label} registry entries — remove them:\n" <>
             Enum.map_join(stale, "\n", &inspect/1)
  end

  defp unregistered(found, registry),
    do: MapSet.reject(found, &Map.has_key?(registry, &1))

  # --- matchers ------------------------------------------------------------

  # `{module, label}` for every system_job actor a module builds: through
  # `Actor.system_job/0,1`, `Actor.new(:system_job, _)` or a struct literal.
  defp system_writers(source) do
    source
    |> module_hits(fn
      {{:., _, [{:__aliases__, _, segments}, :system_job]}, _, args} ->
        if List.last(segments) == :Actor, do: [label(args)], else: []

      {{:., _, [{:__aliases__, _, segments}, :new]}, _, [:system_job | args]} ->
        if List.last(segments) == :Actor, do: [label(args)], else: []

      {:%, _, [{:__aliases__, _, segments}, {:%{}, _, fields}]} ->
        if List.last(segments) == :Actor and Keyword.keyword?(fields) and
             fields[:type] == :system_job,
           do: [label(List.wrap(fields[:label]))],
           else: []

      _node ->
        []
    end)
    |> Enum.uniq()
  end

  defp label([]), do: nil
  defp label([label | _]) when is_binary(label), do: label
  defp label(_computed), do: :computed

  # Every module that schedules its own wake-up: a timer call, a GenServer
  # callback returning a timeout (`{:ok, state, 3_600_000}`), a `receive` with
  # a non-zero `after`, or a cron library (`use Quantum`, Oban's cron plugin).
  defp self_scheduling(source) do
    source
    |> module_hits(fn
      {{:., _, [{:__aliases__, _, [:Process]}, fun]}, _, _} ->
        if fun in @scheduler_calls[:Process], do: [:scheduler], else: []

      {{:., _, [module, fun]}, _, _} when module in [:erlang, :timer] ->
        if fun in @scheduler_calls[module], do: [:scheduler], else: []

      {kind, _, [head, body]} when kind in [:def, :defp] ->
        if callback?(head) and returns_timeout?(body), do: [:timeout], else: []

      {:receive, _, [clauses]} when is_list(clauses) ->
        if wakes_after?(Keyword.get(clauses, :after)), do: [:receive_after], else: []

      {:use, _, [{:__aliases__, _, [:Quantum | _]} | _]} ->
        [:cron]

      {:__aliases__, _, [:Oban, :Plugins, :Cron]} ->
        [:cron]

      _node ->
        []
    end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
  end

  # A GenServer callback's name — `{:ok, 0, 0}` elsewhere is a count, not a
  # timeout.
  defp callback?({:when, _, [head | _guards]}), do: callback?(head)

  defp callback?({name, _, _args}),
    do: name in [:init, :handle_call, :handle_cast, :handle_info, :handle_continue]

  defp callback?(_head), do: false

  defp returns_timeout?(body) do
    {_ast, found} =
      Macro.prewalk(body, false, fn
        {:{}, _, [tag, _state, timeout]} = node, acc when tag in [:ok, :noreply] ->
          {node, acc or timeout?(timeout)}

        {:{}, _, [:reply, _reply, _state, timeout]} = node, acc ->
          {node, acc or timeout?(timeout)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # A GenServer timeout: an integer, a module attribute or a `:timer` duration
  # — never `:hibernate` or `{:continue, _}`.
  defp timeout?(timeout) when is_integer(timeout), do: true
  defp timeout?({:@, _, [{name, _, _}]}) when is_atom(name), do: true
  defp timeout?({{:., _, [:timer, _fun]}, _, _args}), do: true
  defp timeout?(_other), do: false

  # `after 0` drains a mailbox without waiting; any other `after` wakes the
  # process when nothing arrived.
  defp wakes_after?([{:->, _, [[0], _body]}]), do: false
  defp wakes_after?([_clause | _]), do: true
  defp wakes_after?(_none), do: false

  defp scenario_mentions(source) do
    source
    |> module_hits(fn
      :scenario_id -> [:mention]
      _node -> []
    end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
  end

  # Any call into a `Journal` module that hands it a `scenario_id:` option.
  defp scenario_writes(source, path) do
    source
    |> module_hits(fn
      {{:., _, [{:__aliases__, _, segments}, fun]}, _, args} ->
        if List.last(segments) == :Journal and Enum.any?(args, &keyword_with?(&1, :scenario_id)),
          do: ["#{path}: Journal.#{fun}/#{length(args)} passes scenario_id:"],
          else: []

      _node ->
        []
    end)
    |> Enum.map(&elem(&1, 1))
  end

  # `%{function => arity without options}` for every public rules function
  # that takes defaulted options and reads "today" from them — the seam a
  # caller could use to move the no-backdating line.
  defp line_movers(source) do
    {_ast, movers} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk(%{}, fn
        {:def, _, [head, body]} = node, acc ->
          {name, params} = head_parts(head)

          if (name && Enum.any?(params, &default?/1)) and reads_today?(body),
            do: {node, Map.put_new(acc, name, Enum.count(params, &(not default?(&1))))},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    movers
  end

  defp head_parts({:when, _, [head | _]}), do: head_parts(head)
  defp head_parts({name, _, params}) when is_atom(name) and is_list(params), do: {name, params}
  defp head_parts(_head), do: {nil, []}

  defp default?({:\\, _, _}), do: true
  defp default?(_param), do: false

  # A local `today(opts)` helper, or `Keyword.get(opts, :today)` /
  # `opts[:today]` read directly. `Clock.today()` alone is the host's date and
  # moves nothing; a read-side `as_of:` is a reading date, not the line.
  defp reads_today?(body) do
    {_ast, found} =
      Macro.prewalk(body, false, fn
        {:today, _, [_opts]} = node, _acc -> {node, true}
        {{:., _, [_module, :get]}, _, [_opts, :today | _]} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp as_of_violations(source, path, line_movers) do
    rules = alias_names(source, :PolicyRules)
    versions = alias_names(source, :PolicyRuleVersion)

    source
    |> module_hits(fn
      {{:., _, [{:__aliases__, _, segments}, fun]}, _, args} ->
        name = List.last(segments)
        arity = length(args)

        cond do
          name in rules and Map.has_key?(line_movers, fun) and arity > line_movers[fun] ->
            ["#{path}: PolicyRules.#{fun}/#{arity} hands over options, which carry today"]

          name in rules and Enum.any?(args, &keyword_with?(&1, :today)) ->
            ["#{path}: PolicyRules.#{fun}/#{arity} passes today:"]

          name in versions and fun in [:changeset, :close_changeset] ->
            ["#{path}: PolicyRuleVersion.#{fun}/#{arity} builds a version outside PolicyRules"]

          true ->
            []
        end

      _node ->
        []
    end)
    |> Enum.map(&elem(&1, 1))
  end

  # The short names a source uses for a module: its own last segment plus any
  # `alias ..., as:` rename.
  defp alias_names(source, last_segment) do
    {_ast, names} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([last_segment], fn
        {:alias, _, [{:__aliases__, _, segments}, [as: {:__aliases__, _, [short]}]]} = node,
        acc ->
          if List.last(segments) == last_segment, do: {node, [short | acc]}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    names
  end

  defp keyword_with?(list, key) when is_list(list),
    do: Enum.any?(list, &match?({^key, _}, &1))

  defp keyword_with?(_arg, _key), do: false

  # --- AST walk --------------------------------------------------------------

  # `[{module, hit}]`: `matcher` applied to every node and leaf atom, each hit
  # attributed to the innermost `defmodule` around it. Pipes are expanded
  # first, so `rule |> PolicyRules.add_version(attrs, opts)` counts its piped
  # argument.
  defp module_hits(source, matcher) do
    source
    |> Code.string_to_quoted!()
    |> Macro.prewalk(&unpipe/1)
    |> walk([], matcher)
  end

  defp unpipe({:|>, _, [left, right]} = node) do
    Macro.pipe(left, right, 0)
  rescue
    ArgumentError -> node
  end

  defp unpipe(node), do: node

  defp walk({:defmodule, _, [{:__aliases__, _, segments}, body]}, outer, matcher),
    do: walk(body, outer ++ segments, matcher)

  defp walk({form, _meta, args} = node, module, matcher) do
    Enum.map(matcher.(node), &{Enum.join(module, "."), &1}) ++
      walk(form, module, matcher) ++ walk(args, module, matcher)
  end

  defp walk({left, right}, module, matcher),
    do: walk(left, module, matcher) ++ walk(right, module, matcher)

  defp walk(list, module, matcher) when is_list(list),
    do: Enum.flat_map(list, &walk(&1, module, matcher))

  defp walk(leaf, module, matcher) when is_atom(leaf),
    do: Enum.map(matcher.(leaf), &{Enum.join(module, "."), &1})

  defp walk(_leaf, _module, _matcher), do: []
end
