defmodule PortfolixirWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :portfolixir

  # Every response carries the resource policy and a content-security-policy,
  # the error pages and refusals built outside the router included (SR-1).
  @before_compile PortfolixirWeb.DefaultResponseHeaders

  # The salt is derived from the secret key base per installation (#759,
  # ADR-0045 §2) instead of a literal shared by every checkout; `secure` is
  # left to Plug, which sets it when the scheme is https — real or, behind a
  # proxy, rewritten from x-forwarded-proto below.
  @session_options [
    store: :cookie,
    key: "_portfolixir_key",
    signing_salt: {__MODULE__, :session_signing_salt, []},
    same_site: "Lax",
    http_only: true
  ]

  socket("/live", PortfolixirWeb.LiveSocket,
    websocket: [
      connect_info: [session: @session_options],
      # The frame bound and the guard before decoding (security review
      # 2026-10-12, H02): PortfolixirWeb.LiveSocket says how it was sized.
      max_frame_size: PortfolixirWeb.LiveSocket.max_message_bytes()
    ]
  )

  # First of all, so a body or a read that runs away fails its own process
  # rather than the node (E25 S4, G05).
  plug(PortfolixirWeb.HeapCap)

  # Ahead of everything, including static files: a request under a foreign
  # Host never reaches the router (ADR-0045 §2, #758).
  plug(PortfolixirWeb.HostGuard)

  # Behind a proxy the operator has named, the throttle sees the client the
  # proxy vouches for rather than the proxy (#771). Behind a TLS-terminating
  # proxy the scheme arrives in x-forwarded-proto, which is what lets the
  # session cookie carry Secure and the opt-in SSL plug see https (#759); the
  # same plug believes it only from loopback or a named proxy (E25 S1, F09).
  plug(PortfolixirWeb.TrustedProxy)
  plug(PortfolixirWeb.OptionalSsl)

  # Every static response says what the browser pipeline's pages say:
  # nosniff (#763), and this origin as the only reader (E25 S7, F07), so a
  # page on another site can neither embed nor probe the instance's assets.
  @static_headers [
    {"x-content-type-options", "nosniff"},
    {"cross-origin-resource-policy", "same-origin"}
  ]

  plug(Plug.Static,
    at: "/",
    from: :portfolixir,
    gzip: false,
    headers: @static_headers,
    # Stored logos are named by security id and say which companies the
    # operator holds; they are served by a route behind the UI login (#764).
    # theme-boot.js is the root layout's theme script for the pages the
    # static policy serves, the error page (the closing act, E25).
    only: ~w(app.css favicon.ico favicon.svg images theme-boot.js)
  )

  plug(Plug.Static,
    at: "/vendor",
    from: {:phoenix, "priv/static"},
    gzip: false,
    headers: @static_headers,
    only: ~w(phoenix.min.js)
  )

  plug(Plug.Static,
    at: "/vendor",
    from: {:phoenix_live_view, "priv/static"},
    gzip: false,
    headers: @static_headers,
    only: ~w(phoenix_live_view.min.js)
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  # Explicit body bound (#771): the default, stated so it is a decision.
  # No multipart parser (security review 2026-10-12, H01): no route reads a
  # multipart body, the Imports upload travels over the LiveView socket, and
  # the parser wrote every file part to disk before any credential was
  # checked. A future upload route parses multipart in its own pipeline,
  # behind its authentication.
  #
  # The bound is sized to the largest documented API body (security review
  # 2026-10-12, H02): a quote upsert of 10,000 rows, the row cap
  # ListLimit.quote_upsert_max_rows/0 enforces, at under 100 bytes a row as
  # compact JSON, with room for indentation and a `source` per row; 200 bytes
  # a row is 2,000,000 bytes. Nothing larger arrives over HTTP: the Imports
  # upload travels over the LiveView socket. The JSON decoder refuses a body
  # nested past PortfolixirWeb.JsonDepth's bound with 400 before decoding it.
  plug(Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    length: 2_000_000,
    json_decoder: PortfolixirWeb.JsonDepth
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  # The lifetime is runtime configuration, so the options are built per
  # request rather than baked in at compile time (#777).
  plug(PortfolixirWeb.SessionLifetime)
  plug(PortfolixirWeb.Router)

  @doc "The session options, without the lifetime `PortfolixirWeb.SessionLifetime` adds."
  @spec session_options() :: keyword()
  def session_options, do: @session_options

  @doc "The session cookie's signing salt, derived from the secret key base (#759)."
  @spec session_signing_salt() :: String.t()
  def session_signing_salt do
    Portfolixir.RuntimeConfig.derived_salt(config(:secret_key_base), "session")
  end
end
