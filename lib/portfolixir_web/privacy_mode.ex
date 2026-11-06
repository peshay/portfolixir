defmodule PortfolixirWeb.PrivacyMode do
  @moduledoc """
  The privacy mode (Sprint 26 P1, idea I22, FR-51; plan D-4 and D-5): while
  it is on, every figure in a currency and every quantity is hidden behind
  one constant placeholder, **on the server**, so neither the digits nor
  their length reach the page, its source, a copied selection or a screen
  reader. Percentages, dates, counts and ratios stay.

  **Where the mask happens.** `PortfolixirWeb.Format` consults the mode of
  the process that renders: `money/2`, `native_amount/2`, `exact/2`,
  `decimal/3` and `signed_decimal/3` return `hidden/0` while it is on, so a
  call site cannot forget it. A figure that is no amount and no quantity (a
  ratio, a rate, a percent axis) is formatted with the `plain_*` forms, each
  one a reviewed exception. The mode is set for a request by this plug, for a
  LiveView by `on_mount/4` (its disconnected and its connected render alike),
  and carried into a page's load tasks by `PortfolixirWeb.CappedAsync`.

  **The switch is per browser.** `?privacy=on` or `?privacy=off` on any page
  of the browser pipeline is remembered in a signed preference cookie
  (`PortfolixirWeb.PreferenceCookie`) and answered with a redirect to the
  same address without the parameter, so a reload never replays an old
  choice. The cookie travels to a LiveView in its signed session
  (`live_session/1`); nothing about the mode is stored on the server. A
  choice from another site (`PortfolixirWeb.FetchSite`) is not remembered,
  and it can only hide figures on the page it opens, never show them.

  **Not a security boundary.** Anyone at the keyboard switches it off; it
  keeps figures off a screen others can see. The JSON API and the MCP
  companion are untouched: a presentation mode is no capability, so the
  two-way coverage rule does not apply (plan D-4).
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  import Plug.Conn

  alias Phoenix.HTML.Engine
  alias PortfolixirWeb.FetchSite
  alias PortfolixirWeb.PageAddress
  alias PortfolixirWeb.PreferenceCookie

  @cookie "portfolixir_privacy"
  @on "on"
  @key :portfolixir_privacy_mode
  @session_key "privacy_mode"

  # The one text a hidden figure reads as where a string is needed: an
  # interpolation, a native tooltip, a JSON payload. No digit, a fixed length.
  @text "••••"

  defmodule Hidden do
    @moduledoc """
    A figure the privacy mode hides. It renders as look C's bar in markup,
    reads as a constant digit-free text in a string and encodes as that
    text in JSON; it carries nothing of the value it replaces.
    """
    defstruct []

    @type t :: %__MODULE__{}
  end

  # ------------------------------------------------------------ the mode

  @doc "Whether the process renders in the privacy mode."
  @spec on?() :: boolean()
  def on?, do: Process.get(@key, false) === true

  @doc "Sets the mode for the process that renders."
  @spec put(boolean()) :: boolean()
  def put(on) when is_boolean(on) do
    Process.put(@key, on)
    on
  end

  @doc "The placeholder every hidden figure is."
  @spec hidden() :: Hidden.t()
  def hidden, do: %Hidden{}

  @doc "The text a hidden figure reads as in a string."
  @spec text() :: String.t()
  def text, do: @text

  @doc "The cookie the mode is remembered under (over plain HTTP)."
  def cookie_name, do: @cookie

  @doc """
  A text that may carry hidden figures (an interpolated sentence, a label),
  escaped for markup, each hidden figure drawn as the bar.
  """
  @spec html(String.t() | Hidden.t() | Phoenix.HTML.safe() | nil) :: Phoenix.HTML.safe()
  def html(%Hidden{}), do: {:safe, bar()}
  def html(nil), do: {:safe, ""}

  # Markup already escaped: the stand-in text holds no character escaping
  # changes, so it is found and replaced as it is.
  def html({:safe, iodata}) do
    {:safe, iodata |> IO.iodata_to_binary() |> String.split(@text) |> Enum.intersperse(bar())}
  end

  def html(text) when is_binary(text) do
    bar = bar()

    iodata =
      text
      |> String.split(@text)
      |> Enum.map(&Engine.html_escape/1)
      |> Enum.intersperse(bar)

    {:safe, iodata}
  end

  @doc false
  # The bar in markup (DESIGN.md → Privacy mode): an empty element of a
  # fixed width, named for a screen reader, with no text a selection copies.
  # Its attribute values are unquoted words, so the markup holds no quote
  # and no ampersand: a hidden figure a template put into an attribute by
  # mistake stays inside that attribute as text (the leak test finds it)
  # instead of breaking the element open.
  def bar, do: ["<span class=pf-mask role=img aria-label=", label(), "></span>"]

  # One word of letters, the translation's; anything else falls back to the
  # English word, so the unquoted value stays one word.
  @doc "The accessible name of a hidden figure, one word in the page's language."
  @spec label() :: String.t()
  def label do
    word = gettext("hidden")
    if Regex.match?(~r/^\p{L}+$/u, word), do: word, else: "hidden"
  end

  # ------------------------------------------------------------ the plug

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)
    remembered = PreferenceCookie.read(conn, @cookie) === @on

    case conn.query_params["privacy"] do
      nil ->
        apply_mode(conn, remembered)

      raw ->
        wanted = raw === @on

        if FetchSite.remember?(conn) and conn.method in ["GET", "HEAD"] do
          conn
          |> remember(wanted)
          |> redirect_without_choice()
        else
          # Another site may hide the figures of the page it opens, never
          # show them.
          apply_mode(conn, remembered or wanted)
        end
    end
  end

  @doc "Whether the request's page renders in the privacy mode."
  @spec on?(Plug.Conn.t()) :: boolean()
  def on?(%Plug.Conn{assigns: %{privacy_mode: true}}), do: true
  def on?(_conn), do: false

  @doc """
  The live session's part of the mode (`live_session :browser, session:`):
  the request's mode, carried in the LiveView's signed session so its
  connected mount renders as its first render did.
  """
  @spec live_session(Plug.Conn.t()) :: map()
  def live_session(conn), do: %{@session_key => on?(conn)}

  @doc """
  The address a page's switch links to: the page's own path and query with
  `privacy` set to the other state, without a preference another site's
  link put into the address; the preferences `current_path` carries (a
  remembered view) are kept (`PortfolixirWeb.PageAddress`).
  """
  @spec toggle_href(String.t() | nil, String.t() | nil, boolean()) :: String.t()
  def toggle_href(page_address, current_path \\ nil, on) do
    PageAddress.link(page_address, current_path, ["privacy=" <> if(on, do: "off", else: @on)])
  end

  # A query's pairs as written, every `privacy` pair left out. The raw
  # pairs, not a decoded map: a list (`cur[]=EUR&cur[]=USD`) or a nested
  # key (`a[b]=c`) keeps its form, its repeats and its order, which a map
  # re-encoded loses or cannot encode at all.
  defp without_choice(query) do
    query
    |> String.split("&", trim: true)
    |> Enum.reject(&choice?/1)
  end

  defp choice?(pair) do
    [key | _value] = String.split(pair, "=", parts: 2)
    decoded_key(key) == "privacy"
  end

  defp decoded_key(key) do
    URI.decode_www_form(key)
  rescue
    ArgumentError -> key
  end

  defp apply_mode(conn, on) do
    put(on)
    assign(conn, :privacy_mode, on)
  end

  defp remember(conn, true), do: PreferenceCookie.put(conn, @cookie, @on)
  defp remember(conn, false), do: PreferenceCookie.delete(conn, @cookie)

  # The same page without the choice: a reload or a bookmark of it never
  # replays a switch. Only a path of this origin; a path that a browser
  # would read as another host (`//host`, a backslash) goes to the start.
  defp redirect_without_choice(conn) do
    query = conn.query_string |> without_choice() |> Enum.join("&")
    path = local_path(conn.request_path)
    location = if query == "", do: path, else: path <> "?" <> query

    conn
    |> put_resp_header("location", location)
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(302, "")
    |> halt()
  end

  defp local_path("/" <> rest = path) do
    if String.starts_with?(rest, ["/", "\\"]) or String.contains?(path, "\\"),
      do: "/",
      else: path
  end

  defp local_path(_path), do: "/"

  # ------------------------------------------------------------ LiveView

  @doc """
  Sets the mode for a LiveView's process from its session, on its
  disconnected and its connected mount alike, and assigns
  `:privacy_mode`; keeps the page's address in `:page_address` for the
  switch, from every `handle_params`.
  """
  def on_mount(:default, _params, session, socket) do
    on = put(Map.get(session, @session_key) === true)

    socket =
      socket
      |> Phoenix.Component.assign(privacy_mode: on, page_address: nil)
      |> Phoenix.LiveView.attach_hook(:privacy_page_address, :handle_params, &page_address/3)

    {:cont, socket}
  end

  # The address the switch links back to (`PortfolixirWeb.AppShell`'s
  # `page_address`): the page's path and query as this `handle_params`
  # sees them, after every patch too, never its host.
  defp page_address(_params, uri, socket) do
    %URI{path: path, query: query} = URI.parse(uri)
    address = URI.to_string(%URI{path: path || "/", query: query})
    {:cont, Phoenix.Component.assign(socket, :page_address, address)}
  end

  @doc """
  `fun` wrapped to run in the mode of the process that wraps it, for a task
  another process runs (`PortfolixirWeb.CappedAsync`).
  """
  @spec carry((-> term())) :: (-> term())
  def carry(fun) when is_function(fun, 0) do
    on = on?()

    fn ->
      put(on)
      fun.()
    end
  end
end

defimpl Phoenix.HTML.Safe, for: PortfolixirWeb.PrivacyMode.Hidden do
  def to_iodata(_hidden), do: PortfolixirWeb.PrivacyMode.bar()
end

defimpl String.Chars, for: PortfolixirWeb.PrivacyMode.Hidden do
  def to_string(_hidden), do: PortfolixirWeb.PrivacyMode.text()
end

defimpl Jason.Encoder, for: PortfolixirWeb.PrivacyMode.Hidden do
  def encode(_hidden, opts), do: Jason.Encode.string(PortfolixirWeb.PrivacyMode.text(), opts)
end
