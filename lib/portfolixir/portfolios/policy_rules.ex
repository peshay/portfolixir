defmodule Portfolixir.Portfolios.PolicyRules do
  @moduledoc """
  Policy rules as first-class objects (ADR-0049, FR-43): the operator's caps,
  floors and bands, stored as rows instead of prose in a scheduled prompt.

  A rule is a **standard in force over a period** (§4). Its identity
  (`Portfolixir.Portfolios.PolicyRule`: context and name) is stable; its
  predicate lives on **versions** (`Portfolixir.Portfolios.PolicyRuleVersion`),
  each in force over `[valid_from, valid_until]`. So "what was the standard on
  date D" is a read (`version_on/2`), not a reconstruction from the journal.

  ## The writes (§8), and what each one may touch

    * `create_rule/3` — the rule with its first version.
    * `add_version/4` — the **edit**. The new version starts on `valid_from`
      (today by default, never earlier); the previous version is closed the
      day before. A version not yet in force that starts on or after the new
      one is replaced — that is how a scheduled version is edited.
    * `retire_rule/4` — closes the version in force (yesterday by default).
      The rule and every version stay readable.
    * `delete_rule/3` — only while **no** version has ever been in force:
      nothing was ever measured against it.

  **A version that has been in force is immutable**: never updated, never
  deleted; only its `valid_until` is set when an edit or a retirement closes
  it, and never to a day already past. "In force" is decided against the
  host's calendar day (`Portfolixir.Clock`, overridable with `today:` for
  tests); the database refuses a write that bypasses this module, and refuses
  two overlapping versions of one rule outright.

  Every write is journaled (ADR-0017; both tables are guard-armed from their
  first migration) and bumps the portfolio's **rules counter**
  (`Portfolixir.Derived.DataVersion.rules_basis/1`, through
  `Portfolixir.Derived.Invalidation.after_rule_write/2`) in the same transaction,
  so a findings read keyed on it never outlives an edited cap (§5).

  Nothing here evaluates a rule: that is
  `Portfolixir.Engines.PolicyEvaluation`, over measures read from the
  existing payloads.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Classifications.Category
  alias Portfolixir.Clock
  alias Portfolixir.Derived.Invalidation
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios.PolicyRule
  alias Portfolixir.Portfolios.PolicyRuleVersion
  alias Portfolixir.Repo

  @type status :: :in_force | :scheduled | :retired
  @type write_error ::
          Ecto.Changeset.t()
          | {:version, Ecto.Changeset.t()}
          | :in_force
          | :never_in_force
          | :already_retired

  # -- writes ------------------------------------------------------------------

  @doc """
  Creates a rule with its first version, journaled under `actor`.

  `attrs` carries `portfolio_id`, `view_id` (optional; the context view),
  `name`, and `version` — the predicate of `PolicyRuleVersion` with an
  optional `valid_from` (today by default, never earlier).

  Returns `{:ok, rule}` (versions preloaded), `{:error, changeset}` for the
  rule's own fields, or `{:error, {:version, changeset}}` for the version's.
  """
  @spec create_rule(Actor.t(), map(), keyword()) ::
          {:ok, PolicyRule.t()} | {:error, write_error()}
  def create_rule(%Actor{} = actor, attrs, opts \\ []) when is_map(attrs) do
    today = today(opts)
    rule_changeset = PolicyRule.changeset(%PolicyRule{}, attrs)
    version_attrs = version_attrs(attr(attrs, :version), today)

    # The version is validated before anything is written, against a
    # placeholder rule id the insert replaces.
    with {:rule, true} <- {:rule, rule_changeset.valid?},
         {:ok, _valid} <- validate_version(version_attrs, 0, today) do
      transaction(fn ->
        with {:ok, rule} <- journaled_insert(actor, rule_changeset, "policy_rule"),
             {:ok, _version} <-
               journaled_insert(
                 actor,
                 PolicyRuleVersion.changeset(
                   %PolicyRuleVersion{},
                   Map.put(version_attrs, "policy_rule_id", rule.id)
                 ),
                 "policy_rule_version"
               )
               |> tag_version_error() do
          Invalidation.after_rule_write(rule.portfolio_id, Repo)
          rule.id
        end
      end)
      |> reload()
    else
      {:rule, false} -> {:error, %{rule_changeset | action: :insert}}
      {:error, {:version, _changeset}} = error -> error
    end
  end

  @doc """
  Adds a version to `rule` — the edit (§4), journaled under `actor`.

  `attrs` is the new predicate with an optional `valid_from` (today by
  default; never before today, and after the start of the version in force).
  The version in force, or the last scheduled one, is closed the day before
  the new start; a version not yet in force that starts on or after the new
  one is replaced.

  Returns `{:ok, version}` or `{:error, changeset}`.
  """
  @spec add_version(Actor.t(), PolicyRule.t(), map(), keyword()) ::
          {:ok, PolicyRuleVersion.t()} | {:error, write_error()}
  def add_version(%Actor{} = actor, %PolicyRule{} = rule, attrs, opts \\ []) when is_map(attrs) do
    today = today(opts)
    attrs = version_attrs(attrs, today)

    with {:ok, changeset} <- validate_version(attrs, rule.id, today) |> untag() do
      valid_from = Ecto.Changeset.get_field(changeset, :valid_from)

      transaction(fn ->
        versions = versions_of(rule.id)

        with :ok <- starts_after_in_force(changeset, versions, valid_from, today),
             :ok <- replace_scheduled(actor, versions, valid_from, today),
             :ok <- close_predecessor(actor, versions, valid_from),
             {:ok, version} <- journaled_insert(actor, changeset, "policy_rule_version") do
          Invalidation.after_rule_write(rule.portfolio_id, Repo)
          version
        end
      end)
    end
  end

  @doc """
  Retires `rule` (§4): sets `valid_until` on the version in force — yesterday
  by default, or `attrs.valid_until` (never before yesterday, never before the
  version's own start) — and drops every version that has not started: a
  retirement ends the rule, planned changes included.

  A rule none of whose versions has ever been in force is deleted, not
  retired: `{:error, :never_in_force}`. A rule already retired but scheduled
  to restart has the restart cancelled (its versions that have not started
  are dropped); one with nothing scheduled answers `{:error, :already_retired}`.
  """
  @spec retire_rule(Actor.t(), PolicyRule.t(), map(), keyword()) ::
          {:ok, PolicyRuleVersion.t()} | {:error, write_error()}
  def retire_rule(%Actor{} = actor, %PolicyRule{} = rule, attrs, opts \\ []) when is_map(attrs) do
    today = today(opts)

    transaction(fn ->
      versions = versions_of(rule.id)

      with {:ok, current} <- latest_started(versions, today) do
        case retirement_date(current, attr(attrs, :valid_until), today) do
          {:ok, until} -> retire_current(actor, rule, versions, current, until, today)
          {:error, :already_retired} -> cancel_restart(actor, rule, versions, current, today)
          error -> error
        end
      end
    end)
  end

  defp retire_current(actor, rule, versions, current, until, today) do
    with :ok <- replace_scheduled(actor, versions, Date.add(current.valid_from, 1), today),
         {:ok, closed} <- journaled_close(actor, current, until) do
      Invalidation.after_rule_write(rule.portfolio_id, Repo)
      closed
    end
  end

  defp cancel_restart(actor, rule, versions, current, today) do
    if Enum.any?(versions, &(not started?(&1, today))) do
      with :ok <- replace_scheduled(actor, versions, Date.add(current.valid_from, 1), today) do
        Invalidation.after_rule_write(rule.portfolio_id, Repo)
        current
      end
    else
      {:error, :already_retired}
    end
  end

  @doc """
  Deletes `rule` and its versions — only while none of them has ever been in
  force (§8): `{:error, :in_force}` otherwise, and the remedy is retiring it.
  """
  @spec delete_rule(Actor.t(), PolicyRule.t(), keyword()) ::
          {:ok, PolicyRule.t()} | {:error, write_error()}
  def delete_rule(%Actor{} = actor, %PolicyRule{} = rule, opts \\ []) do
    today = today(opts)

    transaction(fn ->
      versions = versions_of(rule.id)

      if Enum.any?(versions, &started?(&1, today)) do
        Repo.rollback(:in_force)
      else
        Enum.each(versions, &ok!(journaled_delete(actor, &1, "policy_rule_version")))
        deleted = ok!(journaled_delete(actor, %{rule | versions: []}, "policy_rule"))
        Invalidation.after_rule_write(rule.portfolio_id, Repo)
        deleted
      end
    end)
  end

  # -- reads -------------------------------------------------------------------

  @doc """
  One rule with its whole version history (oldest first), annotated like a
  list row relative to `as_of` (default today), or `nil`.
  """
  @spec get_rule(integer(), keyword()) :: PolicyRule.t() | nil
  def get_rule(id, opts \\ []) when is_integer(id) do
    case PolicyRule |> Repo.get(id) |> Repo.preload(:versions) do
      nil -> nil
      rule -> annotate(rule, Keyword.get(opts, :as_of) || Clock.today())
    end
  end

  @doc "The version of `rule_id` in force on `date`, or `nil`."
  @spec version_on(integer(), Date.t()) :: PolicyRuleVersion.t() | nil
  def version_on(rule_id, %Date{} = date) when is_integer(rule_id) do
    PolicyRuleVersion
    |> where([v], v.policy_rule_id == ^rule_id)
    |> where_in_force_on(date)
    |> Repo.one()
  end

  @doc """
  The rules of one portfolio, each annotated relative to `as_of` (default
  today) with its `status` (`in_force` · `scheduled` · `retired`), its
  `version_in_force` and its `next_version`.

  Options:

    * `:view` — `:any` (default: every context of the portfolio), `nil` (the
      portfolio-wide context only) or a view id (that context only);
    * `:as_of` — the date the status is read on;
    * `:include_retired` — `true` adds the rules retired by `as_of`;
    * `:updated_since` — a naive-UTC cut: rules whose row or any version was
      written strictly after it (FR-38);
    * `:limit`.

  Oldest rule first.
  """
  @spec list_rules(integer(), keyword()) :: [PolicyRule.t()]
  def list_rules(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    as_of = Keyword.get(opts, :as_of) || Clock.today()
    include_retired = Keyword.get(opts, :include_retired, false)

    PolicyRule
    |> where([r], r.portfolio_id == ^portfolio_id)
    |> maybe_context(Keyword.get(opts, :view, :any))
    |> maybe_updated_since(Keyword.get(opts, :updated_since))
    |> order_by([r], asc: r.id)
    |> preload(:versions)
    |> Repo.all()
    |> Enum.map(&annotate(&1, as_of))
    |> Enum.filter(&(include_retired or &1.status != :retired))
    |> take(Keyword.get(opts, :limit))
  end

  @doc """
  The `{rule, version}` pairs in force on `date` for one evaluation context
  (`view_id` `nil` = the portfolio-wide context) — the input of the findings
  read (§5). Oldest rule first.
  """
  @spec in_force(integer(), integer() | nil, Date.t()) :: [
          {PolicyRule.t(), PolicyRuleVersion.t()}
        ]
  def in_force(portfolio_id, view_id, %Date{} = date) when is_integer(portfolio_id) do
    PolicyRule
    |> where([r], r.portfolio_id == ^portfolio_id)
    |> maybe_context(view_id)
    |> join(:inner, [r], v in PolicyRuleVersion, on: v.policy_rule_id == r.id)
    |> where([_r, v], v.valid_from <= ^date and (is_nil(v.valid_until) or v.valid_until >= ^date))
    |> order_by([r, _v], asc: r.id)
    |> select([r, v], {r, v})
    |> Repo.all()
  end

  @doc """
  The rules that read an object, oldest first, each annotated with its status
  today — the answer a delete of that object gives instead of a foreign-key
  error (ADR-0049 §8). `kind` is `:security`, `:category`, `:classification`
  or `:view`; a view is read both as a rule's context and as a subject.

  Every version counts, retired ones included: a version that has been in
  force keeps its subject as part of the record of what the standard was, so
  the reference outlives the rule's evaluation.
  """
  @spec referencing(:security | :category | :classification | :view, integer()) ::
          [PolicyRule.t()]
  def referencing(kind, id)
      when kind in [:security, :category, :classification, :view] and is_integer(id) do
    rule_ids =
      from(v in PolicyRuleVersion, select: v.policy_rule_id, distinct: true)
      |> where_references(kind, id)

    PolicyRule
    |> where([r], r.id in subquery(rule_ids))
    |> or_context_view(kind, id)
    |> order_by([r], asc: r.id)
    |> preload(:versions)
    |> Repo.all()
    |> Enum.map(&annotate(&1, Clock.today()))
  end

  defp where_references(query, :security, id), do: where(query, [v], v.security_id == ^id)
  defp where_references(query, :category, id), do: where(query, [v], v.category_id == ^id)

  defp where_references(query, :classification, id),
    do: where(query, [v], v.classification_id == ^id)

  defp where_references(query, :view, id), do: where(query, [v], v.subject_view_id == ^id)

  defp or_context_view(query, :view, id), do: or_where(query, [r], r.view_id == ^id)
  defp or_context_view(query, _kind, _id), do: query

  @doc "Whether `version` has been in force by `today` (its start is reached)."
  @spec started?(PolicyRuleVersion.t(), Date.t()) :: boolean()
  def started?(%PolicyRuleVersion{valid_from: from}, %Date{} = today),
    do: Date.compare(from, today) != :gt

  # -- write internals ---------------------------------------------------------

  defp today(opts), do: Keyword.get(opts, :today) || Clock.today()

  # The version's attrs with `valid_from` defaulted to today; `valid_until`
  # and the rule reference are never taken from input.
  defp version_attrs(attrs, today) when is_map(attrs) do
    attrs =
      attrs
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.drop(["valid_until", "policy_rule_id", "id"])

    if attrs["valid_from"] in [nil, ""],
      do: Map.put(attrs, "valid_from", today),
      else: attrs
  end

  defp version_attrs(_attrs, today), do: version_attrs(%{}, today)

  # The changeset of a new version plus the two checks a changeset alone
  # cannot make: the start is never before today, and a category subject
  # belongs to its classification.
  defp validate_version(attrs, rule_id, today) do
    changeset =
      %PolicyRuleVersion{}
      |> PolicyRuleVersion.changeset(Map.put(attrs, "policy_rule_id", rule_id))
      |> validate_not_backdated(today)
      |> validate_category_membership()

    if changeset.valid?,
      do: {:ok, changeset},
      else: {:error, {:version, %{changeset | action: :insert}}}
  end

  defp untag({:error, {:version, changeset}}), do: {:error, changeset}
  defp untag(ok), do: ok

  defp tag_version_error({:error, %Ecto.Changeset{} = changeset}),
    do: {:error, {:version, changeset}}

  defp tag_version_error(ok), do: ok

  # §4, §10: a version never starts before today. A backdated start would
  # rewrite a period that already had its own standard (or none) and replay
  # the rule over it — ladder level (d), which the column exists to keep out.
  defp validate_not_backdated(changeset, today) do
    case Ecto.Changeset.get_field(changeset, :valid_from) do
      %Date{} = from ->
        if Date.compare(from, today) == :lt,
          do: Ecto.Changeset.add_error(changeset, :valid_from, "cannot be before today"),
          else: changeset

      _missing ->
        changeset
    end
  end

  defp validate_category_membership(changeset) do
    category_id = Ecto.Changeset.get_field(changeset, :category_id)
    classification_id = Ecto.Changeset.get_field(changeset, :classification_id)

    with true <- is_integer(category_id) and is_integer(classification_id),
         %Category{classification_id: owner} <- Repo.get(Category, category_id),
         false <- owner == classification_id do
      Ecto.Changeset.add_error(changeset, :category_id, "is not a category of the classification")
    else
      # A category that does not exist at all is the foreign key's error.
      _fits_or_absent -> changeset
    end
  end

  # The new version must start after the version in force started: a
  # version that has started is immutable, so a second one cannot take its
  # first day.
  defp starts_after_in_force(changeset, versions, valid_from, today) do
    blocking =
      Enum.find(versions, fn version ->
        started?(version, today) and Date.compare(version.valid_from, valid_from) != :lt
      end)

    case blocking do
      nil ->
        :ok

      version ->
        {:error,
         Ecto.Changeset.add_error(
           changeset,
           :valid_from,
           "must be after %{date}, the start of the version in force",
           date: version.valid_from
         )}
    end
  end

  # Versions not yet in force that start on or after `from` are replaced
  # (deleted, journaled): nothing was ever measured against them.
  defp replace_scheduled(actor, versions, from, today) do
    versions
    |> Enum.filter(&(not started?(&1, today) and Date.compare(&1.valid_from, from) != :lt))
    |> Enum.reduce_while(:ok, fn version, :ok ->
      case journaled_delete(actor, version, "policy_rule_version") do
        {:ok, _deleted} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # The latest version starting before `from` is closed the day before it,
  # unless it already ends earlier (a retired rule taken up again).
  defp close_predecessor(actor, versions, from) do
    predecessor =
      versions
      |> Enum.filter(&(Date.compare(&1.valid_from, from) == :lt))
      |> Enum.max_by(& &1.valid_from, Date, fn -> nil end)

    until = Date.add(from, -1)

    cond do
      is_nil(predecessor) ->
        :ok

      not is_nil(predecessor.valid_until) and Date.compare(predecessor.valid_until, until) != :gt ->
        :ok

      true ->
        case journaled_close(actor, predecessor, until) do
          {:ok, _closed} -> :ok
          error -> error
        end
    end
  end

  defp latest_started(versions, today) do
    case versions
         |> Enum.filter(&started?(&1, today))
         |> Enum.max_by(& &1.valid_from, Date, fn -> nil end) do
      nil -> {:error, :never_in_force}
      version -> {:ok, version}
    end
  end

  # Yesterday by default; never before yesterday (that would shorten a period
  # already measured) and never before the version's own start.
  defp retirement_date(current, requested, today) do
    yesterday = Date.add(today, -1)

    cond do
      not is_nil(current.valid_until) and Date.compare(current.valid_until, today) == :lt ->
        {:error, :already_retired}

      requested in [nil, ""] ->
        {:ok, latest_date(yesterday, current.valid_from)}

      true ->
        with {:ok, date} <- parse_date(requested),
             :ok <- not_before(date, latest_date(yesterday, current.valid_from)) do
          {:ok, date}
        end
    end
  end

  defp parse_date(%Date{} = date), do: {:ok, date}

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _malformed -> {:error, retire_error("is invalid")}
    end
  end

  defp parse_date(_value), do: {:error, retire_error("is invalid")}

  defp not_before(date, floor) do
    if Date.compare(date, floor) == :lt,
      do: {:error, retire_error("cannot be before %{date}", date: floor)},
      else: :ok
  end

  defp retire_error(message, keys \\ []) do
    %PolicyRuleVersion{}
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.add_error(:valid_until, message, keys)
    |> Map.put(:action, :update)
  end

  defp latest_date(a, b), do: if(Date.compare(a, b) == :lt, do: b, else: a)

  defp versions_of(rule_id) do
    PolicyRuleVersion
    |> where([v], v.policy_rule_id == ^rule_id)
    |> order_by([v], asc: v.valid_from, asc: v.id)
    |> lock("FOR UPDATE")
    |> Repo.all()
  end

  defp journaled_insert(actor, changeset, resource_type) do
    Multi.new()
    |> Multi.insert(:record, changeset)
    |> Journal.record(actor, resource_type: resource_type, operation: :create, source: :record)
    |> Repo.transaction()
    |> normalize_write()
  end

  defp journaled_close(actor, version, until) do
    Multi.new()
    |> Multi.update(:record, PolicyRuleVersion.close_changeset(version, until))
    |> Journal.record(actor,
      resource_type: "policy_rule_version",
      operation: :update,
      source: :record,
      before: version
    )
    |> Repo.transaction()
    |> normalize_write()
  end

  defp journaled_delete(actor, record, resource_type) do
    Multi.new()
    |> Multi.delete(:record, record)
    |> Journal.record(actor,
      resource_type: resource_type,
      operation: :delete,
      source: :record,
      before: record
    )
    |> Repo.transaction()
    |> normalize_write()
  end

  defp normalize_write({:ok, %{record: record}}), do: {:ok, record}

  defp normalize_write({:error, :record, %Ecto.Changeset{} = changeset, _}),
    do: {:error, changeset}

  defp normalize_write({:error, step, reason, _changes}), do: {:error, {step, reason}}

  defp ok!({:ok, value}), do: value
  defp ok!({:error, reason}), do: Repo.rollback(reason)

  # Runs `fun` in one transaction; a `{:error, reason}` it returns rolls the
  # whole write back and becomes the result.
  defp transaction(fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:error, reason} -> Repo.rollback(reason)
        value -> value
      end
    end)
  end

  defp reload({:ok, rule_id}), do: {:ok, get_rule(rule_id)}
  defp reload(error), do: error

  defp attr(attrs, key), do: Map.get(attrs, key, Map.get(attrs, to_string(key)))

  # -- read internals ----------------------------------------------------------

  defp where_in_force_on(query, date) do
    where(
      query,
      [v],
      v.valid_from <= ^date and (is_nil(v.valid_until) or v.valid_until >= ^date)
    )
  end

  defp maybe_context(query, :any), do: query
  defp maybe_context(query, nil), do: where(query, [r], is_nil(r.view_id))

  defp maybe_context(query, view_id) when is_integer(view_id),
    do: where(query, [r], r.view_id == ^view_id)

  defp maybe_updated_since(query, nil), do: query

  defp maybe_updated_since(query, %NaiveDateTime{} = cut) do
    changed_versions =
      from(v in PolicyRuleVersion, where: v.updated_at > ^cut, select: v.policy_rule_id)

    where(query, [r], r.updated_at > ^cut or r.id in subquery(changed_versions))
  end

  defp annotate(%PolicyRule{versions: versions} = rule, as_of) do
    in_force = Enum.find(versions, &in_force_on?(&1, as_of))

    next =
      versions
      |> Enum.filter(&(Date.compare(&1.valid_from, as_of) == :gt))
      |> Enum.min_by(& &1.valid_from, Date, fn -> nil end)

    status =
      cond do
        in_force -> :in_force
        next -> :scheduled
        true -> :retired
      end

    %{rule | status: status, version_in_force: in_force, next_version: next}
  end

  defp in_force_on?(%PolicyRuleVersion{valid_from: from, valid_until: until}, date) do
    Date.compare(from, date) != :gt and (is_nil(until) or Date.compare(until, date) != :lt)
  end

  defp take(rows, nil), do: rows
  defp take(rows, n) when is_integer(n) and n > 0, do: Enum.take(rows, n)
end
