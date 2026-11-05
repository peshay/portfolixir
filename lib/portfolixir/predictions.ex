defmodule Portfolixir.Predictions do
  @moduledoc """
  Predictions (ADR-0055): permanent records of a stated call on one
  security, resolved later against stored closes and scored for
  calibration. Ladder (c): it scores what was recorded before the outcome
  was known.

  This module is the storage and the write path (§§1–2). A prediction is
  written once and never changed: there is deliberately no update, no
  withdrawal and no delete function here, and the table refuses UPDATE,
  DELETE and TRUNCATE (the `create_predictions` migration). Adding one is a
  change to the ADR, not an implementation detail. A mistaken prediction
  stays and counts; a corrected one is a new prediction.

  Every write goes through `Portfolixir.Journal.record/3`: the table is
  guard-armed in the migration that created it, so an unjournaled insert is
  refused by the database.

  The status (`open`, `resolved`, `unresolved`), the outcome and the
  calibration report are derived at read (§§3–4) and are not stored:
  `resolve/2` and `list_with_resolution/2` (`Portfolixir.Predictions.Resolution`),
  and `calibration_report/2` (`Portfolixir.Predictions.Calibration`).
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Clock
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge.SecurityNote
  alias Portfolixir.Portfolios.Performance.WindowReturn
  alias Portfolixir.Predictions.Calibration
  alias Portfolixir.Predictions.Prediction
  alias Portfolixir.Predictions.Resolution
  alias Portfolixir.Repo

  @typedoc """
  The filters of `list_predictions/2`. The status filter of ADR-0055 §5 is
  derived at read and is `list_with_resolution/2`'s (`t:status_filter/0`).
  """
  @type filter ::
          {:security_id, pos_integer()}
          | {:author, :operator | :agent | String.t()}
          | {:model, String.t()}
          | {:due_before, Date.t()}
          | {:resolves_from, Date.t()}
          | {:resolves_to, Date.t()}
          | {:limit, pos_integer()}

  @typedoc "`list_with_resolution/2`'s status filter, an atom or its string."
  @type status_filter :: {:status, Resolution.status() | String.t()}

  @typedoc "One prediction with its resolution at read."
  @type resolved_entry :: %{prediction: Prediction.t(), resolution: Resolution.t()}

  @statuses ~w(open resolved unresolved)a

  @doc """
  Records one prediction on behalf of `actor`, journaled under it as
  `prediction` / create.

  `attrs` (string or atom keys, not mixed) carries the caller's fields of
  ADR-0055 §1:

    * `security_id` — required, an existing security;
    * `direction` — required, `"outperform"` or `"underperform"`;
    * `probability` — required, a decimal string (or a `Decimal`) from
      `"0.50"` to `"0.99"` in steps of 0.01, stored at two places; a float
      is refused;
    * `benchmark` — required, `"security:<id>"` (an existing security
      flagged `is_benchmark`, not the security itself) or `"rate:<decimal>"`
      (a fixed annual rate, `rate:0` for an absolute call);
    * `resolves_on` — required, 7 to 1,830 days after the UTC day of
      `made_at`;
    * `model` — up to 100 characters, required when the author is `agent`
      and refused when it is `operator`;
    * `note_id` — optional, a research-log entry of the same security;
    * `rationale` — optional, up to 4,000 characters.

  The system states the rest: `made_at` is the server's clock, `author` is
  `Portfolixir.Actor.author/1` of `actor` and `actor` is the token's name
  (the journal's actor label, `nil` for the pages or an unnamed token). A
  `made_at`, `author` or `actor` key in `attrs` is refused by name.

  `opts[:now]` injects the clock (a UTC `DateTime`, AR-2), for tests only;
  it defaults to the server's clock. **No web or MCP path may pass it**: a
  caller who chooses `made_at` can date a call after its outcome (§1).

  Returns `{:ok, prediction}` or `{:error, changeset}` with every field
  error at once.
  """
  @spec create_prediction(Actor.t(), map(), keyword()) ::
          {:ok, Prediction.t()} | {:error, Changeset.t()}
  def create_prediction(%Actor{} = actor, attrs, opts \\ []) when is_map(attrs) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    system = %{made_at: now, author: Actor.author(actor), actor: actor.label}

    changeset =
      %Prediction{}
      |> Prediction.changeset(attrs, system)
      |> validate_references()

    Multi.new()
    |> Multi.insert(:prediction, changeset)
    |> Journal.record(actor, resource_type: "prediction", operation: :create, source: :prediction)
    |> Repo.transaction()
    |> case do
      {:ok, %{prediction: prediction}} -> {:ok, prediction}
      {:error, _step, %Changeset{} = invalid, _changes} -> {:error, invalid}
    end
  end

  # The references the changeset can only check for shape: the security
  # exists, a benchmark security exists and is flagged, a linked note is an
  # entry of the same security. The foreign keys stand behind each (the
  # note's is composite, over (note_id, security_id)), so a row removed or
  # changed between this read and the insert is still refused.
  defp validate_references(changeset) do
    changeset
    |> validate_security()
    |> validate_benchmark_security()
    |> validate_note()
  end

  defp validate_security(changeset) do
    with id when is_integer(id) <- Changeset.get_change(changeset, :security_id),
         nil <- Repo.get(Security, id) do
      Changeset.add_error(changeset, :security_id, "does not exist")
    else
      _present_or_absent -> changeset
    end
  end

  defp validate_benchmark_security(changeset) do
    case Changeset.get_change(changeset, :benchmark_security_id) do
      nil ->
        changeset

      id ->
        case Repo.get(Security, id) do
          %Security{is_benchmark: true} ->
            changeset

          _not_flagged_or_gone ->
            if changeset.errors[:benchmark],
              do: changeset,
              else: Changeset.add_error(changeset, :benchmark, "is not a benchmark security")
        end
    end
  end

  defp validate_note(changeset) do
    case Changeset.get_change(changeset, :note_id) do
      nil ->
        changeset

      note_id ->
        security_id = Changeset.get_field(changeset, :security_id)

        case Repo.get(SecurityNote, note_id) do
          %SecurityNote{security_id: ^security_id} ->
            changeset

          _other_security_or_gone ->
            Changeset.add_error(
              changeset,
              :note_id,
              "must reference a research-log entry of the same security"
            )
        end
    end
  end

  @doc """
  How many predictions name each of `security_ids`, as the security a call
  is about or as the benchmark it is scored against; a prediction naming a
  security both ways is counted once. Only the ids some prediction names
  are keys. A security merge refuses a source any prediction names
  (ADR-0050 §9, ADR-0055 §2).
  """
  @spec count_naming([integer()]) :: %{optional(integer()) => pos_integer()}
  def count_naming([]), do: %{}

  def count_naming(security_ids) when is_list(security_ids) do
    named =
      from(p in Prediction,
        where: p.security_id in ^security_ids,
        select: %{id: p.id, security_id: p.security_id}
      )
      |> union_all(
        ^from(p in Prediction,
          where: p.benchmark_security_id in ^security_ids,
          select: %{id: p.id, security_id: p.benchmark_security_id}
        )
      )

    from(n in subquery(named),
      group_by: n.security_id,
      select: {n.security_id, count(n.id, :distinct)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  The prediction's resolution at read (ADR-0055 §3,
  `Portfolixir.Predictions.Resolution`): `open` while today is on or
  before `resolves_on` and after it until its end close is in (at most 7
  days; ADR-0055 amendment of 2026-11-05, §2), then `resolved` with its
  outcome or `unresolved` with its reason, naming the closes, dates and
  returns used. Nothing is stored.

  `opts[:today]` injects today (AR-2), for tests; it defaults to the
  instance's calendar day, `Portfolixir.Clock.today/0`, the one "today"
  every domain check reads (E25 S6, G08).
  """
  @spec resolve(Prediction.t(), keyword()) :: Resolution.t()
  def resolve(%Prediction{} = prediction, opts \\ []) do
    Resolution.resolve(prediction, today(opts))
  end

  defp today(opts), do: Keyword.get_lazy(opts, :today, &Clock.today/0)

  @doc "One prediction by id, or `nil`."
  @spec get_prediction(integer()) :: Prediction.t() | nil
  def get_prediction(id) when is_integer(id), do: Repo.get(Prediction, id)

  @doc """
  The stored predictions, **newest first** (by `made_at`, then id).

  Filters, each optional and combined with AND:

    * `security_id` — the security the call is about;
    * `author` — `:operator` / `:agent` or its string; any other value
      matches nothing (and mints no atom);
    * `model` — the model an agent named, exactly;
    * `due_before` — the due query of ADR-0055 §5: **open** predictions
      whose `resolves_on` is on or before the date. Open is derived at
      read (`Portfolixir.Predictions.Resolution`): a call not yet past its
      date, and one past it still waiting for its end close (at most 7
      days; ADR-0055 amendment of 2026-11-05, §2), so this filter reads
      through `list_with_resolution/2`; a call already resolved or
      unresolved is not due;
    * `resolves_from`, `resolves_to` — `resolves_on` on or after, on or
      before the date (both inclusive);
    * `limit` — at most that many, newest first.

  `opts[:today]` injects the day the due query reads open against (AR-2),
  for tests; it defaults to `Portfolixir.Clock.today/0`, as `resolve/2`.
  """
  @spec list_predictions([filter()], keyword()) :: [Prediction.t()]
  def list_predictions(filters \\ [], opts \\ []) when is_list(filters) and is_list(opts) do
    if Keyword.has_key?(filters, :due_before),
      do: filters |> list_with_resolution(opts) |> Enum.map(& &1.prediction),
      else: list_stored(filters)
  end

  defp list_stored(filters) do
    Enum.reduce_while(filters, Prediction, fn filter, query ->
      case filter(query, filter) do
        :none -> {:halt, :none}
        query -> {:cont, query}
      end
    end)
    |> case do
      :none ->
        []

      query ->
        query
        |> order_by([p], desc: p.made_at, desc: p.id)
        |> Repo.all()
    end
  end

  @doc """
  The stored predictions with their resolution at read (`resolve/2`),
  **newest first**, as `%{prediction: prediction, resolution: resolution}`.

  Takes every filter of `list_predictions/2` and one more, `status`
  (ADR-0055 §5): `:open`, `:resolved` or `:unresolved`, or its string; any
  other value matches nothing (and mints no atom). With a status, `limit`
  counts the predictions that status kept, so the newest resolved call is
  found behind any number of newer open ones. `due_before` is the status
  `open` with `resolves_on` on or before its date, so beside another
  status it matches nothing. `opts[:today]` as in `list_predictions/2`.
  """
  @spec list_with_resolution([filter() | status_filter()], keyword()) :: [resolved_entry()]
  def list_with_resolution(filters \\ [], opts \\ []) when is_list(filters) and is_list(opts) do
    today = today(opts)
    {status_filters, storage} = Keyword.split(filters, [:status])
    {status_filters, storage} = due_as_open(status_filters, storage)

    case parse_status(status_filters) do
      :none ->
        []

      nil ->
        storage
        |> list_stored()
        |> with_resolution(today)

      status ->
        {limit, storage} = Keyword.pop(storage, :limit)

        (storage ++ status_window(status, today))
        |> list_stored()
        |> with_resolution(today)
        |> Enum.filter(&(&1.resolution.status == status))
        |> take(limit)
    end
  end

  @calibration_filters [:author, :model, :resolves_from, :resolves_to]

  @doc """
  The calibration report (ADR-0055 §4): the stored predictions the filters
  name, each resolved at read as of today (`resolve/2`), scored by
  `Portfolixir.Predictions.Calibration.report/1` (`counts`, `brier`,
  `sharpness`, `hit_rate`, `bands`, `groups`), with its
  `computation_basis`.

  Filters, each optional and combined with AND: `author`, `model`,
  `resolves_from` and `resolves_to` (inclusive), read as
  `list_predictions/2` reads them; any other filter raises
  `ArgumentError`, naming it. `opts[:today]` as in `list_predictions/2`.
  """
  @spec calibration_report(keyword(), keyword()) :: map()
  def calibration_report(filters \\ [], opts \\ []) when is_list(filters) and is_list(opts) do
    Enum.each(filters, fn {key, value} ->
      unless key in @calibration_filters,
        do: raise(ArgumentError, "unknown calibration filter #{inspect(key)}: #{inspect(value)}")
    end)

    filters
    |> list_with_resolution(opts)
    |> Calibration.report()
    |> Map.put(:computation_basis, Calibration.computation_basis())
  end

  defp with_resolution(predictions, today) do
    predictions
    |> Repo.preload([:security, :benchmark_security])
    |> Enum.map(&%{prediction: &1, resolution: Resolution.resolve(&1, today)})
  end

  # No status filter is nil; one status (or the same one repeated) is that
  # atom; an unknown value or two different statuses ANDed is :none.
  defp parse_status(status_filters) do
    status_filters
    |> Enum.map(fn {:status, value} -> status_atom(value) end)
    |> Enum.uniq()
    |> case do
      [] -> nil
      [status] when status in @statuses -> status
      _unknown_or_conflicting -> :none
    end
  end

  defp status_atom(status) when status in @statuses, do: status

  defp status_atom(status) when is_binary(status) do
    if status in Enum.map(@statuses, &Atom.to_string/1),
      do: String.to_existing_atom(status),
      else: :none
  end

  defp status_atom(_other), do: :none

  # The due query is the open status with resolves_on on or before its date
  # (ADR-0055 §5): each due_before becomes a resolves_to bound beside it.
  defp due_as_open(status_filters, storage) do
    case Keyword.pop_values(storage, :due_before) do
      {[], storage} ->
        {status_filters, storage}

      {dates, storage} ->
        {status_filters ++ [status: :open], storage ++ Enum.map(dates, &due_bound/1)}
    end
  end

  defp due_bound(%Date{} = date), do: {:resolves_to, date}

  defp due_bound(other),
    do: raise(ArgumentError, "unknown prediction filter :due_before: #{inspect(other)}")

  # The query narrows to the candidates before any close is read: a call is
  # open at most staleness_days after resolves_on (finality, ADR-0055
  # amendment of 2026-11-05, §2), and resolved or unresolved only once
  # resolves_on has passed. The status itself is the resolution's.
  defp status_window(:open, today),
    do: [resolves_from: Date.add(today, -WindowReturn.staleness_days())]

  defp status_window(_passed, today), do: [resolves_to: Date.add(today, -1)]

  defp take(entries, nil), do: entries
  defp take(entries, n) when is_integer(n) and n > 0, do: Enum.take(entries, n)

  defp take(_entries, n),
    do: raise(ArgumentError, "unknown prediction filter :limit: #{inspect(n)}")

  defp filter(query, {:security_id, id}) when is_integer(id),
    do: where(query, [p], p.security_id == ^id)

  defp filter(query, {:author, author}) when author in [:operator, :agent],
    do: where(query, [p], p.author == ^author)

  defp filter(query, {:author, author}) when is_binary(author) do
    if author in Prediction.authors(),
      do: filter(query, {:author, String.to_existing_atom(author)}),
      else: :none
  end

  defp filter(_query, {:author, _other}), do: :none

  defp filter(query, {:model, model}) when is_binary(model),
    do: where(query, [p], p.model == ^model)

  defp filter(query, {:resolves_from, %Date{} = date}),
    do: where(query, [p], p.resolves_on >= ^date)

  defp filter(query, {:resolves_to, %Date{} = date}),
    do: where(query, [p], p.resolves_on <= ^date)

  defp filter(query, {:limit, n}) when is_integer(n) and n > 0, do: limit(query, ^n)

  defp filter(_query, {key, value}) do
    raise ArgumentError, "unknown prediction filter #{inspect(key)}: #{inspect(value)}"
  end
end
