defmodule Portfolixir.Crashes do
  @moduledoc """
  Crash windows (FR-54, idea I24; ADR-0058): declines of 10 % or more in
  the stored closes of one benchmark security the operator chooses, the
  **crash benchmark** (`Portfolixir.Settings.crash_benchmark_security_id/0`,
  §1). The rule fixes a window's dates and is derived at read, never stored
  (§2), so every agent and the screen read the same windows.

  Unset, the rule detects nothing, and the read says why:
  `detected: []` with `reason: "no_crash_benchmark"` (§1); a chosen
  benchmark that is no benchmark any more (merged away since) answers
  `reason: "crash_benchmark_unavailable"`, never its survivor by a guess.

  The windows are `Portfolixir.Crashes.PeakTrough`'s over the benchmark's
  stored closes up to today, in its own currency and the current display
  basis (`Portfolixir.Catalog.Quotes.adjusted_range/3`, ADR-0028 §2), each
  keyed `d:<benchmark_security_id>:<start>` and of kind `"detected"`.
  Nothing is cached: the same closes give the same windows.

  **Names** (§3): a detected window is named by its key
  (`name_window/3`, `unname_window/2`), the name stored with the key's
  benchmark and start (`Portfolixir.Crashes.WindowName`) and journaled under
  its actor. `list_windows/0` reads each detected window with its name; a
  name whose key matches no window the rule detects now (the closes moved
  the start, or it was given for another crash benchmark) is listed under
  `unmatched_names` with its stored key and is never re-attached to another
  window by a guess. Switching the benchmark back restores its names.

  **Manual windows** (§4): a window a person draws, stored
  (`Portfolixir.Crashes.ManualWindow`), keyed `m:<id>` and of kind
  `"manual"` on every read, created, edited and deleted under its actor,
  journaled; it may overlap any window. A name without a window becomes
  one only with a trough the caller gives (`manual_window_from_name/3`,
  the amendment's F1): nothing is guessed from the closes.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Catalog.BenchmarkSecurity
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Clock
  alias Portfolixir.Crashes.ManualWindow
  alias Portfolixir.Crashes.PeakTrough
  alias Portfolixir.Crashes.Rankings
  alias Portfolixir.Crashes.WindowName
  alias Portfolixir.Journal
  alias Portfolixir.Repo
  alias Portfolixir.Settings

  # The floor of the series read, as the per-security metrics read it.
  @series_floor ~D[1900-01-01]

  # The fields each write takes (ADR-0058 §9: an unknown field is refused,
  # naming it).
  @name_fields ~w(name)
  @manual_fields ~w(name start trough)
  @from_name_fields ~w(name trough)

  # The largest id a bigint column holds: a longer key names nothing.
  @max_id 9_223_372_036_854_775_807

  @typedoc "The detected windows over the crash benchmark, or why there are none."
  @type detection :: %{
          benchmark: Security.t() | nil,
          detected: [map()],
          reason: String.t() | nil,
          basis: map()
        }

  @doc """
  The windows the rule detects over the crash benchmark's closes (ADR-0058
  §1, §2). With no crash benchmark chosen: `detected: []`, `reason:
  "no_crash_benchmark"`, `benchmark: nil`.
  """
  @spec detected() :: detection()
  def detected do
    case Settings.crash_benchmark_security_id() do
      nil -> none("no_crash_benchmark")
      id -> detected_for(id)
    end
  end

  defp detected_for(id) do
    case BenchmarkSecurity.resolve(id) do
      {:ok, security} ->
        %{
          benchmark: security,
          detected: windows(security),
          reason: nil,
          basis: basis(security)
        }

      {:error, _refusal} ->
        none("crash_benchmark_unavailable")
    end
  end

  defp windows(%Security{id: id}) do
    id
    |> Quotes.adjusted_range(@series_floor, Clock.today())
    |> PeakTrough.detect()
    |> Enum.map(&Map.merge(&1, %{key: PeakTrough.key(id, &1.start), kind: "detected"}))
  end

  @typedoc "A name whose key matches no window the rule detects now (§3)."
  @type unmatched_name :: %{
          key: String.t(),
          name: String.t(),
          benchmark_security_id: pos_integer(),
          benchmark_name: String.t() | nil,
          start: Date.t(),
          for_current_benchmark: boolean()
        }

  @typedoc "A write's refusal."
  @type refusal ::
          :not_found | {:unknown_fields, %{String.t() => [String.t()]}} | Ecto.Changeset.t()

  @doc """
  The crash windows as every reader reads them (ADR-0058 §3, §9):
  `detected/0`'s answer with each detected window's `name` (`nil` when
  unnamed); `manual`, the manual windows (§4), oldest start first, each
  with its key `m:<id>`, `kind: "manual"`, its dates and the creating
  token, listed whether or not a crash benchmark is chosen; and
  `unmatched_names`, the stored names whose key matches no
  window detected now, oldest start first. Each unmatched name carries its
  stored key, its benchmark's id and current name (`nil` when the security
  is gone), its start, and `for_current_benchmark`: `true` when it was given
  for the crash benchmark chosen now (its window moved or vanished with the
  closes), `false` when it was given for another one (switching back
  restores it).
  """
  @spec list_windows() :: %{
          benchmark: Security.t() | nil,
          detected: [map()],
          manual: [map()],
          unmatched_names: [unmatched_name()],
          reason: String.t() | nil,
          basis: map()
        }
  def list_windows do
    detection = detected()

    stored =
      Repo.all(from(n in WindowName, order_by: [asc: n.start, asc: n.benchmark_security_id]))

    by_key = Map.new(stored, &{name_key(&1), &1})
    detected_keys = MapSet.new(detection.detected, & &1.key)

    detected =
      Enum.map(detection.detected, fn window ->
        Map.put(window, :name, by_key |> Map.get(window.key) |> name_of())
      end)

    unmatched =
      stored
      |> Enum.reject(&MapSet.member?(detected_keys, name_key(&1)))
      |> unmatched_names(Settings.crash_benchmark_security_id())

    Map.merge(detection, %{detected: detected, manual: manual(), unmatched_names: unmatched})
  end

  @doc """
  The list of the window `key` over `universe` (ADR-0058 §5, §6; the
  amendment's F2, F3), as `Portfolixir.Crashes.Rankings` derives it: the
  window (a detected one, `d:`, as the rule detects it now; a manual one,
  `m:`), the list's entries, the crash benchmark's return beside them, the
  answers counted and the computation basis. `opts` take `:list`
  (`"losers"`, the default, `"winners"` or `"rebounders"`), `:limit` (default 8, at most
  50), `:include_unanswered` and `:today`.

  `universe` is `"catalogue"` or `"view:<id>"`, the securities the view
  holds today.

  `{:error, :invalid_list | :invalid_universe | :invalid_limit}` before
  anything is read; `{:error, :not_found}` for a key that names no window;
  `{:error, :view_not_found}` for a view that does not exist.
  """
  @spec rankings(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Rankings.refusal() | :not_found | :view_not_found}
  def rankings(key, universe, opts \\ []) when is_binary(key) do
    with {:ok, request} <- Rankings.request(universe, opts) do
      listing = list_windows()

      case Enum.find(listing.detected ++ listing.manual, &(&1.key == key)) do
        nil -> {:error, :not_found}
        window -> Rankings.rank(window, listing.benchmark, listing.reason, request)
      end
    end
  end

  defp manual do
    from(w in ManualWindow, order_by: [asc: w.start, asc: w.trough, asc: w.id])
    |> Repo.all()
    |> Enum.map(&manual_read/1)
  end

  defp manual_read(%ManualWindow{} = window) do
    window
    |> Map.take([:id, :name, :start, :trough, :author, :actor, :created_at, :updated_at])
    |> Map.merge(%{key: manual_key(window), kind: "manual"})
  end

  @doc """
  The write `PUT /api/v1/crashes/:key` makes (ADR-0058 §9): `name_window/3`
  for a detected window's key (`d:`), `update_manual_window/3` for a manual
  one's (`m:`). Any other key is `{:error, :not_found}`.
  """
  @spec put_window(Actor.t(), String.t(), map()) ::
          {:ok, WindowName.t() | ManualWindow.t()} | {:error, refusal()}
  def put_window(%Actor{} = actor, "d:" <> _rest = key, attrs), do: name_window(actor, key, attrs)

  def put_window(%Actor{} = actor, "m:" <> _rest = key, attrs),
    do: update_manual_window(actor, key, attrs)

  def put_window(%Actor{}, _key, _attrs), do: {:error, :not_found}

  @doc """
  The write `DELETE /api/v1/crashes/:key` makes (ADR-0058 §9):
  `unname_window/2` for a detected window's key (`d:`, its name, matched
  or not), `delete_manual_window/2` for a manual one's (`m:`). Any other
  key is `{:error, :not_found}`.
  """
  @spec delete_window(Actor.t(), String.t()) ::
          {:ok, WindowName.t() | ManualWindow.t()} | {:error, :not_found}
  def delete_window(%Actor{} = actor, "d:" <> _rest = key), do: unname_window(actor, key)
  def delete_window(%Actor{} = actor, "m:" <> _rest = key), do: delete_manual_window(actor, key)
  def delete_window(%Actor{}, _key), do: {:error, :not_found}

  @doc """
  Names the detected window `key` (`d:<benchmark_security_id>:<start>`) on
  behalf of `actor`, or renames it when it carries a name: `attrs` takes
  only `name` (§4's rule, `Portfolixir.Crashes.WindowName`). The key must
  name a window the rule detects now over the current crash benchmark,
  spelled as the read spells it; any other key is `{:error, :not_found}`,
  so a name is never given to a window nobody can read. A field the write
  does not take is `{:error, {:unknown_fields, errors}}` naming it. The
  write is journaled as a `"crash_window_name"` create or update; nothing
  is written on a refusal.
  """
  @spec name_window(Actor.t(), String.t(), map()) :: {:ok, WindowName.t()} | {:error, refusal()}
  def name_window(%Actor{} = actor, key, attrs) when is_binary(key) and is_map(attrs) do
    with :ok <- closed(attrs, @name_fields, "a window's name"),
         {:ok, benchmark_id, start} <- parse_detected_key(key),
         :ok <- detected_now(key) do
      Repo.transaction(fn ->
        lock_name!(benchmark_id, start)

        prior =
          Repo.one(
            from(n in WindowName,
              where: n.benchmark_security_id == ^benchmark_id and n.start == ^start
            )
          )

        case Repo.transaction(name_multi(actor, attrs, benchmark_id, start, prior)) do
          {:ok, %{window_name: written}} -> written
          {:error, _step, refusal, _changes} -> Repo.rollback(refusal)
        end
      end)
    end
  end

  @doc """
  Deletes the name stored under `key` (`d:<benchmark_security_id>:<start>`)
  on behalf of `actor`, journaled as a `"crash_window_name"` delete: the
  name of a detected window, or one listed under `unmatched_names`. A key
  that carries no name is `{:error, :not_found}`.
  """
  @spec unname_window(Actor.t(), String.t()) :: {:ok, WindowName.t()} | {:error, :not_found}
  def unname_window(%Actor{} = actor, key) when is_binary(key) do
    with {:ok, benchmark_id, start} <- parse_detected_key(key) do
      Repo.transaction(fn ->
        lock_name!(benchmark_id, start)

        case locked_name(benchmark_id, start) do
          nil -> Repo.rollback(:not_found)
          %WindowName{} = stored -> delete_name!(actor, stored)
        end
      end)
    end
  end

  # --- manual windows (§4; F1) ---

  @doc """
  Creates a manual window on behalf of `actor` from `attrs`, which take
  only `name`, `start` and `trough` (§4's rules, checked against
  `Portfolixir.Clock.today/0`); the creating token (`author`, `actor`) is
  derived from `actor`. Journaled as a `"crash_manual_window"` create. A
  field the write does not take is `{:error, {:unknown_fields, errors}}`
  naming it; nothing is written on a refusal.
  """
  @spec create_manual_window(Actor.t(), map()) :: {:ok, ManualWindow.t()} | {:error, refusal()}
  def create_manual_window(%Actor{} = actor, attrs) when is_map(attrs) do
    with :ok <- closed(attrs, @manual_fields, "a manual window") do
      actor
      |> insert_manual_multi(attrs)
      |> Repo.transaction()
      |> case do
        {:ok, %{manual_window: window}} -> {:ok, window}
        {:error, :manual_window, %Ecto.Changeset{} = invalid, _changes} -> {:error, invalid}
      end
    end
  end

  @doc """
  Edits the manual window `key` (`m:<id>`) on behalf of `actor`: `attrs`
  take any of `name`, `start` and `trough`, checked on the edited window
  under §4's rules. The creating token stays the creator's. Journaled as a
  `"crash_manual_window"` update with its before-image. A key that names
  no manual window is `{:error, :not_found}`.
  """
  @spec update_manual_window(Actor.t(), String.t(), map()) ::
          {:ok, ManualWindow.t()} | {:error, refusal()}
  def update_manual_window(%Actor{} = actor, key, attrs) when is_binary(key) and is_map(attrs) do
    with :ok <- closed(attrs, @manual_fields, "a manual window"),
         {:ok, prior} <- fetch_manual(key) do
      today = Clock.today()

      Multi.new()
      |> Multi.update(
        :manual_window,
        &(&1 |> Journal.locked_row() |> ManualWindow.changeset(attrs, today))
      )
      |> Journal.record(actor,
        resource_type: "crash_manual_window",
        operation: :update,
        source: :manual_window,
        before: prior
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{manual_window: window}} -> {:ok, window}
        {:error, :manual_window, %Ecto.Changeset{} = invalid, _changes} -> {:error, invalid}
        {:error, {:journal_lock, _step}, :not_found, _changes} -> {:error, :not_found}
      end
    end
  end

  @doc """
  Deletes the manual window `key` (`m:<id>`) on behalf of `actor`,
  journaled as a `"crash_manual_window"` delete with its before-image. A
  key that names no manual window is `{:error, :not_found}`.
  """
  @spec delete_manual_window(Actor.t(), String.t()) ::
          {:ok, ManualWindow.t()} | {:error, :not_found}
  def delete_manual_window(%Actor{} = actor, key) when is_binary(key) do
    with {:ok, prior} <- fetch_manual(key) do
      Multi.new()
      |> Multi.delete(:manual_window, prior)
      |> Journal.record(actor,
        resource_type: "crash_manual_window",
        operation: :delete,
        source: :manual_window,
        before: prior
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{manual_window: window}} -> {:ok, window}
        {:error, {:journal_lock, _step}, :not_found, _changes} -> {:error, :not_found}
      end
    end
  end

  @doc """
  Makes the name stored under `key` (`d:<benchmark_security_id>:<start>`),
  which no window detected now carries (an entry of `unmatched_names`),
  into a manual window on behalf of `actor` (ADR-0058 §3; amendment of
  2026-11-12, F1): its start is the name's stored start, its trough the
  one the caller gives, its name the stored one unless the caller gives
  another. `attrs` take only `name` and `trough`: the trough was never
  stored and is never guessed from today's closes, and the start is the
  key's. The manual window is created and the name deleted in one
  transaction, each journaled under `actor`.

  A key that carries no name is `{:error, :not_found}`; a name whose
  window the rule still detects is `{:error, :name_has_window}`; the
  trough follows §4's rules. Nothing is written on a refusal.
  """
  @spec manual_window_from_name(Actor.t(), String.t(), map()) ::
          {:ok, ManualWindow.t()} | {:error, refusal() | :name_has_window}
  def manual_window_from_name(%Actor{} = actor, key, attrs)
      when is_binary(key) and is_map(attrs) do
    with :ok <- closed(attrs, @from_name_fields, "a window made from a name"),
         {:ok, benchmark_id, start} <- parse_detected_key(key) do
      Repo.transaction(fn ->
        lock_name!(benchmark_id, start)
        stored = locked_name(benchmark_id, start) || Repo.rollback(:not_found)
        if detected_now(key) == :ok, do: Repo.rollback(:name_has_window)

        window_attrs =
          attrs
          |> Map.new(fn {field, value} -> {to_string(field), value} end)
          |> Map.put_new("name", stored.name)
          |> Map.put("start", stored.start)

        case Repo.transaction(insert_manual_multi(actor, window_attrs)) do
          {:ok, %{manual_window: window}} ->
            delete_name!(actor, stored)
            window

          {:error, _step, refusal, _changes} ->
            Repo.rollback(refusal)
        end
      end)
    end
  end

  defp insert_manual_multi(actor, attrs) do
    window = %ManualWindow{author: Actor.author(actor), actor: actor.label}

    Multi.new()
    |> Multi.insert(:manual_window, ManualWindow.changeset(window, attrs, Clock.today()))
    |> Journal.record(actor,
      resource_type: "crash_manual_window",
      operation: :create,
      source: :manual_window
    )
  end

  defp fetch_manual(key) do
    with {:ok, id} <- parse_manual_key(key),
         %ManualWindow{} = window <- Repo.get(ManualWindow, id) do
      {:ok, window}
    else
      _none -> {:error, :not_found}
    end
  end

  # A manual window's key, `m:<id>`, spelled exactly as the read spells it.
  defp parse_manual_key("m:" <> id_text = key) do
    with {id, ""} when id > 0 and id <= @max_id <- Integer.parse(id_text),
         true <- key == "m:#{id}" do
      {:ok, id}
    else
      _not_a_key -> {:error, :not_found}
    end
  end

  defp parse_manual_key(_key), do: {:error, :not_found}

  defp manual_key(%ManualWindow{id: id}), do: "m:#{id}"

  defp name_multi(actor, attrs, benchmark_id, start, nil) do
    window_name = %WindowName{benchmark_security_id: benchmark_id, start: start}

    Multi.new()
    |> Multi.insert(:window_name, WindowName.changeset(window_name, attrs))
    |> Journal.record(actor,
      resource_type: "crash_window_name",
      operation: :create,
      source: :window_name
    )
  end

  defp name_multi(actor, attrs, _benchmark_id, _start, %WindowName{} = prior) do
    Multi.new()
    |> Multi.update(:window_name, &(&1 |> Journal.locked_row() |> WindowName.changeset(attrs)))
    |> Journal.record(actor,
      resource_type: "crash_window_name",
      operation: :update,
      source: :window_name,
      before: prior
    )
  end

  defp delete_name!(actor, %WindowName{} = stored) do
    Multi.new()
    |> Multi.delete(:window_name, stored)
    |> Journal.record(actor,
      resource_type: "crash_window_name",
      operation: :delete,
      source: :window_name,
      before: stored
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{window_name: deleted}} -> deleted
      {:error, _step, refusal, _changes} -> Repo.rollback(refusal)
    end
  end

  # One writer per key at a time, so two first names of one window cannot
  # both pass the "no name yet" read.
  defp lock_name!(benchmark_id, start) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      "crash_window_name|" <> PeakTrough.key(benchmark_id, start)
    ])
  end

  defp locked_name(benchmark_id, start) do
    Repo.one(
      from(n in WindowName,
        where: n.benchmark_security_id == ^benchmark_id and n.start == ^start,
        lock: "FOR UPDATE"
      )
    )
  end

  defp detected_now(key) do
    if Enum.any?(detected().detected, &(&1.key == key)), do: :ok, else: {:error, :not_found}
  end

  # A detected window's key, spelled exactly as the read spells it: any
  # other spelling (a leading zero, a short date) names no window.
  defp parse_detected_key("d:" <> rest) do
    with [id_text, date_text] <- String.split(rest, ":", parts: 2),
         {id, ""} when id > 0 and id <= @max_id <- Integer.parse(id_text),
         {:ok, start} <- Date.from_iso8601(date_text),
         true <- PeakTrough.key(id, start) == "d:" <> rest do
      {:ok, id, start}
    else
      _not_a_key -> {:error, :not_found}
    end
  end

  defp parse_detected_key(_key), do: {:error, :not_found}

  # ADR-0058 §9: a field the write does not take is refused, naming it,
  # never dropped in silence.
  defp closed(attrs, fields, kind) do
    attrs
    |> Map.keys()
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 in fields))
    |> case do
      [] ->
        :ok

      unknown ->
        message = "is unknown: #{kind} takes only #{Enum.join(fields, ", ")}"
        {:error, {:unknown_fields, Map.new(unknown, &{&1, [message]})}}
    end
  end

  defp name_key(%WindowName{benchmark_security_id: id, start: start}),
    do: PeakTrough.key(id, start)

  defp name_of(nil), do: nil
  defp name_of(%WindowName{name: name}), do: name

  defp unmatched_names([], _benchmark), do: []

  defp unmatched_names(stored, current_id) do
    ids = stored |> Enum.map(& &1.benchmark_security_id) |> Enum.uniq()

    security_names =
      Map.new(Repo.all(from(s in Security, where: s.id in ^ids, select: {s.id, s.name})))

    Enum.map(stored, fn name ->
      %{
        key: name_key(name),
        name: name.name,
        benchmark_security_id: name.benchmark_security_id,
        benchmark_name: Map.get(security_names, name.benchmark_security_id),
        start: name.start,
        for_current_benchmark: name.benchmark_security_id == current_id
      }
    end)
  end

  defp none(reason), do: %{benchmark: nil, detected: [], reason: reason, basis: basis(nil)}

  # ADR-0058 §6: the parts of the computation basis the detection owns.
  defp basis(security) do
    %{
      rule: PeakTrough.rule(),
      threshold: PeakTrough.threshold(),
      comparison:
        "a window opens on the first close for which (peak - close) / peak >= 0.10, " <>
          "compared exactly in Decimal as (peak - close) x 10 >= peak, no rounding before it",
      peak_ties:
        "among equal highs the latest is the peak: the decline starts on the last day at the high",
      trough_ties: "among equal lows the earliest is the trough",
      input_series:
        "the crash benchmark's stored closes up to today, positive closes only, in date " <>
          "order; detected at read and never stored",
      currency: security && security.currency_code,
      currency_note: "the benchmark's own currency, never converted",
      split_adjustment:
        "closes in the current display basis: a booked split divides the raw closes " <>
          "before its effective date (ADR-0028 §2), so a split is not a fall",
      gaps:
        "a day without a close is skipped, never interpolated: a fall inside a gap shows " <>
          "on the first close after it, and each window names max_gap_days, the longest " <>
          "span in calendar days between two consecutive closes from its start to its " <>
          "recovery, or to the last close while it is provisional",
      recovery:
        "a window closes on the first close at or above its peak (recovered_on) and the " <>
          "walk continues from it; a window not recovered by the last close is " <>
          "provisional, its trough the lowest close so far"
    }
  end
end
