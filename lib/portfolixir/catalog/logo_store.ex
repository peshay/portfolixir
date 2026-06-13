defmodule Portfolixir.Catalog.LogoStore do
  @moduledoc """
  Downloads a logo URL once and stores the bytes under
  `priv/static/security_logos/<security_id>.<ext>`.

  The path is registered on the security's `attributes` map as
  `logo_path` (an app-relative URL starting with `/security_logos/...`)
  and `logo_source` (the adapter name, e.g. `"coingecko"`,
  `"wikipedia"`).

  Defensive checks:
    * Content-Type must be one of png / jpg / jpeg / webp.
    * Body must be at most `:max_bytes` (default 256 KiB).
  """

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security

  @pubsub Portfolixir.PubSub
  @topic "security_logos"

  @default_max_bytes 256 * 1024
  @allowed_content_types %{
    "image/png" => "png",
    "image/jpeg" => "jpg",
    "image/jpg" => "jpg",
    "image/webp" => "webp"
  }

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
    req = build_req(opts)

    with {:ok, response} <- fetch(req, url),
         {:ok, ext} <- content_type_extension(response),
         :ok <- size_ok(response.body, max_bytes),
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

    attributes = security.attributes || %{}

    attrs = %{
      attributes:
        attributes
        |> Map.drop(["logo_path", "logo_source"])
        |> Map.put("logo_locked", true)
    }

    case Catalog.update_security(security, attrs) do
      {:ok, updated} ->
        broadcast_logo_change(updated.id)
        {:ok, updated}

      other ->
        other
    end
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

  defp fetch(req, url) do
    case Req.get(req, url: url) do
      {:ok, %Req.Response{status: 200} = response} ->
        {:ok, response}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
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

  defp update_security_attributes(security, ext, source, opts) do
    base = %{
      "logo_path" => "/security_logos/#{security.id}.#{ext}",
      "logo_source" => Atom.to_string(source)
    }

    base = if Keyword.get(opts, :lock, false), do: Map.put(base, "logo_locked", true), else: base

    attrs = %{attributes: Map.merge(security.attributes || %{}, base)}

    Catalog.update_security(security, attrs)
  end

  defp build_req(opts) do
    base =
      Req.new(
        headers: [{"user-agent", "portfolixir/0.1 (logo-store)"}],
        receive_timeout: 5_000,
        retry: false,
        decode_body: false
      )

    case opts[:req] do
      nil -> base
      overrides when is_list(overrides) -> Req.merge(base, overrides)
    end
  end

  defp default_storage_dir do
    Application.app_dir(:portfolixir, "priv/static/security_logos")
  end
end
