defmodule PortfolixirWeb.JournalPrivacyLiveTest do
  # The audit journal in the privacy mode (Sprint 26 P1, I22, FR-51; plan
  # D-4, D-5; closing-act finding S2): the page's change lines and its fold
  # „Gespeicherte Werte“ show every stored amount, price and quantity as the
  # bar while the mode is on, and keep the ids, dates, kinds, text and
  # ratios. Every name and figure is synthetic.
  use PortfolixirWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Journal.Entry
  alias Portfolixir.Ledger
  alias Portfolixir.Predictions
  alias Portfolixir.Repo
  alias PortfolixirWeb.Journal.Change
  alias PortfolixirWeb.PreferenceCookieHelpers

  # The stored figures the world books; none may reach the page in the mode.
  @figures ["123.45", "124.5", "17.5", "4.95", "1234.56"]

  setup do
    world = base_world(name: "Masked Journal", cash_name: "Masked Cash", depot_name: "MJ Depot")
    deposit!(world, "1234.56", ~D[2026-01-02])
    security = create_security!(name: "Synthetic Journal Fund", ticker: "SJF")

    buy =
      buy!(world, security, quantity: "17.5", price: "123.45", fees: "4.95", date: ~D[2026-01-05])

    {:ok, _changed} = Ledger.update_transaction(Actor.owner_ui(), buy, %{price: "124.5"})

    {:ok, _prediction} =
      Predictions.create_prediction(Actor.owner_ui(), %{
        "security_id" => security.id,
        "direction" => "outperform",
        "probability" => "0.70",
        "benchmark" => "rate:0",
        "resolves_on" => Date.to_iso8601(Date.add(Portfolixir.Clock.today(), 60))
      })

    %{buy: buy}
  end

  defp masked(conn) do
    conn
    |> PreferenceCookieHelpers.put_preference_cookie("portfolixir_privacy", "on")
    |> PreferenceCookieHelpers.put_preference_cookie("portfolixir_locale", "de")
  end

  # User story (P1, the closing act's finding on /journal):
  # As the operator who switched the privacy mode on before sharing my
  # screen,
  # I want the audit journal to hide every stored amount, price and
  # quantity as the bar, in its change lines and in „Gespeicherte Werte“,
  # so that opening the journal shows no figure the rest of the app hides.
  #
  # Acceptance criteria:
  # - With the mode on, a buy's price, quantity and fees and a deposit's
  #   amount appear nowhere in the page's HTML, neither on the first render
  #   nor on the connected one; the bar stands in their place and no
  #   „••••“ is drawn as text.
  # - An update's change line „price: … → …“ keeps its field name and
  #   draws both values as the bar.
  # - Ids, dates, kinds and ratios stay: the booking's date, the type
  #   „buy“ and a prediction's probability 0.70 read as stored.
  # - With the mode off, the stored values read as stored.
  test "the journal hides stored amounts, prices and quantities in the privacy mode", %{
    conn: conn,
    buy: buy
  } do
    static = conn |> masked() |> get("/journal") |> html_response(200)
    {:ok, view, _html} = conn |> masked() |> live("/journal")
    connected = render(view)

    for html <- [static, connected], figure <- @figures do
      refute html =~ figure, "the journal shows #{figure} with the privacy mode on"
    end

    for html <- [static, connected] do
      main = html |> Floki.parse_document!() |> Floki.find("main") |> Floki.raw_html()
      assert main =~ ~r/class="?pf-mask/
      # The page's own text; the layout's script names the stand-in text.
      refute main =~ "••••"
      assert html =~ "2026-01-05"
      assert html =~ ">buy<"
      assert html =~ "0.70"
    end

    update_id =
      Repo.one!(
        from(e in Entry,
          where:
            e.resource_type == "transaction" and e.resource_id == ^to_string(buy.id) and
              e.operation == :update,
          select: e.id
        )
      )

    line = view |> element("#journal-entry-#{update_id} .journal-change__line") |> render()
    assert line =~ "price"
    assert length(Regex.scan(~r/class="?pf-mask/, line)) == 2

    {:ok, plain, _html} = live(conn, "/journal")
    plain_html = render(plain)

    for figure <- @figures do
      assert plain_html =~ figure, "the journal hides #{figure} with the privacy mode off"
    end
  end

  # User story (P1): as the operator reading a quote write in the journal
  # with the privacy mode on, I want the closes inside its stored list
  # hidden as well, so that no price reaches the page inside a JSON value.
  #
  # Acceptance criteria:
  # - A list of quote rows reads as its JSON with each close as the bar;
  #   its dates and its source stay; with the mode off it reads as stored.
  test "a hidden field inside a stored list or map is the bar" do
    entry = %Entry{
      operation: :upsert,
      before: nil,
      after: %{
        "security_id" => 5,
        "quotes" => [%{"date" => "2026-01-02", "close" => "88.12", "source" => "manual"}]
      }
    }

    PortfolixirWeb.PrivacyMode.put(true)
    on_exit(fn -> PortfolixirWeb.PrivacyMode.put(false) end)

    %{values: values} = Change.build(entry)
    {"quotes", "—", quotes} = List.keyfind(values, "quotes", 0)
    html = Phoenix.HTML.safe_to_string(quotes)

    refute html =~ "88.12"
    refute html =~ "••••"
    assert html =~ "pf-mask"
    assert html =~ "2026-01-02"
    assert html =~ "manual"
    assert {"security_id", "—", "5"} in values

    PortfolixirWeb.PrivacyMode.put(false)
    %{values: plain} = Change.build(entry)
    {"quotes", "—", text} = List.keyfind(plain, "quotes", 0)
    assert text =~ ~s("close":"88.12")
  end

  # User story (P1): as the owner who trusts the mode to grow with the
  # schema, I want every stored decimal field classified as hidden (an
  # amount, a price, a quantity) or shown (a ratio, a rate, a weight), so
  # that a new field cannot reach the journal unclassified.
  #
  # Acceptance criteria:
  # - Every `:decimal` field (or list of decimals) of every schema of the
  #   application is in exactly one of Change's two lists.
  test "every stored decimal field is classified as hidden or shown" do
    {:ok, modules} = :application.get_key(:portfolixir, :modules)

    fields =
      for module <- modules,
          Code.ensure_loaded?(module),
          function_exported?(module, :__schema__, 1),
          field <- module.__schema__(:fields),
          module.__schema__(:type, field) in [:decimal, {:array, :decimal}],
          uniq: true,
          do: Atom.to_string(field)

    assert fields != []
    hidden = Change.hidden_fields()
    shown = Change.shown_fields()

    unclassified = Enum.reject(fields, &(&1 in hidden or &1 in shown))
    assert unclassified == [], "unclassified decimal fields: #{inspect(unclassified)}"
    assert MapSet.disjoint?(MapSet.new(hidden), MapSet.new(shown))
  end
end
