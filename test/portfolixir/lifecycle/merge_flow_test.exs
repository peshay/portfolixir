defmodule Portfolixir.Lifecycle.MergeFlowTest do
  # ADR-0050 §7 and §12 (#328; risk-tier: the merge record, ADR-0036): the
  # two helpers every merge kind writes through. `each/2` runs a merge's
  # per-row writes and must stop at the first refusal, so nothing is written
  # after a row the merge could not write; `jsonable/1` is the form a merge
  # record stores, which must read the same whichever kind of value the
  # snapshot holds. Every value is synthetic.
  use ExUnit.Case, async: true

  alias Portfolixir.Lifecycle.MergeFlow

  # User story:
  # As the maintainer of a merge's writes,
  # I want the per-row loop to stop at the first row it cannot write,
  # so that a refusal is the last write the merge attempts before it rolls
  # back.
  #
  # Acceptance criteria:
  # - Every item answering :ok gives :ok.
  # - The first {:error, reason} is the answer, and no later item runs.
  test "each/2 stops at the first refusal and answers it" do
    assert MergeFlow.each([1, 2, 3], fn _item -> :ok end) == :ok

    parent = self()

    answer =
      MergeFlow.each([1, 2, 3], fn item ->
        send(parent, {:visited, item})
        if item == 2, do: {:error, {:refused, item}}, else: :ok
      end)

    assert answer == {:error, {:refused, 2}}
    assert_received {:visited, 1}
    assert_received {:visited, 2}
    refute_received {:visited, 3}
  end

  # User story:
  # As the maintainer reading a merge record,
  # I want its snapshot and manifest stored as plain JSON,
  # so that a record reads the same in every client and never changes with
  # a struct's representation.
  #
  # Acceptance criteria:
  # - Keys become strings; a Decimal its normalized string; a date and a
  #   timestamp (naive or UTC) ISO 8601; an atom its name; nil and booleans
  #   stay; lists and maps are converted all the way down.
  test "jsonable/1 is the plain JSON a merge record stores" do
    assert MergeFlow.jsonable(%{
             amount: Decimal.new("12.500"),
             date: ~D[2025-06-30],
             inserted_at: ~N[2025-06-30 10:15:00],
             merged_at: ~U[2025-06-30 10:15:00Z],
             reason: :collapsed_duplicate,
             superseded_by: nil,
             retires_hash: true,
             rows: [%{id: 7, quantity: Decimal.new("5")}]
           }) == %{
             "amount" => "12.5",
             "date" => "2025-06-30",
             "inserted_at" => "2025-06-30T10:15:00",
             "merged_at" => "2025-06-30T10:15:00Z",
             "reason" => "collapsed_duplicate",
             "superseded_by" => nil,
             "retires_hash" => true,
             "rows" => [%{"id" => 7, "quantity" => "5"}]
           }
  end
end
