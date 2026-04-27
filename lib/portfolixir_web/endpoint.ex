defmodule PortfolixirWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :portfolixir

  socket("/live", Phoenix.LiveView.Socket)

  @session_options [
    store: :cookie,
    key: "_portfolixir_key",
    signing_salt: "change_me"
  ]

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
