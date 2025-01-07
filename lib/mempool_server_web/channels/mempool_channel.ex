defmodule MempoolServerWeb.MempoolChannel do
  use Phoenix.Channel

  alias MempoolServer.TransactionsCache
  alias MempoolServer.TxHistoryCache
  alias MempoolServer.Constants

  # -------------------------------------------
  #  Join "mempool:transactions"
  # -------------------------------------------
  def join("mempool:transactions", _message, socket) do
    all_transactions = TransactionsCache.get_all_transactions()

    reply_payload = %{
      unconfirmed_transactions: all_transactions,
      confirmed_transactions: []
    }

    {:ok, reply_payload, socket}
  end

  # -------------------------------------------
  #  Join filtered transaction channels
  # -------------------------------------------
  def join("mempool:" <> name, _message, socket) do
    case Enum.find(Constants.filtered_transactions(), fn ft -> ft.name == name end) do
      nil ->
        {:error, %{reason: "Invalid channel name"}}

      %{ergo_trees: ergo_trees} ->
        unconfirmed_transactions = TransactionsCache.get_transactions_by_ergo_trees(ergo_trees)
        history = TxHistoryCache.get_recent(name)

        reply_payload = %{
          unconfirmed_transactions: unconfirmed_transactions,
          confirmed_transactions: [],
          history: history
        }

        {:ok, reply_payload, socket}
    end
  end

  # -------------------------------------------
  #  Handle inbound events (not used here)
  # -------------------------------------------
  def handle_in(_event, _params, socket) do
    {:noreply, socket}
  end
end