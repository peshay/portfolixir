defmodule Portfolixir.Portfolios.PolicyRuleStatus do
  @moduledoc """
  The status of a policy rule and the writes it permits, named once
  (ADR-0059; ADR-0049 §4, §8, §9) — the one module the read annotation, the
  write guards of `Portfolixir.Portfolios.PolicyRules`, the API payload and
  the Risk page's buttons consult.

  Nothing here is stored. A rule's **status** on a date derives from its
  versions, each the standard of its own period `[valid_from, valid_until]`:

    * `:in_force` — a version covers the date;
    * `:scheduled` — none does, but a version starts after it (a rule not
      yet started, or a retired rule taken up again from a later date);
    * `:retired` — every version has ended by the date.

  What a rule **permits** is read against today, the day a write runs:

    * `:add_version` and `:rename` — always: an edit adds a version from a
      later date (a retired rule is taken up again that way), and the name
      is a label outside the versioning;
    * `:retire` — while a version is in force, or while a restart is
      scheduled, which a retirement cancels; refused as `:never_in_force`
      when no version has ever started (such a rule is deleted, not
      retired) and as `:already_retired` when the rule is retired with
      nothing scheduled;
    * `:delete` — only while no version has ever been in force: a standard
      somebody was measured against is never removed; refused as
      `:in_force` otherwise.

  The SQL filters of the list read (`maybe_not_retired`) and of the findings
  read (`in_force/3`) mirror `:in_force` and `:retired` in the query, so a
  long history is not loaded to answer a short list; they agree with
  `read/2` by construction and `policy_rules_test.exs` pins both.
  """
  @behaviour Portfolixir.Status

  alias Portfolixir.Portfolios.PolicyRuleVersion

  @statuses [:in_force, :scheduled, :retired]
  @actions [:add_version, :rename, :retire, :delete]

  @basis "Derived at read from the rule's versions, never stored: status is in_force " <>
           "when a version's [valid_from, valid_until] covers as_of, scheduled when none " <>
           "does but a version starts after it, retired otherwise; permits are the writes " <>
           "the rule accepts today: add_version and rename always, retire while a version " <>
           "is in force or a restart is scheduled (which it cancels), delete only while no " <>
           "version has ever been in force."

  @type status :: :in_force | :scheduled | :retired
  @type action :: :add_version | :rename | :retire | :delete
  @type refusal :: :in_force | :never_in_force | :already_retired

  @typedoc "The read annotation of one rule relative to a date."
  @type read :: %{
          status: status(),
          version_in_force: PolicyRuleVersion.t() | nil,
          next_version: PolicyRuleVersion.t() | nil
        }

  @impl true
  def statuses, do: @statuses

  @impl true
  def actions, do: @actions

  @impl true
  def basis, do: @basis

  @doc """
  The status of a rule with `versions` on `date`, with the version in force
  and the next version to start — the annotation of a list row (§9).
  """
  @spec read([PolicyRuleVersion.t()], Date.t()) :: read()
  def read(versions, %Date{} = date) when is_list(versions) do
    in_force = Enum.find(versions, &in_force_on?(&1, date))

    next =
      versions
      |> Enum.filter(&(Date.compare(&1.valid_from, date) == :gt))
      |> Enum.min_by(& &1.valid_from, Date, fn -> nil end)

    status =
      cond do
        in_force -> :in_force
        next -> :scheduled
        true -> :retired
      end

    %{status: status, version_in_force: in_force, next_version: next}
  end

  @impl true
  @spec status([PolicyRuleVersion.t()], Date.t()) :: status()
  def status(versions, %Date{} = date), do: read(versions, date).status

  @impl true
  @spec permits([PolicyRuleVersion.t()], Date.t()) :: [action()]
  def permits(versions, %Date{} = today) when is_list(versions),
    do: Enum.filter(@actions, &is_nil(refusal(versions, today, &1)))

  @impl true
  @spec refusal([PolicyRuleVersion.t()], Date.t(), action()) :: refusal() | nil
  def refusal(versions, %Date{} = today, :delete) when is_list(versions) do
    if Enum.any?(versions, &started?(&1, today)), do: :in_force
  end

  def refusal(versions, %Date{} = today, :retire) when is_list(versions) do
    cond do
      not Enum.any?(versions, &started?(&1, today)) -> :never_in_force
      Enum.any?(versions, &in_force_on?(&1, today)) -> nil
      Enum.any?(versions, &(not started?(&1, today))) -> nil
      true -> :already_retired
    end
  end

  def refusal(versions, %Date{}, action)
      when is_list(versions) and action in [:add_version, :rename],
      do: nil

  @doc "Whether `version` has been in force by `today` (its start is reached)."
  @spec started?(PolicyRuleVersion.t(), Date.t()) :: boolean()
  def started?(%PolicyRuleVersion{valid_from: from}, %Date{} = today),
    do: Date.compare(from, today) != :gt

  @doc "Whether `version` is the standard on `date`."
  @spec in_force_on?(PolicyRuleVersion.t(), Date.t()) :: boolean()
  def in_force_on?(%PolicyRuleVersion{valid_from: from, valid_until: until}, %Date{} = date) do
    Date.compare(from, date) != :gt and (is_nil(until) or Date.compare(until, date) != :lt)
  end
end
