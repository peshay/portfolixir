defmodule PortfolixirWeb.PeriodMenuHelpers do
  @moduledoc """
  The dashboard's period picked as the operator picks it (Sprint 32 T4;
  board 04): a chip of the quick choice where the bar shows one, else the
  menu's button, then the period in the menu.
  """
  import Phoenix.LiveViewTest

  @doc "Picks `period` on the dashboard `view`, through the bar or its menu."
  @spec pick_period(term(), String.t()) :: String.t()
  def pick_period(view, period) do
    chip = "[data-role='dashboard-period'] button[data-period='#{period}']"

    if has_element?(view, chip) do
      view |> element(chip) |> render_click()
    else
      unless has_element?(view, "#dashboard-period-menu"),
        do: view |> element("[data-role='period-menu-toggle']") |> render_click()

      view
      |> element("[data-role='period-option'][data-period='#{period}']")
      |> render_click()
    end
  end

  @doc """
  Pins `period` on the widget `widget` (a selector of its frame) as the
  operator does (Sprint 32 T5): its ⋯ „Zeitraum festpinnen …“, then the
  period in the menu it opens.
  """
  @spec pin_widget_period(term(), String.t(), String.t()) :: String.t()
  def pin_widget_period(view, widget, period) do
    view |> element(widget <> " [data-role='pin-menu']") |> render_click()

    view
    |> element("#dashboard-period-menu [data-role='period-option'][data-period='#{period}']")
    |> render_click()
  end

  @doc "The dashboard's active period, as its bar names it."
  @spec active_period(term()) :: String.t() | nil
  def active_period(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("[data-role='period-menu-root']")
    |> Floki.attribute("data-active-period")
    |> List.first()
  end
end
