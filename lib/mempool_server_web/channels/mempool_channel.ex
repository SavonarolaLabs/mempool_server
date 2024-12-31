defmodule MempoolServerWeb.MempoolChannel do
  use Phoenix.Channel

  alias MempoolServer.TransactionsCache

  # When the client requests to join "mempool:transactions"
  def join("mempool:transactions", _message, socket) do
    # 1) Queue up an internal message to ourselves (the channel process)
    send(self(), :after_join_all)

    # 2) Respond with {:ok, socket} so Phoenix knows the channel is joined
    {:ok, socket}
  end

  # When the client requests to join "mempool:sigmausd_transactions"
  def join("mempool:sigmausd_transactions", _message, socket) do
    # 1) Queue up an internal message
    send(self(), :after_join_sigmausd)

    # 2) Respond with {:ok, socket}
    {:ok, socket}
  end

  # Our "after_join_all" handler is called after the socket is joined.
  # Now we can safely push the data we want to send.
  def handle_info(:after_join_all, socket) do
    all_transactions = TransactionsCache.get_all_transactions()
    push(socket, "all_transactions", %{unconfirmed_transactions: all_transactions})
    {:noreply, socket}
  end

  # Similarly for sigmausd
  def handle_info(:after_join_sigmausd, socket) do
    sigmausd_transactions = TransactionsCache.get_sigmausd_transactions()
    push(socket, "sigmausd_transactions", %{unconfirmed_transactions: sigmausd_transactions})
    {:noreply, socket}
  end

  # Standard no-op for any inbound events
  def handle_in(_event, _params, socket) do
    {:noreply, socket}
  end
end
