defmodule MempoolServerWeb.Router do
  use MempoolServerWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", MempoolServerWeb do
    pipe_through :api
  end
end
