defmodule MempoolServerWeb.HistoryController do
    use MempoolServerWeb, :controller
  
    import Ecto.Query, only: [order_by: 2, limit: 2]
  
    alias MempoolServer.{Repo, Transaction}
  
    def recent_transactions(conn, _params) do
      transactions =
        Transaction
        |> order_by(desc: :inserted_at)
        |> limit(2)
        |> Repo.all()
  
      json(conn, transactions)
    end
  end
  