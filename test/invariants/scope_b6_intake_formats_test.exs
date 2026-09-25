defmodule Portfolixir.Invariants.ScopeB6IntakeFormatsTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Imports

  # NFR-9 backstop B6 (Sprint 16 Lane N, #885). The gate it backs, as
  # registered in scope_b7_gate_registry_test.exs:
  #   gate:gated.document_intake
  #
  # User story:
  # As the operator whose import takes Portfolio Performance CSV and JSON
  # exports only,
  # I want a meta-test that fails when any intake path would accept PP XML or
  # the binary `.portfolio` workspace — whatever the file is called,
  # so that FR-5's gated XML intake cannot open through a renamed file, a new
  # upload, a body parser or a decoder dependency before its ADR and the
  # AGENTS.md amendment exist.
  #
  # Acceptance criteria:
  # - The importer rejects synthetic PP XML and binary workspace bodies (zip,
  #   protobuf and encrypted signatures) under every filename, including
  #   `.csv` and `.json`: rejection is by content, not only by extension. The
  #   real CSV and JSON fixtures still parse, so the rejections are not vacuous.
  # - The Imports page refuses an `.xml` or `.portfolio` upload outright, and a
  #   workspace body smuggled in under an accepted name reaches no preview.
  # - Every LiveView upload in lib/portfolixir_web accepts only CSV and JSON.
  # - No module takes a raw multipart upload (`Plug.Upload`), the endpoint
  #   parses no XML body, and nothing in lib/ calls an XML, zip or protobuf
  #   decoder.
  # - No route, MCP tool, LiveView event or module is named for XML.
  # - Each static matcher catches a synthetic violation.

  @fixtures "test/support/fixtures/portfolio_performance"

  # Synthetic, invented content: an example client with one made-up security.
  @pp_xml """
  <?xml version="1.0" encoding="UTF-8"?>
  <client>
    <version>66</version>
    <baseCurrency>EUR</baseCurrency>
    <securities>
      <security>
        <uuid>00000000-0000-0000-0000-000000000001</uuid>
        <name>Example Equity</name>
        <currencyCode>EUR</currencyCode>
        <isin>XX0000000001</isin>
      </security>
    </securities>
  </client>
  """

  # Workspace signatures: a zipped XML workspace, the protobuf workspace, the
  # password-encrypted workspace. Each is followed by filler bytes.
  @workspaces %{
    zip: <<"PK", 3, 4, 20, 0, 0, 0, 8, 0>> <> :binary.copy(<<0x5A>>, 48),
    protobuf: <<"PPPBV1", 10, 3, "EUR", 18, 0>> <> :binary.copy(<<0x01>>, 32),
    encrypted: <<"PORTFOLIO", 1>> <> :binary.copy(<<0xA5>>, 48)
  }

  @filenames [
    nil,
    "export.xml",
    "export.portfolio",
    "export.xml.zip",
    "export.csv",
    "export.json"
  ]

  @accepted_upload ~w(.csv .json application/json text/csv text/plain)
  @allowed_parsers [:urlencoded, :multipart, :json]

  # Decoders whose presence in lib/ would be the first line of an XML or
  # workspace intake: Erlang modules with their decoding functions (`:all` for
  # the XML parsers), Elixir modules by last alias segment.
  @decoder_calls %{
    xmerl: :all,
    xmerl_scan: :all,
    xmerl_sax_parser: :all,
    xmerl_xpath: :all,
    zip: ~w(unzip extract zip_open table list_dir foldl)a,
    zlib: ~w(unzip gunzip uncompress inflate inflateInit safeInflate)a,
    erl_tar: ~w(extract open table)a
  }
  @decoder_aliases ~w(SweetXml Saxy XmlBuilder Protobuf Protox Unzip)a

  describe "the importer" do
    test "rejects PP XML and binary workspaces by content, whatever the filename" do
      bodies =
        Map.merge(@workspaces, %{
          xml: @pp_xml,
          xml_without_prolog: "<client><version>66</version></client>",
          xml_with_bom: <<0xEF, 0xBB, 0xBF>> <> @pp_xml
        })

      accepted =
        for {kind, body} <- bodies,
            filename <- @filenames,
            match?({:ok, _}, Imports.parse_portfolio_performance(body, filename: filename)),
            do: {kind, filename}

      assert accepted == [],
             "PP XML or a binary workspace was accepted (FR-5 is gated, NFR-9 B6): " <>
               inspect(accepted)
    end

    test "still parses the CSV and JSON exports it is for (positive control)" do
      for file <- ["sample.csv", "sample.json"], filename <- [file, nil] do
        body = File.read!(Path.join(@fixtures, file))

        assert {:ok, _preview} = Imports.parse_portfolio_performance(body, filename: filename),
               "#{file} (filename #{inspect(filename)}) no longer parses"
      end
    end
  end

  describe "the Imports page" do
    test "refuses an .xml or .portfolio upload outright", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/imports")

      for {name, content, type} <- [
            {"export.xml", @pp_xml, "application/xml"},
            {"export.portfolio", @workspaces.protobuf, "application/octet-stream"}
          ] do
        upload =
          file_input(view, "#pp-import-form", :pp_file, [
            %{name: name, content: content, type: type, last_modified: 1_700_000_000_000}
          ])

        assert {:error, [[_ref, :not_accepted]]} = render_upload(upload, name)
      end

      refute has_element?(view, "form#pp-import-apply")
    end

    test "a workspace smuggled in under an accepted name reaches no preview", %{conn: conn} do
      for {name, content, type} <- [
            {"export.xml", @pp_xml, "text/plain"},
            {"export.csv", @workspaces.zip, "text/csv"},
            {"export.json", @pp_xml, "application/json"}
          ] do
        {:ok, view, _html} = live(conn, "/imports")

        view
        |> file_input("#pp-import-form", :pp_file, [
          %{name: name, content: content, type: type, last_modified: 1_700_000_000_000}
        ])
        |> render_upload(name)

        assert has_element?(view, "p.alert-error[role=alert]"), "#{name} showed no refusal"
        refute has_element?(view, "form#pp-import-apply"), "#{name} reached a preview"
      end
    end
  end

  describe "the intake surface" do
    test "every LiveView upload accepts only CSV and JSON" do
      uploads = Enum.flat_map(web_sources(), &upload_accepts(File.read!(&1), &1))

      assert uploads != [], "the upload scan found no allow_upload call"

      offenders = Enum.reject(uploads, fn {_where, accept} -> csv_or_json_only?(accept) end)

      assert offenders == [],
             "Uploads accepting more than CSV/JSON (NFR-9 B6): #{inspect(offenders)}"
    end

    test "no raw multipart upload, no XML body parser, no XML or workspace decoder" do
      offenders = Enum.flat_map(lib_sources(), &intake_violations(File.read!(&1), &1))

      assert offenders == [],
             "An XML or workspace intake path (NFR-9 B6):\n" <> Enum.join(offenders, "\n")

      parsers = endpoint_parsers(File.read!("lib/portfolixir_web/endpoint.ex"))

      assert parsers != [], "the endpoint scan found no Plug.Parsers"
      assert parsers -- @allowed_parsers == [], "unexpected body parsers: #{inspect(parsers)}"
    end

    test "no route, MCP tool, LiveView event or module is named for XML" do
      routes = for r <- PortfolixirWeb.Router.__routes__(), do: "#{r.verb} #{r.path}"

      tools =
        ~r/tool\(\s*"(portfolixir\.[a-z0-9_.]+)"/
        |> Regex.scan(File.read!("mcp-server/src/tools.ts"))
        |> Enum.map(fn [_, name] -> name end)

      events =
        Enum.flat_map(web_sources(), fn path ->
          ~r/def handle_event\(\s*"([^"]+)"/
          |> Regex.scan(File.read!(path))
          |> Enum.map(fn [_, name] -> name end)
        end)

      {:ok, modules} = :application.get_key(:portfolixir, :modules)

      names = routes ++ tools ++ events ++ Enum.map(modules, &inspect/1)

      assert length(names) > 100, "the name scan found too few names"
      assert Enum.filter(names, &xml_name?/1) == []
    end
  end

  describe "the matchers (self-test: a clean tree cannot pass vacuously)" do
    test "a synthetic upload accepting XML, a workspace or anything is caught" do
      source = """
      defmodule PortfolixirWeb.SyntheticLive do
        def mount(_params, _session, socket) do
          socket
          |> allow_upload(:a, accept: ~w(.csv .xml))
          |> allow_upload(:b, accept: :any)
          |> allow_upload(:c, accept: [".portfolio"])
          |> allow_upload(:d, accept: ~w(.json))
          |> then(&{:ok, allow_upload(&1, :e, accept: ~w(application/zip))})
        end
      end
      """

      accepts = upload_accepts(source, "synthetic.ex")

      assert length(accepts) == 5

      assert accepts |> Enum.reject(&csv_or_json_only?(elem(&1, 1))) |> length() == 4
    end

    test "a synthetic multipart intake and synthetic decoders are caught" do
      source = """
      defmodule PortfolixirWeb.SyntheticUploadController do
        def create(conn, %{"file" => %Plug.Upload{path: path}}) do
          {:ok, [xml]} = :zip.unzip(File.read!(path), [:memory])
          {doc, _} = :xmerl_scan.string(String.to_charlist(elem(xml, 1)))
          SweetXml.xpath(doc, ~x"//client")
        end

        def backup(files), do: :zip.create(~c"backup.zip", files, [:memory])
      end
      """

      offenders = intake_violations(source, "synthetic.ex")

      assert length(offenders) == 4, Enum.join(offenders, "\n")
      refute Enum.any?(offenders, &(&1 =~ ":zip.create"))
    end

    test "a synthetic XML body parser is caught" do
      source = """
      defmodule PortfolixirWeb.SyntheticEndpoint do
        plug(Plug.Parsers, parsers: [:json, PortfolixirWeb.XmlParser], pass: ["*/*"])
      end
      """

      assert endpoint_parsers(source) == [:json, "PortfolixirWeb.XmlParser"]
      assert endpoint_parsers(source) -- @allowed_parsers == ["PortfolixirWeb.XmlParser"]
    end

    test "names for XML are caught, innocent neighbours are not" do
      assert xml_name?("POST /api/v1/imports/xml")
      assert xml_name?("Portfolixir.Imports.PortfolioPerformance.XmlParser")
      assert xml_name?("portfolixir.imports.parse_xml")
      refute xml_name?("Portfolixir.Fx.RateSync.Ecb")
      refute xml_name?("portfolixir.imports.preview")
    end
  end

  # --- matchers ------------------------------------------------------------

  defp csv_or_json_only?(accept) when is_list(accept),
    do: accept != [] and Enum.all?(accept, &(&1 in @accepted_upload))

  defp csv_or_json_only?(_any_or_computed), do: false

  # `[{"path:line", accept}]` for every `allow_upload/2,3` call, piped or not.
  # `accept` is the literal list, `:any`, or `:computed` when the scan cannot
  # read it (which fails: an upload's formats must be visible).
  defp upload_accepts(source, path) do
    {_ast, found} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:allow_upload, meta, args} = node, acc when is_list(args) and args != [] ->
          {node, acc ++ [{"#{path}:#{meta[:line]}", accept_of(List.last(args))}]}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp accept_of(opts) when is_list(opts) do
    case Keyword.get(opts, :accept) do
      :any -> :any
      {:sigil_w, _, [{:<<>>, _, [words]}, _modifiers]} -> String.split(words)
      list when is_list(list) -> if Enum.all?(list, &is_binary/1), do: list, else: :computed
      _other -> :computed
    end
  end

  defp accept_of(_opts), do: :computed

  defp intake_violations(source, path) do
    {_ast, found} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn node, acc -> {node, acc ++ intake_hit(node, path)} end)

    found
  end

  defp intake_hit({:__aliases__, meta, segments}, path) do
    cond do
      Enum.take(segments, -2) == [:Plug, :Upload] ->
        ["#{path}:#{meta[:line]}: Plug.Upload takes a raw multipart file"]

      List.last(segments) in @decoder_aliases ->
        ["#{path}:#{meta[:line]}: #{Enum.join(segments, ".")} decodes XML or a workspace"]

      true ->
        []
    end
  end

  defp intake_hit({{:., meta, [module, fun]}, _, _}, path) when is_atom(module) do
    case Map.get(@decoder_calls, module) do
      nil -> []
      funs -> decoder_hit(funs, module, fun, meta, path)
    end
  end

  defp intake_hit(_node, _path), do: []

  defp decoder_hit(funs, module, fun, meta, path) do
    if funs == :all or fun in funs,
      do: ["#{path}:#{meta[:line]}: :#{module}.#{fun} decodes XML or a workspace"],
      else: []
  end

  # The `parsers:` of every `plug Plug.Parsers`: atoms as written, a custom
  # parser module as its dotted name.
  defp endpoint_parsers(source) do
    {_ast, found} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:plug, _, [{:__aliases__, _, [:Plug, :Parsers]}, opts]} = node, acc ->
          {node, acc ++ Enum.map(Keyword.get(opts, :parsers, []), &parser_name/1)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp parser_name({:__aliases__, _, segments}), do: Enum.join(segments, ".")
  defp parser_name(parser), do: parser

  defp xml_name?(name) do
    name
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1_\\2")
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    |> Enum.member?("xml")
  end

  # --- sources -------------------------------------------------------------

  defp lib_sources, do: Path.wildcard("lib/**/*.ex")
  defp web_sources, do: Path.wildcard("lib/portfolixir_web/**/*.ex")
end
