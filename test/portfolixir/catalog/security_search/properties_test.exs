defmodule Portfolixir.Catalog.SecuritySearch.PropertiesTest do
  # Issue #763: a search provider's free-form "properties" object used to be
  # merged verbatim into a security's attributes, where the logo keys live
  # and where a non-map crashed the confirm step.
  use ExUnit.Case, async: true

  alias Portfolixir.Catalog.SecuritySearch.Properties

  # User story:
  # As an operator confirming a search result,
  # I want only plain, bounded, non-reserved provider properties copied,
  # so that a provider payload can neither forge the logo bookkeeping nor crash the dialog.
  #
  # Acceptance criteria:
  # - Non-map input becomes an empty map.
  # - Keys starting with "logo_" are dropped; keys are strings of at most 64 bytes.
  # - Values are strings (at most 500 bytes), numbers or booleans; nested values are dropped.
  # - At most 50 keys are kept.
  test "keeps only bounded scalar properties under non-reserved keys" do
    assert Properties.sanitize(nil) == %{}
    assert Properties.sanitize("string") == %{}
    assert Properties.sanitize([1, 2]) == %{}

    assert Properties.sanitize(%{
             "sector" => "Technology",
             "employees" => 12_345,
             "listed" => true,
             "logo_path" => "https://evil.test/pixel.png",
             "logo_locked" => true,
             "nested" => %{"a" => 1},
             "list" => [1, 2],
             "long" => String.duplicate("x", 501),
             String.duplicate("k", 65) => "v",
             :atom_key => "v"
           }) == %{"sector" => "Technology", "employees" => 12_345, "listed" => true}

    many = Map.new(1..60, fn i -> {"k#{i}", i} end)
    assert map_size(Properties.sanitize(many)) == 50
  end
end
