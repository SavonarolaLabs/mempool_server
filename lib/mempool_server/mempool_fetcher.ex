defmodule MempoolServer.MempoolFetcher do
  use GenServer
  require Logger
  alias MempoolServer.TransactionsCache
  alias MempoolServer.BoxCache
  alias MempoolServer.TxHistoryCache
  alias MempoolServer.BoxHistoryCache
  alias MempoolServer.ErgoTreeSubscriptionsCache
  alias MempoolServer.Constants
  alias MempoolServer.OracleBoxesUtil
  alias MempoolServer.ErgoNode
  alias MempoolServer.NodeCache

  @polling_interval 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_seen_message_time: nil, best_full_header_id: nil, last_confirmed_transactions: []}, name: __MODULE__)
  end

  def init(state) do
    schedule_poll()
    {:ok, state, {:continue, :init_history}}
  end

  def handle_continue(:init_history, state) do
    TxHistoryCache.update_history("sigmausd_transactions")
    TxHistoryCache.update_history("dexygold_transactions")
    BoxHistoryCache.update_all_history()
    {:noreply, state}
  end

  def handle_info(:poll, state) do
    new_state = poll_info(state)
    schedule_poll()
    {:noreply, new_state}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @polling_interval)
  end

  defp poll_info(state) do
    case ErgoNode.fetch_info() do
      {:ok, info_data} ->
        new_last_seen = info_data["lastSeenMessageTime"]
        new_header_id = info_data["bestFullHeaderId"]

        if new_last_seen == state.last_seen_message_time and new_header_id == state.best_full_header_id do
          state
        else
          broadcast_node_info(info_data)
          NodeCache.put_node_info(info_data)

          confirmed_txs =
            if new_header_id != state.best_full_header_id do
              ErgoNode.fetch_block_transactions(new_header_id)
              |> enhance_transactions()
            else
              []
            end

          if new_header_id != state.best_full_header_id do
            TxHistoryCache.update_history("sigmausd_transactions")
            TxHistoryCache.update_history("dexygold_transactions")
            BoxHistoryCache.update_all_history()
          end

          unconfirmed_txs = fetch_and_enrich_mempool_transactions()
          broadcast_all_transactions(unconfirmed_txs, confirmed_txs, info_data)
          broadcast_filtered_transactions(unconfirmed_txs, confirmed_txs, info_data)
          broadcast_tree_transactions(unconfirmed_txs, confirmed_txs, info_data)
          broadcast_oracle_boxes()

          %{
            state
            | last_seen_message_time: new_last_seen,
              best_full_header_id: new_header_id,
              last_confirmed_transactions: confirmed_txs
          }
        end

      _ ->
        state
    end
  end

  defp fetch_and_enrich_mempool_transactions do
    transactions = fetch_all_mempool_transactions()
    new_tx_ids = Enum.map(transactions, & &1["id"])
    TransactionsCache.remove_unobserved_transactions(new_tx_ids)

    input_box_ids =
      transactions
      |> Enum.flat_map(fn tx -> tx["inputs"] || [] end)
      |> Enum.map(& &1["boxId"])
      |> Enum.uniq()

    output_boxes =
      transactions
      |> Enum.flat_map(fn tx -> tx["outputs"] || [] end)
      |> Enum.uniq_by(& &1["boxId"])

    Enum.each(output_boxes, fn b -> BoxCache.put_box(b["boxId"], b) end)

    missing_input_box_ids = Enum.filter(input_box_ids, fn id -> BoxCache.get_box(id) == nil end)
    new_boxes = ErgoNode.fetch_boxes_by_ids(missing_input_box_ids)
    Enum.each(new_boxes, fn b -> BoxCache.put_box(b["boxId"], b) end)

    enriched =
      transactions
      |> enhance_transactions()
      |> add_creation_timestamps()

    TransactionsCache.put_all_transactions(enriched)
    enriched
  end

  defp fetch_all_mempool_transactions(offset \\ 0, acc \\ []) do
    case ErgoNode.fetch_mempool_transactions(offset) do
      {:ok, data} ->
        if length(data) == 10_000 do
          fetch_all_mempool_transactions(offset + 10_000, acc ++ data)
        else
          acc ++ data
        end

      _ ->
        acc
    end
  end

  defp broadcast_node_info(info_data) do
    MempoolServerWeb.Endpoint.broadcast!("mempool:info", "node_info", info_data)
  end

  defp broadcast_all_transactions(u, c, info) do
    MempoolServerWeb.Endpoint.broadcast!("mempool:transactions", "all_transactions", %{unconfirmed_transactions: u, confirmed_transactions: c, info: info})
  end

  defp broadcast_filtered_transactions(u, c, info) do
    Enum.each(Constants.filtered_transactions(), fn %{name: n, ergo_trees: t} ->
      uf = Enum.filter(u, &transaction_has_output?(&1, t))
      cf = Enum.filter(c, &transaction_has_output?(&1, t))
      MempoolServerWeb.Endpoint.broadcast!("mempool:#{n}", n, %{unconfirmed_transactions: uf, confirmed_transactions: cf, info: info})
    end)
  end

  defp broadcast_tree_transactions(u, c, info) do
    ErgoTreeSubscriptionsCache.get_all_subscriptions()
    |> Enum.each(fn {ergo_tree, _} ->
      uf = Enum.filter(u, &transaction_has_output?(&1, [ergo_tree]))
      cf = Enum.filter(c, &transaction_has_output?(&1, [ergo_tree]))
      if uf != [] or cf != [] do
        MempoolServerWeb.Endpoint.broadcast!("ergotree:#{ergo_tree}", "transactions", %{unconfirmed_transactions: uf, confirmed_transactions: cf, info: info})
      end
    end)
  end

  defp broadcast_oracle_boxes do
    payload = OracleBoxesUtil.oracle_boxes_payload()
    MempoolServerWeb.Endpoint.broadcast!("mempool:oracle_boxes", "oracle_boxes", payload)
  end

  defp enhance_transactions(txs) do
    Enum.map(txs, fn tx ->
      inputs = tx["inputs"] || []

      enhanced =
        Enum.map(inputs, fn i ->
          box_data = BoxCache.get_box(i["boxId"])
          if box_data, do: Map.merge(i, box_data), else: i
        end)

      Map.put(tx, "inputs", enhanced)
    end)
  end

  defp add_creation_timestamps(txs) do
    Enum.map(txs, fn tx ->
      id = tx["id"]
      ts = TransactionsCache.get_timestamp(id)

      if ts do
        Map.put(tx, "creationTimestamp", ts)
      else
        now_ms = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
        TransactionsCache.put_timestamp(id, now_ms)
        Map.put(tx, "creationTimestamp", now_ms)
      end
    end)
  end

  defp transaction_has_output?(tx, trees) do
    Enum.any?(tx["outputs"] || [], fn o -> o["ergoTree"] in trees end)
  end
end
