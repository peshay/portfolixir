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
      `recv` and a slow-drip upstream never trips it.

  `new/1` builds the request, `get/2` runs it under the deadline. Callers
  merge their test stubs (`plug:`) exactly as they did with `Req.get/2`.
  """

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

  @doc """
  A bounded `Req`. Options: `:max_bytes` (required), `:deadline_ms`
  (default 30 s), `:receive_timeout` (default 10 s), `:headers`,
  `:decode_body`, `:redirect`.
  """
  @spec new(keyword()) :: Req.Request.t()
  def new(opts) do
    max_bytes = Keyword.fetch!(opts, :max_bytes)

    Req.new(
      headers: Keyword.get(opts, :headers, []),
      receive_timeout: Keyword.get(opts, :receive_timeout, @default_receive_timeout),
      connect_options: [timeout: @connect_timeout],
      retry: false,
      decode_body: Keyword.get(opts, :decode_body, true),
      redirect: Keyword.get(opts, :redirect, true),
      into: collector(max_bytes)
    )
    |> Req.Request.put_private(:portfolixir_max_bytes, max_bytes)
    |> Req.Request.put_private(
      :portfolixir_deadline_ms,
      Keyword.get(opts, :deadline_ms, @default_deadline_ms)
    )
  end

  @doc """
  `Req.get/2` under the request's deadline. A body over the cap is
  `{:error, %BodyTooLarge{}}`; a request past the deadline is
  `{:error, :deadline}`; an exception inside the adapter is `{:error, exception}`.
  """
  @spec get(Req.Request.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def get(%Req.Request{} = req, options \\ []) do
    deadline_ms = Req.Request.get_private(req, :portfolixir_deadline_ms, @default_deadline_ms)
    max_bytes = Req.Request.get_private(req, :portfolixir_max_bytes)

    task =
      Task.async(fn ->
        try do
          Req.get(req, options)
        rescue
          exception -> {:error, exception}
        catch
          :exit, reason -> {:error, {:exit, reason}}
        end
      end)

    case Task.yield(task, deadline_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, %Req.Response{} = response}} -> check_cap(response, max_bytes)
      {:ok, {:error, reason}} -> {:error, reason}
      {:exit, reason} -> {:error, {:exit, reason}}
      nil -> {:error, :deadline}
    end
  end

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
