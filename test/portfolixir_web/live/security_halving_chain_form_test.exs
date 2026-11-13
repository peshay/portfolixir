defmodule PortfolixirWeb.SecurityHalvingChainFormTest do
  # ADR-0059 §4, §8, §11 and ADR-0060 §1 (Sprint 29 H8, FR-58; board
  # ux-design-2026-11-12-sprint29/07 ①, ②, ③, D-6 Q1 to Q5): the
  # „Halving-Kette“ choice in „Wertpapier bearbeiten“ with its help, the
  # count of confirmed halvings the view needs, the chain's health line and
  # a refused own URL's reason; the question before halving events are
  # deleted, inside the dialog; and „Jetzt lesen“, the on-demand read, in
  # the cycle bar and in the form, with its ten-minute wait.
  #
  # Every coin, name, height and close is synthetic; the chain source is a
  # fake Esplora host (`Portfolixir.EsploraFixtures`), never the network.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.CycleFixtures
  import Portfolixir.EsploraFixtures, only: [serve: 1]
  import Portfolixir.WorldFixtures, only: [create_security!: 1]
  import PortfolixirWeb.PreferenceCookieHelpers, only: [put_preference_cookie: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Chains.Esplora
  alias Portfolixir.Knowledge.Events
  alias PortfolixirWeb.Format

  @form "#security-dialog-form"
  @select "#security-dialog-form select[name='security[halving_chain]']"

  defp open_edit(conn, security, path \\ nil) do
    {:ok, view, _html} = live(conn, path || "/securities/#{security.id}")
    view |> element("#detail-edit") |> render_click()
    assert has_element?(view, @form)
    view
  end

  defp choose(view, chain) do
    view |> form(@form, security: %{halving_chain: chain}) |> render_change()
    view
  end

  defp api_security(security) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get("/api/v1/securities/#{security.id}")
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp api_bitcoin do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get("/api/v1/chains")
    |> json_response(200)
    |> Map.fetch!("data")
    |> Enum.find(&(&1["chain"] == "bitcoin"))
  end

  defp bind!(security, chain) do
    {:ok, bound} =
      Catalog.update_security(Actor.api_token_rw("synthetic-agent"), security, %{
        halving_chain: chain
      })

    bound
  end

  defp option_texts(view) do
    view
    |> render()
    |> LazyHTML.from_document()
    |> LazyHTML.query(@select <> " option")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  # User story (ADR-0059 §4, §11; ADR-0060 §1; board 07 ①, Q1, Q3 A):
  # As the operator editing a security's master data,
  # I want a „Halving-Kette“ choice below the master data that says where
  # the halvings come from and how many confirmed ones the view still
  # needs,
  # so that I bind a coin myself and see why its chart has no „Zyklen“.
  #
  # Acceptance criteria:
  # - The choice offers none, Bitcoin, Bitcoin Cash and Litecoin; the
  #   stored binding is selected.
  # - Litecoin, a chain without a source, says the halvings are entered by
  #   hand and checked against its 840,000 blocks, and with one confirmed
  #   halving „1 of 2 confirmed halvings · cycles appear in the chart from
  #   the second“; the chart shows no toggle.
  # - Binding an unbound security to Bitcoin asks nothing, saves with
  #   „Save changes“, and the API answers the binding.
  # - A value the registry does not hold, pushed, is refused on the field
  #   and stores nothing.
  test "the choice says where the halvings come from and why the chart has no toggle",
       %{conn: conn} do
    one = synthetic_cycle_coin!(name: "One Halving Coin", halvings: 1)
    view = open_edit(conn, one)

    assert option_texts(view) == ["None", "Bitcoin", "Bitcoin Cash", "Litecoin"]
    assert has_element?(view, @select <> " option[value='litecoin'][selected]")

    assert has_element?(
             view,
             "[data-role='halving-chain-help']",
             "For Litecoin the app reads no chain"
           )

    assert has_element?(view, "[data-role='halving-chain-help']", "840,000 blocks")

    # The closing act (known from the build, H9): the screen has no event
    # form, so the halvings of a chain without a source come through the API.
    assert has_element?(
             view,
             "[data-role='halving-chain-help']",
             "halvings are written through the API as events of kind halving"
           )

    refute has_element?(view, "[data-role='halving-chain-help']", "entered by hand")

    assert has_element?(
             view,
             "[data-role='halving-chain-count']",
             "1 of 2 confirmed halvings · cycles appear in the chart from the second"
           )

    refute has_element?(view, "[data-role='halving-delete-warning']")
    {:ok, chart, _html} = live(conn, "/securities/#{one.id}?tab=chart")
    refute has_element?(chart, "#toggle-cycles")

    plain = create_security!(name: "Plain Synthetic Coin")
    view = open_edit(conn, plain)
    assert has_element?(view, @select <> " option[value=''][selected]", "None")
    refute has_element?(view, "[data-role='halving-chain-help']")

    choose(view, "bitcoin")
    assert has_element?(view, "[data-role='halving-chain-help']", "come from the Bitcoin chain")
    refute has_element?(view, "[data-role='halving-delete-warning']")
    assert has_element?(view, "#{@form} button[type='submit']", "Save changes")

    view |> form(@form) |> render_submit()
    refute has_element?(view, @form)
    assert api_security(plain)["halving_chain"] == "bitcoin"

    view = open_edit(conn, plain)

    view
    |> element(@form)
    |> render_submit(%{"security" => %{"name" => plain.name, "halving_chain" => "zcash"}})

    assert has_element?(view, "#{@form} .field-error", "is not a registered chain")
    assert api_security(plain)["halving_chain"] == "bitcoin"
  end

  # User story (ADR-0059 §4; board 07 ②, Q2 A):
  # As the operator unbinding or rebinding a coin,
  # I want the dialog to say which halving events the save deletes, and its
  # save button to name the count,
  # so that one click confirms it and nothing opens on top of the dialog.
  #
  # Acceptance criteria:
  # - Choosing none on a coin with five halving events shows the warning
  #   „Without a halving chain, 5 halving events are deleted“, the four
  #   confirmed ones by year and the one estimate by its block and date,
  #   and that the journal keeps every row; the button reads „Save and
  #   delete 5 events“.
  # - Choosing another chain names that chain; choosing the stored one
  #   again takes the warning away.
  # - The save goes through: the events are gone, the API answers no
  #   binding, the page's note counts the deleted events, and the chart has
  #   no toggle.
  test "the dialog asks before the halving events go, and the save names the count",
       %{conn: conn} do
    coin = synthetic_cycle_coin!()
    assert Events.count_halvings(coin.id) == 5
    view = open_edit(conn, coin)

    choose(view, "")
    warning = "[data-role='halving-delete-warning']"
    assert has_element?(view, warning, "Without a halving chain, 5 halving events are deleted")
    assert has_element?(view, warning, "4 confirmed halvings (2013, 2015, 2017, 2019)")

    assert has_element?(
             view,
             warning,
             "1 estimate (block 4,200,000, #{Format.date(~D[2021-01-05])})"
           )

    assert has_element?(view, warning, "The journal keeps every deleted row.")
    assert has_element?(view, "#{@form} button[type='submit']", "Save and delete 5 events")

    choose(view, "bitcoin")
    assert has_element?(view, warning, "Bound to Bitcoin, 5 halving events are deleted")
    assert has_element?(view, "#{@form} button[type='submit']", "Save and delete 5 events")

    choose(view, "litecoin")
    refute has_element?(view, warning)
    assert has_element?(view, "#{@form} button[type='submit']", "Save changes")

    choose(view, "")
    view |> form(@form) |> render_submit()

    assert Events.count_halvings(coin.id) == 0
    assert api_security(coin)["halving_chain"] == nil
    assert render(view) =~ "5 halving events deleted"

    {:ok, chart, _html} = live(conn, "/securities/#{coin.id}?tab=chart")
    refute has_element?(chart, "#toggle-cycles")

    german =
      conn
      |> put_preference_cookie("portfolixir_locale", "de")
      |> open_edit(synthetic_cycle_coin!(name: "German Cycle Coin"))

    choose(german, "")

    assert has_element?(
             german,
             warning,
             "Ohne Halving-Kette werden 5 Halving-Ereignisse gelöscht"
           )

    assert has_element?(
             german,
             "#{@form} button[type='submit']",
             "Speichern und 5 Ereignisse löschen"
           )
  end

  # User story (ADR-0059 §8, §11; board 07 ①, Q4 A):
  # As the operator whose coin is bound to a chain with a source,
  # I want the chain's health line in the form, a refused own URL with its
  # reason, and what the own URL has to be,
  # so that a coin whose source is refused from the start, and which so
  # never has a halving, a view or a cycle bar, still shows why.
  #
  # Acceptance criteria:
  # - A coin bound to Bitcoin shows „Chain source: mempool.space · read 2 h
  #   ago“ and its confirmed halvings with the next one's window.
  # - A freshly bound coin, its own URL refused as a private address, shows
  #   „Own chain source refused: node.home.arpa resolves to a private
  #   address“, that no halvings are written, and that the URL must be
  #   public https and is read at start, never written by the app; its
  #   chart has no toggle.
  test "the form carries the chain's health line and a refused own URL's reason",
       %{conn: conn} do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    two_hours_ago = DateTime.add(now, -2 * 3600)

    chain_state!(:bitcoin, %{
      source_host: "mempool.space",
      last_tried_at: two_hours_ago,
      last_ok_at: two_hours_ago
    })

    coin = synthetic_cycle_coin!(name: "Synthetic Chain Coin", chain: :bitcoin)
    view = open_edit(conn, coin)

    assert has_element?(
             view,
             "#{@form} [data-role='cycle-health'][data-status='current']",
             "Chain source: mempool.space · read 2 h ago"
           )

    assert has_element?(
             view,
             "[data-role='halving-chain-count']",
             "4 confirmed halvings, the next ≈ #{Format.date(~D[2021-01-05])}"
           )

    Portfolixir.Repo.delete_all(Portfolixir.Chains.ChainRead)
    saved = Application.get_env(:portfolixir, Esplora)
    on_exit(fn -> Application.put_env(:portfolixir, Esplora, saved) end)

    Application.put_env(
      :portfolixir,
      Esplora,
      Keyword.put(saved, :own_url, "https://node.home.arpa/api")
    )

    chain_state!(:bitcoin, %{
      last_tried_at: DateTime.add(now, -600),
      last_error: "node.home.arpa: url_not_allowed:private_address",
      inserted_at: DateTime.add(now, -3600)
    })

    fresh = "Fresh Chain Coin" |> then(&create_security!(name: &1)) |> bind!(:bitcoin)
    view = open_edit(conn, fresh)

    assert has_element?(
             view,
             "#{@form} [data-role='cycle-health'][data-status='refused']",
             "Own chain source refused: node.home.arpa resolves to a private address"
           )

    assert has_element?(view, "[data-role='halving-chain-refused']", "No halvings are written.")

    assert has_element?(
             view,
             "[data-role='halving-chain-refused']",
             "PORTFOLIXIR_BITCOIN_ESPLORA_URL"
           )

    assert has_element?(view, "[data-role='halving-chain-refused']", "public address")

    assert has_element?(
             view,
             "[data-role='halving-chain-count']",
             "0 of 2 confirmed halvings"
           )

    {:ok, chart, _html} = live(conn, "/securities/#{fresh.id}?tab=chart")
    refute has_element?(chart, "#toggle-cycles")
  end

  # User story (ADR-0059 §11; board 07 ③, Q5):
  # As the operator who bound a coin or wonders whether the source is alive,
  # I want „Jetzt lesen“ beside the health line, in the cycle bar and in
  # the form,
  # so that the on-demand read is not the agent's alone, and I see the
  # ten-minute wait instead of a refusal.
  #
  # Acceptance criteria:
  # - In the form of a freshly bound coin, „Read now“ reads the chain once:
  #   the health line says the source answered, the count reads the four
  #   confirmed halvings it wrote, and the button waits „again in 10 min“,
  #   as GET /api/v1/chains answers (`refresh.available_at` ten minutes
  #   after `last_tried_at`).
  # - A second read pushed while it waits asks no host and keeps the wait.
  # - In the cycle bar the button waits as well, with the minutes left.
  # - A chain without a source has no button.
  # User story (UAT S3 #5, the closing act):
  # As the operator reading the next halving's estimate,
  # I want a window whose two ends fall on one day shown as that day,
  # so that the form does not read „21.12.2028 – 21.12.2028“.
  #
  # Acceptance criteria:
  # - A next halving stored as a window of one day reads „the next ≈
  #   ‹day›“ in the form, with no range; on the chart its label reads
  #   „Halving ≈ ‹day› (estimate)“. The stored event stays a window.
  test "a one-day halving window reads as its day in the form and on the chart",
       %{conn: conn} do
    coin =
      synthetic_cycle_coin!(
        name: "Synthetic One Day Coin",
        chain: :bitcoin,
        shift_days: recent_shift(Portfolixir.Clock.today()),
        next_window_days: 0
      )

    [next] =
      for e <- Events.list_for_security(coin.id),
          e.kind == :halving and not e.confirmed,
          do: e

    assert {next.timing, next.date_end} == {:window, next.date}
    day = Format.date(next.date)

    view = open_edit(conn, coin)
    count = view |> element("[data-role='halving-chain-count']") |> render()
    assert count =~ "the next ≈ #{day}"
    refute count =~ "#{day} – #{day}"

    {:ok, chart, _html} = live(conn, "/securities/#{coin.id}?tab=chart")
    chart |> element("#toggle-cycles") |> render_click()
    chart |> element("button[phx-value-range='CYCLE']") |> render_click()

    assert chart
           |> element("text.cycle-label--halving.is-estimate")
           |> render() =~ "Halving ≈ #{day} (estimate)"
  end

  test "„Jetzt lesen“ reads the chain once and shows the ten-minute wait", %{conn: conn} do
    fresh = "Fresh Chain Coin" |> then(&create_security!(name: &1)) |> bind!(:bitcoin)
    serve(%{"mempool.space" => {:chain, 870_000}})

    view = open_edit(conn, fresh)
    assert has_element?(view, "#{@form} [data-role='cycle-health'][data-status='never_read']")

    assert has_element?(
             view,
             "#{@form} button[data-role='chain-read-now']:not([disabled])",
             "Read now"
           )

    view |> element("#{@form} button[data-role='chain-read-now']") |> render_click()
    render_async(view)

    assert_received {:esplora, "mempool.space", _path}
    flush()

    assert has_element?(
             view,
             "#{@form} [data-role='cycle-health'][data-status='current']",
             "Chain source: mempool.space · read 0 min ago"
           )

    assert has_element?(view, "[data-role='halving-chain-count']", "4 confirmed halvings")
    assert has_element?(view, "#{@form} button[data-role='chain-read-now'][disabled]")
    assert has_element?(view, "#{@form} [data-role='chain-read-wait']", "again in 10 min")

    bitcoin = api_bitcoin()
    tried = bitcoin["health"]["last_tried_at"] |> DateTime.from_iso8601() |> elem(1)

    assert bitcoin["refresh"]["available_at"] ==
             tried |> DateTime.add(600) |> DateTime.to_iso8601()

    view |> with_target("#security-form-dialog") |> render_click("read_chain_now", %{})
    render_async(view)
    refute_received {:esplora, _host, _path}
    assert has_element?(view, "#{@form} [data-role='chain-read-wait']", "again in 10 min")

    coin = synthetic_cycle_coin!(name: "Synthetic Chain Coin", chain: :bitcoin)
    {:ok, chart, _html} = live(conn, "/securities/#{coin.id}?tab=chart&cycles=1")

    assert has_element?(
             chart,
             "[data-role='cycle-bar'] button[data-role='chain-read-now'][disabled]"
           )

    assert has_element?(
             chart,
             "[data-role='cycle-bar'] [data-role='chain-read-wait']",
             "again in"
           )

    litecoin = synthetic_cycle_coin!(name: "Hand Cycle Coin")
    {:ok, chart, _html} = live(conn, "/securities/#{litecoin.id}?tab=chart&cycles=1")
    assert has_element?(chart, "[data-role='cycle-bar']")
    refute has_element?(chart, "button[data-role='chain-read-now']")
  end

  # User story (ADR-0059 §11; board 07 ③, Q5):
  # As the operator in the cycle bar,
  # I want „Jetzt lesen“ to read the chain and show the result in the
  # health line.
  #
  # Acceptance criteria:
  # - With no read for ten minutes the bar's button reads the chain; the
  #   health line then names the host that answered and the button waits.
  # - Both sources failing: the health line says the last attempt failed.
  test "the cycle bar's „Jetzt lesen“ shows the result in the health line", %{conn: conn} do
    long_ago = DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -3 * 3600)

    chain_state!(:bitcoin, %{
      source_host: "mempool.space",
      last_tried_at: long_ago,
      last_ok_at: long_ago
    })

    coin = synthetic_cycle_coin!(name: "Synthetic Chain Coin", chain: :bitcoin)
    {:ok, chart, _html} = live(conn, "/securities/#{coin.id}?tab=chart&cycles=1")
    assert has_element?(chart, "[data-role='cycle-health']", "read 3 h ago")

    serve(%{"mempool.space" => {:status, 503}, "blockstream.info" => {:chain, 870_000}})

    chart
    |> element("[data-role='cycle-bar'] button[data-role='chain-read-now']")
    |> render_click()

    render_async(chart)

    assert has_element?(
             chart,
             "[data-role='cycle-health'][data-status='current']",
             "Chain source: blockstream.info (fallback) · read 0 min ago"
           )

    assert has_element?(
             chart,
             "[data-role='cycle-bar'] [data-role='chain-read-wait']",
             "again in 10 min"
           )

    assert has_element?(chart, "button[phx-value-range='CYCLE'].is-active")
  end

  defp flush do
    receive do
      {:esplora, _host, _path} -> flush()
    after
      0 -> :ok
    end
  end
end
