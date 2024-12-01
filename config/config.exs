# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :mempool_server,
  generators: [timestamp_type: :utc_datetime],
  ecto_repos: [MempoolServer.Repo] # Add this line

# Configures the Repo (SQLite3 database)
config :mempool_server, MempoolServer.Repo,
  database: "priv/repo/mempool_server.sqlite3",
  pool_size: 10

# Configures the endpoint
config :mempool_server, MempoolServerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [json: MempoolServerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MempoolServer.PubSub,
  live_view: [signing_salt: "znrpyCZH"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
