defmodule Portfolixir.Catalog.LogoStoreTest do
  # User story (continuation of the dispatcher story):
  # Once a logo URL is known, Portfolixir downloads the image once and stores
  # it next to the app's other static assets, so that
  #   - the list view never makes third-party requests at render time,
  #   - the logo survives the upstream service going down or rotating URLs,
  #   - the user's holdings are not leaked to the source's CDN logs.
  #
  # Acceptance criteria:
  # - Successful PNG download is written to
  #   `<storage_dir>/<security_id>.png` and the security's
  #   `attributes["logo_path"]` + `attributes["logo_source"]` are updated.
  # - Content types outside the allowlist (png/jpg/jpeg/webp) are
  #   refused.
  # - Files larger than the configured max size are refused.
  # - Network/HTTP errors return `{:error, _}` and do not touch the DB.
  use Portfolixir.DataCase, async: false

  import ExUnit.CaptureLog

  require Logger

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.LogoStore
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Journal
  alias Portfolixir.Repo

  # 1x1 PNG
  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
         6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 250, 207, 0, 0,
         0, 3, 0, 1, 5, 12, 60, 192, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  setup do
    tmp = Path.join(System.tmp_dir!(), "portfolixir-logos-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, sec} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Arbolia Inc.",
        currency_code: "USD",
        provider: "manual",
        asset_class: "equity"
      })

    %{tmp: tmp, security: sec}
  end

  defp png_stub(bytes, content_type \\ "image/png") do
    [
      plug: fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type(content_type)
        |> Plug.Conn.send_resp(200, bytes)
      end
    ]
  end

  test "writes the image to <storage_dir>/<id>.png and updates the attributes",
       %{tmp: tmp, security: sec} do
    assert {:ok, updated} =
             LogoStore.download_and_store(
               sec,
               "https://example.test/logo.png",
               :wikipedia,
               req: png_stub(@png),
               storage_dir: tmp
             )

    expected_path = "/security_logos/#{sec.id}.png"
    assert updated.attributes["logo_path"] == expected_path
    assert updated.attributes["logo_source"] == "wikipedia"
    assert File.read!(Path.join(tmp, "#{sec.id}.png")) == @png

    # Reload from DB to verify persistence
    reloaded = Repo.get!(Security, sec.id)
    assert reloaded.attributes["logo_path"] == expected_path
  end

  test "refuses content types outside the image allowlist",
       %{tmp: tmp, security: sec} do
    assert {:error, :unsupported_content_type} =
             LogoStore.download_and_store(
               sec,
               "https://example.test/logo.html",
               :wikipedia,
               req: png_stub("<html/>", "text/html"),
               storage_dir: tmp
             )

    refute File.exists?(Path.join(tmp, "#{sec.id}.png"))
    refute Repo.get!(Security, sec.id).attributes["logo_path"]
  end

  test "refuses SVG content and leaves the security untouched",
       %{tmp: tmp, security: sec} do
    svg = ~S|<svg xmlns="http://www.w3.org/2000/svg"><script>alert("x")</script></svg>|

    assert {:error, :unsupported_content_type} =
             LogoStore.download_and_store(
               sec,
               "https://example.test/logo.svg",
               :wikipedia,
               req: png_stub(svg, "image/svg+xml"),
               storage_dir: tmp
             )

    refute File.exists?(Path.join(tmp, "#{sec.id}.svg"))
    refute Repo.get!(Security, sec.id).attributes["logo_path"]
  end

  test "refuses files larger than the size limit", %{tmp: tmp, security: sec} do
    big = :binary.copy(<<0>>, 300 * 1024)

    assert {:error, :too_large} =
             LogoStore.download_and_store(
               sec,
               "https://example.test/big.png",
               :wikipedia,
               req: png_stub(big),
               storage_dir: tmp,
               max_bytes: 256 * 1024
             )

    refute File.exists?(Path.join(tmp, "#{sec.id}.png"))
  end

  test "transport errors surface and leave the security untouched",
       %{tmp: tmp, security: sec} do
    stub = [
      plug: fn conn ->
        Plug.Conn.send_resp(conn, 503, "down")
      end
    ]

    assert {:error, _} =
             LogoStore.download_and_store(
               sec,
               "https://example.test/logo.png",
               :wikipedia,
               req: stub,
               storage_dir: tmp
             )

    refute Repo.get!(Security, sec.id).attributes["logo_path"]
  end

  # User story:
  # As a maintainer whose security has no automatic logo (an exotic title),
  # I want to paste an image URL and have it stick, so background discovery
  # never overwrites my manual choice.
  test "store_manual_override downloads, marks the source manual and locks",
       %{tmp: tmp, security: sec} do
    assert {:ok, updated} =
             LogoStore.store_manual_override(
               sec,
               "https://example.test/logo.png",
               req: png_stub(@png),
               storage_dir: tmp
             )

    assert updated.attributes["logo_path"] == "/security_logos/#{sec.id}.png"
    assert updated.attributes["logo_source"] == "manual"
    assert updated.attributes["logo_locked"] == true
    assert File.exists?(Path.join(tmp, "#{sec.id}.png"))
  end

  test "store_manual_bytes writes validated upload bytes and locks",
       %{tmp: tmp, security: sec} do
    assert {:ok, updated} =
             LogoStore.store_manual_bytes(sec, @png, "image/png", storage_dir: tmp)

    assert updated.attributes["logo_source"] == "manual"
    assert updated.attributes["logo_locked"] == true
    assert File.read!(Path.join(tmp, "#{sec.id}.png")) == @png
  end

  test "store_manual_bytes refuses content types outside the allowlist",
       %{tmp: tmp, security: sec} do
    assert {:error, :unsupported_content_type} =
             LogoStore.store_manual_bytes(sec, "<html/>", "text/html", storage_dir: tmp)

    refute Repo.get!(Security, sec.id).attributes["logo_locked"]
  end

  # User story:
  # As a maintainer, I want to remove a wrong/unwanted logo and have the row
  # fall back to initials, with discovery leaving it alone afterwards.
  test "remove_logo deletes the file, clears the path/source and locks",
       %{tmp: tmp, security: sec} do
    {:ok, with_logo} =
      LogoStore.download_and_store(
        sec,
        "https://example.test/logo.png",
        :wikipedia,
        req: png_stub(@png),
        storage_dir: tmp
      )

    assert File.exists?(Path.join(tmp, "#{sec.id}.png"))

    assert {:ok, removed} = LogoStore.remove_logo(with_logo, storage_dir: tmp)

    refute removed.attributes["logo_path"]
    refute removed.attributes["logo_source"]
    assert removed.attributes["logo_locked"] == true
    refute File.exists?(Path.join(tmp, "#{sec.id}.png"))
    refute Repo.get!(Security, sec.id).attributes["logo_path"]
  end

  # User story:
  # As a maintainer watching the securities list during a large import, I want
  # freshly discovered logos to replace the initials placeholder without a page
  # reload. LogoStore broadcasts on the "security_logos" topic after every
  # store/remove so subscribed LiveViews can patch the affected row.
  # E25 S2, F59: the directory is configuration, so a release keeps its logos
  # on a volume outside its own tree. Unconfigured, it is the release's own
  # priv directory, as before.
  test "stores into the configured directory, and storage_dir/0 names it",
       %{tmp: tmp, security: sec} do
    assert LogoStore.storage_dir() ==
             Application.app_dir(:portfolixir, "priv/static/security_logos")

    previous = Application.get_env(:portfolixir, LogoStore, [])
    Application.put_env(:portfolixir, LogoStore, Keyword.put(previous, :storage_dir, tmp))
    on_exit(fn -> Application.put_env(:portfolixir, LogoStore, previous) end)

    assert LogoStore.storage_dir() == tmp
    assert {:ok, _} = LogoStore.store_manual_bytes(sec, @png, "image/png")
    assert File.read!(Path.join(tmp, "#{sec.id}.png")) == @png
  end

  # User story (#933, redesigned in review pass 1):
  # As an operator whose instance lost logo files — an upgrade across F59's
  # move into the volume, a lost, unmounted or restored volume —
  # I want a stored logo whose file is gone marked rather than cleared,
  # so that the row shows its monogram or flag and counts as without a logo,
  # while nothing about the logo is destroyed: the path, the source and the
  # lock stay, a remounted or restored volume heals the mark at the next run,
  # and no holding is reclassified.
  #
  # Acceptance criteria:
  # - A path that names no regular file gets logo_file_missing: true; path,
  #   source and lock are kept, whatever the lock. has_logo reads false and
  #   file_missing true. The effective asset class does not move.
  # - A present file of every stored extension (png, jpg, webp) is never
  #   marked; the "no logo" choice is never touched; nothing is journaled for
  #   them.
  # - A mark is removed when the file is back.
  # - Every write is journaled under the system job "logo_reconcile" and
  #   broadcast; a second run writes, journals and broadcasts nothing.
  # - A missing or unreadable directory skips the run with a warning and
  #   writes nothing; an existing empty one marks every row.
  # - The write is a compare-and-set inside the locked row: a path that moved
  #   or a file state that changed since the check writes nothing.
  # - Storing a logo (discovered, chosen or uploaded) and removing one clear
  #   the mark.
  # - One info line names the counts when anything changed.
  defp security!(name, attrs \\ %{}) do
    {:ok, security} =
      Catalog.create_security(
        Portfolixir.Actor.owner_ui(),
        Map.merge(%{name: name, currency_code: "EUR", provider: "manual"}, attrs)
      )

    security
  end

  defp with_logo!(security, source, locked? \\ false) do
    attrs = %{"logo_path" => "/security_logos/#{security.id}.png", "logo_source" => source}
    attrs = if locked?, do: Map.put(attrs, "logo_locked", true), else: attrs
    {:ok, updated} = Catalog.put_logo_attributes(security, attrs)
    updated
  end

  defp reconcile_journal(security) do
    [resource_type: "security", resource_id: to_string(security.id)]
    |> Journal.list_entries()
    |> Enum.filter(&(&1.actor_type == :system_job and &1.actor_label == "logo_reconcile"))
  end

  defp journal(security),
    do: Journal.list_entries(resource_type: "security", resource_id: to_string(security.id))

  defp reload(security), do: Repo.get!(Security, security.id)

  describe "reconcile_missing_files/1 (#933)" do
    test "marks a discovered logo whose file is gone and keeps everything else",
         %{tmp: tmp, security: sec} do
      discovered = with_logo!(sec, "wikipedia")
      :ok = LogoStore.subscribe()

      assert LogoStore.reconcile_missing_files(storage_dir: tmp) ==
               {:ok, %{marked: 1, unmarked: 0, failed: 0}}

      marked = reload(discovered)

      assert marked.attributes ==
               Map.put(discovered.attributes, "logo_file_missing", true)

      assert Catalog.logo_status(marked) == %{
               path: "/security_logos/#{sec.id}.png",
               source: "wikipedia",
               has_logo: false,
               locked: false,
               file_missing: true
             }

      assert [entry] = reconcile_journal(discovered)
      assert entry.operation == :update
      assert_receive {:security_logo_updated, id}
      assert id == discovered.id
    end

    test "marks a locked manual logo whose file is gone, keeping its source and lock",
         %{tmp: tmp, security: sec} do
      manual = with_logo!(sec, "manual", true)

      assert LogoStore.reconcile_missing_files(storage_dir: tmp) ==
               {:ok, %{marked: 1, unmarked: 0, failed: 0}}

      assert Catalog.logo_status(reload(manual)) == %{
               path: "/security_logos/#{sec.id}.png",
               source: "manual",
               has_logo: false,
               locked: true,
               file_missing: true
             }
    end

    test "a mark does not move the effective asset class", %{tmp: tmp} do
      unclassified =
        "Zentavo"
        |> security!(%{isin: "DEEXMPL20530", asset_class: nil})
        |> with_logo!("wikipedia")

      assert Security.effective_asset_class(unclassified) == "equity"

      LogoStore.reconcile_missing_files(storage_dir: tmp)

      assert Catalog.logo_status(reload(unclassified)).file_missing
      assert Security.effective_asset_class(reload(unclassified)) == "equity"
    end

    test "never marks a present file of any stored extension, nor the no-logo choice",
         %{tmp: tmp, security: sec} do
      jpg = <<0xFF, 0xD8, 0xFF, 0xE0, 0, 16>>
      webp = "RIFF" <> <<0, 0, 0, 0>> <> "WEBP" <> "VP8 "

      stored =
        for {security, bytes, type} <- [
              {sec, @png, "image/png"},
              {security!("Brindle AG"), jpg, "image/jpeg"},
              {security!("Corvala AG"), webp, "image/webp"}
            ] do
          {:ok, stored} = LogoStore.store_manual_bytes(security, bytes, type, storage_dir: tmp)
          stored
        end

      assert stored |> Enum.map(&Path.extname(&1.attributes["logo_path"])) |> Enum.sort() ==
               [".jpg", ".png", ".webp"]

      {:ok, no_logo} = LogoStore.remove_logo(security!("Dunmere AG"), storage_dir: tmp)
      before = Enum.map([no_logo | stored], &{&1.attributes, journal(&1)})
      :ok = LogoStore.subscribe()

      assert LogoStore.reconcile_missing_files(storage_dir: tmp) ==
               {:ok, %{marked: 0, unmarked: 0, failed: 0}}

      assert Enum.map([no_logo | stored], &{reload(&1).attributes, journal(&1)}) == before
      refute_receive {:security_logo_updated, _id}
    end

    test "removes the mark once the file is back, and a second run does nothing",
         %{tmp: tmp, security: sec} do
      discovered = with_logo!(sec, "wikipedia")
      manual = with_logo!(security!("Brindle AG"), "manual", true)

      assert LogoStore.reconcile_missing_files(storage_dir: tmp) ==
               {:ok, %{marked: 2, unmarked: 0, failed: 0}}

      after_first = {reload(discovered), reload(manual), journal(discovered), journal(manual)}
      :ok = LogoStore.subscribe()

      assert LogoStore.reconcile_missing_files(storage_dir: tmp) ==
               {:ok, %{marked: 0, unmarked: 0, failed: 0}}

      assert {reload(discovered), reload(manual), journal(discovered), journal(manual)} ==
               after_first

      refute_receive {:security_logo_updated, _id}

      File.write!(Path.join(tmp, "#{manual.id}.png"), @png)

      assert LogoStore.reconcile_missing_files(storage_dir: tmp) ==
               {:ok, %{marked: 0, unmarked: 1, failed: 0}}

      assert reload(manual).attributes == manual.attributes
      assert Catalog.logo_status(reload(manual)).has_logo
      assert length(reconcile_journal(manual)) == 2
      assert_receive {:security_logo_updated, id}
      assert id == manual.id
    end

    test "skips a missing or unreadable directory with a warning and writes nothing",
         %{tmp: tmp, security: sec} do
      discovered = with_logo!(sec, "wikipedia")
      not_a_dir = Path.join(tmp, "a-file")
      File.write!(not_a_dir, "")

      for dir <- [Path.join(tmp, "missing"), not_a_dir] do
        log =
          capture_log(fn ->
            assert {:skipped, _reason} = LogoStore.reconcile_missing_files(storage_dir: dir)
          end)

        assert log =~ "logo directory"
        assert log =~ dir
        assert log =~ "#933"
      end

      assert reload(discovered).attributes == discovered.attributes
      assert reconcile_journal(discovered) == []
    end

    test "an existing empty directory marks every stored logo, retired and benchmark included",
         %{tmp: tmp, security: sec} do
      rows = [
        with_logo!(sec, "wikipedia"),
        with_logo!(security!("Brindle AG"), "manual", true),
        with_logo!(security!("Corvala AG", %{is_retired: true}), "wikipedia"),
        with_logo!(security!("Dunmere Index", %{is_benchmark: true}), "coingecko")
      ]

      assert LogoStore.reconcile_missing_files(storage_dir: tmp) ==
               {:ok, %{marked: 4, unmarked: 0, failed: 0}}

      assert Enum.all?(rows, &Catalog.logo_status(reload(&1)).file_missing)
    end

    test "logs one info line with the counts when it changes anything",
         %{tmp: tmp, security: sec} do
      Logger.put_module_level(LogoStore, :info)
      on_exit(fn -> Logger.delete_module_level(LogoStore) end)

      with_logo!(sec, "wikipedia")
      with_logo!(security!("Brindle AG"), "manual", true)

      log =
        capture_log([level: :info], fn -> LogoStore.reconcile_missing_files(storage_dir: tmp) end)

      assert [line] = log |> String.split("\n") |> Enum.filter(&(&1 =~ "#933"))
      assert line =~ "2 marked"
      assert line =~ "0 unmarked"
      assert line =~ "0 failed"

      assert capture_log([level: :info], fn ->
               LogoStore.reconcile_missing_files(storage_dir: tmp)
             end) == ""
    end

    test "the mark is a compare-and-set inside the locked row", %{security: sec} do
      discovered = with_logo!(sec, "wikipedia")
      path = discovered.attributes["logo_path"]

      # The path moved since the check: nothing is written.
      assert Catalog.put_logo_file_mark(discovered, "/security_logos/0.png", fn -> false end) ==
               {:error, :changed}

      # The file came back between the check and the write: nothing is written.
      assert Catalog.put_logo_file_mark(discovered, path, fn -> true end) == {:error, :changed}

      assert reload(discovered).attributes == discovered.attributes
      assert reconcile_journal(discovered) == []

      assert {:ok, marked} = Catalog.put_logo_file_mark(discovered, path, fn -> false end)
      assert marked.attributes["logo_file_missing"] == true
      assert [_entry] = reconcile_journal(discovered)
    end

    test "storing or removing a logo clears the mark", %{tmp: tmp, security: sec} do
      marked = fn security ->
        security = with_logo!(security, "manual", true)

        {:ok, marked} =
          Catalog.put_logo_file_mark(security, security.attributes["logo_path"], fn -> false end)

        assert Catalog.logo_status(marked).file_missing
        marked
      end

      {:ok, uploaded} =
        LogoStore.store_manual_bytes(marked.(sec), @png, "image/png", storage_dir: tmp)

      {:ok, chosen} =
        LogoStore.store_manual_override(
          marked.(security!("Brindle AG")),
          "https://example.test/l.png",
          req: png_stub(@png),
          storage_dir: tmp
        )

      {:ok, discovered} =
        LogoStore.download_and_store(
          marked.(security!("Corvala AG")),
          "https://example.test/l.png",
          :wikipedia,
          req: png_stub(@png),
          storage_dir: tmp
        )

      {:ok, removed} = LogoStore.remove_logo(marked.(security!("Dunmere AG")), storage_dir: tmp)

      for security <- [uploaded, chosen, discovered, removed] do
        refute Map.has_key?(reload(security).attributes, "logo_file_missing")
      end

      assert Catalog.logo_status(reload(uploaded)).has_logo
      refute Catalog.logo_status(reload(removed)).has_logo
    end
  end

  # User story (#933, review pass 1):
  # As an operator starting an instance,
  # I want the logo reconciliation to run after the supervisor is up, in a
  # supervised task of its own, against the configured logo directory,
  # so that it can neither hold up nor stop the boot, and its errors land in
  # the log.
  #
  # Acceptance criteria:
  # - Application.after_start/0, the step start/2 runs once the supervisor is
  #   up, starts it when :reconcile_logos_on_boot is on (off in config/test.exs)
  #   and returns :ok at once.
  # - It reads the configured directory: a file present there is not marked,
  #   a missing one is.
  # - A crash in the work is logged and the boot step still answers.
  # - A task that cannot start, with no supervisor or one that refuses it, is
  #   logged, and the boot step answers {:error, reason} rather than raising.
  describe "the boot reconciliation (#933)" do
    setup %{tmp: tmp} do
      gate = Application.fetch_env(:portfolixir, :reconcile_logos_on_boot)
      previous = Application.get_env(:portfolixir, LogoStore, [])
      Application.put_env(:portfolixir, LogoStore, Keyword.put(previous, :storage_dir, tmp))

      on_exit(fn ->
        case gate do
          {:ok, value} -> Application.put_env(:portfolixir, :reconcile_logos_on_boot, value)
          :error -> Application.delete_env(:portfolixir, :reconcile_logos_on_boot)
        end

        Application.put_env(:portfolixir, LogoStore, previous)
      end)

      %{gate: gate}
    end

    defp await_logo_tasks do
      for pid <- Task.Supervisor.children(Portfolixir.LogoSupervisor) do
        ref = Process.monitor(pid)
        assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 5_000
      end

      :ok
    end

    test "after_start/0 starts it against the configured directory when the gate is on",
         %{tmp: tmp, security: sec, gate: gate} do
      assert gate == {:ok, false}

      # The file of one sits in the configured directory, the other's nowhere.
      {:ok, present} = LogoStore.store_manual_bytes(sec, @png, "image/png")
      assert File.exists?(Path.join(tmp, "#{sec.id}.png"))
      missing = with_logo!(security!("Brindle AG"), "wikipedia")

      # after_start/0 also logs the exposure warnings, which depend on how the
      # test endpoint is bound; they are not this test's subject.
      capture_log(fn ->
        assert Portfolixir.Application.after_start() == :ok
        await_logo_tasks()
      end)

      refute Catalog.logo_status(reload(missing)).file_missing

      Application.put_env(:portfolixir, :reconcile_logos_on_boot, true)

      capture_log(fn ->
        assert Portfolixir.Application.after_start() == :ok
        await_logo_tasks()
      end)

      refute Catalog.logo_status(reload(present)).file_missing
      assert Catalog.logo_status(reload(missing)).file_missing
    end

    test "a crash in the work is logged and the boot step still answers" do
      Application.put_env(:portfolixir, :reconcile_logos_on_boot, true)

      log =
        capture_log(fn ->
          assert {:ok, pid} = Catalog.reconcile_logos_on_boot(fn -> raise "synthetic failure" end)
          ref = Process.monitor(pid)
          assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 5_000
        end)

      assert log =~ "logo reconciliation"
      assert log =~ "synthetic failure"
      # Review pass 2: the crash keeps its stacktrace.
      assert log =~ "RuntimeError"
      assert log =~ ~r/test\/portfolixir\/catalog\/logo_store_test\.exs:\d+/
    end

    test "a task that cannot start is logged and the boot step still answers" do
      Application.put_env(:portfolixir, :reconcile_logos_on_boot, true)

      log =
        capture_log(fn ->
          assert {:error, _reason} =
                   Catalog.reconcile_logos_on_boot(fn -> :ok end, :no_such_logo_supervisor)
        end)

      assert log =~ "The logo reconciliation (#933) could not start"
    end

    test "a supervisor that refuses the task is logged and the boot step answers its reason" do
      Application.put_env(:portfolixir, :reconcile_logos_on_boot, true)
      supervisor = start_supervised!({Task.Supervisor, max_children: 0})

      log =
        capture_log(fn ->
          assert {:error, :max_children} =
                   Catalog.reconcile_logos_on_boot(fn -> :ok end, supervisor)
        end)

      assert log =~ "The logo reconciliation (#933) could not start: :max_children"
    end
  end

  # User story (#933, review pass 2):
  # As an operator reading the log of an instance whose logo directory is in
  # an unusual state,
  # I want the reconciliation to stay quiet when there is nothing to check,
  # to stop rather than mark everything when it cannot look inside the
  # directory, to pass over a stored path that is not a string, and to name
  # a write it could not make,
  # so that a warning means something, and no mark is set on a guess.
  #
  # Acceptance criteria:
  # - No security stores a logo path: {:ok, all zero}, no warning, even when
  #   the directory does not exist yet.
  # - A directory readable but not searchable (its "." answers :eacces)
  #   skips the run with the warning; nothing is written.
  # - A file that answers :eacces after that (a link into a directory the
  #   app may not search) stops the run there with a warning naming what was
  #   written before it; those writes stand.
  # - A stored logo_path that is not a string is passed over, not crashed on.
  # - A write that fails for another reason than :changed is logged with the
  #   security's id and counted as failed, in the result and the info line.
  # - put_logo_file_mark/3 on a row that has gone answers {:error, :not_found}.
  describe "reconcile_missing_files/1 edge cases (#933, review pass 2)" do
    test "is quiet when no security stores a logo path", %{tmp: tmp} do
      log =
        capture_log(fn ->
          assert LogoStore.reconcile_missing_files(storage_dir: Path.join(tmp, "not-yet")) ==
                   {:ok, %{marked: 0, unmarked: 0, failed: 0}}
        end)

      assert log == ""
    end

    test "a directory it may not search skips the run instead of marking everything",
         %{tmp: tmp, security: sec} do
      discovered = with_logo!(sec, "wikipedia")

      log =
        capture_log(fn ->
          assert LogoStore.reconcile_missing_files(
                   storage_dir: tmp,
                   stat: fn _path -> {:error, :eacces} end
                 ) == {:skipped, :eacces}
        end)

      assert log =~ "logo directory"
      assert log =~ tmp
      assert reload(discovered).attributes == discovered.attributes
      assert reconcile_journal(discovered) == []
    end

    test "a file it may not check stops the run partway and names what it wrote",
         %{tmp: tmp, security: sec} do
      first = with_logo!(sec, "wikipedia")
      second = with_logo!(security!("Brindle AG"), "wikipedia")

      stat = fn path ->
        if Path.basename(path) == "#{second.id}.png",
          do: {:error, :eacces},
          else: File.stat(path)
      end

      log =
        capture_log(fn ->
          assert LogoStore.reconcile_missing_files(storage_dir: tmp, stat: stat) ==
                   {:stopped, :eacces, %{marked: 1, unmarked: 0, failed: 0}}
        end)

      assert log =~ "stopped partway"
      assert log =~ "1 marked as file missing"
      refute log =~ "no logo was marked"
      assert Catalog.logo_status(reload(first)).file_missing
      refute Catalog.logo_status(reload(second)).file_missing
    end

    test "passes over a stored logo path that is not a string", %{tmp: tmp, security: sec} do
      {:ok, odd} = Catalog.put_logo_attributes(sec, %{"logo_path" => 42})

      assert LogoStore.reconcile_missing_files(storage_dir: tmp) ==
               {:ok, %{marked: 0, unmarked: 0, failed: 0}}

      assert reload(odd).attributes == odd.attributes
    end

    test "logs a write it could not make with the security's id and counts it as failed",
         %{tmp: tmp, security: sec} do
      Logger.put_module_level(LogoStore, :info)
      on_exit(fn -> Logger.delete_module_level(LogoStore) end)

      gone = with_logo!(sec, "wikipedia")
      kept = with_logo!(security!("Brindle AG"), "wikipedia")

      # The row goes away between the check and the write.
      stat = fn path ->
        if Path.basename(path) == "#{gone.id}.png" and Repo.get(Security, gone.id),
          do: {:ok, _} = Catalog.delete_security(Portfolixir.Actor.owner_ui(), gone)

        File.stat(path)
      end

      log =
        capture_log([level: :info], fn ->
          assert LogoStore.reconcile_missing_files(storage_dir: tmp, stat: stat) ==
                   {:ok, %{marked: 1, unmarked: 0, failed: 1}}
        end)

      assert log =~ "##{gone.id}"
      assert log =~ ":not_found"
      assert log =~ "1 marked"
      assert log =~ "1 failed"
      assert Catalog.logo_status(reload(kept)).file_missing
    end

    test "put_logo_file_mark/3 on a row that has gone answers :not_found", %{security: sec} do
      discovered = with_logo!(sec, "wikipedia")
      {:ok, _} = Catalog.delete_security(Portfolixir.Actor.owner_ui(), discovered)

      assert Catalog.put_logo_file_mark(discovered, discovered.attributes["logo_path"], fn ->
               false
             end) == {:error, :not_found}
    end
  end

  # User story (#933, review pass 2):
  # As the operator whose logo files are served and checked by one rule,
  # I want served_file/2 to admit exactly a security id and an extension the
  # store writes,
  # so that the route and the reconciliation can never disagree about which
  # name is a logo file.
  #
  # Acceptance criteria:
  # - "<id>.png", "<id>.jpg" and "<id>.webp" with an id of up to 18 digits
  #   map onto the directory, with their extension.
  # - A 19-digit id, an unknown or uppercase extension, a double extension, a
  #   path segment and a non-binary are :error.
  test "served_file/2 admits a security id and an extension the store writes" do
    for ext <- ~w(png jpg webp) do
      assert LogoStore.served_file("42.#{ext}", "/logos") == {:ok, "/logos/42.#{ext}", ext}
    end

    assert {:ok, _path, "png"} = LogoStore.served_file(String.duplicate("9", 18) <> ".png", "/l")

    for name <- [
          String.duplicate("9", 19) <> ".png",
          "42.svg",
          "42.jpeg",
          "42.PNG",
          "1.png.png",
          ".png",
          "../42.png",
          "42"
        ] do
      assert LogoStore.served_file(name, "/logos") == :error, name
    end

    assert LogoStore.served_file(42, "/logos") == :error
    assert LogoStore.served_file(nil, "/logos") == :error
  end

  describe "PubSub broadcast" do
    test "download_and_store broadcasts the updated security id",
         %{tmp: tmp, security: sec} do
      :ok = LogoStore.subscribe()

      assert {:ok, _updated} =
               LogoStore.download_and_store(
                 sec,
                 "https://example.test/logo.png",
                 :wikipedia,
                 req: png_stub(@png),
                 storage_dir: tmp
               )

      assert_receive {:security_logo_updated, id}
      assert id == sec.id
    end

    test "store_manual_bytes broadcasts", %{tmp: tmp, security: sec} do
      :ok = LogoStore.subscribe()

      assert {:ok, _updated} =
               LogoStore.store_manual_bytes(sec, @png, "image/png", storage_dir: tmp)

      assert_receive {:security_logo_updated, id}
      assert id == sec.id
    end

    test "remove_logo broadcasts", %{tmp: tmp, security: sec} do
      {:ok, with_logo} =
        LogoStore.download_and_store(
          sec,
          "https://example.test/logo.png",
          :wikipedia,
          req: png_stub(@png),
          storage_dir: tmp
        )

      :ok = LogoStore.subscribe()
      assert {:ok, _removed} = LogoStore.remove_logo(with_logo, storage_dir: tmp)

      assert_receive {:security_logo_updated, id}
      assert id == sec.id
    end

    test "a failed download does not broadcast", %{tmp: tmp, security: sec} do
      :ok = LogoStore.subscribe()

      assert {:error, _} =
               LogoStore.download_and_store(
                 sec,
                 "https://example.test/logo.png",
                 :wikipedia,
                 req: [plug: fn conn -> Plug.Conn.send_resp(conn, 503, "down") end],
                 storage_dir: tmp
               )

      refute_receive {:security_logo_updated, _id}
    end
  end
end
