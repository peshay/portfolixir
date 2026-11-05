defmodule PortfolixirWeb.Api.V1.PredictionJSON do
  @moduledoc """
  The wire shape of a prediction and its resolution at read (ADR-0055
  §§1, 3, 5): closed-set values and reasons as strings, dates ISO 8601,
  `made_at` ISO 8601 UTC, and every `Decimal` a string. A stated value
  keeps the places it was stated at (`probability` `"0.70"`, a band's
  `"0.50"`); a computed one (a close, a rate, a return) is normalized, as
  every other read answers it (`PortfolixirWeb.Api.V1.JSON.decimal/1`).

  The resolution is serialized whole: the status, the outcome or the
  reason, the dates the closes stand for, both sides with each close
  (`stands_for`, `date`, `close`, `stored_close`, `source`, `fx_rate`,
  `eur_value`) and its return, and the excess, so a reader checks the
  figure against the closes rather than trusting it.
  """

  alias Portfolixir.Predictions.Calibration
  alias Portfolixir.Predictions.Prediction
  alias Portfolixir.Predictions.Resolution
  alias PortfolixirWeb.Api.V1.JSON

  @permanence_note "A prediction is permanent: it cannot be edited, withdrawn or deleted, " <>
                     "by anyone. A mistaken one stays and counts; a correction is a new " <>
                     "prediction, and both count. Its status, outcome and figures are " <>
                     "derived at every read from stored closes, never stored."

  # The resolution rule of ADR-0055 §3, as the calibration report's basis
  # states it, so the two cannot drift.
  @resolution_basis_keys [
    :resolution,
    :start_close,
    :end_close,
    :staleness_days,
    :currency,
    :benchmark,
    :outcome,
    :distributions,
    :precision
  ]

  @doc "The note every prediction read carries: what permanence means."
  @spec permanence_note() :: String.t()
  def permanence_note, do: @permanence_note

  @doc """
  The resolution rule's `computation_basis` (ADR-0055 §3), the part of the
  calibration report's basis a single prediction is resolved by.
  """
  @spec resolution_basis() :: map()
  def resolution_basis do
    Calibration.computation_basis()
    |> Map.take(@resolution_basis_keys)
    |> basis()
  end

  @doc "One prediction with its resolution at read."
  @spec prediction(Prediction.t(), Resolution.t()) :: map()
  def prediction(%Prediction{} = prediction, %Resolution{} = resolution) do
    %{
      id: prediction.id,
      security_id: prediction.security_id,
      direction: Atom.to_string(prediction.direction),
      probability: stated(prediction.probability),
      benchmark: Prediction.benchmark(prediction),
      resolves_on: JSON.date(prediction.resolves_on),
      made_at: JSON.datetime(prediction.made_at),
      made_on: JSON.date(Prediction.made_on(prediction)),
      author: Atom.to_string(prediction.author),
      actor: prediction.actor,
      model: prediction.model,
      note_id: prediction.note_id,
      rationale: prediction.rationale,
      resolution: resolution(resolution)
    }
  end

  @doc "A resolution (`Portfolixir.Predictions.Resolution`), whole."
  @spec resolution(Resolution.t()) :: map()
  def resolution(%Resolution{} = resolution) do
    %{
      status: Atom.to_string(resolution.status),
      outcome: atom(resolution.outcome),
      reason: atom(resolution.reason),
      start_on: JSON.date(resolution.start_on),
      end_on: JSON.date(resolution.end_on),
      security: security_side(resolution.security),
      benchmark: benchmark_side(resolution.benchmark),
      excess: JSON.decimal(resolution.excess)
    }
  end

  defp security_side(nil), do: nil

  defp security_side(side) do
    %{
      security_id: side.security_id,
      currency_code: side.currency_code,
      start: window_end(side.start),
      end: window_end(side.end),
      return: JSON.decimal(side.return)
    }
  end

  defp benchmark_side(nil), do: nil

  defp benchmark_side(%{kind: :security} = side) do
    %{
      kind: "security",
      security_id: side.security_id,
      currency_code: side.currency_code,
      start: window_end(side.start),
      end: window_end(side.end),
      return: JSON.decimal(side.return)
    }
  end

  defp benchmark_side(%{kind: :rate} = side) do
    %{
      kind: "rate",
      rate: JSON.decimal(side.rate),
      from: JSON.date(side.from),
      to: JSON.date(side.to),
      days: side.days,
      return: JSON.decimal(side.return)
    }
  end

  defp window_end(point) do
    %{
      stands_for: JSON.date(point.stands_for),
      date: JSON.date(point.date),
      close: JSON.decimal(point.close),
      stored_close: JSON.decimal(point.stored_close),
      source: point.source,
      fx_rate: JSON.decimal(point.fx_rate),
      eur_value: JSON.decimal(point.eur_value)
    }
  end

  @doc """
  The calibration report (`Portfolixir.Predictions.calibration_report/2`,
  ADR-0055 §4): `counts`, `brier`, `sharpness`, `hit_rate`, `bands` and
  `groups`, each figure a string or null, a band's `hit_rate` the string
  `"too_few"` below the minimum count, a standard error's reason a string,
  and the whole `computation_basis`.
  """
  @spec calibration(map()) :: map()
  def calibration(report) do
    report
    |> block()
    |> Map.merge(%{
      groups: %{
        author: Enum.map(report.groups.author, &group(&1, :author)),
        model: Enum.map(report.groups.model, &group(&1, :model))
      },
      computation_basis: basis(report.computation_basis)
    })
  end

  defp group(group, :author), do: group |> block() |> Map.put(:author, atom(group.author))
  defp group(group, :model), do: group |> block() |> Map.put(:model, group.model)

  defp block(block) do
    %{
      counts: %{
        total: block.counts.total,
        open: block.counts.open,
        resolved: block.counts.resolved,
        unresolved: Map.new(block.counts.unresolved, fn {reason, n} -> {atom(reason), n} end)
      },
      brier: %{
        score: JSON.decimal(block.brier.score),
        standard_error: JSON.decimal(block.brier.standard_error),
        standard_error_reason: atom(block.brier.standard_error_reason),
        reference: stated(block.brier.reference)
      },
      sharpness: JSON.decimal(block.sharpness),
      hit_rate: %{
        rate: JSON.decimal(block.hit_rate.rate),
        hits: block.hit_rate.hits,
        mean_probability: JSON.decimal(block.hit_rate.mean_probability),
        standard_error: JSON.decimal(block.hit_rate.standard_error),
        standard_error_reason: atom(block.hit_rate.standard_error_reason)
      },
      bands: Enum.map(block.bands, &band/1)
    }
  end

  defp band(band) do
    %{
      from: stated(band.from),
      to: stated(band.to),
      count: band.count,
      mean_probability: JSON.decimal(band.mean_probability),
      hit_rate: band_hit_rate(band.hit_rate)
    }
  end

  defp band_hit_rate(:too_few), do: "too_few"
  defp band_hit_rate(%Decimal{} = rate), do: JSON.decimal(rate)

  # A basis map: its text and integers as they are, a Decimal as a string.
  defp basis(map), do: Map.new(map, fn {key, value} -> {key, basis_value(value)} end)

  defp basis_value(%Decimal{} = value), do: stated(value)
  defp basis_value(value), do: value

  # A stated value at the places it was stated at: "0.70", not "0.7".
  defp stated(nil), do: nil
  defp stated(%Decimal{} = value), do: Decimal.to_string(value, :normal)

  defp atom(nil), do: nil
  defp atom(value) when is_atom(value), do: Atom.to_string(value)
end
