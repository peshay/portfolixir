defmodule PortfolixirWeb.TransactionKindLabelTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Catalog.AssetClasses
  alias Portfolixir.Catalog.Feeds
  alias Portfolixir.Knowledge.SecurityEvent
  alias Portfolixir.Ledger.Transaction
  alias PortfolixirWeb.SecurityEventLabel
  alias PortfolixirWeb.TransactionKindLabel

  # User story (#785, EXPERIENCE.md → Amendment 2026-09-12 → Voice and Tone):
  # As a local portfolio maintainer reading the transactions history,
  # I want every kind to read as a word in my language,
  # so that no internal slug such as "balance_adjustment" reaches a chip or
  # a row.
  #
  # Acceptance criteria:
  # - Every element of Transaction.kinds/0 has a gettext label; none is the
  #   slug itself, none carries an underscore.
  # - There is no fallback clause: an unknown kind is refused, not printed.
  # - The German catalog carries the labels (balance_adjustment reads
  #   "Saldo gesetzt").
  test "every transaction kind has a localized label and an unknown kind is refused" do
    for kind <- Transaction.kinds() do
      label = TransactionKindLabel.label(kind)
      assert is_binary(label) and label != "", kind
      refute label == kind, kind
      refute label =~ "_", kind
    end

    assert_raise FunctionClauseError, fn -> TransactionKindLabel.label("bogus_kind") end

    Gettext.put_locale(PortfolixirWeb.Gettext, "de")
    assert TransactionKindLabel.label("balance_adjustment") == "Saldo gesetzt"
    assert TransactionKindLabel.label("inbound_delivery") != "inbound_delivery"
  end

  # The same rule, applied to a NEW enum from its first commit rather than
  # after a review finds a slug on a screen (ADR-0048 §6: "the enum-label
  # meta-test Sprint 12 added for transaction kinds applies here from the
  # first commit").
  test "every security-event kind and timing has a localized label and an unknown value is refused" do
    Gettext.put_locale(PortfolixirWeb.Gettext, "en")

    for kind <- SecurityEvent.kinds() do
      label = SecurityEventLabel.kind(kind)
      assert is_binary(label) and label != "", kind
      refute label == kind, kind
      refute label =~ "_", kind
    end

    for timing <- SecurityEvent.timings() do
      label = SecurityEventLabel.timing(timing)
      assert is_binary(label) and label != "", timing
      refute label == timing, timing
      refute label =~ "_", timing
    end

    assert_raise FunctionClauseError, fn -> SecurityEventLabel.kind("bogus_kind") end
    assert_raise FunctionClauseError, fn -> SecurityEventLabel.timing("soonish") end

    Gettext.put_locale(PortfolixirWeb.Gettext, "de")
    assert SecurityEventLabel.kind("earnings") == "Geschäftszahlen"
    assert SecurityEventLabel.timing("estimated") == "Geschätzt"
  end

  # The feed identifier is the second slug the review saw on a page: the
  # closed set reads through gettext, and an identifier an import carried in
  # from outside the set is humanised rather than printed raw.
  test "a feed identifier never reads as its slug" do
    Gettext.put_locale(PortfolixirWeb.Gettext, "en")
    assert Feeds.label("PORTFOLIO_PERFORMANCE") == "Portfolio Performance"
    assert Feeds.label("COINGECKO") == "CoinGecko"
    assert Feeds.label(nil) == ""
    assert Feeds.label("SOME_OTHER_FEED") == "Some other feed"

    for code <- Feeds.codes() do
      refute Feeds.label(code) == code, code
    end
  end

  # The third slug the rule covers, closed in the Sprint 12 closing act: an
  # asset-class code outside the catalog's own set reached the screen as the
  # stored value through a catch-all clause. The clause is unreachable through
  # a validated write, so this is the meta-test the rule asks for rather than
  # a regression test for a live defect.
  test "an asset-class code never reads as its slug" do
    Gettext.put_locale(PortfolixirWeb.Gettext, "en")

    assert AssetClasses.label("equity") == "Equity"
    assert AssetClasses.label(nil) == ""
    assert AssetClasses.label("some_new_kind") == "Some new kind"
    refute AssetClasses.label("some_new_kind") == "some_new_kind"

    for {_label, code} <- AssetClasses.options() do
      refute AssetClasses.label(code) == code, code
    end
  end
end
