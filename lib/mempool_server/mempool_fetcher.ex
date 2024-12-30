defmodule MempoolServer.MempoolFetcher do
  use GenServer
  require Logger

  alias MempoolServer.TransactionsCache
  alias MempoolServer.Constants

  @polling_interval 10_000

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

    # 2. Remove transactions from cache that are no longer in mempool
    new_tx_ids = Enum.map(transactions, & &1["id"])
    TransactionsCache.remove_unobserved_transactions(new_tx_ids)

    # 3. Build a map of boxId to box data from mempool outputs
    box_map = build_box_map(transactions)

    # 4. Collect all unique input boxIds
    input_box_ids = collect_input_box_ids(transactions)

    # 5. Fetch all input box data using the batch API
    input_boxes = fetch_boxes_by_ids(input_box_ids)

    # 6. Merge input box data into a single map
    input_box_map = Map.new(input_boxes, fn box -> {box["boxId"], box} end)

    # 7. Combine mempool box map and input box map
    combined_box_map = Map.merge(box_map, input_box_map)

    # 8. Enhance transactions with full input data, then add creation timestamps
    enriched_transactions =
      transactions
      |> enhance_transactions(combined_box_map)
      |> add_creation_timestamps()

    # 9. Broadcast to channels
    broadcast_all_transactions(enriched_transactions)
    broadcast_sigmausd_transactions(enriched_transactions)
  end

  defp add_creation_timestamps(transactions) do
    Enum.map(transactions, fn tx ->
      tx_id = tx["id"]

      # If not in the cache, store "now" as its creation time
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

  defp fetch_all_mempool_transactions(offset \\ 0, transactions \\ []) do
    url = "#{Constants.node_url()}/transactions/unconfirmed?limit=10000&offset=#{offset}"

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, data} = Jason.decode(body)

        # If we got exactly 10,000, there's possibly more. Keep paginating.
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

  defp build_box_map(transactions) do
    transactions
    |> Enum.flat_map(&(&1["outputs"] || []))
    |> Enum.reduce(%{}, fn output, acc ->
      Map.put(acc, output["boxId"], output)
    end)
  end

  defp collect_input_box_ids(transactions) do
    transactions
    |> Enum.flat_map(&(&1["inputs"] || []))
    |> Enum.map(& &1["boxId"])
    |> Enum.uniq()
  end

  defp fetch_boxes_by_ids(box_ids) do
    box_ids
    |> Enum.chunk_every(100)  # avoid large request payloads
    |> Enum.flat_map(&fetch_boxes_batch/1)
  end

  defp fetch_boxes_batch(box_ids_chunk) do
    url = "#{Constants.node_url()}/utxo/withPool/byIds"
    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    body = Jason.encode!(box_ids_chunk)

    case HTTPoison.post(url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        {:ok, boxes} = Jason.decode(response_body)
        boxes

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        Logger.error("Error fetching boxes: HTTP #{status_code} - #{response_body}")
        []

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Error fetching boxes: #{inspect(reason)}")
        []
    end
  end

  defp enhance_transactions(transactions, box_map) do
    transactions
    |> Enum.map(&enhance_transaction(&1, box_map))
  end

  defp enhance_transaction(transaction, box_map) do
    inputs = transaction["inputs"] || []
    enhanced_inputs = Enum.map(inputs, &enhance_input(&1, box_map))
    Map.put(transaction, "inputs", enhanced_inputs)
  end

  defp enhance_input(input, box_map) do
    box_id = input["boxId"]

    case Map.get(box_map, box_id) do
      nil ->
        # Box data not found, return input as-is
        input

      box_data ->
        # Merge the box data fields into the input
        Map.merge(input, box_data)
    end
  end

  defp broadcast_all_transactions(transactions) do
    MempoolServerWeb.Endpoint.broadcast!(
      "mempool:transactions",
      "all_transactions",
      %{transactions: transactions}
    )
  end

  defp broadcast_sigmausd_transactions(transactions) do
    sigmausd_transactions = Enum.filter(transactions, &transaction_has_sigmausd_output?/1)

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
