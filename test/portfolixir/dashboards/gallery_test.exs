defmodule Portfolixir.Dashboards.GalleryTest do
  # Sprint 32 S4 (ADR-0062's amendment of 2026-11-25, point 5; I61; board
  # ux-design-2026-11-25-sprint32/03): what the gallery offers and the name
  # its dialog suggests, as the context answers them for the screen and
  # the API alike.
  #
  # group: :dashboards -- a create takes the count lock (LockTable row 30).
  use Portfolixir.DataCase, async: true, group: :dashboards

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Templates

  # User story:
  # As the operator choosing a template,
  # I want only templates whose widgets all exist offered, each marked as a
  # starter or a theme and saying whether it asks for a scope,
  # so that nothing I pick draws an empty place.
  #
  # Acceptance criteria:
  # - `Templates.offered/1` keeps a template whose kinds are all
  #   registered and leaves out one naming a kind that is not (a synthetic
  #   template naming "heatmap", the board's unbuilt kind).
  # - Every shipped template is offered, has a group (`starter` or
  #   `theme`, a starter exactly when it is marked one), a title and a
  #   subtitle in the current locale, and `asks_scope`.
  test "a template is offered only when all its kinds exist" do
    unbuilt = %{
      key: "performance",
      starter: false,
      asks_scope: false,
      layout: [
        %{"kind" => "performance", "size" => "XL", "col" => 1, "row" => 1, "settings" => %{}},
        %{"kind" => "heatmap", "size" => "L", "col" => 1, "row" => 5, "settings" => %{}}
      ]
    }

    shipped = Templates.templates()
    assert Templates.offered([unbuilt | shipped]) == shipped

    for template <- shipped do
      assert Templates.group(template) == if(template.starter, do: "starter", else: "theme")
      assert is_binary(Templates.title(template.key)), template.key
      assert is_binary(Templates.subtitle(template.key)), template.key
      assert is_boolean(template.asks_scope), template.key
    end
  end

  # User story:
  # As the operator naming a copy,
  # I want a name suggested that no dashboard of mine holds,
  # so that two dashboards are never called the same by default.
  #
  # Acceptance criteria:
  # - A free name is suggested as it is; a taken one as „… (2)“, then the
  #   first free number; a name compared trimmed, case as stored; a
  #   suggestion longer than the name's limit is cut before its number.
  test "a taken name is suggested with the first free number" do
    assert Dashboards.suggested_name("Überblick") == "Überblick"

    {:ok, _} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Überblick"})
    assert Dashboards.suggested_name("Überblick") == "Überblick (2)"

    {:ok, _} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Überblick (3)"})
    assert Dashboards.suggested_name("Überblick") == "Überblick (2)"

    {:ok, _} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Überblick (2)"})
    assert Dashboards.suggested_name("Überblick") == "Überblick (4)"
    assert Dashboards.suggested_name("überblick") == "überblick"

    long = String.duplicate("x", Dashboards.name_max())
    {:ok, _} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => long})
    suggested = Dashboards.suggested_name(long)
    assert String.length(suggested) == Dashboards.name_max()
    assert String.ends_with?(suggested, " (2)")
  end
end
