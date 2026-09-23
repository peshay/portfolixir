defmodule Portfolixir.Derived.SecurityBasisMemoTest do
  # async: false — the derived configuration and the memo are process-global.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.SecurityMetrics
  alias Portfolixir.Derived
  alias Portfolixir.Derived.Memo
  alias Portfolixir.DerivedConfig

  # User story (2026-09-23, issue #825, ADR-0047 §8):
  # As the maintainer who will one day take the ADR-0039 C3 measurement for
  # `security_metrics`,
  # I want its derived entry keyed under the security's own basis,
  # so that switching the lifetime on is the whole move: a quote write for the
  # security supersedes the entry, and a write for another security does not.
  #
  # Acceptance criteria:
  # - With `security_metrics` configured `:request` (a test-only override —
  #   the registry default stays `:none`), a computed entry is current under
  #   `Derived.security_basis/1`.
  # - A quote write for ANOTHER security leaves it current.
  # - A quote write for the security itself — one no portfolio ever held —
  #   supersedes it.

  @as_of ~D[2024-03-29]

  setup do
    Memo.reset()
    DerivedConfig.enable!(lifetimes: [security_metrics: :request])
    :ok
  end

  defp security!(name) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{name: name, currency_code: "EUR"})

    security
  end

  defp quote!(security, date, close) do
    {:ok, 1} =
      Quotes.upsert_many(security.id, [
        %{date: date, close: Decimal.new(close), source: "manual"}
      ])
  end

  defp peek(security) do
    Derived.peek(
      :security_metrics,
      Derived.security_basis(security.id),
      "#{security.id}:#{Date.to_iso8601(@as_of)}"
    )
  end

  test "the security_metrics entry lives under the security's own basis" do
    watched = security!("Watch-Only Candidate")
    other = security!("Another Watch-Only")
    quote!(watched, ~D[2024-03-01], "10")

    assert {:ok, _payload} = SecurityMetrics.for_security(watched.id, as_of: @as_of)
    assert {:fresh, _metrics} = peek(watched)

    quote!(other, ~D[2024-03-01], "20")
    assert {:fresh, _metrics} = peek(watched)

    quote!(watched, ~D[2024-03-04], "11")
    assert {:stale, _metrics, _as_of} = peek(watched)
  end
end
