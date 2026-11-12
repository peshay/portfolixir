defmodule PortfolixirWeb.Api.V1.SettingsController do
  @moduledoc """
  JSON API for the minimal user preferences (ADR-0024): the default-view
  preference the Wealth page and dashboard open on (`view_id` is `null` for
  the built-in Everything scope), and the crash benchmark (ADR-0058 §1), the
  security whose closes the crash rule reads. No financial decimals are
  involved. A change is journaled under the request's actor (H61).
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.View
  alias Portfolixir.Catalog.BenchmarkSecurity
  alias Portfolixir.Settings
  alias PortfolixirWeb.Api.V1.ClosedBody
  alias PortfolixirWeb.Api.V1.IdParam

  @crash_benchmark_fields ["security_id"]

  def show_default_view(conn, _params) do
    json(conn, %{data: default_view_payload()})
  end

  def set_default_view(conn, %{"view_id" => nil}) do
    :ok = Settings.set_default_view(conn.assigns.actor, nil)
    json(conn, %{data: default_view_payload()})
  end

  def set_default_view(conn, %{"view_id" => view_id}) when is_integer(view_id) do
    case Buckets.get_view(view_id) do
      %View{} = view ->
        :ok = Settings.set_default_view(conn.assigns.actor, view.id)
        json(conn, %{data: default_view_payload()})

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "not found"}})
    end
  end

  def set_default_view(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{detail: "view_id must be a positive integer or null"}})
  end

  # --- S29 C1 begin ---
  # ADR-0058 §1, §9: PUT /api/v1/settings/crash_benchmark. Body
  # {"security_id": <id> | null}; any security with a stored quote, flagged
  # or not (BenchmarkSecurity.resolve/1), null clears it. A refusal answers
  # 422 naming security_id, a merged-away id its survivor as merged_into; a
  # field the write does not take, 422 naming it.
  def set_crash_benchmark(conn, params) do
    with :ok <- closed(conn),
         {:ok, security_id} <- crash_benchmark_id(params),
         {:ok, security} <- Settings.set_crash_benchmark(conn.assigns.actor, security_id) do
      json(conn, %{data: crash_benchmark_payload(security)})
    else
      {:error, errors} when is_map(errors) -> ClosedBody.refuse(conn, errors)
      {:error, refusal} -> ClosedBody.refuse(conn, refusal_errors(refusal))
    end
  end

  defp closed(conn) do
    request = Map.merge(conn.query_params, conn.body_params)

    case ClosedBody.unknown(request, @crash_benchmark_fields, "this write") do
      empty when empty == %{} -> :ok
      errors -> {:error, errors}
    end
  end

  defp crash_benchmark_id(%{"security_id" => nil}), do: {:ok, nil}

  defp crash_benchmark_id(%{"security_id" => raw}) do
    case IdParam.parse(raw) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, %{security_id: ["is invalid"]}}
    end
  end

  defp crash_benchmark_id(_params), do: {:error, %{security_id: ["can't be blank"]}}

  defp refusal_errors(:no_quote), do: %{security_id: ["has no stored quote"]}
  defp refusal_errors(:not_found), do: %{security_id: ["is not a benchmark security"]}

  defp refusal_errors({:merged_into, survivor}),
    do: %{
      security_id: ["is not a benchmark security"],
      merged_into: %{kind: "security", id: survivor}
    }

  defp crash_benchmark_payload(nil), do: %{security_id: nil, security: nil}

  defp crash_benchmark_payload(security) do
    %{
      security_id: security.id,
      security: %{
        id: security.id,
        name: security.name,
        is_benchmark: security.is_benchmark,
        benchmark_security: Atom.to_string(BenchmarkSecurity.standing(security))
      }
    }
  end

  # --- S29 C1 end ---

  defp default_view_payload do
    case Settings.default_view_id() do
      nil ->
        %{view_id: nil, view: nil}

      view_id ->
        view = Buckets.get_view(view_id)
        %{view_id: view_id, view: %{id: view.id, name: view.name}}
    end
  end
end
