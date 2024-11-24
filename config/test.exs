import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :mempool_server, MempoolServerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "menwAILlppRhozZHJpnuQg43QHBSZx4ZJxG7JhWrJnWcphlA46I7n/ACkNyPRM8j",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
