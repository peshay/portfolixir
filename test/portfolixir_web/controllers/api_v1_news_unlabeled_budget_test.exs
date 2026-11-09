defmodule PortfolixirWeb.ApiV1NewsUnlabeledBudgetTest do
  # ADR-0056 §7, §9 and the amendment of 2026-11-08, C5 (Sprint 28, N1;
  # plan D-8, carry-forward 4): the labeller's read holds its budget on the
  # text the companion returns, where every invisible character is spelled
  # `[U+XXXX]` (ADR-0054 §4), from the commit that adds it.
  #
  # The answer is also written, with ids and times normalized, to
  # mcp-server/test/fixtures/news-budget/unlabeled-worst-case.json, and the
  # companion's test (news-labels.test.ts) runs it through `callTool` and
  # counts what the tool returns; this test fails when the fixture no longer
  # matches what the server answers. Regenerate it with
  # PORTFOLIXIR_WRITE_NEWS_BUDGET=1. Synthetic names and hosts only.
  use PortfolixirWeb.ConnCase

  import Portfolixir.NewsFixtures, only: [feed!: 1]
  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Isin
  alias Portfolixir.Input.Text
  alias Portfolixir.Knowledge
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Parser.Item, as: Parsed

  @agent_token String.duplicate("l", 40)
  @fixture Path.expand(
             "../../../mcp-server/test/fixtures/news-budget/unlabeled-worst-case.json",
             __DIR__
           )

  # The budget (stated in the plan's N1 row as a test on the companion's
  # text): at the default limit of 10 stories, over a 40-security universe,
  # every row and thesis at its widest, at most 6,000 tokens — about 600 a
  # story with its thesis, the universe once.
  @budget 6_000

  setup %{conn: conn} do
    previous = Application.get_env(:portfolixir, :api_tokens)
    Application.put_env(:portfolixir, :api_tokens, [{"labeller", @agent_token}])
    on_exit(fn -> Application.put_env(:portfolixir, :api_tokens, previous) end)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer " <> @agent_token)

    %{conn: conn}
  end

  @tag_a <<0xE0041::utf8>>

  # N1 attack AT1: a name of one letter and 254 combining marks, one
  # grapheme and 255 characters on the wire, is cut like any other.
  @hostile_name "H" <> String.duplicate("\u0301", 254)

  defp tag_title(n), do: String.pad_trailing("Profit warning #{n} ", 160, @tag_a)
  defp tag_excerpt, do: String.pad_trailing("Excerpt ", 600, @tag_a)

  # A host of 253 characters, the most a name holds.
  defp long_host(n) do
    label = String.duplicate("n", 63)
    Enum.join([label, label, label, String.pad_trailing("m#{n}", 53, "m"), "example"], ".")
  end

  defp isin(n) do
    body = "XS" <> String.pad_leading(Integer.to_string(n), 9, "0")
    Enum.find_value(0..9, &(Isin.valid?(body <> "#{&1}") && body <> "#{&1}"))
  end

  # Eight clauses of 200 double quotes, each two characters in JSON: the
  # widest a clause can be on the wire, since a research note refuses
  # invisible characters.
  defp wide_condition, do: Enum.map_join(1..8, ";\n", fn _n -> String.duplicate(~s("), 200) end)

  defp tokens(%Plug.Conn{resp_body: body}),
    do: (body |> Text.escape_invisible() |> String.length()) / 4

  # Normalized so the fixture does not change with ids and the clock, and
  # written in ASCII (every character beyond it a JSON \u escape), so the
  # file holds no raw invisible character.
  defp normalize(body) do
    body
    |> String.replace(~r/\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?Z/, "2026-11-09T09:00:00Z")
    |> String.replace(~r/"(\w*id)":\d+/, ~s("\\1":1))
    |> Jason.decode!()
    |> Jason.encode!(pretty: true, escape: :unicode_safe)
  end

  defp fixture!(%Plug.Conn{resp_body: body}) do
    normalized = normalize(body) <> "\n"

    if System.get_env("PORTFOLIXIR_WRITE_NEWS_BUDGET") == "1" do
      File.mkdir_p!(Path.dirname(@fixture))
      File.write!(@fixture, normalized)
    else
      assert File.read!(@fixture) == normalized,
             "#{@fixture} no longer matches the server's answer: regenerate it with " <>
               "PORTFOLIXIR_WRITE_NEWS_BUDGET=1 and rerun the companion's test"
    end
  end

  # User story (ADR-0056 §7, §9; the amendment of 2026-11-08, C5; plan D-8,
  # carry-forward 4):
  # As the operator whose labeller pays for every token it reads,
  # I want news.unlabeled to hold its budget on the text the companion
  # hands the labeller, whatever invisible characters a feed put in its
  # titles and excerpts, however long its domains, and however wide a
  # thesis's clauses,
  # so that a hostile feed or a long thesis cannot make one batch cost ten
  # times its budget.
  #
  # Acceptance criteria (characters / 4 of the answer with every invisible
  # character spelled [U+XXXX], counted in code points):
  # - at the default limit of 10 (one more story stored, so truncated),
  #   over a universe of 40 held securities with ISINs, each story's title
  #   160 tag characters, its excerpt 600 and its domain 253 characters,
  #   and each story's security with an intact thesis of eight clauses of
  #   200 double quotes: at most 6,000 tokens; the domain cut to 40, at
  #   most six clauses listed with `more`, each cut; one security named
  #   by one letter and 254 combining marks, cut to 20 like every name;
  # - the answer is the fixture the companion's test measures.
  test "news.unlabeled holds its budget with invisible characters spelled", %{conn: conn} do
    world = base_world(name: "Budget", cash_name: "Cash", depot_name: "Depot")
    now = DateTime.utc_now()

    securities =
      for n <- 1..40 do
        security =
          create_security!(
            name: if(n == 1, do: @hostile_name, else: "Holding #{n} Synthetic Group AG"),
            ticker: nil,
            asset_class: "equity",
            isin: isin(n)
          )

        buy!(world, security, quantity: "1", price: "10")
        security
      end

    securities
    |> Enum.take(11)
    |> Enum.with_index(1)
    |> Enum.each(fn {security, n} ->
      {:ok, _thesis} =
        Knowledge.append_note(Actor.owner_ui(), %{
          security_id: security.id,
          author: :operator,
          kind: :thesis,
          body: "Synthetic thesis",
          source_quality: :primary,
          as_of: Date.utc_today(),
          invalidation_condition: wide_condition()
        })

      {:ok, %{stored: 1}} =
        Ingest.ingest(
          feed!(%{class: "issuer", security_id: security.id}),
          [
            %Parsed{
              title: tag_title(n),
              link: "https://#{long_host(n)}/r/#{n}",
              excerpt: tag_excerpt()
            }
          ],
          DateTime.add(now, -n, :second)
        )
    end)

    answer = get(conn, "/api/v1/news/unlabeled?prompt_version=v1")
    data = json_response(answer, 200)["data"]

    assert {length(data["rows"]), data["truncated"]} == {10, true}
    assert length(data["universe"]) == 40

    names = Enum.map(data["universe"], & &1["name"])
    assert Enum.any?(names, &String.starts_with?(&1, "H\u0301"))
    assert Enum.all?(names, &(length(String.codepoints(&1)) <= 20)), inspect(names)
    assert length(data["theses"]) == 10

    for row <- data["rows"] do
      assert String.length(row["domain"]) == 40 and String.ends_with?(row["domain"], "…")
    end

    for thesis <- data["theses"] do
      assert length(thesis["clauses"]) == 6 and thesis["more"] == 2
    end

    assert tokens(answer) <= @budget, "news.unlabeled: #{tokens(answer)} tokens"
    fixture!(answer)
  end
end
