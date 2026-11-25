defmodule PortfolixirWeb.Api.V1.DashboardController do
  @moduledoc """
  The widget catalogue and the dashboards over the API (FR-60, ADR-0062 §1,
  §8; Sprint 31, D2), each answer rendered by
  `PortfolixirWeb.Api.V1.DashboardJSON` from `Portfolixir.Dashboards`:

    * `GET /api/v1/widgets` — the catalogue: every widget kind with its
      title, group, sizes, source routes, period rule, scope and compact
      flag; the groups, the grid, the periods and the limits.
    * `GET /api/v1/dashboards` — the stored dashboards in the menu's order,
      then the templates, each marked by `type`; a template is `in_menu`
      only while no dashboard is stored (§3).
    * `GET /api/v1/dashboards/:id` — a stored dashboard, or a template as
      `template:<key>`, with its layout, each item with the registry's
      title and source for its kind.
    * `POST /api/v1/dashboards` — `{"dashboard": {name, layout}}` creates;
      `{"dashboard": {template, name?}}` copies a template (201).
    * `PUT /api/v1/dashboards/:id` — `{"dashboard": {name, layout,
      lock_version}}` replaces; a stale lock_version answers 409 with the
      dashboard as stored under `errors.stored`. With `arrange: "push"` and
      `arranged_index` (the item changed) the layout is arranged before it
      is validated: that item keeps its place, the others make room
      (`Portfolixir.Dashboards.Arrange`); without them an overlap is 422.
    * `PATCH /api/v1/dashboards/:id` — `{"dashboard": {name?, position?,
      lock_version?}}` renames and/or moves; a lock_version sent and stale
      answers 409 the same way.
    * `DELETE /api/v1/dashboards/:id` — 204; `dry_run=true` answers what it
      would remove (`PortfolixirWeb.Api.V1.DryRunParam`): the one dashboard.

  Every read and write is closed: a parameter or field it does not take
  answers 422 naming it. One exception: an item's `title` and `source`,
  which the read adds from the registry, are read-only and ignored on
  write, dropped before the layout is validated, so a layout is sent back
  as it was read (Sprint 31 closing act, C3); neither is ever stored, and
  the registry is read again for every answer (§11). A layout refused answers 422 with `errors.layout`
  and `errors.layout_item` naming the first bad item (`index`, `field`,
  `reason`, and `other` for an overlap). A template key that names none
  answers 404 naming the keys offered. A template is never written: a
  write to `template:<key>` answers 422 naming `id`. Every write is
  journaled under the request's token (ADR-0017).
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias PortfolixirWeb.Api.V1.ClosedBody
  alias PortfolixirWeb.Api.V1.DashboardJSON
  alias PortfolixirWeb.Api.V1.DryRunParam
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON

  plug(
    PortfolixirWeb.Api.V1.BodyObject,
    "dashboard" when action in [:create, :replace, :update]
  )

  @create_fields ~w(name layout)
  @copy_fields ~w(template name)
  # `arrange` and `arranged_index`: the arrangement on request (ADR-0062's
  # amendment of 2026-11-25, point 2; Sprint 32 E3).
  @replace_fields ~w(name layout lock_version arrange arranged_index)
  @update_fields ~w(name position lock_version)

  # What a read adds to an item from the registry (`DashboardJSON`): read-only,
  # dropped from a sent item before validation, never stored (§11).
  @read_only_item_keys ~w(title source)

  # --- the reads ---

  def widgets(conn, _params) do
    case ClosedBody.check(conn, nil, []) do
      :ok -> json(conn, %{data: DashboardJSON.catalogue()})
      {:error, errors} -> ClosedBody.refuse(conn, errors)
    end
  end

  def index(conn, _params) do
    case ClosedBody.check(conn, nil, []) do
      :ok ->
        stored = Dashboards.list_dashboards()
        templates_in_menu = stored == []

        data =
          Enum.map(stored, &DashboardJSON.entry(&1, true)) ++
            Enum.map(Dashboards.templates(), &DashboardJSON.entry(&1, templates_in_menu))

        json(conn, %{data: data})

      {:error, errors} ->
        ClosedBody.refuse(conn, errors)
    end
  end

  def show(conn, %{"id" => id}) do
    with :ok <- ClosedBody.check(conn, nil, []),
         {:ok, found} <- find(id) do
      json(conn, %{data: payload(found)})
    else
      {:error, :no_template} ->
        not_found(conn, "names no template; #{offered_templates()} is offered")

      {:error, :not_found} ->
        not_found(conn)

      {:error, errors} ->
        ClosedBody.refuse(conn, errors)
    end
  end

  # --- the writes ---

  def create(conn, _params) do
    attrs = wrapped(conn)
    copy? = Map.has_key?(attrs, "template")
    fields = if copy?, do: @copy_fields, else: @create_fields

    with :ok <- ClosedBody.check(conn, "dashboard", fields),
         {:ok, dashboard} <- create_or_copy(conn.assigns.actor, attrs, copy?) do
      conn
      |> put_status(:created)
      |> json(%{data: DashboardJSON.dashboard(dashboard)})
    else
      refusal -> refuse(conn, refusal)
    end
  end

  def replace(conn, %{"id" => id}) do
    with {:ok, dashboard_id} <- writable(id),
         :ok <- ClosedBody.check(conn, "dashboard", @replace_fields),
         {:ok, dashboard} <-
           Dashboards.replace_dashboard(conn.assigns.actor, dashboard_id, wrapped(conn)) do
      json(conn, %{data: DashboardJSON.dashboard(dashboard)})
    else
      refusal -> refuse(conn, refusal)
    end
  end

  def update(conn, %{"id" => id}) do
    with {:ok, dashboard_id} <- writable(id),
         :ok <- ClosedBody.check(conn, "dashboard", @update_fields),
         {:ok, dashboard} <-
           Dashboards.update_dashboard(conn.assigns.actor, dashboard_id, wrapped(conn)) do
      json(conn, %{data: DashboardJSON.dashboard(dashboard)})
    else
      refusal -> refuse(conn, refusal)
    end
  end

  # dry_run=true (as the cascading deletes take it, Sprint 25 X1): the same
  # delete, rolled back, answers what it would remove — the one dashboard.
  def delete(conn, %{"id" => id}) do
    with {:ok, dry_run} <- DryRunParam.parse(conn),
         {:ok, dashboard_id} <- writable(id),
         {:ok, removed} <- delete_dashboard(conn.assigns.actor, dashboard_id, dry_run) do
      if dry_run,
        do: DryRunParam.answer(conn, removed),
        else: send_resp(conn, :no_content, "")
    else
      {:error, {:dry_run_param, errors}} -> DryRunParam.invalid(conn, errors)
      {:error, :concurrent_change} -> DryRunParam.concurrent_change(conn)
      refusal -> refuse(conn, refusal)
    end
  end

  defp delete_dashboard(actor, id, true), do: Dashboards.dry_run_delete_dashboard(actor, id)

  defp delete_dashboard(actor, id, false) do
    with {:ok, _deleted} <- Dashboards.delete_dashboard(actor, id), do: {:ok, :deleted}
  end

  defp create_or_copy(actor, attrs, true) do
    case Dashboards.copy_template(
           actor,
           Map.get(attrs, "template"),
           Map.delete(attrs, "template")
         ) do
      {:error, :not_found} ->
        {:error, %{template: ["names no template: #{offered_templates()} is offered"]}}

      result ->
        result
    end
  end

  defp create_or_copy(actor, attrs, false), do: Dashboards.create_dashboard(actor, attrs)

  defp offered_templates, do: Enum.map_join(Dashboards.templates(), ", ", & &1.key)

  # --- the id ---

  # A template is read as template:<key>, its key matched as a string; any
  # other id is a stored dashboard's whole number.
  defp find("template:" <> key) do
    case Dashboards.fetch_template(key) do
      {:ok, template} -> {:ok, {:template, template}}
      :error -> {:error, :no_template}
    end
  end

  defp find(id) do
    with {:ok, dashboard_id} <- IdParam.parse(id),
         %Dashboard{} = dashboard <- Dashboards.get_dashboard(dashboard_id) do
      {:ok, dashboard}
    else
      _none -> {:error, :not_found}
    end
  end

  defp payload({:template, template}), do: DashboardJSON.dashboard(template, menu_template?())
  defp payload(%Dashboard{} = dashboard), do: DashboardJSON.dashboard(dashboard)

  defp menu_template?, do: Dashboards.list_dashboards() == []

  # A write names a stored dashboard; a template is never written (§3).
  defp writable("template:" <> _key), do: {:error, :template}

  defp writable(id) do
    case IdParam.parse(id) do
      {:ok, dashboard_id} -> {:ok, dashboard_id}
      :error -> {:error, :not_found}
    end
  end

  defp wrapped(conn) do
    case conn.body_params do
      %{"dashboard" => %{} = attrs} when not is_struct(attrs) -> without_read_only(attrs)
      _absent -> %{}
    end
  end

  defp without_read_only(%{"layout" => layout} = attrs) when is_list(layout),
    do: %{attrs | "layout" => Enum.map(layout, &without_read_only_keys/1)}

  defp without_read_only(attrs), do: attrs

  defp without_read_only_keys(item) when is_map(item) and not is_struct(item),
    do: Map.drop(item, @read_only_item_keys)

  defp without_read_only_keys(item), do: item

  # --- the refusals ---

  defp refuse(conn, {:error, :not_found}), do: not_found(conn)

  defp refuse(conn, {:error, :template}) do
    ClosedBody.refuse(conn, %{
      id: [
        "names a template, which is never written: copy it with POST /api/v1/dashboards " <>
          "and {\"dashboard\": {\"template\": <key>}}"
      ]
    })
  end

  defp refuse(conn, {:error, :stale, %Dashboard{} = stored}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      errors: %{
        code: "stale",
        detail:
          "the dashboard changed since it was read and nothing was written: it is stored " <>
            "with lock_version #{stored.lock_version}, as errors.stored shows; build on it " <>
            "and send that lock_version (an item's title and source are read-only and " <>
            "ignored on write)",
        stored: DashboardJSON.dashboard(stored)
      }
    })
  end

  defp refuse(conn, {:error, :too_many_dashboards}) do
    ClosedBody.refuse(conn, %{
      code: "too_many_dashboards",
      detail:
        "at most #{Dashboards.max_dashboards()} dashboards are stored: delete one before " <>
          "adding another"
    })
  end

  defp refuse(conn, {:error, %Ecto.Changeset{} = changeset}),
    do: ClosedBody.refuse(conn, changeset_errors(changeset))

  defp refuse(conn, {:error, {:unknown_fields, errors}}), do: ClosedBody.refuse(conn, errors)
  defp refuse(conn, {:error, {:missing_fields, errors}}), do: ClosedBody.refuse(conn, errors)
  defp refuse(conn, {:error, {:invalid_fields, errors}}), do: ClosedBody.refuse(conn, errors)
  defp refuse(conn, {:error, errors}) when is_map(errors), do: ClosedBody.refuse(conn, errors)

  # The changeset's messages, and for a refused layout the first bad item
  # its error carries (`Portfolixir.Dashboards.Layout`'s refusal).
  defp changeset_errors(changeset) do
    errors = JSON.errors(changeset)

    case Keyword.get(changeset.errors, :layout) do
      {_message, meta} when is_list(meta) ->
        if Keyword.has_key?(meta, :reason),
          do: Map.put(errors, :layout_item, layout_item(meta)),
          else: errors

      _none ->
        errors
    end
  end

  defp layout_item(meta) do
    item = %{
      index: Keyword.get(meta, :index),
      field: Keyword.get(meta, :field),
      reason: Atom.to_string(Keyword.fetch!(meta, :reason))
    }

    case Keyword.fetch(meta, :other) do
      {:ok, other} -> Map.put(item, :other, other)
      :error -> item
    end
  end

  defp not_found(conn, why \\ nil) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: if(why, do: "not found: " <> why, else: "not found")}})
  end
end
