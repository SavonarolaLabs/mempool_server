defmodule MempoolServerWeb.MempoolChannel do
  use Phoenix.Channel
  alias MempoolServer.TransactionsCache
  alias MempoolServer.TxHistoryCache
  alias MempoolServer.Constants
  alias MempoolServer.ErgoTreeSubscriptionsCache
  alias MempoolServer.OracleBoxesUtil
  alias MempoolServer.ErgoNode
  alias MempoolServer.NodeCache

  def join("mempool:info", _msg, socket) do
    {:ok, NodeCache.get_node_info(), socket}
  end

  def join("mempool:oracle_boxes", _msg, socket) do
    {:ok, OracleBoxesUtil.oracle_boxes_payload(), socket}
  end

  def join("mempool:transactions", _msg, socket) do
    txs = TransactionsCache.get_all_transactions()
    {:ok, %{unconfirmed_transactions: txs, confirmed_transactions: []}, socket}
  end

  def join("mempool:" <> name, _msg, socket) do
    match = Enum.find(Constants.filtered_transactions(), fn ft -> ft.name == name end)
    if match do
      unconfirmed = TransactionsCache.get_transactions_by_ergo_trees(match.ergo_trees)
      history = TxHistoryCache.get_recent(name)
      {:ok, %{unconfirmed_transactions: unconfirmed, confirmed_transactions: [], history: history}, socket}
    else
      {:error, %{reason: "Invalid channel name"}}
    end
  end

  def join("ergotree:" <> ergo_tree, _msg, socket) do
    ErgoTreeSubscriptionsCache.subscribe(ergo_tree)
    unconfirmed = TransactionsCache.get_transactions_by_ergo_trees([ergo_tree])
    {:ok, %{unconfirmed_transactions: unconfirmed, confirmed_transactions: []}, assign(socket, :ergo_tree, ergo_tree)}
  end

  def handle_in("submit_tx", %{"transaction" => tx}, socket) do
    case ErgoNode.check_transaction(tx) do
      {:ok, _} ->
        case ErgoNode.submit_transaction(tx) do
          {:ok, r} ->
            {:reply, {:ok, %{status: "success", detail: "Transaction submitted", response: r}}, socket}

          {:error, e} ->
            {:reply, {:error, %{status: "error", detail: "Transaction submission failed", error: e}}, socket}
        end
      {:error, e} ->
        {:reply, {:error, %{status: "error", detail: "Transaction check failed", error: e}}, socket}
    end
  end

  def handle_in(_event, _params, socket) do
    {:noreply, socket}
  end

  def terminate(_reason, socket) do
    if socket.assigns[:ergo_tree] do
      ErgoTreeSubscriptionsCache.unsubscribe(socket.assigns[:ergo_tree])
    end
    :ok
  end
end
