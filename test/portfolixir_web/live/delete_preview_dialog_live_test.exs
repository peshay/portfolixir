defmodule PortfolixirWeb.DeletePreviewDialogLiveTest do
  # Sprint 26 V4 (F21, #894; board 04, pick A "counts only"): the three
  # cascading deletes — a classification, a category, a view — confirm in
  # the app's own delete dialog, which lists from the delete's dry run what
  # the delete removes, or the refusal instead of a delete button. The
  # confirm deletes only what the dialog showed.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Portfolios.Targets

  defp owner, do: Actor.owner_ui()

  # A custom tree "Strategy" with a root "Growth" holding one security and a
  # child "Growth income" holding another, a portfolio plan with a target on
  # the child, a view "Held scope" with a plan of its own (a target on the
  # root), and a view "Bare scope" with nothing on it.
  defp world do
    world = base_world(name: "Dialog Portfolio")
    first = create_security!(name: "Northwind Harbour Logistics AG", ticker: "NHL")
    second = create_security!(name: "Larkspur Robotics Inc", ticker: "LRK")
    third = create_security!(name: "Quillfeather Paper SE", ticker: "QPS")
    {:ok, classification} = Classifications.create_classification(owner(), %{name: "Strategy"})

    {:ok, root} =
      Classifications.create_category(owner(), %{
        classification_id: classification.id,
        name: "Growth"
      })

    {:ok, child} =
      Classifications.create_category(owner(), %{
        classification_id: classification.id,
        name: "Growth income",
        parent_id: root.id
      })

    {:ok, _} = Classifications.assign_security(owner(), first.id, classification.id, root.id)
    {:ok, _} = Classifications.assign_security(owner(), second.id, classification.id, child.id)

    {:ok, _targets} =
      Targets.set_targets(owner(), world.portfolio.id, classification.id, [
        %{category_id: child.id, target_weight: Decimal.new("0.4")}
      ])

    suffix = System.unique_integer([:positive])
    {:ok, held} = Buckets.create_view(owner(), %{name: "Held scope #{suffix}"})
    {:ok, bare} = Buckets.create_view(owner(), %{name: "Bare scope #{suffix}"})

    {:ok, _view_targets} =
      Targets.set_targets(
        owner(),
        world.portfolio.id,
        classification.id,
        [%{category_id: root.id, target_weight: Decimal.new("0.5")}],
        view: held
      )

    %{
      world: world,
      first: first,
      second: second,
      third: third,
      classification: classification,
      root: root,
      child: child,
      held: held,
      bare: bare
    }
  end

  defp rule!(world, name, version, opts \\ []) do
    {:ok, rule} =
      PolicyRules.create_rule(owner(), %{
        portfolio_id: world.portfolio.id,
        view_id: Keyword.get(opts, :view_id),
        name: name,
        version: version
      })

    rule
  end

  defp category_rule!(t, name) do
    rule!(t.world, name, %{
      subject_type: "category",
      classification_id: t.classification.id,
      category_id: t.root.id,
      measure: "drift",
      kind: "band",
      lower: "-3",
      upper: "3",
      severity: "warn"
    })
  end

  # The tree page loads its holdings and per-category results in tasks
  # (`PortfolixirWeb.CappedAsync`), at mount and again after its tree
  # changes. They share this async test's one sandbox connection (#1425): a
  # dry run, a delete or a write of the test that holds the connection past
  # the sandbox's queue limit, as a loaded machine makes it, failed a
  # waiting load's checkout, and a load still running when the test ended
  # was killed mid-query with its page. Both reached the console log, which
  # fails the run (#927). So a test lets the page's loads land before it
  # drives the next database work and before it ends: after the mount here,
  # and with `render_async/1` after a confirm, which may reload the tree.
  defp tree_page(conn, classification) do
    {:ok, view, html} = live(conn, "/classifications/#{classification.id}")
    render_async(view)
    {:ok, view, html}
  end

  defp dialog(view), do: view |> element("#delete-preview-dialog") |> render()

  # The lines under "The delete removes:", as the operator reads them.
  defp lines(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(~s(#delete-preview-dialog [data-role="delete-preview-removes"] li))
    |> Enum.map(&(&1 |> Floki.text() |> String.split() |> Enum.join(" ")))
  end

  defp plural(1, one, _many), do: "1 " <> one
  defp plural(n, _one, many), do: "#{n} " <> many

  # The lines a dry-run answer means, written out here on their own: one
  # line per kind with rows, in the board's order; the subject, the view's
  # bucket sets and a kind with no rows get none.
  defp expected_lines(answer, subject_name \\ nil) do
    count = fn kind -> get_in(answer, [kind, :count]) || 0 end

    categories =
      case subject_name do
        nil ->
          [{count.(:categories), "category", "categories"}]

        name ->
          below = count.(:categories) - 1

          if below > 0,
            do: [
              {:text,
               "“#{name}” and " <> plural(below, "category below it", "categories below it")}
            ],
            else: []
      end

    (categories ++
       [
         {count.(:assignments), "security assignment", "security assignments"},
         {count.(:target_plans), "target plan", "target plans"},
         {count.(:targets), "target weight", "target weights"},
         {count.(:depot_snapshots), "snapshot", "snapshots"}
       ])
    |> Enum.flat_map(fn
      {:text, text} -> [text]
      {0, _one, _many} -> []
      {n, one, many} -> [plural(n, one, many)]
    end)
  end

  defp api_dry_run(path) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> delete(path <> "?dry_run=true")
    |> json_response(200)
    |> get_in(["data", "would_remove"])
    |> Map.new(fn {kind, %{"count" => count}} ->
      {String.to_existing_atom(kind), %{count: count}}
    end)
  end

  defp open_view_menu(view, id) do
    view
    |> element(~s(button.row-actions__kebab[phx-value-kind="view"][phx-value-id="#{id}"]))
    |> render_click()
  end

  # User story (V4, #894; board 04):
  # As the operator deleting a classification,
  # I want the confirmation to say how many categories, assignments, plans
  # and targets go with it, read from the delete's own dry run,
  # so that I know what I give up before I give it up.
  #
  # Acceptance criteria:
  # - "Delete classification" opens the app's dialog (no browser confirm):
  #   the subject box names the tree with its categories and levels, "The
  #   delete removes:" lists one line per kind with its count, as the dry
  #   run — and the API's dry_run=true for the same tree — answers.
  # - What stays and the journal sentence follow; Cancel and the danger
  #   button "Delete classification" form the foot.
  # - Confirming deletes the tree and its rows and returns to the index.
  test "a classification's dialog lists the dry run's counts, and its confirm deletes", %{
    conn: conn
  } do
    t = world()
    {:ok, answer} = Classifications.dry_run_delete_classification(owner(), t.classification)
    api = api_dry_run("/api/v1/classifications/#{t.classification.id}")
    assert Map.new(answer, fn {kind, %{count: c}} -> {kind, %{count: c}} end) == api

    {:ok, view, _html} = tree_page(conn, t.classification)

    view |> element("header.detail-head button.button-danger") |> render_click()

    html = dialog(view)
    assert html =~ "Delete classification"
    assert html =~ "2 categories · 2 levels"
    assert html =~ "The delete removes:"
    assert lines(view) == expected_lines(answer)

    assert lines(view) == [
             "2 categories",
             "2 security assignments",
             "2 target plans",
             "2 target weights"
           ]

    assert html =~ "The securities themselves, their bookings and quotes stay."
    assert html =~ "The audit journal records each deletion with every value"

    assert has_element?(
             view,
             "#delete-preview-dialog [data-role=delete-preview-cancel]",
             "Cancel"
           )

    assert {:error, {:live_redirect, %{to: "/classifications"}}} =
             view |> element("#delete-preview-confirm") |> render_click()

    refute Classifications.get_classification(t.classification.id)
    refute Classifications.get_category(t.child.id)
  end

  # Acceptance criteria:
  # - The index row menu's "Delete" opens the same dialog, and its confirm
  #   deletes the tree.
  test "the classification index's row menu opens the same dialog", %{conn: conn} do
    t = world()
    {:ok, answer} = Classifications.dry_run_delete_classification(owner(), t.classification)
    {:ok, view, _html} = live(conn, "/classifications")

    view |> element("#tree-kebab-#{t.classification.id}") |> render_click()
    view |> element("#tree-delete-#{t.classification.id}") |> render_click()

    assert dialog(view) =~ "Delete classification"
    assert lines(view) == expected_lines(answer)

    view |> element("#delete-preview-confirm") |> render_click()
    refute Classifications.get_classification(t.classification.id)
  end

  # User story (V4, #894; board 04):
  # As the operator deleting one branch of a tree,
  # I want the dialog to count the branch's categories below it, its
  # assignments and its targets,
  # so that I see what the branch takes with it.
  #
  # Acceptance criteria:
  # - The category counts itself: its line reads "“Growth” and 1 category
  #   below it"; the box says which classification it is in.
  # - Confirming deletes the branch; the page says "Category deleted" and
  #   the dialog closes.
  test "a category's dialog counts the branch, and its confirm deletes it", %{conn: conn} do
    t = world()
    {:ok, answer} = Classifications.dry_run_delete_category(owner(), t.root)

    api =
      api_dry_run("/api/v1/classifications/#{t.classification.id}/categories/#{t.root.id}")

    assert Map.new(answer, fn {kind, %{count: c}} -> {kind, %{count: c}} end) == api

    {:ok, view, _html} = tree_page(conn, t.classification)

    view
    |> element(~s(button[phx-click="ask_delete_category"][phx-value-id="#{t.root.id}"]))
    |> render_click()

    html = dialog(view)
    assert html =~ "Delete category"
    assert html =~ "Category in"
    assert lines(view) == expected_lines(answer, "Growth")

    assert lines(view) == [
             "“Growth” and 1 category below it",
             "2 security assignments",
             "2 target weights"
           ]

    assert html =~ "in this classification they then sit under “Unassigned”"

    html = view |> element("#delete-preview-confirm") |> render_click()
    render_async(view)
    assert html =~ "Category deleted"
    refute has_element?(view, "#delete-preview-dialog")
    refute Classifications.get_category(t.root.id)
    refute Classifications.get_category(t.child.id)
  end

  # User story (V4, #894; board 04):
  # As the operator deleting a view,
  # I want the dialog to say which plans, targets and snapshots go with it,
  # or that nothing else goes,
  # so that a view's delete is not a guess.
  #
  # Acceptance criteria:
  # - The view's dialog lists its plan and its targets; its bucket sets are
  #   the view itself and get no line.
  # - A view with nothing on it says "Nothing else is removed with it."
  # - Confirming deletes the view; the page says "View deleted".
  test "a view's dialog lists its plan, or that nothing else goes", %{conn: conn} do
    t = world()
    {:ok, answer} = Buckets.dry_run_delete_view(owner(), t.held)

    assert Map.new(answer, fn {kind, %{count: c}} -> {kind, %{count: c}} end) ==
             api_dry_run("/api/v1/views/#{t.held.id}")

    {:ok, view, _html} = live(conn, "/buckets")

    open_view_menu(view, t.held.id)

    view
    |> element(~s([role="menu"] button[phx-click="ask_delete_view"][phx-value-id="#{t.held.id}"]))
    |> render_click()

    assert dialog(view) =~ "Delete view"
    # The box names the view as its row does: its rule, no amount.
    assert view
           |> element("#delete-preview-dialog [data-role=delete-preview-subject]")
           |> render() =~ "All depots, cash accounts and positions · no filters"

    assert lines(view) == expected_lines(answer)
    assert lines(view) == ["1 target plan", "1 target weight"]
    assert dialog(view) =~ "The buckets and their assignments stay."

    html = view |> element("#delete-preview-confirm") |> render_click()
    assert html =~ "View deleted"
    refute Buckets.get_view(t.held.id)

    open_view_menu(view, t.bare.id)

    view
    |> element(~s([role="menu"] button[phx-click="ask_delete_view"][phx-value-id="#{t.bare.id}"]))
    |> render_click()

    assert lines(view) == []
    assert dialog(view) =~ "Nothing else is removed with it."
  end

  # User story (V4, #894; board 04, ADR-0049 §8):
  # As the operator deleting something a policy rule reads,
  # I want the dialog to say so before I click delete, naming the rules,
  # so that I do not confirm a delete that will be refused.
  #
  # Acceptance criteria:
  # - The dialog is titled "Cannot delete", names the subject as read by
  #   policy rules, lists each rule linked to Risk, says the delete stays
  #   blocked, and its foot offers only "Close" — no delete button.
  # - The confirm event, sent anyway, deletes nothing.
  test "a delete a rule blocks shows the refusal and only Close", %{conn: conn} do
    t = world()
    category_rule!(t, "Growth in band")

    rule!(t.world, "Held scope small", %{
      subject_type: "view",
      subject_view_id: t.held.id,
      measure: "weight",
      kind: "cap",
      threshold: "5",
      severity: "hard"
    })

    {:ok, view, _html} = tree_page(conn, t.classification)

    view
    |> element(~s(button[phx-click="ask_delete_category"][phx-value-id="#{t.root.id}"]))
    |> render_click()

    html = dialog(view)
    assert html =~ "Cannot delete"
    assert html =~ "is read by policy rules:"
    assert html =~ "Growth in band"
    assert html =~ "so the delete stays blocked"
    assert has_element?(view, "#delete-preview-dialog [data-role=policy-rule-link]")
    refute has_element?(view, "#delete-preview-confirm")
    refute html =~ "The delete removes:"
    assert has_element?(view, "#delete-preview-dialog .modal-footer button", "Close")

    render_click(view, "confirm_delete_preview", %{
      "kind" => "category",
      "id" => to_string(t.root.id)
    })

    render_async(view)
    assert Classifications.get_category(t.root.id)

    view |> element("header.detail-head button.button-danger") |> render_click()
    assert dialog(view) =~ "Cannot delete"
    assert dialog(view) =~ "Growth in band"

    {:ok, buckets, _html} = live(conn, "/buckets")
    open_view_menu(buckets, t.held.id)

    buckets
    |> element(~s([role="menu"] button[phx-click="ask_delete_view"][phx-value-id="#{t.held.id}"]))
    |> render_click()

    assert dialog(buckets) =~ "Held scope small"
    refute has_element?(buckets, "#delete-preview-confirm")
    assert Buckets.get_view(t.held.id)
  end

  # User story (V4, #894; board 04, "the confirm holds to the list it
  # showed"):
  # As the operator whose tree changed while the dialog was open,
  # I want the confirm to delete nothing and show me the new state,
  # so that I never delete a row the dialog did not list.
  #
  # Acceptance criteria:
  # - A security assigned under the category after the dialog opened: the
  #   confirm deletes nothing, the dialog stays open with the attention note
  #   and the new count.
  # - Confirming the new state deletes.
  test "a change while the dialog is open deletes nothing and shows the new state", %{
    conn: conn
  } do
    t = world()
    {:ok, view, _html} = tree_page(conn, t.classification)

    view
    |> element(~s(button[phx-click="ask_delete_category"][phx-value-id="#{t.root.id}"]))
    |> render_click()

    assert "2 security assignments" in lines(view)

    {:ok, _} =
      Classifications.assign_security(owner(), t.third.id, t.classification.id, t.child.id)

    view |> element("#delete-preview-confirm") |> render_click()
    render_async(view)

    assert Classifications.get_category(t.root.id)
    assert Classifications.get_category(t.child.id)
    assert dialog(view) =~ "What the delete removes changed while this dialog was open."
    assert has_element?(view, "#delete-preview-dialog [data-role=delete-preview-changed]")
    assert "3 security assignments" in lines(view)

    view |> element("#delete-preview-confirm") |> render_click()
    render_async(view)
    refute Classifications.get_category(t.root.id)
  end

  # --- Sprint 26 fix D begin ---
  # User story (closing act, UAT persona on V4):
  # As the operator whose tree changed while the delete dialog was open,
  # I want the refreshed dialog's subject box to count what is there now,
  # so that its head does not say "2 positions" over a list that counts 3.
  #
  # Acceptance criteria:
  # - A category's dialog that found the answer changed shows the branch's
  #   new position count in its subject box.
  # - A classification's dialog that found the answer changed shows the
  #   tree's new category and level counts in its subject box.
  test "a refreshed dialog's subject box counts what is there now", %{conn: conn} do
    t = world()

    # Held, so the tree's rows count them as positions once the holdings
    # are in.
    for security <- [t.first, t.second, t.third], do: buy!(t.world, security, [])

    {:ok, view, _html} = tree_page(conn, t.classification)

    view
    |> element(~s(button[phx-click="ask_delete_category"][phx-value-id="#{t.root.id}"]))
    |> render_click()

    assert subject(view) =~ "2 positions"

    {:ok, _} =
      Classifications.assign_security(owner(), t.third.id, t.classification.id, t.child.id)

    view |> element("#delete-preview-confirm") |> render_click()
    render_async(view)
    assert has_element?(view, "#delete-preview-dialog [data-role=delete-preview-changed]")
    assert subject(view) =~ "3 positions"

    view |> element("[data-role=delete-preview-cancel]") |> render_click()
    view |> element("header.detail-head button.button-danger") |> render_click()
    assert subject(view) =~ "2 categories · 2 levels"

    {:ok, _} =
      Classifications.create_category(owner(), %{
        classification_id: t.classification.id,
        name: "Growth income small caps",
        parent_id: t.child.id
      })

    view |> element("#delete-preview-confirm") |> render_click()
    render_async(view)
    assert has_element?(view, "#delete-preview-dialog [data-role=delete-preview-changed]")
    assert subject(view) =~ "3 categories · 3 levels"
  end

  defp subject(view) do
    view
    |> element("#delete-preview-dialog [data-role=delete-preview-subject]")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text(sep: " ")
    |> String.split()
    |> Enum.join(" ")
  end

  # --- Sprint 26 fix D end ---

  # User story (V4, #894):
  # As the operator who opened a delete dialog by mistake,
  # I want Cancel, the close button and Escape to close it,
  # so that nothing is deleted.
  #
  # Acceptance criteria:
  # - The dialog is the booking delete's (`.booking-delete-dialog`, the
  #   phone's bottom sheet) on the ModalDialog hook, Escape pushing its
  #   close event.
  # - Cancel and the close event (what Escape sends) close it; every row
  #   stays.
  test "Cancel and Escape close the dialog and delete nothing", %{conn: conn} do
    t = world()
    {:ok, view, _html} = tree_page(conn, t.classification)

    ask = fn ->
      view
      |> element(~s(button[phx-click="ask_delete_category"][phx-value-id="#{t.root.id}"]))
      |> render_click()
    end

    ask.()
    # The booking delete's dialog: 460 px, under 720 px its bottom sheet.
    assert has_element?(view, ~s(dialog#delete-preview-dialog.modal.booking-delete-dialog))
    assert has_element?(view, ~s(#delete-preview-dialog[phx-hook="ModalDialog"]))

    assert has_element?(
             view,
             ~s(#delete-preview-dialog[data-close-event="cancel_delete_preview"])
           )

    view |> element("#delete-preview-dialog [data-role=delete-preview-cancel]") |> render_click()
    refute has_element?(view, "#delete-preview-dialog")

    ask.()
    render_hook(view, "cancel_delete_preview", %{})
    refute has_element?(view, "#delete-preview-dialog")

    assert Classifications.get_category(t.root.id)
    assert Classifications.get_category(t.child.id)
  end

  # User story (V4, #894; Sprint 25 carry-forward 2, plan D-8):
  # As the operator whose screen only asks before it deletes,
  # I want no event or parameter the page receives — misspelled, forged or
  # sent without the dialog — to reach the real delete,
  # so that opening the dialog can never delete and the confirm deletes only
  # what the dialog showed.
  #
  # Acceptance criteria:
  # - Opening runs only the dry run; a misspelled open parameter opens
  #   nothing.
  # - The confirm sent without an open dialog deletes nothing.
  # - The confirm with a forged id or kind deletes neither the forged target
  #   nor the dialog's subject.
  # - A misspelled confirm event and the retired direct-delete events
  #   delete nothing.
  test "no misspelled or forged event or parameter reaches the real delete", %{conn: conn} do
    t = world()
    {:ok, view, _html} = tree_page(conn, t.classification)

    render_click(view, "confirm_delete_preview", %{
      "kind" => "category",
      "id" => to_string(t.root.id)
    })

    render_async(view)
    render_click(view, "ask_delete_category", %{"ID" => to_string(t.root.id)})
    refute has_element?(view, "#delete-preview-dialog")

    render_click(view, "ask_delete_category", %{"id" => to_string(t.root.id)})
    assert has_element?(view, "#delete-preview-dialog")
    assert Classifications.get_category(t.root.id)

    for params <- [
          %{"kind" => "category", "id" => to_string(t.child.id)},
          %{"kind" => "classification", "id" => to_string(t.root.id)},
          %{"kind" => "categroy", "id" => to_string(t.root.id)},
          %{"kind" => "category", "id" => to_string(t.root.id) <> "x"},
          %{"kind" => "category"},
          %{}
        ] do
      render_click(view, "confirm_delete_preview", params)
    end

    for event <- [
          "confirm_delete_previews",
          "confirm-delete-preview",
          "delete_category",
          "delete_classification",
          "delete_classification_row"
        ] do
      render_click(view, event, %{"id" => to_string(t.root.id)})
    end

    render_async(view)
    assert Classifications.get_category(t.root.id)
    assert Classifications.get_category(t.child.id)
    assert Classifications.get_classification(t.classification.id)

    {:ok, buckets, _html} = live(conn, "/buckets")

    render_click(buckets, "confirm_delete_preview", %{
      "kind" => "view",
      "id" => to_string(t.bare.id)
    })

    render_click(buckets, "delete_view", %{"id" => to_string(t.bare.id)})
    render_click(buckets, "ask_delete_view", %{"view_id" => to_string(t.bare.id)})
    refute has_element?(buckets, "#delete-preview-dialog")
    assert Buckets.get_view(t.bare.id)
  end

  # User story (V4, #894; board 04's strings):
  # As the operator who reads the app in German,
  # I want the dialog in the board's German,
  # so that the delete reads as the rest of the page does.
  #
  # Acceptance criteria:
  # - "Kategorie löschen", "Das Löschen entfernt:", the category's line
  #   „Growth“ und 1 Kategorie darunter, the counts, what stays and the
  #   journal sentence in German.
  test "the dialog reads in German on a German page", %{conn: conn} do
    t = world()

    conn =
      PortfolixirWeb.PreferenceCookieHelpers.put_preference_cookie(
        conn,
        "portfolixir_locale",
        "de"
      )

    {:ok, view, _html} = tree_page(conn, t.classification)
    render_click(view, "ask_delete_category", %{"id" => to_string(t.root.id)})

    html = dialog(view)
    assert html =~ "Kategorie löschen"
    assert html =~ "Das Löschen entfernt:"

    assert lines(view) == [
             "„Growth“ und 1 Kategorie darunter",
             "2 Wertpapierzuordnungen",
             "2 Zielgewichte"
           ]

    assert html =~ "in dieser Klassifizierung stehen sie danach unter „Nicht zugeordnet“."
    assert html =~ "Das Audit-Journal hält jede Löschung mit allen Werten fest"
    assert html =~ "Abbrechen"
  end

  # Acceptance criteria:
  # - The three controls carry no browser confirmation (`data-confirm`)
  #   any more; each opens the dialog.
  test "the three delete controls carry no browser confirmation", %{conn: conn} do
    t = world()
    {:ok, view, html} = tree_page(conn, t.classification)
    doc = Floki.parse_document!(html)

    assert [_] =
             Floki.find(doc, ~s(header.detail-head button[phx-click="ask_delete_classification"]))

    assert [] = Floki.find(doc, "header.detail-head button[data-confirm]")
    assert [_ | _] = Floki.find(doc, ~s(button[phx-click="ask_delete_category"]))
    assert [] = Floki.find(doc, ~s(.cat-actions button[data-confirm]))
    _ = view

    {:ok, index, _html} = live(conn, "/classifications")
    index |> element("#tree-kebab-#{t.classification.id}") |> render_click()
    refute has_element?(index, "#tree-delete-#{t.classification.id}[data-confirm]")

    {:ok, buckets, _html} = live(conn, "/buckets")
    open_view_menu(buckets, t.held.id)
    assert has_element?(buckets, ~s([role="menu"] button[phx-click="ask_delete_view"]))

    refute has_element?(
             buckets,
             ~s([role="menu"] button[phx-click="ask_delete_view"][data-confirm])
           )
  end
end
