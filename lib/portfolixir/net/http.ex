defmodule Portfolixir.Net.Http do
  @moduledoc """
  The one bounded `Req` every outbound client is built from (#763).

  Three bounds, all of which a provider adapter used to lack:

    * **a byte cap enforced while the body streams** — a declared
      `Content-Length` over the cap is refused on the first chunk, and a body
      that grows past the cap is cut there; either becomes
      `{:error, %Portfolixir.Net.Http.BodyTooLarge{}}` rather than a response;
    * **a connect timeout** next to the receive timeout;
    * **a deadline on the whole request**, because a receive timeout is per
      `recv` and a slow-drip upstream never trips it. Every redirect hop runs
      inside the same deadline.

  And one guard (E25 S3, F27): **a redirect is followed only through the URL
  policy.** Every client declares its own host allow-list (`:allowed_hosts`,
  required). Req's own redirect following is always off; this module follows
  at most `:max_redirects` hops (default 3) itself, and each hop must pass
  `Portfolixir.Net.UrlPolicy` against that allow-list — https only, so a
  downgrade to plain http is refused, no userinfo, public addresses only. A
  refused hop is `{:error, {:url_not_allowed, reason}}` and makes no request;
  a chain past the cap is `{:error, :too_many_redirects}`. When a hop changes
  the scheme, host or port, every header the client set except the user agent
  and the accept headers is dropped, and stays dropped for the rest of the
  chain, so no credential crosses to another host whatever its header is
  called. The first request passes the same policy without name resolution
  (its host is the client's compiled-in endpoint).

  `new/1` builds the request, `get/2` runs it under the deadline. Callers
  merge their test stubs (`plug:`) exactly as they did with `Req.get/2`.
  """

  alias Portfolixir.Net.UrlPolicy

  defmodule BodyTooLarge do
    @moduledoc "Raised as a value: the upstream body exceeded the client's byte cap."
    defexception [:limit, :size]

    @impl true
    def message(%{limit: limit, size: size}) do
      "upstream body of #{size} bytes exceeds the #{limit}-byte cap"
    end
  end

  @default_deadline_ms 30_000
  @default_receive_timeout 10_000
  @connect_timeout 5_000
  @default_max_redirects 3
  @redirect_statuses [301, 302, 303, 307, 308]
  # The only headers a hop to another origin keeps. Every other header the
  # client set is treated as one that can carry a credential (F27).
  @cross_origin_headers ~w(user-agent accept accept-language)

  @doc """
  A bounded `Req`. Options: `:max_bytes` (required), `:allowed_hosts`
  (required: `:any` or a list of exact and `.domain` entries, as
  `Portfolixir.Net.UrlPolicy` reads them), `:deadline_ms` (default 30 s),
  `:receive_timeout` (default 10 s), `:max_redirects` (default 3),
  `:headers`, `:decode_body`.
  """
  @spec new(keyword()) :: Req.Request.t()
  def new(opts) do
    max_bytes = Keyword.fetch!(opts, :max_bytes)
    allowed_hosts = Keyword.fetch!(opts, :allowed_hosts)

    Req.new(
      headers: Keyword.get(opts, :headers, []),
      receive_timeout: Keyword.get(opts, :receive_timeout, @default_receive_timeout),
      connect_options: [timeout: @connect_timeout],
      retry: false,
      decode_body: Keyword.get(opts, :decode_body, true),
      redirect: false,
      into: collector(max_bytes)
    )
    |> Req.Request.put_private(:portfolixir_max_bytes, max_bytes)
    |> Req.Request.put_private(:portfolixir_allowed_hosts, allowed_hosts)
    |> Req.Request.put_private(
      :portfolixir_max_redirects,
      Keyword.get(opts, :max_redirects, @default_max_redirects)
    )
    |> Req.Request.put_private(
      :portfolixir_deadline_ms,
      Keyword.get(opts, :deadline_ms, @default_deadline_ms)
    )
  end

  @doc """
  `Req.get/2` under the request's deadline, following redirects only through
  the guard. A body over the cap is `{:error, %BodyTooLarge{}}`; a request
  past the deadline is `{:error, :deadline}`; a URL or hop the policy refuses
  is `{:error, {:url_not_allowed, reason}}`; a chain past the hop cap is
  `{:error, :too_many_redirects}`; an exception inside the adapter is
  `{:error, exception}`. A redirect status without a `Location` is returned
  as the response it is.
  """
  @spec get(Req.Request.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def get(%Req.Request{} = req, options \\ []) do
    deadline_ms = Req.Request.get_private(req, :portfolixir_deadline_ms, @default_deadline_ms)

    task =
      Task.async(fn ->
        try do
          # Req's own following stays off whatever a caller merged in.
          req = req |> Req.merge(options) |> Req.merge(redirect: false)

          with :ok <- check_url(req.url, req, resolve: false) do
            run(req, Req.Request.get_private(req, :portfolixir_max_redirects))
          end
        rescue
          exception -> {:error, exception}
        catch
          :exit, reason -> {:error, {:exit, reason}}
        end
      end)

    case Task.yield(task, deadline_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, %Req.Response{} = response}} -> {:ok, response}
      {:ok, {:error, reason}} -> {:error, reason}
      {:exit, reason} -> {:error, {:exit, reason}}
      nil -> {:error, :deadline}
    end
  end

  defp run(req, hops_left) do
    max_bytes = Req.Request.get_private(req, :portfolixir_max_bytes)

    with {:ok, response} <- Req.request(%{req | method: :get}),
         {:ok, response} <- check_cap(response, max_bytes) do
      case redirect_location(response) do
        nil -> {:ok, response}
        location -> follow(req, location, hops_left)
      end
    end
  end

  defp follow(_req, _location, 0), do: {:error, :too_many_redirects}

  defp follow(req, location, hops_left) do
    target = URI.merge(req.url, location)

    with :ok <- check_url(target, req, resolve: true) do
      req
      # The first hop's query already rode on its URL; a Location carries its own.
      |> Req.Request.delete_option(:params)
      |> drop_credentials_across_origins(target)
      |> Map.put(:url, target)
      |> run(hops_left - 1)
    end
  end

  defp redirect_location(%Req.Response{status: status} = response)
       when status in @redirect_statuses do
    case Req.Response.get_header(response, "location") do
      [location | _] when is_binary(location) and location != "" -> location
      _ -> nil
    end
  end

  defp redirect_location(_response), do: nil

  defp check_url(%URI{} = url, req, opts) do
    UrlPolicy.check(
      URI.to_string(url),
      Keyword.put(opts, :allowed_hosts, Req.Request.get_private(req, :portfolixir_allowed_hosts))
    )
  end

  defp drop_credentials_across_origins(req, target) do
    if origin(target) == origin(req.url) do
      req
    else
      req
      |> Req.get_headers_list()
      |> Enum.map(&elem(&1, 0))
      |> Enum.reject(&(&1 in @cross_origin_headers))
      |> Enum.reduce(req, &Req.Request.delete_header(&2, &1))
      |> Req.Request.delete_option(:auth)
    end
  end

  defp origin(%URI{scheme: scheme, host: host, port: port}),
    do: {scheme, host && String.downcase(host), port}

  defp check_cap(response, max_bytes) do
    case Req.Response.get_private(response, :portfolixir_too_large) do
      nil -> {:ok, response}
      size -> {:error, %BodyTooLarge{limit: max_bytes, size: size}}
    end
  end

  # Runs per body chunk. The declared length is checked on the first chunk so
  # an honest oversized upstream costs nothing; a dishonest one is cut where
  # its body crosses the cap.
  defp collector(max_bytes) do
    fn {:data, chunk}, {req, response} ->
      declared = declared_length(response)
      body = accumulate(response.body, chunk)

      cond do
        is_integer(declared) and declared > max_bytes ->
          {:halt, {req, too_large(response, declared)}}

        byte_size(body) > max_bytes ->
          {:halt, {req, too_large(response, byte_size(body))}}

        true ->
          {:cont, {req, %{response | body: body}}}
      end
    end
  end

  defp accumulate(body, chunk) when is_binary(body), do: body <> chunk
  defp accumulate(_body, chunk), do: chunk

  defp too_large(response, size) do
    response
    |> Map.put(:body, "")
    |> Req.Response.put_private(:portfolixir_too_large, size)
  end

  defp declared_length(response) do
    case Req.Response.get_header(response, "content-length") do
      [value | _] ->
        case Integer.parse(value) do
          {length, _} -> length
          :error -> nil
        end

      _ ->
        nil
    end
  end
end
