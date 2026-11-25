# Throwaway review database only: one dashboard holding every kind in every grid size.
alias Portfolixir.Dashboards
alias Portfolixir.Dashboards.Widgets
{items, _row} =
  Enum.flat_map_reduce(Widgets.kinds(), 1, fn kind, row ->
    sizes = Enum.filter(kind.sizes, &match?({:ok, _}, Widgets.dimensions(&1)))
    Enum.map_reduce(sizes, row, fn size, r ->
      {:ok, {_w, h}} = Widgets.dimensions(size)
      {%{"kind" => kind.key, "size" => size, "col" => 1, "row" => r, "settings" => %{}}, r + h}
    end)
  end)
IO.inspect(length(items), label: "items")
{:ok, d} = Dashboards.create_dashboard(Portfolixir.Actor.system_job("review"), %{"name" => "Alle Größen", "layout" => items})
IO.puts("id=#{d.id}")
