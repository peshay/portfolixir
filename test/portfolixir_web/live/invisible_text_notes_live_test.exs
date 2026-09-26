defmodule PortfolixirWeb.InvisibleTextNotesLiveTest do
  # E25 S7, G20; the owner's pick G12.2 = B on board 12-e25-new-marks: a row
  # stored before the refusal existed can still carry characters the
  # operator cannot see. Where its text renders, ONE attention data note says
  # so, with the remedy as a child control and the text, spelled the way the
  # MCP companion spells it for the agent, in a disclosure.
  use PortfolixirWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1, deposit!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.SecurityEvent
  alias Portfolixir.Knowledge.SecurityNote
  alias Portfolixir.Portfolios.PolicyRule
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Portfolios.PolicyRuleVersion
  alias Portfolixir.Repo

  defp today, do: Portfolixir.Clock.today()

  # One character by its code point: the source carries none itself.
  defp c(code_point), do: <<code_point::utf8>>
  defp zwsp, do: c(0x200B)

  # A write as the tables held it before the refusal: straight to the
  # table, with the journal's actor set so its guard lets it through.
  defp legacy!(fun) do
    {:ok, result} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'system_job', true)")
        fun.()
      end)

    result
  end

  defp rename!(schema, id, fields) do
    legacy!(fn -> Repo.update_all(from(r in schema, where: r.id == ^id), set: fields) end)
  end

  defp note_in(view, selector) do
    view |> element("#{selector} [data-role='invisible-text-note']") |> render()
  end

  # User story (E25 S7, G20; pick G12.2 = B):
  # As the operator reading my research log, which never changes a stored
  # entry,
  # I want an entry whose text carries characters I cannot see to say so,
  # with the text spelled out behind a disclosure and the way to replace it,
  # so that I read what the agent reads and can append a clean entry.
  #
  # Acceptance criteria:
  # - The entry carries one attention data note: "The text contains 2
  #   invisible characters." — one sentence whatever the count — with the
  #   log's reason and a control "Append an entry that supersedes #n".
  # - The disclosure "Text with the characters made visible" holds the body
  #   as the MCP boundary spells it ("Auftrags[U+200B]bestand").
  # - The control preselects the entry in the form's "Supersedes".
  # - A clean entry, and the thesis card of a clean thesis, carry no note;
  #   a thesis whose text or invalidation condition carries such characters
  #   shows the note under the thesis text.
  test "a research entry and the thesis with invisible characters carry one attention note",
       %{conn: conn} do
    security = create_security!(name: "Meridian Global Equity ETF", ticker: "MGEQ")

    legacy_entry =
      legacy!(fn ->
        Repo.insert!(%SecurityNote{
          security_id: security.id,
          author: :agent,
          kind: :thesis,
          body: "Auftrags" <> zwsp() <> "bestand stabil, Bedingung nicht erreicht." <> zwsp(),
          invalidation_condition: "Marge unter 8 %" <> c(0x202E),
          source_quality: :primary,
          as_of: today()
        })
      end)

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=research")

    note = note_in(view, "#research-entry-#{legacy_entry.id}")
    assert note =~ "data-note--attention"
    assert note =~ "The text contains 3 invisible characters."
    assert note =~ "Auftrags[U+200B]bestand stabil, Bedingung nicht erreicht.[U+200B]"
    assert note =~ "Marge unter 8 %[U+202E]"
    assert note =~ "Text with the characters made visible"

    assert has_element?(view, "[data-role='thesis-state'] [data-role='invisible-text-note']")

    view
    |> element(
      "#research-entry-#{legacy_entry.id} [data-role='invisible-text-note'] button",
      "Append an entry that supersedes ##{legacy_entry.id}"
    )
    |> render_click()

    assert has_element?(
             view,
             "#research-entry-form select[name='note[supersedes_id]'] option[value='#{legacy_entry.id}'][selected]"
           )

    view
    |> form("#research-entry-form",
      note: %{kind: "thesis", body: "Clean restatement.", source_quality: "primary"}
    )
    |> render_submit()

    refute has_element?(view, "[data-role='thesis-state'] [data-role='invisible-text-note']")
  end

  # Acceptance criteria:
  # - An event whose note carries invisible characters shows the note in the
  #   event, saying it is corrected over the API or MCP (the page has no
  #   event edit).
  test "an event note with invisible characters carries the note in the event", %{conn: conn} do
    security = create_security!(name: "Coastal Ferry Lines", ticker: "CFL")

    legacy!(fn ->
      Repo.insert!(%SecurityEvent{
        security_id: security.id,
        kind: :earnings,
        date: Date.add(today(), 20),
        timing: :estimated,
        source_quality: :awareness,
        note: "Q3 call" <> zwsp()
      })
    end)

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=events")

    note = note_in(view, "[data-role='event-entry']")
    assert note =~ "The text contains 1 invisible character."
    assert note =~ "Q3 call[U+200B]"
  end

  # Acceptance criteria:
  # - A security whose stored name carries invisible characters shows the
  #   note in the detail pane under its head: "The name contains 1 invisible
  #   character.", "Typed in anew, it is clean." and the head's own remedy,
  #   "Edit master data", once more; the disclosure is "Name with the
  #   characters made visible".
  test "a security name with invisible characters is marked where it is edited", %{conn: conn} do
    security = create_security!(name: "Meridian Global Equity ETF", ticker: "MGEQ")

    rename!(Portfolixir.Catalog.Security, security.id,
      name: "Meridian Global" <> zwsp() <> " Equity ETF"
    )

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    note = note_in(view, "#security-detail-pane")
    assert note =~ "The name contains 1 invisible character."
    assert note =~ "Typed in anew, it is clean."
    assert note =~ "Name with the characters made visible"
    assert note =~ "Meridian Global[U+200B] Equity ETF"

    assert has_element?(
             view,
             "#security-detail-pane [data-role='invisible-text-note'] button[phx-value-action='edit']",
             "Edit master data"
           )

    # The board's German words.
    conn = Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")
    {:ok, view, _html} = live(conn, "/securities/#{security.id}")
    note = note_in(view, "#security-detail-pane")
    assert note =~ "Der Name enthält 1 unsichtbares Zeichen."
    assert note =~ "Neu eingegeben ist er sauber."
    assert note =~ "Stammdaten bearbeiten"
    assert note =~ "Name mit sichtbar gemachten Zeichen"
  end

  # Acceptance criteria:
  # - Editing a booking whose notes carry invisible characters shows the
  #   note above "Costs and note", and that disclosure stands open.
  test "a booking's notes with invisible characters are marked in the drawer", %{conn: conn} do
    world = base_world(name: "Invisible notes")
    tx = deposit!(world, "100", Date.add(today(), -3))
    rename!(Portfolixir.Ledger.Transaction, tx.id, notes: "Bonus" <> zwsp())

    {:ok, view, _html} = live(conn, "/transactions")
    view |> element("#tx-kebab-#{tx.id}") |> render_click()
    view |> element("#tx-edit-#{tx.id}") |> render_click()

    note = note_in(view, "#booking-drawer")
    assert note =~ "The text contains 1 invisible character."
    assert note =~ "Bonus[U+200B]"
    assert has_element?(view, "#booking-drawer details#transaction-costs[open]")
  end

  # Acceptance criteria:
  # - The rule dialog marks a stored rule name and the note of the version in
  #   force that carry invisible characters, each with its own note.
  test "a policy rule's name and note with invisible characters are marked in its dialog",
       %{conn: conn} do
    world = base_world(name: "Invisible rules")

    rule =
      legacy!(fn ->
        rule = Repo.insert!(%PolicyRule{portfolio_id: world.portfolio.id, name: "Cash" <> zwsp()})

        Repo.insert!(%PolicyRuleVersion{
          policy_rule_id: rule.id,
          subject_type: :cash,
          measure: :weight,
          kind: :floor,
          threshold: Decimal.new(5),
          severity: :warn,
          note: "floor" <> zwsp() <> zwsp(),
          valid_from: today(),
          author: :operator
        })

        rule
      end)

    {:ok, view, _html} = live(conn, "/risk")
    view |> element("#policy-findings button[phx-value-id='#{rule.id}']") |> render_click()

    dialog = view |> element("dialog#policy-rule-dialog") |> render()
    assert dialog =~ "The name contains 1 invisible character."
    assert dialog =~ "Cash[U+200B]"
    assert dialog =~ "The text contains 2 invisible characters."
    assert dialog =~ "floor[U+200B][U+200B]"
  end

  # User story (E25 S7, G20; pick G12.2 = B, "Why B"):
  # As the operator reading a sentence that carries a stored name or reason,
  # I want the stored text isolated from the words around it,
  # so that a direction control a legacy row still carries reorders at most
  # the stored text itself, never the sentence.
  #
  # Acceptance criteria:
  # - The subject of a rule's words line (a security's, a category's or a
  #   view's stored name) renders inside <bdi>; the rest of the line does not.
  # - A retraction's reason in the thesis card renders inside <bdi>.
  test "stored text inside running text is isolated in bdi", %{conn: conn} do
    world = base_world(name: "Isolated text")
    security = create_security!(name: "Nordic Timber Holdings AB", ticker: "NTH")

    {:ok, rule} =
      PolicyRules.create_rule(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "Single name",
        version: %{
          subject_type: "security",
          security_id: security.id,
          measure: "weight",
          kind: "cap",
          threshold: "10",
          severity: "hard"
        }
      })

    {:ok, view, _html} = live(conn, "/risk")

    words =
      view
      |> element("#policy-findings tr[data-rule-id='#{rule.id}'] .policy-rule__words")
      |> render()

    assert words =~ "Weight · <bdi>Nordic Timber Holdings AB</bdi> · Cap · Hard"

    {:ok, thesis} =
      Knowledge.append_note(Actor.owner_ui(), %{
        security_id: security.id,
        author: "operator",
        kind: "thesis",
        body: "Timber prices recover.",
        source_quality: "primary",
        as_of: Date.to_iso8601(today())
      })

    {:ok, _retraction} =
      Knowledge.append_note(Actor.owner_ui(), %{
        security_id: security.id,
        author: "operator",
        kind: "retraction",
        supersedes_id: thesis.id,
        body: "Prices kept falling.",
        source_quality: "primary",
        as_of: Date.to_iso8601(today())
      })

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=research")
    assert view |> element("#thesis-retracted") |> render() =~ "<bdi>Prices kept falling.</bdi>"
  end

  # Acceptance criteria:
  # - A view's and a bucket's name, and a category's name, are marked in
  #   their inline rename forms.
  test "view, bucket and category names are marked where they are renamed", %{conn: conn} do
    {:ok, view_record} = Buckets.create_view(Actor.owner_ui(), %{name: "Retirement"})
    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Household"})
    rename!(Portfolixir.Buckets.View, view_record.id, name: "Retire" <> zwsp() <> "ment")
    rename!(Portfolixir.Buckets.Bucket, bucket.id, name: "House" <> zwsp() <> "hold")

    {:ok, page, _html} = live(conn, "/buckets")

    page |> element("#view-kebab-#{view_record.id}") |> render_click()

    page
    |> element("#view-row-menu-#{view_record.id} button[phx-click='edit_view']")
    |> render_click()

    assert note_in(page, "#view-#{view_record.id}") =~ "Retire[U+200B]ment"

    page |> element("#bucket-kebab-#{bucket.id}") |> render_click()

    page
    |> element("#bucket-row-menu-#{bucket.id} button[phx-click='edit_bucket']")
    |> render_click()

    assert note_in(page, "#bucket-#{bucket.id}") =~ "House[U+200B]hold"

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Themes"})

    {:ok, category} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Energy"
      })

    rename!(Portfolixir.Classifications.Category, category.id, name: "Ener" <> zwsp() <> "gy")

    {:ok, page, _html} = live(conn, "/classifications/#{classification.id}")

    page
    |> element("button[phx-click='edit_category'][phx-value-id='#{category.id}']")
    |> render_click()

    assert page |> element("[data-role='invisible-text-note']") |> render() =~ "Ener[U+200B]gy"
  end
end
