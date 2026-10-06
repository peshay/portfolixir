defmodule Portfolixir.Catalog.LogoStore do
  @moduledoc """
  Downloads a logo URL once and stores the bytes as
  `<security_id>.<ext>` in the logo directory (`storage_dir/0`).

  The path is registered on the security's `attributes` map as
  `logo_path` (an app-relative URL starting with `/security_logos/...`)
  and `logo_source` (the adapter name, e.g. `"coingecko"`,
  `"wikipedia"`).

  Defensive checks:
    * The URL passes `Portfolixir.Net.UrlPolicy` before any connection (#762):
      https only, public addresses only, and for a discovery source only the
      hosts configured for it (`config :portfolixir, Portfolixir.Catalog.LogoStore,
      allowed_hosts: %{source => list | :any}`). A redirect is followed only by
      the bounded client's guard (E25 S3, F27): a few hops at most, each one
      re-checked against the same policy and the same host list.
    * Content-Type must be one of png / jpg / jpeg / webp.
    * Body must be at most `:max_bytes` (default 256 KiB).
  """

  import Ecto.Query, only: [where: 3, order_by: 3]

  require Logger

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Net.Http
  alias Portfolixir.Net.UrlPolicy
  alias Portfolixir.Repo

  # Logo bytes are operational, machine-discovered assets that happen to live on
  # the guard-armed `securities` table (ADR-0017). They are journaled like any
  # other security write, attributed to a fixed system actor inside
  # `Catalog.put_logo_attributes/2` rather than threaded from the caller —
  # logos are not financial records authored by a user.

  @pubsub Portfolixir.PubSub
  @topic "security_logos"

  @default_max_bytes 256 * 1024
  @allowed_content_types %{
    "image/png" => "png",
    "image/jpeg" => "jpg",
    "image/jpg" => "jpg",
    "image/webp" => "webp"
  }
  # The extensions a stored file can carry: the write path's set, so the
  # served shape (`served_file/2`) cannot drift from what is written (#933).
  @extensions @allowed_content_types |> Map.values() |> Enum.uniq()
  @url_prefix "/security_logos/"

  @doc """
  Topic on which `{:security_logo_updated, security_id}` messages are
  broadcast whenever a logo is stored, replaced or removed. LiveViews
  subscribe so freshly discovered logos appear without a page reload.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, @topic)

  @spec download_and_store(Security.t(), String.t(), atom(), keyword()) ::
          {:ok, Security.t()} | {:error, term()}
  # storage_dir comes from app config/opts and the filename from the security
  # id plus a validated extension — no user-controlled path segments.
  # sobelow_skip ["Traversal.FileModule"]
  def download_and_store(%Security{} = security, url, source, opts \\ [])
      when is_binary(url) and is_atom(source) do
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)
    storage_dir = Keyword.get(opts, :storage_dir) || default_storage_dir()
    allowed_hosts = allowed_hosts_for(source)
    req = build_req(opts, max_bytes, allowed_hosts)

    with :ok <- UrlPolicy.check(url, allowed_hosts: allowed_hosts),
         {:ok, response} <- fetch(req, url),
         {:ok, ext} <- content_type_extension(response),
         :ok <- size_ok(response.body, max_bytes),
         :ok <- image_bytes_ok(response.body, ext),
         :ok <- File.mkdir_p(storage_dir),
         file_path = Path.join(storage_dir, "#{security.id}.#{ext}"),
         :ok <- File.write(file_path, response.body),
         {:ok, updated} <- update_security_attributes(security, ext, source, opts) do
      broadcast_logo_change(updated.id)
      {:ok, updated}
    end
  end

  @doc """
  Sets a manual logo from a user-supplied image URL.

  Stored with `logo_source = "manual"` and `logo_locked = true`, so the
  background discovery never overwrites a manual choice.
  """
  @spec store_manual_override(Security.t(), String.t(), keyword()) ::
          {:ok, Security.t()} | {:error, term()}
  def store_manual_override(%Security{} = security, url, opts \\ []) when is_binary(url) do
    download_and_store(security, url, :manual, Keyword.put(opts, :lock, true))
  end

  @doc """
  Stores manual logo bytes (e.g. from a file upload) after validating the
  content type and size. Locks the logo like `store_manual_override/3`.
  """
  @spec store_manual_bytes(Security.t(), binary(), String.t(), keyword()) ::
          {:ok, Security.t()} | {:error, term()}
  # storage_dir comes from app config/opts and the filename from the security
  # id plus a validated extension — no user-controlled path segments.
  # sobelow_skip ["Traversal.FileModule"]
  def store_manual_bytes(%Security{} = security, body, content_type, opts \\ [])
      when is_binary(body) and is_binary(content_type) do
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)
    storage_dir = Keyword.get(opts, :storage_dir) || default_storage_dir()

    with {:ok, ext} <- extension_for_type(content_type),
         :ok <- size_ok(body, max_bytes),
         :ok <- image_bytes_ok(body, ext),
         :ok <- File.mkdir_p(storage_dir),
         file_path = Path.join(storage_dir, "#{security.id}.#{ext}"),
         :ok <- File.write(file_path, body),
         {:ok, updated} <- update_security_attributes(security, ext, :manual, lock: true) do
      broadcast_logo_change(updated.id)
      {:ok, updated}
    end
  end

  @doc """
  Removes a security's logo and records an explicit "no logo" decision.

  The stored file (if any) is deleted, `logo_path`/`logo_source` are cleared
  and `logo_locked = true` is set so discovery treats the security as
  intentionally logo-less and leaves the initials/flag fallback in place.
  """
  @spec remove_logo(Security.t(), keyword()) :: {:ok, Security.t()} | {:error, term()}
  # storage_dir comes from app config/opts; the deleted path is the one we
  # previously wrote under that dir — no user-controlled path segments.
  # sobelow_skip ["Traversal.FileModule"]
  def remove_logo(%Security{} = security, opts \\ []) do
    storage_dir = Keyword.get(opts, :storage_dir) || default_storage_dir()
    delete_existing_logo_file(security, storage_dir)

    logo_attrs = %{
      "logo_path" => nil,
      "logo_source" => nil,
      "logo_locked" => true,
      "logo_file_missing" => nil
    }

    case Catalog.put_logo_attributes(security, logo_attrs) do
      {:ok, updated} ->
        broadcast_logo_change(updated.id)
        {:ok, updated}

      other ->
        other
    end
  end

  @doc """
  The file a logo file name names in the logo directory (#764, #933): a
  security id of up to 18 digits plus an extension the write path stores,
  joined onto `storage_dir` only after the name matched, so nothing else from
  a request or a stored path reaches the file system. The one shape check,
  shared by `PortfolixirWeb.LogoFileController`, which serves the file, and
  the reconciliation, which checks it. It does not look at the disk.
  """
  @spec served_file(term(), Path.t()) :: {:ok, Path.t(), String.t()} | :error
  def served_file(file, storage_dir \\ default_storage_dir())

  def served_file(file, storage_dir) when is_binary(file) do
    with [id, ext] <- String.split(file, ".", parts: 2),
         true <- ext in @extensions,
         true <- Regex.match?(~r/\A[0-9]{1,18}\z/, id) do
      {:ok, Path.join(storage_dir, file), ext}
    else
      _ -> :error
    end
  end

  def served_file(_file, _storage_dir), do: :error

  @doc """
  Reconciles the logo bookkeeping with the logo directory (#933). A security
  can carry a `logo_path` with no file behind it — an upgrade across F59's
  move of the logos into the volume, a lost, unmounted or restored volume —
  and every logo surface used to read the attribute, never the file. This is
  the one place that compares the two.

  A path that names no regular file is **marked** `logo_file_missing: true`;
  a mark whose file is back is removed. Nothing else is touched: the path,
  the source and the lock stay, so a restored or remounted volume heals at
  the next run, and nothing that reads the path (the asset-class inference
  among them) moves. Each write is `Catalog.put_logo_file_mark/3`, a
  compare-and-set inside the locked row journaled under its own system job,
  and is broadcast like any logo change; a second run writes nothing. One
  info line names the counts when anything changed.

  A missing, unreadable or unsearchable directory skips the run with a
  warning, so a mistyped `PORTFOLIXIR_LOGO_DIR` or an unmounted volume marks
  nothing; a file that cannot be checked after that stops the run with a
  warning naming what was written before it (`{:stopped, reason, counts}`); an
  existing empty one marks every stored logo, which is the alarm the Overview
  raises. No network. `:storage_dir` overrides the configured directory.
  """
  @spec reconcile_missing_files(keyword()) ::
          {:ok, counts}
          | {:skipped, File.posix()}
          | {:stopped, File.posix(), counts}
        when counts: %{
               marked: non_neg_integer(),
               unmarked: non_neg_integer(),
               failed: non_neg_integer()
             }
  # storage_dir comes from app config/opts and is only listed; every file
  # checked is a served_file/2 name joined onto it.
  # sobelow_skip ["Traversal.FileModule"]
  def reconcile_missing_files(opts \\ []) do
    storage_dir = Keyword.get(opts, :storage_dir) || default_storage_dir()
    # The file check, File.stat/1 unless a test hands in another.
    stat = Keyword.get(opts, :stat, &File.stat/1)

    # No stored logo, nothing to compare: quiet, whatever the directory.
    with [_ | _] = rows <- securities_with_logo_path(),
         {:ok, _names} <- File.ls(storage_dir),
         :ok <- searchable(storage_dir, stat),
         {:ok, counts} <- reconcile_rows(rows, storage_dir, stat) do
      log_reconciliation(counts)
      {:ok, counts}
    else
      [] ->
        {:ok, %{marked: 0, unmarked: 0, failed: 0}}

      {:error, reason} ->
        Logger.warning(
          "Logo reconciliation skipped (#933): the logo directory #{storage_dir} is " <>
            "missing or unreadable (#{:file.format_error(reason)}), so no logo was " <>
            "marked. Check PORTFOLIXIR_LOGO_DIR and that its volume is mounted."
        )

        {:skipped, reason}

      {:stopped, reason, counts} ->
        Logger.warning(
          "Logo reconciliation stopped partway (#933): a logo file in #{storage_dir} " <>
            "could not be checked (#{:file.format_error(reason)}), after " <>
            "#{counts.marked} marked as file missing, #{counts.unmarked} unmarked and " <>
            "#{counts.failed} failed. Check the permissions of PORTFOLIXIR_LOGO_DIR and " <>
            "of anything its entries link to."
        )

        {:stopped, reason, counts}
    end
  end

  # A directory that lists but cannot be searched answers :eacces for "."
  # inside it: the run stops there, before any write, rather than marking
  # every logo.
  defp searchable(storage_dir, stat) do
    case stat.(Path.join(storage_dir, ".")) do
      {:error, :eacces} -> {:error, :eacces}
      _searchable -> :ok
    end
  end

  defp securities_with_logo_path do
    Security
    |> where([s], not is_nil(fragment("? ->> ?", s.attributes, "logo_path")))
    |> order_by([s], s.id)
    |> Repo.all()
  end

  # A file that answers :eacces after the directory passed searchable/2 (a
  # link into a directory the app may not search) stops the run there; the
  # writes made before it stand and are counted.
  defp reconcile_rows(rows, storage_dir, stat) do
    Enum.reduce_while(rows, {:ok, %{marked: 0, unmarked: 0, failed: 0}}, fn security,
                                                                            {:ok, counts} ->
      case reconcile_file(security, storage_dir, stat, counts) do
        {:ok, counts} -> {:cont, {:ok, counts}}
        {:error, reason} -> {:halt, {:stopped, reason, counts}}
      end
    end)
  end

  # A mark that disagrees with the disk is written: a missing file not yet
  # marked, or a marked one whose file is back. A stored path that is not a
  # string is passed over.
  defp reconcile_file(%Security{attributes: attributes} = security, storage_dir, stat, counts) do
    path = attributes["logo_path"]
    marked? = attributes["logo_file_missing"] == true

    case file_state(path, storage_dir, stat) do
      :unsearchable -> {:error, :eacces}
      :not_a_path -> {:ok, counts}
      state when state == :present and not marked? -> {:ok, counts}
      state when state == :missing and marked? -> {:ok, counts}
      _disagrees -> {:ok, write_mark(security, path, storage_dir, stat, counts)}
    end
  end

  defp write_mark(security, path, storage_dir, stat, counts) do
    # Re-checked under the row lock; a directory gone unsearchable since
    # marks nothing.
    present? = fn -> file_state(path, storage_dir, stat) != :missing end

    case Catalog.put_logo_file_mark(security, path, present?) do
      {:ok, updated} ->
        broadcast_logo_change(updated.id)
        key = if updated.attributes["logo_file_missing"], do: :marked, else: :unmarked
        Map.update!(counts, key, &(&1 + 1))

      {:error, :changed} ->
        counts

      {:error, reason} ->
        Logger.warning(
          "Logo reconciliation (#933) could not write security ##{security.id}: " <>
            inspect(reason)
        )

        Map.update!(counts, :failed, &(&1 + 1))
    end
  end

  # storage_dir comes from app config/opts, and the name is served_file/2's.
  # sobelow_skip ["Traversal.FileModule"]
  defp file_state(@url_prefix <> file, storage_dir, stat) do
    with {:ok, path, _ext} <- served_file(file, storage_dir),
         {:ok, %File.Stat{type: :regular}} <- stat.(path) do
      :present
    else
      {:error, :eacces} -> :unsearchable
      _other -> :missing
    end
  end

  defp file_state(path, _storage_dir, _stat) when is_binary(path), do: :missing
  defp file_state(_path, _storage_dir, _stat), do: :not_a_path

  defp log_reconciliation(%{marked: 0, unmarked: 0, failed: 0}), do: :ok

  defp log_reconciliation(%{marked: marked, unmarked: unmarked, failed: failed}) do
    Logger.info(
      "Logo reconciliation (#933): #{marked} marked as file missing, " <>
        "#{unmarked} unmarked with their file back, #{failed} failed."
    )
  end

  defp broadcast_logo_change(security_id) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:security_logo_updated, security_id})
  end

  # storage_dir comes from app config/opts and the filename is the security id
  # plus a validated extension — no user-controlled path segments.
  # sobelow_skip ["Traversal.FileModule"]
  defp delete_existing_logo_file(%Security{id: id}, storage_dir) do
    @allowed_content_types
    |> Map.values()
    |> Enum.uniq()
    |> Enum.each(fn ext -> File.rm(Path.join(storage_dir, "#{id}.#{ext}")) end)
  end

  defp extension_for_type(content_type) do
    type = content_type |> String.split(";") |> List.first() |> String.trim() |> String.downcase()

    case Map.fetch(@allowed_content_types, type) do
      {:ok, ext} -> {:ok, ext}
      :error -> {:error, :unsupported_content_type}
    end
  end

  # The bounded client follows a redirect only through its guard: every hop is
  # re-checked against the policy the first URL passed, so a redirect can never
  # reach what a direct URL may not (#762, F27).
  defp fetch(req, url) do
    case Http.get(req, url: url) do
      {:ok, %Req.Response{status: 200} = response} ->
        {:ok, response}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      # The bounded client cuts the body at the cap (#763); callers keep the
      # store's own error atom.
      {:error, %Http.BodyTooLarge{}} ->
        {:error, :too_large}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp allowed_hosts_for(source) do
    :portfolixir
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:allowed_hosts, %{})
    |> Map.get(source, [])
  end

  defp content_type_extension(%Req.Response{} = response) do
    response
    |> Req.Response.get_header("content-type")
    |> List.first()
    |> case do
      nil -> {:error, :unsupported_content_type}
      header -> extension_for_type(header)
    end
  end

  defp size_ok(body, max_bytes) when byte_size(body) <= max_bytes, do: :ok
  defp size_ok(_body, _max_bytes), do: {:error, :too_large}

  # The header is the upstream's claim; the leading bytes are the file's (#763).
  defp image_bytes_ok(<<137, 80, 78, 71, 13, 10, 26, 10, _::binary>>, "png"), do: :ok
  defp image_bytes_ok(<<0xFF, 0xD8, 0xFF, _::binary>>, "jpg"), do: :ok
  defp image_bytes_ok(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>, "webp"), do: :ok
  defp image_bytes_ok(_body, _ext), do: {:error, :unsupported_content_type}

  defp update_security_attributes(security, ext, source, opts) do
    # A stored file answers the reconciliation's mark (#933): it is cleared.
    base = %{
      "logo_path" => @url_prefix <> "#{security.id}.#{ext}",
      "logo_source" => Atom.to_string(source),
      "logo_file_missing" => nil
    }

    base = if Keyword.get(opts, :lock, false), do: Map.put(base, "logo_locked", true), else: base

    Catalog.put_logo_attributes(security, base)
  end

  defp build_req(opts, max_bytes, allowed_hosts) do
    base =
      Http.new(
        headers: [{"user-agent", "portfolixir/0.1 (logo-store)"}],
        receive_timeout: 5_000,
        allowed_hosts: allowed_hosts,
        decode_body: false,
        max_bytes: max_bytes,
        deadline_ms: 15_000
      )

    case opts[:req] do
      nil -> base
      overrides when is_list(overrides) -> Req.merge(base, overrides)
    end
  end

  @doc """
  The directory stored logos are written to and served from: the configured
  `:storage_dir` (`PORTFOLIXIR_LOGO_DIR` in a release, E25 S2), else the
  release's own `priv/static/security_logos`.
  """
  @spec storage_dir() :: Path.t()
  def storage_dir, do: default_storage_dir()

  defp default_storage_dir do
    :portfolixir
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:storage_dir)
    |> case do
      dir when is_binary(dir) -> dir
      nil -> Application.app_dir(:portfolixir, "priv/static/security_logos")
    end
  end
end
