defmodule MempoolServerWeb.CacheController do
  use MempoolServerWeb, :controller

  alias MempoolServer.Constants
  alias MempoolServer.TransactionsCache
  alias MempoolServer.TxHistoryCache
  alias MempoolServer.OracleBoxesUtil

  def index(conn, _params) do
    payload = OracleBoxesUtil.oracle_boxes_payload()
    json(conn, payload)
  end

  def transactions(conn, %{"name" => name}) do
    match = Enum.find(Constants.filtered_transactions(), fn ft -> ft.name == name end)
  
    if match do
      unconfirmed = TransactionsCache.get_transactions_by_ergo_trees(match.ergo_trees)
      history = TxHistoryCache.get_recent(name) |> Enum.take(1)
  
      json(conn, %{
        unconfirmed_transactions: unconfirmed,
        confirmed_transactions: history
      })
    else
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Invalid name"})
    end
  end
end
