defmodule PortfolixirWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :portfolixir

  @session_options [
    store: :cookie,
    key: "_portfolixir_key",
    signing_salt: "change_me"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Static,
    at: "/vendor",
    from: {:phoenix, "priv/static"},
    gzip: false,
    only: ~w(phoenix.min.js)
  )

  plug(Plug.Static,
    at: "/vendor",
    from: {:phoenix_live_view, "priv/static"},
    gzip: false,
    only: ~w(phoenix_live_view.min.js)
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(PortfolixirWeb.Router)
end
