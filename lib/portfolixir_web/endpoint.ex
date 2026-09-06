defmodule PortfolixirWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :portfolixir

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

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  # Ahead of everything, including static files: a request under a foreign
  # Host never reaches the router (ADR-0045 §2, #758).
  plug(PortfolixirWeb.HostGuard)

  # Behind a proxy the operator has named, the throttle sees the client the
  # proxy vouches for rather than the proxy (#771).
  plug(PortfolixirWeb.TrustedProxy)

  # Behind a TLS-terminating proxy the scheme arrives in x-forwarded-proto;
  # rewriting it here is what lets the session cookie carry Secure and the
  # opt-in SSL plug see https (#759).
  plug(Plug.RewriteOn, [:x_forwarded_proto])
  plug(PortfolixirWeb.OptionalSsl)

  plug(Plug.Static,
    at: "/",
    from: :portfolixir,
    gzip: false,
    headers: [{"x-content-type-options", "nosniff"}],
    # Stored logos are named by security id and say which companies the
    # operator holds; they are served by a route behind the UI login (#764).
    only: ~w(app.css favicon.ico favicon.svg images)
  )

  plug(Plug.Static,
    at: "/vendor",
    from: {:phoenix, "priv/static"},
    gzip: false,
    headers: [{"x-content-type-options", "nosniff"}],
    only: ~w(phoenix.min.js)
  )

  plug(Plug.Static,
    at: "/vendor",
    from: {:phoenix_live_view, "priv/static"},
    gzip: false,
    headers: [{"x-content-type-options", "nosniff"}],
    only: ~w(phoenix_live_view.min.js)
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  # Explicit body bound (#771): the default, stated so it is a decision.
  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    length: 8_000_000,
    json_decoder: Phoenix.json_library()
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
