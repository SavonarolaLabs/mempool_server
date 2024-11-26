# lib/mempool_server_web/router.ex

defmodule MempoolServerWeb.Router do
  use MempoolServerWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", MempoolServerWeb do
    pipe_through :api

    get "/transactions", TransactionController, :index
    get "/transactions/sigmausd", TransactionController, :sigmausd_transactions
  end
end
