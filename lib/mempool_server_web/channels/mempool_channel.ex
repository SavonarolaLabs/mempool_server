defmodule MempoolServerWeb.MempoolChannel do
  use Phoenix.Channel

  alias MempoolServer.TransactionsCache

  # -------------------------------------------
  #  Join "mempool:transactions"
  # -------------------------------------------
  def join("mempool:transactions", _message, socket) do
    # 1) Retrieve any unconfirmed transactions from your cache
    all_transactions = TransactionsCache.get_all_transactions()

    # 2) Construct your initial payload.
    #    Optionally include confirmed_transactions: [] if you like
    reply_payload = %{
      unconfirmed_transactions: all_transactions,
      confirmed_transactions: []
    }

    # 3) Return the payload in the 'ok' tuple, so the client
    #    sees it immediately in the .receive('ok', resp) callback
    {:ok, reply_payload, socket}
  end

  # -------------------------------------------
  #  Join "mempool:sigmausd_transactions"
  # -------------------------------------------
  def join("mempool:sigmausd_transactions", _message, socket) do
    # 1) Retrieve any SigmaUSD transactions from your cache
    sigmausd_transactions = TransactionsCache.get_sigmausd_transactions()

    # 2) Build your initial payload
    reply_payload = %{
      unconfirmed_transactions: sigmausd_transactions,
      confirmed_transactions: []
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
