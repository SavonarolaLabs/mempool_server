defmodule MempoolServer.MempoolFetcher do
  use GenServer
  require Logger

  @node_url "http://213.239.193.208:9053"
  @polling_interval 10_000

  # The ErgoTree of the SigmaUSD address, as provided
  @sigmausd_ergo_tree "102a0400040004000e20011d3364de07e5a26f0c4eef0852cddb387039a921b7154ef3cab22c6eda887f0400040204020400040004020500050005c8010500050005feffffffffffffffff0105000580897a05000580897a040405c80104c0933805c00c0580a8d6b907050005c8010580dac40905000500040404040500050005a0060101050005a0060100040004000e20239c170b7e82f94e6b05416f14b8a2a57e0bfff0e3c93f4abbcd160b6a5b271ad801d601db6501fed1ec9591b172017300d821d602b27201730100d603938cb2db63087202730200017303d604b2a5730400d605c17204d606db6308a7d607b27206730500d6088c720702d609db63087204d60ab27209730600d60b8c720a02d60c947208720bd60db27206730700d60e8c720d02d60fb27209730800d6108c720f02d61194720e7210d612e4c6a70505d613e4c672040505d614e4c6a70405d615e4c672040405d616b2a5730900d617e4c672160405d61895720c730a7217d61995720c7217730bd61ac1a7d61be4c672160505d61c9de4c672020405730cd61da2a1721a9c7214721c730dd61e9572119ca1721c95937214730e730f9d721d72147218d801d61e99721a721d9c9593721e7310731195937212731273139d721e72127219d61f9d9c721e7e7314057315d6209c7215721cd6219591a3731673177318d62295937220731972219d9c7205731a7220edededed7203ededededed927205731b93c27204c2a7edec720c7211efed720c7211ed939a720872129a720b7213939a720e72149a72107215edededed939a721472187215939a721272197213939a721a721b7205927215731c927213731deded938c720f018c720d01938c720a018c720701938cb27209731e00018cb27206731f000193721b9a721e958f721f7320f0721f721f957211959172187321927222732273239591721973249072227221927222732572037326938cb2db6308b2a4732700732800017329"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_state) do
    schedule_poll()
    {:ok, %{}}
  end

  def handle_info(:poll, state) do
    fetch_and_broadcast()
    schedule_poll()
    {:noreply, state}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @polling_interval)
  end

  defp fetch_and_broadcast() do
    transactions = fetch_all_mempool_transactions()

    # Build a map of boxId to box data from mempool outputs
    box_map = build_box_map(transactions)

    # Collect all unique input boxIds
    input_box_ids = collect_input_box_ids(transactions)

    # Fetch all input box data using the batch API
    input_boxes = fetch_boxes_by_ids(input_box_ids)

    # Merge input box data into a single map
    input_box_map = Map.new(input_boxes, fn box -> {box["boxId"], box} end)

    # Combine mempool box map and input box map
    combined_box_map = Map.merge(box_map, input_box_map)

    # Enhance transactions with full input data
    enhanced_transactions = enhance_transactions(transactions, combined_box_map)

    broadcast_all_transactions(enhanced_transactions)
    broadcast_sigmausd_transactions(enhanced_transactions)
  end

  defp fetch_all_mempool_transactions(offset \\ 0, transactions \\ []) do
    url = "#{@node_url}/transactions/unconfirmed?limit=10000&offset=#{offset}"

    case HTTPoison.get(url) do
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
    # Split box_ids into chunks to avoid exceeding request size limits
    box_ids
    |> Enum.chunk_every(100)
    |> Enum.flat_map(&fetch_boxes_batch/1)
  end

  defp fetch_boxes_batch(box_ids_chunk) do
    url = "#{@node_url}/utxo/withPool/byIds"

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
        # Box data not found, return input as is
        input

      box_data ->
        # Merge box data into input
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

  # Function to broadcast SigmaUSD transactions
  defp broadcast_sigmausd_transactions(transactions) do
    sigmausd_transactions = Enum.filter(transactions, &transaction_has_sigmausd_output?/1)

    MempoolServerWeb.Endpoint.broadcast!(
      "mempool:sigmausd_transactions",
      "sigmausd_transactions",
      %{transactions: sigmausd_transactions}
    )
  end

  # Checks if the transaction has outputs to the SigmaUSD address
  defp transaction_has_sigmausd_output?(transaction) do
    outputs = transaction["outputs"] || []

    Enum.any?(outputs, fn output ->
      output["ergoTree"] == @sigmausd_ergo_tree
    end)
  end
end
