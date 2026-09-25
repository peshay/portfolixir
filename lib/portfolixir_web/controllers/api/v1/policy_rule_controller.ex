defmodule PortfolixirWeb.Api.V1.PolicyRuleController do
  @moduledoc """
  JSON API for policy rules (ADR-0049 §8, §9, FR-43): the operator's caps,
  floors and bands as stored, versioned objects.

  Reads: the rule list of a portfolio (the rules in force on `as_of`, today
  by default; `include_retired=true` adds the retired ones; `view=` narrows to
  one evaluation context; `since=` is the row delta) and one rule with its
  whole version history.

  Writes, each journaled under the credential: create a rule with its first
  version, add a version (**the edit** — the old version stays readable as
  the standard of its own period), retire, and delete — the last only while
  no version has ever been in force, because a version that has been the
  standard is never removed.

  Nothing here evaluates a rule: the findings read is
  `PortfolixirWeb.Api.V1.PolicyFindingController`. Mirrored by the
  `portfolixir.policy_rules.*` MCP tools (API/MCP parity, FR-16/AR-11).
  """
  use PortfolixirWeb, :controller

  plug(PortfolixirWeb.Api.V1.BodyObject, "rule" when action in [:create])
  plug(PortfolixirWeb.Api.V1.BodyObject, "version" when action in [:add_version])

  alias Portfolixir.Clock
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.PolicyRule
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Portfolios.PolicyRuleVersion
  alias Portfolixir.Portfolios.Portfolio
  alias PortfolixirWeb.Api.V1.DateParam
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ListLimit
  alias PortfolixirWeb.Api.V1.PolicyJSON
  alias PortfolixirWeb.Api.V1.SinceParam
  alias PortfolixirWeb.Api.V1.ViewParam

  @rules_note "A rule is the operator's own standard over a figure the product already " <>
                "serves (ADR-0049): a cap, floor or band on a weight, a drift, the HHI, or a " <>
                "portfolio metric. Rules are versioned: an edit adds a version from a date and " <>
                "closes the previous one the day before, so the standard in force on any date " <>
                "stays readable (as_of=). A version that has been in force is never changed or " <>
                "deleted. Evaluating the rules is the findings read; a finding is the rule " <>
                "applied to the figure, never an action, and nothing here places, proposes or " <>
                "sizes a trade."

  @default_limit 1_000
  @max_limit 10_000

  def index(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, pid} <- IdParam.parse(portfolio_id),
         %Portfolio{} <- Portfolios.get_portfolio(pid),
         {:ok, view} <- view_param(params),
         {:ok, as_of} <- date_param(params, "as_of"),
         {:ok, include_retired} <- boolean_param(params, "include_retired"),
         {:ok, since} <- SinceParam.parse(params),
         {:ok, limit} <- ListLimit.parse(params, @default_limit, @max_limit) do
      as_of = as_of || Clock.today()

      rules =
        PolicyRules.list_rules(pid,
          view: view,
          as_of: as_of,
          include_retired: include_retired,
          updated_since: since && since.cut,
          limit: limit
        )

      payload = %{
        data: %{
          portfolio_id: pid,
          view_id: if(view == :any, do: nil, else: view),
          as_of: JSON.date(as_of),
          include_retired: include_retired,
          limit: limit,
          rules: Enum.map(rules, &PolicyJSON.rule/1),
          rules_note: @rules_note
        }
      }

      json(conn, SinceParam.put_envelope(payload, since))
    else
      {:error, field} -> unprocessable(conn, %{field => ["is invalid"]})
      :view_not_found -> not_found(conn)
      :error -> not_found(conn)
      nil -> not_found(conn)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, rule_id} <- IdParam.parse(id),
         %PolicyRule{} = rule <- PolicyRules.get_rule(rule_id) do
      json(conn, %{
        data: rule |> PolicyJSON.rule_with_versions() |> Map.put(:rules_note, @rules_note)
      })
    else
      _missing -> not_found(conn)
    end
  end

  def create(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, pid} <- IdParam.parse(portfolio_id),
         %Portfolio{} <- Portfolios.get_portfolio(pid),
         :ok <- nested_version_object(params["rule"]) do
      attrs =
        params
        |> Map.get("rule", %{})
        |> map_or_empty()
        |> Map.take(["name", "view_id", "version"])
        |> Map.put("portfolio_id", pid)
        |> Map.update("version", %{}, &map_or_empty/1)

      case PolicyRules.create_rule(conn.assigns.actor, attrs) do
        {:ok, rule} ->
          conn |> put_status(:created) |> json(%{data: PolicyJSON.rule_with_versions(rule)})

        {:error, {:version, changeset}} ->
          unprocessable(conn, %{version: JSON.errors(changeset)})

        {:error, %Ecto.Changeset{} = changeset} ->
          unprocessable(conn, JSON.errors(changeset))
      end
    else
      {:error, :version_not_object} ->
        unprocessable(conn, %{version: ["must be an object"]})

      _missing ->
        not_found(conn)
    end
  end

  # The BodyObject contract (#853), one level down: the rule carries its first
  # version under `version`, and a non-object there is named, not read as
  # four missing fields.
  defp nested_version_object(%{"version" => version}) when not is_map(version),
    do: {:error, :version_not_object}

  defp nested_version_object(_rule), do: :ok

  def add_version(conn, %{"id" => id} = params) do
    with {:ok, rule_id} <- IdParam.parse(id),
         %PolicyRule{} = rule <- PolicyRules.get_rule(rule_id) do
      attrs = params |> Map.get("version", %{}) |> map_or_empty()

      case PolicyRules.add_version(conn.assigns.actor, rule, attrs) do
        {:ok, version} ->
          conn |> put_status(:created) |> json(%{data: PolicyJSON.version(version)})

        {:error, %Ecto.Changeset{} = changeset} ->
          unprocessable(conn, JSON.errors(changeset))
      end
    else
      _missing -> not_found(conn)
    end
  end

  # The rename (#872; ADR-0049 §4 and §8 as amended by the Sprint 16 plan
  # D-6): the name is the operator's label, so it changes outside the
  # versioning — no version is added or changed. Only `name` is read, as on
  # PATCH /api/v1/plans/:id. A field of the predicate or of the context in the
  # same body is refused rather than dropped: an agent that sent a new line
  # with a new name would otherwise read a 200 as "the line changed".
  def rename(conn, %{"id" => id} = params) do
    with {:ok, rule_id} <- IdParam.parse(id),
         %PolicyRule{} = rule <- PolicyRules.get_rule(rule_id) do
      case not_a_rename(params, rule_id) do
        refused when map_size(refused) > 0 ->
          unprocessable(conn, refused)

        _none ->
          case PolicyRules.rename_rule(conn.assigns.actor, rule, Map.take(params, ["name"])) do
            {:ok, renamed} -> json(conn, %{data: PolicyJSON.rule_with_versions(renamed)})
            {:error, %Ecto.Changeset{} = changeset} -> unprocessable(conn, JSON.errors(changeset))
          end
      end
    else
      _missing -> not_found(conn)
    end
  end

  @context_fields ~w(portfolio_id view_id)

  defp not_a_rename(params, rule_id) do
    version_fields = ["version" | PolicyRuleVersion.predicate_fields()]

    version_error =
      "is not changed by a rename; a new line is a new version " <>
        "(POST /api/v1/policy_rules/#{rule_id}/versions)"

    context_error =
      "is the rule's context and never changes; a rule in another context is a new rule"

    Enum.reduce(params, %{}, fn {key, _value}, acc ->
      cond do
        key in version_fields -> Map.put(acc, key, [version_error])
        key in @context_fields -> Map.put(acc, key, [context_error])
        true -> acc
      end
    end)
  end

  def retire(conn, %{"id" => id} = params) do
    with {:ok, rule_id} <- IdParam.parse(id),
         %PolicyRule{} = rule <- PolicyRules.get_rule(rule_id) do
      case PolicyRules.retire_rule(conn.assigns.actor, rule, Map.take(params, ["valid_until"])) do
        {:ok, _closed} ->
          json(conn, %{data: rule_id |> PolicyRules.get_rule() |> PolicyJSON.rule_with_versions()})

        {:error, :never_in_force} ->
          conflict(
            conn,
            "no version of this rule has been in force yet; a rule nobody was ever " <>
              "measured against is deleted, not retired"
          )

        {:error, :already_retired} ->
          conflict(conn, "this rule is already retired")

        {:error, %Ecto.Changeset{} = changeset} ->
          unprocessable(conn, JSON.errors(changeset))
      end
    else
      _missing -> not_found(conn)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, rule_id} <- IdParam.parse(id),
         %PolicyRule{} = rule <- PolicyRules.get_rule(rule_id) do
      case PolicyRules.delete_rule(conn.assigns.actor, rule) do
        {:ok, _deleted} ->
          send_resp(conn, :no_content, "")

        {:error, :in_force} ->
          conflict(
            conn,
            "a version of this rule has been in force, and a standard that was in force " <>
              "is never removed; retire the rule instead (POST /api/v1/policy_rules/#{rule_id}/retire)"
          )
      end
    else
      _missing -> not_found(conn)
    end
  end

  # -- params ------------------------------------------------------------------

  # `view=` narrows the list to one evaluation context; absent is every
  # context of the portfolio (`:any`).
  defp view_param(params) do
    case ViewParam.resolve(params) do
      {:ok, nil} -> {:ok, :any}
      {:ok, view} -> {:ok, view.id}
      other -> other
    end
  end

  # The bounded date every writer meets (DateParam, F70 review round).
  defp date_param(params, key) do
    case DateParam.parse(params, key) do
      {:ok, date} -> {:ok, date}
      :error -> {:error, String.to_existing_atom(key)}
    end
  end

  defp boolean_param(params, key) do
    case Map.get(params, key) do
      value when value in [nil, "", "false", false] -> {:ok, false}
      value when value in ["true", true] -> {:ok, true}
      _other -> {:error, String.to_existing_atom(key)}
    end
  end

  defp map_or_empty(value) when is_map(value), do: value
  defp map_or_empty(_value), do: %{}

  defp unprocessable(conn, errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end

  defp conflict(conn, detail) do
    conn
    |> put_status(:conflict)
    |> json(%{errors: %{detail: detail}})
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end
end
