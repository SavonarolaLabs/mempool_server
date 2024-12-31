defmodule MempoolServerWeb.MempoolChannel do
  use Phoenix.Channel

  alias MempoolServer.TransactionsCache

  def join("mempool:transactions", _message, socket) do
    # On channel join, immediately send the current mempool transactions
    all_transactions = TransactionsCache.get_all_transactions()
    push(socket, "all_transactions", %{transactions: all_transactions})

    {:ok, socket}
  end

  def join("mempool:sigmausd_transactions", _message, socket) do
    # On channel join, immediately send the SigmaUSD-filtered transactions
    sigmausd_transactions = TransactionsCache.get_sigmausd_transactions()
    push(socket, "sigmausd_transactions", %{transactions: sigmausd_transactions})

    {:ok, socket}
  end

  def handle_in(_event, _params, socket) do
    {:noreply, socket}
  end
end
