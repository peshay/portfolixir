# Throwaway review database only: the template „Überblick“ and two theme
# dashboards approximated with today's kinds and sizes.
alias Portfolixir.Dashboards
actor = Portfolixir.Actor.system_job("review")
{:ok, t} = Portfolixir.Dashboards.Templates.fetch("overview")
i = fn k, s, c, r -> %{"kind" => k, "size" => s, "col" => c, "row" => r, "settings" => %{}} end
boards = [
  {"Überblick (Vorlage)", t.layout},
  {"Krypto Lover (heute)", [i.("bitcoin_cycle", "L", 1, 1), i.("allocation_drift", "T", 9, 1), i.("movers", "M", 1, 4), i.("crashes", "M", 7, 4), i.("performance", "S", 1, 6), i.("total_value", "S", 4, 6)]},
  {"Rücksetzer (heute)", [i.("crashes", "L", 1, 1), i.("movers", "S", 9, 1), i.("total_value", "S", 9, 2), i.("performance", "M", 1, 4), i.("off_target", "M", 7, 4)]}
]
for {name, layout} <- boards do
  {:ok, d} = Dashboards.create_dashboard(actor, %{"name" => name, "layout" => layout})
  IO.puts("dash #{d.id} #{name}")
end
