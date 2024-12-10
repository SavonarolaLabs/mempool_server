defmodule MempoolServerWeb.Router do
  use MempoolServerWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", MempoolServerWeb do
    pipe_through :api

    get "/transactions", TransactionController, :index
    get "/transactions/sigmausd", TransactionController, :sigmausd_transactions
    get "/history/recent", HistoryController, :recent_transactions

    # New routes for TrackedErgoTreeController
    resources "/tracked_ergo_trees", TrackedErgoTreeController, only: [:index, :create, :update]
  end
end
