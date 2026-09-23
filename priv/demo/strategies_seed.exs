# Seeds a compact "Strategies" classification + target weights on the demo
# instance, sized to the 7 synthetic fixtures, so the portfolio allocation view
# shows target-vs-actual drift for rebalancing. Run after importing the demo
# dataset:
#
#   DATABASE_NAME=portfolixir_demo PORT=4003 mix run priv/demo/strategies_seed.exs
alias Portfolixir.{Actor, Classifications, Portfolios}
alias Portfolixir.Portfolios.Targets
alias Portfolixir.Catalog

portfolio = Enum.find(Portfolios.list_portfolios(), &(&1.name == "Demo Depot"))
unless portfolio, do: raise("Demo Depot portfolio not found")

# Idempotent re-run: reuse an existing Strategies tree and its categories
# instead of dropping them. Dropping used to be the idempotency mechanism, but
# a tree a policy rule reads cannot be deleted (ADR-0049 §8), and the review
# seed's rules read this one.
owner = Portfolixir.Actor.owner_ui()

cls =
  case Enum.find(Classifications.list_classifications(), &(&1.name == "Strategies")) do
    nil ->
      {:ok, created} =
        Classifications.create_classification(owner, %{
          name: "Strategies",
          position: 0,
          description: "Demo strategy tree with target weights for rebalancing."
        })

      created

    existing ->
      existing
  end

cat = fn name, color, parent_id ->
  case Enum.find(Classifications.list_categories(cls.id), &(&1.name == name)) do
    nil ->
      {:ok, c} =
        Classifications.create_category(owner, %{
          name: name,
          color: color,
          classification_id: cls.id,
          parent_id: parent_id
        })

      c

    existing ->
      existing
  end
end

stability = cat.("Stability", "#16a34a", nil)
quality = cat.("Quality", "#22c55e", stability.id)
wachstum = cat.("Growth", "#2563eb", nil)
core = cat.("Global Core", "#1e40af", wachstum.id)
platforms = cat.("Platforms", "#3b82f6", wachstum.id)
krypto = cat.("Crypto", "#ffab01", nil)

secs = Catalog.list_securities()
find = fn frag -> Enum.find(secs, &String.contains?(String.downcase(&1.name), frag)) end

assign = fn frag, category ->
  case find.(frag) do
    %{id: id} -> Classifications.assign_security(owner, id, cls.id, category.id)
    nil -> IO.puts("WARN: no security matching #{frag}")
  end
end

assign.("allianz", quality)
assign.("ishares", core)
assign.("vanguard", core)
assign.("apple", platforms)
assign.("microsoft", platforms)
assign.("nvidia", platforms)
assign.("bitcoin", krypto)

{:ok, _} =
  Targets.set_targets(owner, portfolio.id, cls.id, [
    %{category_id: stability.id, target_weight: "0.15"},
    %{category_id: quality.id, target_weight: "0.15"},
    %{category_id: wachstum.id, target_weight: "0.65"},
    %{category_id: core.id, target_weight: "0.35"},
    %{category_id: platforms.id, target_weight: "0.30"},
    %{category_id: krypto.id, target_weight: "0.05"}
  ])

:ok = Targets.set_cash_target(owner, portfolio.id, Decimal.new("0.15"))

IO.puts("Seeded 'Strategies' (id #{cls.id}) on portfolio #{portfolio.id} with target weights.")
