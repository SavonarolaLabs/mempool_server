defmodule MempoolServer.MempoolFetcher do
  use GenServer
  require Logger

  alias MempoolServer.TransactionsCache
  alias MempoolServer.BoxCache
  alias MempoolServer.Constants
  alias MempoolServer.TxHistoryCache

  @polling_interval 1_000
  @timeout_opts [hackney: [recv_timeout: 60_000, connect_timeout: 60_000]]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{
      last_seen_message_time: nil,
      best_full_header_id: nil,
      last_confirmed_transactions: []
    }, name: __MODULE__)
  end

  @impl true
  def init(state) do
    # Schedule our periodic poll
    schedule_poll()

    # We use :continue so that init/1 returns immediately,
    # then do the "history load" in handle_continue/2
    {:ok, state, {:continue, :init_history}}
  end

  @impl true
  def handle_continue(:init_history, state) do
    # Force the TxHistoryCache to load (and thereby create its ETS table) once.
    TxHistoryCache.update_history("sigmausd_transactions")
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, state) do
    new_state = poll_info(state)
    schedule_poll()
    {:noreply, new_state}
  end

  # -----------------------------------------------------
  # Poll /info once per second. If lastSeenMessageTime
  # has *not* changed, do nothing at all.
  # Otherwise:
  #   - fetch mempool (unconfirmed) transactions
  #   - if bestFullHeaderId changed => fetch confirmed transactions
  #   - if bestFullHeaderId changed => update TxHistory
  # -----------------------------------------------------
  defp poll_info(state) do
    url = "#{Constants.node_url()}/info"

    case HTTPoison.get(url, [], @timeout_opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        with {:ok, info_data} <- Jason.decode(body) do
          new_last_seen = info_data["lastSeenMessageTime"]
          new_header_id = info_data["bestFullHeaderId"]

          # If neither changed, do nothing
          if new_last_seen == state.last_seen_message_time and
             new_header_id == state.best_full_header_id do
            state
          else
            # Possibly fetch newly confirmed transactions if the header changed
            confirmed_txs =
              if new_header_id != state.best_full_header_id do
                fetch_and_enrich_confirmed_transactions(new_header_id)
              else
                []
              end

            # If bestFullHeaderId changed, update the TxHistory
            if new_header_id != state.best_full_header_id do
              TxHistoryCache.update_history("sigmausd_transactions")
            end

            # Fetch & broadcast new mempool transactions
            unconfirmed_txs = fetch_and_enrich_mempool_transactions()
            broadcast_all_transactions(unconfirmed_txs, confirmed_txs, info_data)
            broadcast_filtered_transactions(unconfirmed_txs, confirmed_txs, info_data)

            # Update local state
            %{
              state
              | last_seen_message_time: new_last_seen,
                best_full_header_id: new_header_id,
                last_confirmed_transactions: confirmed_txs
            }
          end
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
  # Fetch & enrich Mempool Transactions
  # ------------------------------------------------------------------
  defp fetch_and_enrich_mempool_transactions do
    # 1. Fetch all mempool transactions
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
  # Fetch & enrich Confirmed Transactions
  # ------------------------------------------------------------------
  defp fetch_and_enrich_confirmed_transactions(best_full_header_id) do
    url = "#{Constants.node_url()}/blocks/#{best_full_header_id}/transactions"

    case HTTPoison.get(url, [], @timeout_opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"headerId" => _header_id, "transactions" => confirmed_txs}} ->
            enhance_transactions(confirmed_txs)

          _ ->
            Logger.error("Unexpected JSON structure for block transactions.")
            []
        end

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Error fetching confirmed transactions: #{inspect(reason)}")
        []
    end
  end

  # ------------------------------------------------------------------
  # Broadcast
  # ------------------------------------------------------------------
  defp broadcast_all_transactions(unconfirmed, confirmed, info_data) do
    MempoolServerWeb.Endpoint.broadcast!(
      "mempool:transactions",
      "all_transactions",
      %{
        unconfirmed_transactions: unconfirmed,
        confirmed_transactions: confirmed,
        info: info_data
      }
    )
  end

  defp broadcast_filtered_transactions(unconfirmed, confirmed, info_data) do
    Enum.each(Constants.filtered_transactions(), fn %{name: name, ergo_trees: trees} ->
      unconfirmed_filtered = Enum.filter(unconfirmed, &transaction_has_output?(&1, trees))
      confirmed_filtered = Enum.filter(confirmed, &transaction_has_output?(&1, trees))
  
      MempoolServerWeb.Endpoint.broadcast!(
        "mempool:#{name}",
        name,
        %{
          unconfirmed_transactions: unconfirmed_filtered,
          confirmed_transactions: confirmed_filtered,
          info: info_data
        }
      )
    end)
  end

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------
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

  defp transaction_has_output?(transaction, ergo_trees) do
    outputs = transaction["outputs"] || []
    Enum.any?(outputs, fn output ->
      output["ergoTree"] in ergo_trees
    end)
  end
end
