defmodule Portfolixir.Catalog.LogoStore do
  @moduledoc """
  Downloads a logo URL once and stores the bytes under
  `priv/static/security_logos/<security_id>.<ext>`.

  The path is registered on the security's `attributes` map as
  `logo_path` (an app-relative URL starting with `/security_logos/...`)
  and `logo_source` (the adapter name, e.g. `"coingecko"`,
  `"wikipedia"`).

  Defensive checks:
    * Content-Type must be one of png / jpg / jpeg / svg+xml / webp.
    * Body must be at most `:max_bytes` (default 256 KiB).
  """

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security

  @default_max_bytes 256 * 1024
  @allowed_content_types %{
    "image/png" => "png",
    "image/jpeg" => "jpg",
    "image/jpg" => "jpg",
    "image/svg+xml" => "svg",
    "image/webp" => "webp"
  }

  @spec download_and_store(Security.t(), String.t(), atom(), keyword()) ::
          {:ok, Security.t()} | {:error, term()}
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
         {:ok, updated} <- update_security_attributes(security, ext, source) do
      {:ok, updated}
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
      nil ->
        {:error, :unsupported_content_type}

      header ->
        type = header |> String.split(";") |> List.first() |> String.trim() |> String.downcase()

        case Map.fetch(@allowed_content_types, type) do
          {:ok, ext} -> {:ok, ext}
          :error -> {:error, :unsupported_content_type}
        end
    end
  end

  defp size_ok(body, max_bytes) when byte_size(body) <= max_bytes, do: :ok
  defp size_ok(_body, _max_bytes), do: {:error, :too_large}

  defp update_security_attributes(security, ext, source) do
    attrs = %{
      attributes:
        Map.merge(security.attributes || %{}, %{
          "logo_path" => "/security_logos/#{security.id}.#{ext}",
          "logo_source" => Atom.to_string(source)
        })
    }

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
