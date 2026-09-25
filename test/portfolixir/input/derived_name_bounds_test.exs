defmodule Portfolixir.Input.DerivedNameBoundsTest do
  # E25 S4, G17 and G24 (#889), from the S3/S4 review round (R2): the name
  # bounds now count Unicode code points, the unit the database counts, but
  # the names the contexts derive themselves (a duplicated plan's default
  # name, a seeded bucket's and view's name) were still cut to length in
  # graphemes, and the import preview's tag-name check counted graphemes too.
  # A name made of combining marks fit the grapheme count and not the code
  # point bound, so the derived write was refused — and the import preview
  # passed a tag its apply then failed on.
  use Portfolixir.DataCase, async: false

  import Portfolixir.WorldFixtures, only: [base_world: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Input.Text
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets

  # One grapheme, three code points.
  @mark "e\u0301\u0301"

  defp codepoints(text), do: text |> String.codepoints() |> length()

  test "truncate/2 cuts to a code point bound without splitting a grapheme" do
    assert Text.truncate("Growth", 120) == "Growth"
    assert Text.truncate(String.duplicate(@mark, 10), 10) == String.duplicate(@mark, 3)
    assert codepoints(Text.truncate(String.duplicate(@mark, 50), 100)) == 99
    assert Text.codepoint_length(String.duplicate(@mark, 4)) == 12
  end

  # User story:
  # As an operator whose plan has a long name written with combining marks,
  # I want to duplicate the plan without typing a new name,
  # so that the default copy name never makes the duplicate fail.
  #
  # Acceptance criteria:
  # - The default copy name fits the plan-name bound in code points, and the
  #   duplicate succeeds.
  test "a duplicated plan's default name fits the bound in code points" do
    world = base_world(name: "Derived names")
    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, growth} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Growth"
      })

    {:ok, [target]} =
      Targets.set_targets(Actor.owner_ui(), world.portfolio.id, tree.id, [
        %{"category_id" => growth.id, "target_weight" => "0.5"}
      ])

    {:ok, _renamed} =
      Targets.rename_plan(Actor.owner_ui(), target.plan_id, String.duplicate(@mark, 40))

    assert {:ok, copy} = Targets.duplicate_plan(Actor.owner_ui(), target.plan_id)
    assert codepoints(copy.name) <= 120
    assert String.starts_with?(copy.name, String.duplicate(@mark, 30))
  end

  # User story:
  # As an operator upgrading a portfolio whose name is written with combining
  # marks,
  # I want its seeded bucket and view named within their bound,
  # so that the seed never stops on a name it derived itself.
  #
  # Acceptance criteria:
  # - A portfolio name within its own bound but past the bucket-name bound in
  #   code points seeds a bucket and a view whose names fit the bound.
  test "a seeded bucket's and view's name fit the bound in code points" do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: String.duplicate(@mark, 80),
        base_currency_code: "EUR"
      })

    assert {:ok, %{buckets_created: 1, views_created: 1}} =
             Buckets.seed_portfolio_scope_buckets(Actor.system_job("portfolio_scope_seed"))

    [bucket] = Enum.filter(Buckets.list_buckets(), &(&1.source_portfolio_id == portfolio.id))
    assert codepoints(bucket.name) <= 100
  end

  # Acceptance criteria:
  # - The import preview's tag-name check refuses a tag name past the
  #   bucket-name bound in code points, as the apply would.
  test "the tag-bucket name check counts code points" do
    assert Buckets.validate_tag_bucket_name(String.duplicate(@mark, 34)) ==
             {:error, :name_too_long}

    assert Buckets.validate_tag_bucket_name(String.duplicate(@mark, 33)) == :ok
  end
end
