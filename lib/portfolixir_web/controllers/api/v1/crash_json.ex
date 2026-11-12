defmodule PortfolixirWeb.Api.V1.CrashJSON do
  @moduledoc """
  The crash windows' API payloads (ADR-0058 §6, §9; Sprint 29, C5), rendered
  from `Portfolixir.Crashes`' answers: every `Decimal` a string
  (`PortfolixirWeb.Api.V1.JSON.decimal/1`), every date ISO 8601, every atom
  value its name, never a JSON number for a figure. The context's `basis`
  is answered as `computation_basis`, as every metric payload names it, and
  the crash benchmark is named with its standing as `benchmark_security`
  (`flagged`, `held` or `unheld`), as the crash benchmark's write answers it.

  No key here is a verdict: the lists compare prices and say nothing about
  what to buy (ADR-0058 §8; `test/invariants/metrics_carry_no_verdict_test.exs`
  walks these payloads).
  """

  alias Portfolixir.Catalog.BenchmarkSecurity
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Crashes.ManualWindow
  alias Portfolixir.Crashes.WindowName
  alias PortfolixirWeb.Api.V1.JSON

  @doc "`GET /api/v1/crashes`: `Portfolixir.Crashes.list_windows/0`'s answer."
  @spec windows(map()) :: map()
  def windows(listing) do
    %{
      benchmark: benchmark(listing.benchmark),
      reason: listing.reason,
      detected: Enum.map(listing.detected, &detected/1),
      manual: Enum.map(listing.manual, &plain/1),
      unmatched_names: Enum.map(listing.unmatched_names, &plain/1),
      computation_basis: plain(listing.basis)
    }
  end

  @doc "`GET /api/v1/crashes/:key/rankings`: `Portfolixir.Crashes.rankings/3`'s answer."
  @spec rankings(map()) :: map()
  def rankings(payload) do
    {basis, payload} = Map.pop!(payload, :basis)

    payload
    |> Map.put(:benchmark, benchmark(payload.benchmark))
    |> plain()
    |> Map.put(
      :computation_basis,
      basis |> Map.put(:benchmark, benchmark(basis.benchmark)) |> plain()
    )
  end

  @doc """
  A written window: a detected window's name (`WindowName`, read back as
  the detected window it names) or a manual window (`ManualWindow`), each
  under its key.
  """
  @spec written(WindowName.t() | ManualWindow.t()) :: map()
  def written(%WindowName{} = name) do
    %{
      key: key(name),
      kind: "detected",
      name: name.name,
      benchmark_security_id: name.benchmark_security_id,
      start: JSON.date(name.start)
    }
  end

  def written(%ManualWindow{} = window) do
    window
    |> Map.take([:id, :name, :start, :trough, :author, :actor, :created_at, :updated_at])
    |> Map.merge(%{key: key(window), kind: "manual"})
    |> plain()
  end

  @doc "What `DELETE /api/v1/crashes/:key` removed: a name, or a manual window."
  @spec deleted(WindowName.t() | ManualWindow.t()) :: map()
  def deleted(%WindowName{} = name),
    do: %{key: key(name), kind: "detected", deleted: "name", name: name.name}

  def deleted(%ManualWindow{} = window),
    do: %{key: key(window), kind: "manual", deleted: "manual_window", name: window.name}

  defp key(%WindowName{benchmark_security_id: id, start: start}),
    do: "d:#{id}:#{Date.to_iso8601(start)}"

  defp key(%ManualWindow{id: id}), do: "m:#{id}"

  defp detected(window) do
    window
    |> Map.take([
      :key,
      :kind,
      :name,
      :start,
      :peak_close,
      :trough,
      :trough_close,
      :decline,
      :recovered_on,
      :provisional,
      :max_gap_days
    ])
    |> plain()
  end

  # The crash benchmark, from the security (the windows' read) or the map
  # the lists carry; its standing named as the crash benchmark's write
  # names it.
  defp benchmark(nil), do: nil

  defp benchmark(%Security{} = security) do
    %{
      id: security.id,
      name: security.name,
      isin: security.isin,
      currency_code: security.currency_code,
      benchmark_security: security |> BenchmarkSecurity.standing() |> Atom.to_string()
    }
  end

  defp benchmark(%{standing: standing} = read) do
    read
    |> Map.take([:id, :name, :isin, :currency_code])
    |> Map.put(:benchmark_security, standing)
  end

  # Decimals as strings, dates and times ISO 8601, atoms by name; maps and
  # lists walked. A rendered benchmark passes through unchanged.
  defp plain(%Decimal{} = decimal), do: JSON.decimal(decimal)
  defp plain(%Date{} = date), do: JSON.date(date)
  defp plain(%DateTime{} = datetime), do: JSON.datetime(datetime)
  defp plain(%NaiveDateTime{} = timestamp), do: JSON.timestamp(timestamp)
  defp plain(value) when is_boolean(value) or is_nil(value), do: value
  defp plain(value) when is_atom(value), do: Atom.to_string(value)
  defp plain(list) when is_list(list), do: Enum.map(list, &plain/1)

  defp plain(%{} = map) when not is_struct(map),
    do: Map.new(map, fn {key, value} -> {key, plain(value)} end)

  defp plain(value), do: value
end
