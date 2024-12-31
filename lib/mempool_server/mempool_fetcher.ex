defmodule MempoolServer.MempoolFetcher do
  use GenServer
  require Logger

  alias MempoolServer.TransactionsCache
  alias MempoolServer.BoxCache
  alias MempoolServer.Constants

  @polling_interval 10_000
  @timeout_opts [hackney: [recv_timeout: 60_000, connect_timeout: 60_000]]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    schedule_poll()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:poll, state) do
    fetch_and_broadcast()
    schedule_poll()
    {:noreply, state}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @polling_interval)
  end

  defp fetch_and_broadcast do
    # 1. Fetch all mempool transactions
    transactions = fetch_all_mempool_transactions()

    # 2. Remove transactions from the timestamp cache that are no longer in mempool
    new_tx_ids = Enum.map(transactions, & &1["id"])
    TransactionsCache.remove_unobserved_transactions(new_tx_ids)

    # 3. Gather all box IDs (both inputs & outputs) so we know what's relevant this cycle
    output_box_ids = collect_output_box_ids(transactions)
    input_box_ids = collect_input_box_ids(transactions)
    all_box_ids = (output_box_ids ++ input_box_ids) |> Enum.uniq()

    # 4. Remove from BoxCache any boxes not in current mempool
    BoxCache.remove_unobserved_boxes(all_box_ids)

    # 5. For each box_id, if not in cache, we need to fetch from the node
    missing_box_ids =
      all_box_ids
      |> Enum.filter(fn box_id -> BoxCache.get_box(box_id) == nil end)

    # 6. Fetch only the missing boxes via batch calls
    newly_fetched_boxes = fetch_boxes_by_ids(missing_box_ids)

    # 7. Store newly fetched boxes in the BoxCache
    Enum.each(newly_fetched_boxes, fn box ->
      BoxCache.put_box(box["boxId"], box)
    end)

    # 8. Enhance transactions: combine with BoxCache data & add creation timestamps
    enriched_transactions =
      transactions
      |> enhance_transactions()
      |> add_creation_timestamps()

    # 8.5. Store the entire mempool transaction set in the TransactionsCache
    TransactionsCache.put_all_transactions(enriched_transactions)

    # 9. Broadcast final results
    broadcast_all_transactions(enriched_transactions)
    broadcast_sigmausd_transactions(enriched_transactions)
  end

  defp fetch_all_mempool_transactions(offset \\ 0, transactions \\ []) do
    url = "#{Constants.node_url()}/transactions/unconfirmed?limit=10000&offset=#{offset}"

    case HTTPoison.get(url, [], @timeout_opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, data} = Jason.decode(body)

        if length(data) == 10_000 do
          fetch_all_mempool_transactions(offset + 10_000, transactions ++ data)
        else
          transactions ++ data
        end

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Error fetching mempool transactions: #{inspect(reason)}")
        transactions
    end
  end

  defp collect_output_box_ids(transactions) do
    transactions
    |> Enum.flat_map(fn tx -> tx["outputs"] || [] end)
    |> Enum.map(& &1["boxId"])
    |> Enum.uniq()
  end

  defp collect_input_box_ids(transactions) do
    transactions
    |> Enum.flat_map(fn tx -> tx["inputs"] || [] end)
    |> Enum.map(& &1["boxId"])
    |> Enum.uniq()
  end

  defp fetch_boxes_by_ids([]), do: []
  defp fetch_boxes_by_ids(box_ids) do
    box_ids
    |> Enum.chunk_every(100)
    |> Enum.flat_map(&fetch_boxes_batch/1)
  end

  defp fetch_boxes_batch(box_ids_chunk) do
    url = "#{Constants.node_url()}/utxo/withPool/byIds"
    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    body = Jason.encode!(box_ids_chunk)

    case HTTPoison.post(url, body, headers, @timeout_opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, boxes} -> boxes
          _ -> []
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        Logger.error("Error fetching boxes (HTTP #{status_code}): #{response_body}")
        []

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Error fetching boxes: #{inspect(reason)}")
        []
    end
  end

  defp enhance_transactions(transactions) do
    Enum.map(transactions, &enhance_transaction/1)
  end

  defp enhance_transaction(transaction) do
    inputs = transaction["inputs"] || []

    enhanced_inputs =
      Enum.map(inputs, fn input ->
        box_id = input["boxId"]
        case BoxCache.get_box(box_id) do
          nil ->
            input

          box_data ->
            Map.merge(input, box_data)
        end
      end)

    Map.put(transaction, "inputs", enhanced_inputs)
  end

  defp add_creation_timestamps(transactions) do
    Enum.map(transactions, fn tx ->
      tx_id = tx["id"]

      creation_ts =
        case TransactionsCache.get_timestamp(tx_id) do
          nil ->
            now_ms = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
            TransactionsCache.put_timestamp(tx_id, now_ms)
            now_ms

          existing_ts ->
            existing_ts
        end

      Map.put(tx, "creationTimestamp", creation_ts)
    end)
  end

  defp broadcast_all_transactions(transactions) do
    MempoolServerWeb.Endpoint.broadcast!(
      "mempool:transactions",
      "all_transactions",
      %{transactions: transactions}
    )
  end

  defp broadcast_sigmausd_transactions(transactions) do
    sigmausd_transactions =
      Enum.filter(transactions, &transaction_has_sigmausd_output?/1)

    MempoolServerWeb.Endpoint.broadcast!(
      "mempool:sigmausd_transactions",
      "sigmausd_transactions",
      %{transactions: sigmausd_transactions}
    )
  end

  defp transaction_has_sigmausd_output?(transaction) do
    outputs = transaction["outputs"] || []
    Enum.any?(outputs, fn output ->
      output["ergoTree"] == Constants.sigmausd_ergo_tree()
    end)
  end
end
