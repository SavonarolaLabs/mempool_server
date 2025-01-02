defmodule MempoolServerWeb.MempoolChannel do
  use Phoenix.Channel

  alias MempoolServer.TransactionsCache
  alias MempoolServer.TxHistoryCache

  # -------------------------------------------
  #  Join "mempool:transactions"
  # -------------------------------------------
  def join("mempool:transactions", _message, socket) do
    # 1) Retrieve any unconfirmed transactions from your cache
    all_transactions = TransactionsCache.get_all_transactions()

    # 2) Construct your initial payload.
    reply_payload = %{
      unconfirmed_transactions: all_transactions,
      confirmed_transactions: []
    }

    # 3) Return the payload in the 'ok' tuple
    {:ok, reply_payload, socket}
  end

  # -------------------------------------------
  #  Join "mempool:sigmausd_transactions"
  # -------------------------------------------
  def join("mempool:sigmausd_transactions", _message, socket) do
    # 1) Retrieve any unconfirmed SigmaUSD transactions from your transaction cache
    sigmausd_transactions = TransactionsCache.get_sigmausd_transactions()

    # 2) Retrieve the last 10 cached transactions ("history") from TxHistoryCache
    sigmausd_history = TxHistoryCache.get_recent("sigmausd_transactions")

    # 3) Build your initial payload including "history"
    reply_payload = %{
      unconfirmed_transactions: sigmausd_transactions,
      confirmed_transactions: [],
      history: sigmausd_history
    }

    {:ok, reply_payload, socket}
  end

  # -------------------------------------------
  #  Handle inbound events (not used here)
  # -------------------------------------------
  def handle_in(_event, _params, socket) do
    {:noreply, socket}
  end
end
