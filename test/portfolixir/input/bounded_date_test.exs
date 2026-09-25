defmodule Portfolixir.Input.BoundedDateTest do
  # E25 S4, F70 (#889): a cast date field accepted any year the cast could
  # build, and a year the database cannot hold faithfully reached storage
  # altered, so the stored row, the response and the journal disagreed. One
  # bounded date rule is shared by every writer: an ISO 8601 calendar date
  # string or a `Date`, inside one fixed range of years.
  use ExUnit.Case, async: true

  import Ecto.Changeset

  alias Portfolixir.Input.BoundedDate

  defp changeset(attrs) do
    {%{}, %{on: :date, until: :date}}
    |> cast(attrs, [:on, :until])
    |> BoundedDate.validate([:on, :until])
  end

  # User story:
  # As an operator or agent writing a dated record,
  # I want every date the product stores to be a plain calendar date inside a
  # sane range of years,
  # so that the date I sent is the date that is stored, answered and journaled.
  #
  # Acceptance criteria:
  # - An ISO date string or a `Date` inside the range is accepted unchanged.
  # - A date outside the range, a date given as a map or a date-time, and a
  #   non-ISO string are field errors.
  # - The range's first and last day are accepted.
  test "only an ISO date or a Date inside the bounded years passes" do
    assert changeset(%{"on" => "2024-02-29"}).valid?
    assert get_change(changeset(%{"on" => "2024-02-29"}), :on) == ~D[2024-02-29]
    assert changeset(%{on: ~D[2024-02-29]}).valid?
    assert changeset(%{"on" => Date.to_iso8601(BoundedDate.earliest())}).valid?
    assert changeset(%{"on" => Date.to_iso8601(BoundedDate.latest())}).valid?

    for refused <- [
          Date.add(BoundedDate.earliest(), -1),
          Date.add(BoundedDate.latest(), 1),
          Date.new!(-1, 1, 1),
          %{"year" => 2024, "month" => 1, "day" => 1},
          %{"year" => 6_000_000, "month" => 1, "day" => 1},
          "2024-01-01T00:00:00Z",
          ~N[2024-01-01 00:00:00],
          "20240101",
          "0001-01-01"
        ] do
      changeset = changeset(%{"on" => refused})
      refute changeset.valid?, "accepted #{inspect(refused)}"
      assert Keyword.has_key?(changeset.errors, :on)
    end
  end

  test "an absent or blank date is left to validate_required" do
    assert changeset(%{}).valid?
    assert changeset(%{"on" => nil}).valid?
    assert changeset(%{"on" => ""}).valid?
  end

  test "parse/1 applies the same rule to a date that does not travel in a changeset" do
    assert BoundedDate.parse("2024-02-29") == {:ok, ~D[2024-02-29]}
    assert BoundedDate.parse(~D[2024-02-29]) == {:ok, ~D[2024-02-29]}
    assert BoundedDate.parse("9999-12-31") == :error
    assert BoundedDate.parse(Date.new!(6_000_000, 1, 1)) == :error
    assert BoundedDate.parse(%{"year" => 2024, "month" => 1, "day" => 1}) == :error
    assert BoundedDate.parse("not a date") == :error
    assert BoundedDate.parse(nil) == :error
  end

  test "the refusal names the accepted range" do
    [on: {message, _}] = changeset(%{"on" => "1800-01-01"}).errors
    assert message =~ Date.to_iso8601(BoundedDate.earliest())
    assert message =~ Date.to_iso8601(BoundedDate.latest())
  end
end
