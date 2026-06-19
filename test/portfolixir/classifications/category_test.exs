defmodule Portfolixir.Classifications.CategoryTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Classifications.Category

  # User story:
  # As a maintainer naming and colouring a classification category,
  # I want the name, description and colour normalised before they are stored,
  # so that stray whitespace and mixed-case hex colours don't create
  # near-duplicate or invalid-looking tree nodes.
  #
  # Acceptance criteria:
  # - The name is trimmed.
  # - A whitespace-only description normalises to nil rather than "".
  # - The colour is trimmed and lower-cased, and a non-hex colour is rejected.

  test "changeset/2 trims the name and normalises description and colour" do
    changeset =
      Category.changeset(%Category{}, %{
        name: "  Equities  ",
        description: "   ",
        color: "  #AABBCC  ",
        classification_id: 1
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :name) == "Equities"
    assert Ecto.Changeset.get_change(changeset, :color) == "#aabbcc"
    # Whitespace-only description collapses to nil (a real change to nil).
    assert Ecto.Changeset.get_field(changeset, :description) == nil
  end

  test "changeset/2 rejects a non-hex colour" do
    changeset =
      Category.changeset(%Category{}, %{
        name: "Bonds",
        color: "red",
        classification_id: 1
      })

    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :color)
  end

  test "color_changeset/2 trims and lower-cases the colour" do
    changeset = Category.color_changeset(%Category{}, "  #FF8800 ")

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :color) == "#ff8800"
  end
end
