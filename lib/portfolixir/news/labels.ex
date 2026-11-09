defmodule Portfolixir.News.Labels do
  @moduledoc """
  The labels of ADR-0056 §7: the one write (`put/2`, `news.label_put`).

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
  """
  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge.SecurityNote
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Label
  alias Portfolixir.Repo

  @integers ~w(cluster_id materiality tone thesis_note_id clause_idx suggested_security_id)
  @texts ~w(model prompt_version event_type)
  @booleans ~w(machine_generated)
  @decimal_strings ~w(confidence)

  # Line breaks (and Unicode's line and paragraph separators) and semicolons
  # end a clause (§7).
  @clause_break ~r/\r\n|[\r\n;\x{2028}\x{2029}]/u

  @type written :: :created | :updated | :unchanged

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
