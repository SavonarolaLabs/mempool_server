defmodule MempoolServer.MempoolFetcher do
  use GenServer
  require Logger

  alias MempoolServer.TransactionsCache
  alias MempoolServer.BoxCache
  alias MempoolServer.Constants

  # Poll /info every second
  @polling_interval 1_000
  @timeout_opts [hackney: [recv_timeout: 60_000, connect_timeout: 60_000]]

  def start_link(_opts) do
    GenServer.start_link(
      __MODULE__,
      %{
        last_seen_message_time: nil,
        previous_full_header_id: nil,
        # We'll keep the most recent block's confirmed transactions here
        last_confirmed_transactions: []
      },
      name: __MODULE__
    )
  end

  @impl true
  def init(state) do
    schedule_poll()
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    new_state = poll_info(state)
    schedule_poll()
    {:noreply, new_state}
  end

  # -----------------------------------------------------
  # 1. Poll /info once per second.
  #    - If lastSeenMessageTime changed => fetch mempool (unconfirmed) transactions.
  #    - If previousFullHeaderId changed => fetch confirmed transactions from the block.
  # -----------------------------------------------------
  defp poll_info(state) do
    url = "https://ergfi.xyz:9443/info"

    case HTTPoison.get(url, [], @timeout_opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        with {:ok, info_data} <- Jason.decode(body) do
          last_seen_message_time = info_data["lastSeenMessageTime"]
          prev_full_header_id    = info_data["previousFullHeaderId"]

          # 1) Possibly fetch Mempool TXs
          unconfirmed_transactions =
            if last_seen_message_time != state.last_seen_message_time do
              fetch_and_enrich_mempool_transactions()
            else
              # If there's no change to lastSeenMessageTime,
              # we can reuse the existing mempool from the cache.
              # So we read from TransactionsCache:
              TransactionsCache.get_all_transactions()
            end

          # 2) Possibly fetch Confirmed TXs
          last_confirmed_transactions =
            if prev_full_header_id != state.previous_full_header_id do
              fetch_and_enrich_confirmed_transactions(prev_full_header_id)
            else
              # If header didn't change, we broadcast an empty set for confirmed
              []
            end

          # 3) Broadcast both unconfirmed and confirmed in the **same** payload
          broadcast_all_transactions(unconfirmed_transactions, last_confirmed_transactions)
          broadcast_sigmausd_transactions(unconfirmed_transactions, last_confirmed_transactions)

          # Update state
          %{
            state
            | last_seen_message_time: last_seen_message_time,
              previous_full_header_id: prev_full_header_id,
              last_confirmed_transactions: last_confirmed_transactions
          }
        else
          _ ->
            Logger.error("Failed to decode /info response body or missing keys.")
            state
        end

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Error fetching /info: #{inspect(reason)}")
        state
    end
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @polling_interval)
  end

  # ------------------------------------------------------------------
  # 2. Fetch & enrich Mempool Transactions
  # ------------------------------------------------------------------
  defp fetch_and_enrich_mempool_transactions do
    # 1. Fetch all mempool transactions from node
    transactions = fetch_all_mempool_transactions()

    # 2. Remove stale transactions from timestamp cache
    new_tx_ids = Enum.map(transactions, & &1["id"])
    TransactionsCache.remove_unobserved_transactions(new_tx_ids)

    # 3. Gather all relevant box IDs
    output_box_ids = collect_output_box_ids(transactions)
    input_box_ids  = collect_input_box_ids(transactions)
    all_box_ids    = (output_box_ids ++ input_box_ids) |> Enum.uniq()

    # 4. Remove stale boxes from BoxCache
    BoxCache.remove_unobserved_boxes(all_box_ids)

    # 5. Identify which box IDs need fetching
    missing_box_ids =
      all_box_ids
      |> Enum.filter(fn box_id -> BoxCache.get_box(box_id) == nil end)

    # 6. Fetch missing boxes
    newly_fetched_boxes = fetch_boxes_by_ids(missing_box_ids)

    # 7. Store them in BoxCache
    Enum.each(newly_fetched_boxes, fn box ->
      BoxCache.put_box(box["boxId"], box)
    end)

    # 8. Enhance & add creation timestamps
    enriched =
      transactions
      |> enhance_transactions()
      |> add_creation_timestamps()

    # 9. Cache them so we can quickly reuse them
    TransactionsCache.put_all_transactions(enriched)
    enriched
  end

  # ------------------------------------------------------------------
  # 3. Fetch & enrich Confirmed Transactions
  # ------------------------------------------------------------------
  defp fetch_and_enrich_confirmed_transactions(previous_full_header_id) do
    url = "#{Constants.node_url()}/blocks/#{previous_full_header_id}/transactions"

    case HTTPoison.get(url, [], @timeout_opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"headerId" => _header_id, "transactions" => confirmed_txs}} ->
            # We have confirmed_txs in the "transactions" field.
            # Let's enhance those transactions before returning them.
            enhance_transactions(confirmed_txs)

          _ ->
            Logger.error("Unexpected JSON structure when fetching block transactions.")
            []
        end

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Error fetching confirmed transactions: #{inspect(reason)}")
        []
    end
  end


  # ------------------------------------------------------------------
  # Broadcast both unconfirmed & confirmed in the same message
  # ------------------------------------------------------------------
  defp broadcast_all_transactions(unconfirmed, confirmed) do
    MempoolServerWeb.Endpoint.broadcast!(
      "mempool:transactions",
      "all_transactions",
      %{
        unconfirmed_transactions: unconfirmed,
        confirmed_transactions: confirmed
      }
    )
  end

  defp broadcast_sigmausd_transactions(unconfirmed, confirmed) do
    sigmausd_unconfirmed =
      Enum.filter(unconfirmed, &transaction_has_sigmausd_output?/1)

    sigmausd_confirmed =
      Enum.filter(confirmed, &transaction_has_sigmausd_output?/1)

    MempoolServerWeb.Endpoint.broadcast!(
      "mempool:sigmausd_transactions",
      "sigmausd_transactions",
      %{
        unconfirmed_transactions: sigmausd_unconfirmed,
        confirmed_transactions: sigmausd_confirmed
      }
    )
  end

  # --- Same helpers for fetching mempool, boxes, & enhancing ---

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
          nil -> input
          box_data -> Map.merge(input, box_data)
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

  defp transaction_has_sigmausd_output?(transaction) do
    outputs = transaction["outputs"] || []
    Enum.any?(outputs, fn output ->
      output["ergoTree"] == Constants.sigmausd_ergo_tree()
    end)
  end
end
