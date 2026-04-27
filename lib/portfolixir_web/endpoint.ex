defmodule PortfolixirWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :portfolixir

  @session_options [
    store: :cookie,
    key: "_portfolixir_key",
    signing_salt: "change_me"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Static,
    at: "/",
    from: :portfolixir,
    gzip: false,
    only: ~w(favicon.ico favicon.svg images)
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
