defmodule MempoolServer.Repo do
    use Ecto.Repo,
      otp_app: :mempool_server,
      adapter: Ecto.Adapters.SQLite3
  end
  