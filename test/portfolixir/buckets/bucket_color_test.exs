defmodule Portfolixir.Buckets.BucketColorTest do
  # Issue #770: a bucket colour lands in a style attribute on every page that
  # renders it, so its shape is validated like a category colour already is.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Buckets.Bucket

  # User story:
  # As the operator,
  # I want a bucket colour accepted only as a six-digit hex value,
  # so that a stored value can never carry CSS declarations onto the page.
  #
  # Acceptance criteria:
  # - "#RRGGBB" in either case passes; blank passes (no colour).
  # - Anything else, including a value with a semicolon or url(), is refused.
  test "accepts hex colours and refuses everything else" do
    for color <- ["#12ab3F", "#000000", nil, ""] do
      changeset = Bucket.changeset(%Bucket{}, %{name: "B", dimension: "custom", color: color})
      refute errors_on(changeset)[:color], inspect(color)
    end

    for color <- ["red", "#fff", "#12ab3Fzz", "red;position:fixed;inset:0", "url(https://x)"] do
      changeset = Bucket.changeset(%Bucket{}, %{name: "B", dimension: "custom", color: color})
      assert errors_on(changeset)[:color], color
    end
  end
end
