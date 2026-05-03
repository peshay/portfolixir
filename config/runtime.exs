import Config

read_api_auth_enabled =
  System.get_env("READ_API_AUTH_ENABLED", if(config_env() == :prod, do: "true", else: "false"))
  |> String.downcase()
  |> Kernel.in(["1", "true", "yes", "on"])

read_api_key = System.get_env("READ_API_KEY")

if config_env() == :prod and not read_api_auth_enabled do
  raise "READ_API_AUTH_ENABLED must be true in production to protect /api/read/*"
end

config :portfolixir, PortfolixirWeb.Plugs.ReadApiKeyAuth,
  enabled: read_api_auth_enabled,
  api_key: read_api_key

browser_auth_enabled =
  System.get_env("BROWSER_AUTH_ENABLED", if(config_env() == :prod, do: "true", else: "false"))
  |> String.downcase()
  |> Kernel.in(["1", "true", "yes", "on"])

browser_auth_key = System.get_env("BROWSER_AUTH_KEY")

if config_env() == :prod and not browser_auth_enabled do
  raise "BROWSER_AUTH_ENABLED must be true in production to protect browser/export routes"
end

config :portfolixir, PortfolixirWeb.Plugs.BrowserApiKeyAuth,
  enabled: browser_auth_enabled,
  api_key: browser_auth_key

if config_env() == :prod do
  config :portfolixir, PortfolixirWeb.Endpoint,
    server: true,
    url: [host: System.fetch_env!("PHX_HOST")],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    check_origin: [System.fetch_env!("PHX_HOST")],
    http: [
      port: String.to_integer(System.get_env("PORT") || "4000"),
      ip: {0, 0, 0, 0}
    ],
    cache_static_manifest: "/opt/app/priv/static/cache_manifest.json"

  config :portfolixir, Portfolixir.Repo,
    url: System.fetch_env!("DATABASE_URL"),
    ssl: true,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
end
