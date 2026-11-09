defmodule Portfolixir.News.Labels do
  @moduledoc """
  The labels of ADR-0056 §7: the one write (`put/2`, `news.label_put`) and
  the labeller's one read (`unlabeled/2`, `news.unlabeled`).

  ## A closed write

  §7: "`news.label_put` takes exactly those fields. The schema is closed."
  The write itself refuses, naming the key, anything outside
  `Portfolixir.News.Label.fields/0` — a `security_id`, a `tier`, a `status`,
  `notes`, a time — so no caller, the API's or another, writes more than a
  label through it. It refuses a value of the wrong JSON type naming its
  field too, before anything is cast: an integer field takes a JSON integer
  (not `"2"`, not `2.0`), a text field a string, `machine_generated` a
  boolean, and `confidence` a decimal **string** (a JSON number answers
  `"must be a decimal string"`, as every decimal the API takes, ADR-0003).

  ## What a label may name

  Checked inside the write's transaction, each refusal a field error:

    * `cluster_id` names a story that exists; its row is held `FOR KEY
      SHARE` until the write commits, so the story cannot be deleted under
      it. There is no foreign key (§12: labels are kept without limit, and
      a story follows its items out of retention or merges away);
    * `suggested_security_id`, when given, names a security that exists,
      held the same way;
    * `thesis_note_id`, when given, names a `thesis` entry of the story's
      own security (a category's story has none); `clause_idx`, when given,
      needs it and is one of that thesis's invalidation condition's clauses
      as `clauses/1` numbers them, the numbering `news.unlabeled` answers.

  ## Idempotent per (cluster, model, prompt version)

  A put of a triple already stored **replaces that label in place** — a
  full replacement: an optional field the put leaves out is cleared — and
  is journaled as an update whose before image is the old label; a put
  equal to the stored label writes and journals nothing (`:unchanged`).
  *Why replace, not ignore:* a labeller that corrects itself without a new
  prompt version is believed, and the old label stays readable in the
  journal; ignoring the second put would keep a label its own author
  withdrew. Puts of one triple are serialized by a transaction-scoped
  advisory lock on the triple, so two at once never race to a unique
  violation.

  Every write is journaled as `news_label` under the actor that made it,
  the API token's name (§7, §14 item 6; ADR-0054 §3), and the table is armed
  with the journal-actor guard.

  ## The labeller's read (`unlabeled/2`)

  The stories without a label of one prompt version, from any model, newest
  first by their first sight (then the best tier, then the id: a work
  queue, so a story labelled leaves it and the next call reads the next
  ones). Each row is what a label needs: the story's id, its security or
  category, its representative's title, excerpt, domain and publication
  time, and its best tier. Once per answer, the **universe** a label may
  name in `suggested_security_id` — the news universe
  (`Portfolixir.News.Universe`) and the rows' own securities, each with a
  name of at most 20 characters and its ISIN — and the rows' categories;
  and per security of the rows whose current thesis is intact and states an
  invalidation condition, the thesis's note id and the condition's
  **clauses** as `clauses/1` numbers them (the numbering `clause_idx` is
  checked against), at most six of them, with `more` counting the rest.

  **Its size** (§9; the amendment of 2026-11-08, C5): a title is cut at
  160, an excerpt at 600, a domain at 40 and a clause at 160 characters as
  the companion spells them (`Portfolixir.News.Reads.clip_spelled/2`); at
  most 25 rows, 10 by default.
  """
  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Classifications.Category
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.SecurityNote
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Item
  alias Portfolixir.News.Label
  alias Portfolixir.News.Reads
  alias Portfolixir.News.Universe
  alias Portfolixir.Repo

  @integers ~w(cluster_id materiality tone thesis_note_id clause_idx suggested_security_id)
  @texts ~w(model prompt_version event_type)
  @booleans ~w(machine_generated)
  @decimal_strings ~w(confidence)

  # Line breaks (and Unicode's line and paragraph separators) and semicolons
  # end a clause (§7).
  @clause_break ~r/\r\n|[\r\n;\x{2028}\x{2029}]/u

  @title_max 160
  @excerpt_max 600
  @domain_max 40
  @clause_max 160
  @clauses_listed 6
  @rank_sql "CASE ? WHEN 'primary' THEN 0 WHEN 'secondary' THEN 1 ELSE 2 END"

  @type written :: :created | :updated | :unchanged

  @type unlabeled :: %{
          rows: [map()],
          truncated: boolean(),
          universe: [%{id: pos_integer(), name: String.t(), isin: String.t() | nil}],
          categories: [%{id: pos_integer(), name: String.t()}],
          theses: [map()]
        }

  @doc """
  Stores the label `attrs` (string keys, as the JSON names them) on behalf
  of `actor`; see the moduledoc.

  Answers `{:ok, :created | :updated | :unchanged, label}`, `{:error,
  errors}` for a key outside the schema or a value of the wrong type
  (`%{"key" => [message]}`), or `{:error, changeset}`.
  """
  @spec put(Actor.t(), map()) ::
          {:ok, written(), Label.t()}
          | {:error, %{String.t() => [String.t()]}}
          | {:error, Changeset.t()}
  def put(%Actor{} = actor, attrs) when is_map(attrs) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

    with :ok <- shape(attrs) do
      changeset = Label.changeset(%Label{}, attrs)

      if changeset.valid?,
        do: write(actor, attrs, changeset),
        else: {:error, %{changeset | action: :insert}}
    end
  end

  @doc """
  The clauses of an invalidation condition (§7): the text split at line
  breaks and semicolons, each trimmed, the empty ones dropped. The first is
  clause 1. `nil` has none.
  """
  @spec clauses(String.t() | nil) :: [String.t()]
  def clauses(nil), do: []

  def clauses(condition) when is_binary(condition) do
    condition
    |> String.split(@clause_break)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  The stories without a label of `prompt_version`, at most `limit` of them,
  with the universe, the rows' categories and their securities' thesis
  clauses; see the moduledoc.
  """
  @spec unlabeled(String.t(), pos_integer()) :: unlabeled()
  def unlabeled(prompt_version, limit)
      when is_binary(prompt_version) and is_integer(limit) and limit > 0 do
    labelled =
      from(l in Label,
        where: l.cluster_id == parent_as(:story).id and l.prompt_version == ^prompt_version,
        select: 1
      )

    rows =
      from(c in Cluster,
        as: :story,
        join: i in Item,
        on: i.id == c.representative_item_id,
        where: not exists(subquery(labelled)),
        order_by: [
          desc: c.earliest_first_seen_at,
          asc: fragment(@rank_sql, c.best_tier),
          desc: c.id
        ],
        limit: ^(limit + 1),
        select: %{
          id: c.id,
          security_id: c.security_id,
          category_id: c.category_id,
          title: i.title,
          excerpt: i.excerpt,
          domain: i.domain,
          tier: c.best_tier,
          at: i.published_at
        }
      )
      |> Repo.all()

    {rows, more} = Enum.split(rows, limit)
    security_ids = rows |> Enum.map(& &1.security_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    %{
      rows: Enum.map(rows, &clip_row/1),
      truncated: more != [],
      universe: universe(security_ids),
      categories: categories(rows),
      theses: security_ids |> Enum.sort() |> Enum.flat_map(&thesis/1)
    }
  end

  defp clip_row(row) do
    %{
      row
      | title: Reads.clip_spelled(row.title, @title_max),
        excerpt: Reads.clip_spelled(row.excerpt, @excerpt_max),
        domain: Reads.clip_spelled(row.domain, @domain_max)
    }
  end

  # The news universe and the rows' own securities (an issuer feed's
  # security need not be held, targeted or watched), by id.
  defp universe(security_ids) do
    members = Universe.members()
    known = MapSet.new(members, & &1.id)

    others =
      case Enum.reject(security_ids, &MapSet.member?(known, &1)) do
        [] ->
          []

        ids ->
          Repo.all(
            from(s in Security,
              where: s.id in ^ids,
              select: %{id: s.id, name: s.name, isin: s.isin}
            )
          )
      end

    (members ++ others)
    |> Enum.map(&%{id: &1.id, name: Reads.short_name(&1.name), isin: &1.isin})
    |> Enum.sort_by(& &1.id)
  end

  defp categories(rows) do
    case rows |> Enum.map(& &1.category_id) |> Enum.reject(&is_nil/1) |> Enum.uniq() do
      [] ->
        []

      ids ->
        from(c in Category,
          where: c.id in ^ids,
          order_by: c.id,
          select: %{id: c.id, name: c.name}
        )
        |> Repo.all()
        |> Enum.map(&%{&1 | name: Reads.short_name(&1.name)})
    end
  end

  # The current thesis, when intact and stating a condition: its clauses as
  # `clauses/1` numbers them, the first six listed, each cut at 160.
  defp thesis(security_id) do
    with %{status: :intact, derived_from_entry_id: note_id, invalidation_condition: condition}
         when is_integer(note_id) <- Knowledge.thesis_state(security_id),
         [_ | _] = clauses <- clauses(condition) do
      {listed, rest} = Enum.split(clauses, @clauses_listed)

      [
        %{
          security_id: security_id,
          note_id: note_id,
          clauses:
            listed
            |> Enum.with_index(1)
            |> Enum.map(fn {text, idx} ->
              %{idx: idx, text: Reads.clip_spelled(text, @clause_max)}
            end),
          more: if(rest == [], do: nil, else: length(rest))
        }
      ]
    else
      _none -> []
    end
  end

  # -- the shape: keys and JSON types ------------------------------------------

  defp shape(attrs) do
    errors =
      attrs
      |> Enum.flat_map(fn {key, value} -> shape_error(key, value) end)
      |> Map.new()

    if errors == %{}, do: :ok, else: {:error, errors}
  end

  defp shape_error(key, value) do
    cond do
      key not in Label.fields() ->
        [{key, ["is unknown: a label takes only #{Enum.join(Label.fields(), ", ")}"]}]

      is_nil(value) ->
        []

      key in @integers and not is_integer(value) ->
        [{key, ["must be an integer"]}]

      key in @texts and not is_binary(value) ->
        [{key, ["must be a string"]}]

      key in @booleans and not is_boolean(value) ->
        [{key, ["must be true or false"]}]

      key in @decimal_strings and not is_binary(value) ->
        [{key, ["must be a decimal string"]}]

      true ->
        []
    end
  end

  # -- the write ---------------------------------------------------------------

  defp write(actor, attrs, changeset) do
    %{cluster_id: cluster_id, model: model, prompt_version: version} = changeset.changes

    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
        "news_label|#{cluster_id}|#{model}|#{version}"
      ])

      with {:ok, story} <- lock_story(changeset, cluster_id),
           :ok <- check_suggested(changeset),
           :ok <- check_thesis(changeset, story) do
        prior = Repo.get_by(Label, cluster_id: cluster_id, model: model, prompt_version: version)

        case Repo.transaction(label_multi(actor, attrs, prior)) do
          {:ok, %{label: label, journal_entry: :unchanged}} -> {:unchanged, label}
          {:ok, %{label: label}} -> {if(prior, do: :updated, else: :created), label}
          {:error, :label, %Changeset{} = invalid, _changes} -> Repo.rollback(invalid)
        end
      else
        {:error, refused} -> Repo.rollback(refused)
      end
    end)
    |> case do
      {:ok, {written, label}} -> {:ok, written, label}
      {:error, %Changeset{} = refused} -> {:error, %{refused | action: :insert}}
    end
  end

  defp label_multi(actor, attrs, nil) do
    Multi.new()
    |> Multi.insert(:label, Label.changeset(%Label{}, attrs))
    |> Journal.record(actor, resource_type: "news_label", operation: :create, source: :label)
  end

  defp label_multi(actor, attrs, %Label{} = prior) do
    Multi.new()
    |> Multi.update(:label, &(&1 |> Journal.locked_row() |> Label.changeset(attrs)))
    |> Journal.record(actor,
      resource_type: "news_label",
      operation: :update,
      source: :label,
      before: prior
    )
  end

  defp lock_story(changeset, cluster_id) do
    case Repo.one(from(c in Cluster, where: c.id == ^cluster_id, lock: "FOR KEY SHARE")) do
      nil -> {:error, Changeset.add_error(changeset, :cluster_id, "names no story")}
      story -> {:ok, story}
    end
  end

  defp check_suggested(changeset) do
    case Changeset.get_field(changeset, :suggested_security_id) do
      nil ->
        :ok

      id ->
        from(s in Security, where: s.id == ^id, lock: "FOR KEY SHARE", select: s.id)
        |> Repo.one()
        |> case do
          nil ->
            {:error, Changeset.add_error(changeset, :suggested_security_id, "names no security")}

          _id ->
            :ok
        end
    end
  end

  defp check_thesis(changeset, story) do
    note_id = Changeset.get_field(changeset, :thesis_note_id)
    clause = Changeset.get_field(changeset, :clause_idx)

    case thesis_refusal(note_id && Repo.get(SecurityNote, note_id), note_id, story, clause) do
      nil -> :ok
      {field, message} -> {:error, Changeset.add_error(changeset, field, message)}
    end
  end

  defp thesis_refusal(_note, nil, _story, _clause), do: nil
  defp thesis_refusal(nil, _id, _story, _clause), do: {:thesis_note_id, "names no note"}

  defp thesis_refusal(_note, _id, %Cluster{security_id: nil}, _clause),
    do: {:thesis_note_id, "is refused: a category's story has no thesis"}

  defp thesis_refusal(%SecurityNote{kind: kind, security_id: of}, _id, story, _clause)
       when kind != :thesis or of != story.security_id,
       do: {:thesis_note_id, "must name a thesis entry of the story's security"}

  defp thesis_refusal(_note, _id, _story, nil), do: nil

  defp thesis_refusal(%SecurityNote{} = note, _id, _story, clause) do
    count = length(clauses(note.invalidation_condition))

    if clause <= count,
      do: nil,
      else:
        {:clause_idx,
         "is not a clause of the thesis's invalidation condition, which has #{count}"}
  end
end
