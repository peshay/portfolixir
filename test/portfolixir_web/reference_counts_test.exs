defmodule PortfolixirWeb.ReferenceCountsTest do
  use ExUnit.Case, async: true

  alias PortfolixirWeb.ReferenceCounts

  # User story (#918, #921; Sprint 18 pick H8):
  # As the operator reading what holds a record on a page,
  # I want every count named in my language, a table the page has no noun
  # for included as "other records",
  # so that a reference the page does not know yet is never dropped from
  # the sentence that says what blocks or freezes the record.
  #
  # Acceptance criteria:
  # - The known tables are named in a fixed order: what a merge carries
  #   first, then research entries and rule versions.
  # - A table without a noun is counted as "1 other record" / "3 other
  #   records", after the known ones, summed over every such table.
  # - The German catalog carries the "other records" plural.
  test "an unknown referencing table is counted as other records, after the named ones" do
    counts = %{
      "policy_rule_versions" => 1,
      "security_quotes" => 840,
      "future_references" => 2,
      "another_table" => 1
    }

    assert ReferenceCounts.parts(counts) == [
             "840 quotes",
             "1 rule version",
             "3 other records"
           ]

    assert ReferenceCounts.parts(%{"transactions" => 12, "future_references" => 1}) == [
             "12 bookings",
             "1 other record"
           ]

    assert ReferenceCounts.parts(counts) |> ReferenceCounts.and_list() ==
             "840 quotes, 1 rule version and 3 other records"

    Gettext.put_locale(PortfolixirWeb.Gettext, "de")

    assert ReferenceCounts.parts(counts) == [
             "840 Kurse",
             "1 Regelversion",
             "3 weitere Einträge"
           ]
  end
end
