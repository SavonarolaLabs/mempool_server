defmodule MempoolServer.MempoolFetcher do
    use GenServer
    require Logger
  
    @node_url "http://213.239.193.208:9053"
    @polling_interval 5000
    @token_bank_nft "7d672d1def471720ca5782fd6473e47e796d9ac0c138d9911346f118b2f6d9d9"
  
    def start_link(_opts) do
      GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
    end
  
    def init(_state) do
      # Schedule the first poll
      schedule_poll()
      {:ok, %{}}
    end
  
    def handle_info(:poll, state) do
      new_state = fetch_and_broadcast(state)
      schedule_poll()
      {:noreply, new_state}
    end
  
    defp schedule_poll do
      Process.send_after(self(), :poll, @polling_interval)
    end
  
    defp fetch_and_broadcast(state) do
      transactions = fetch_all_mempool_transactions()
      build_and_broadcast_bank_box_chains(transactions)
      state
    end
  
    defp fetch_all_mempool_transactions(offset \\ 0, transactions \\ []) do
      url = "#{@node_url}/transactions/unconfirmed?limit=10000&offset=#{offset}"
      case HTTPoison.get(url) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          {:ok, data} = Jason.decode(body)
          if length(data) == 10000 do
            fetch_all_mempool_transactions(offset + 10000, transactions ++ data)
          else
            transactions ++ data
          end
        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("Error fetching mempool transactions: #{inspect(reason)}")
          transactions
      end
    end
  
    defp build_and_broadcast_bank_box_chains(transactions) do
      chains = build_bank_box_chains(transactions)
      # Broadcast the chains to the Phoenix channel
      MempoolServerWeb.Endpoint.broadcast!("mempool:transactions", "bank_box_chains", %{chains: chains})
    end
  
    defp build_bank_box_chains(transactions) do
      # Initialize maps
      boxes = %{}    # box_id => box_info
      tx_map = %{}   # tx_id => transaction
    
      # Build the tx_map
      tx_map = Enum.reduce(transactions, %{}, fn tx, acc ->
        Map.put(acc, tx["id"], tx)
      end)
    
      # Build the boxes map
      boxes = Enum.reduce(transactions, %{}, fn tx, acc ->
        # Process outputs
        Enum.reduce(tx["outputs"], acc, fn output, acc2 ->
          Map.put(acc2, output["boxId"], %{
            box: output,
            created_by: tx["id"],
            spent_by: []
          })
        end)
      end)
    
      # Map inputs to spending transactions
      boxes = Enum.reduce(transactions, boxes, fn tx, acc ->
        Enum.reduce(tx["inputs"], acc, fn input, acc2 ->
          Map.update(acc2, input["boxId"], %{
            box: %{"boxId" => input["boxId"]},
            created_by: nil,
            spent_by: [tx["id"]]
          }, fn existing ->
            Map.update!(existing, :spent_by, fn spent_by -> [tx["id"] | spent_by] end)
          end)
        end)
      end)
    
      # Identify bank boxes
      bank_boxes =
        boxes
        |> Enum.filter(fn {_box_id, box_info} ->
          Enum.any?(box_info.box["assets"] || [], fn asset ->
            asset["tokenId"] == @token_bank_nft
          end)
        end)
        |> Enum.map(fn {box_id, _box_info} -> box_id end)
    
      # Build chains starting from the latest bank boxes
      {chains, _, _} =
        Enum.reduce(bank_boxes, {[], MapSet.new(), MapSet.new()}, fn bank_box_id, {chains_acc, visited_boxes, visited_txs} ->
          {chain, visited_boxes_new, visited_txs_new} =
            traverse_bank_box_chain(bank_box_id, [], visited_boxes, visited_txs, boxes, tx_map)
          {[chain | chains_acc], visited_boxes_new, visited_txs_new}
        end)
    
      chains
    end

    defp traverse_bank_box_chain(box_id, chain, visited_boxes, visited_txs, boxes, tx_map) do
      if MapSet.member?(visited_boxes, box_id) do
        {chain, visited_boxes, visited_txs}
      else
        visited_boxes = MapSet.put(visited_boxes, box_id)
        box_info = Map.get(boxes, box_id)
    
        if is_nil(box_info) do
          {chain, visited_boxes, visited_txs}
        else
          chain = chain ++ [%{type: "box", box: box_info.box}]
    
          if length(box_info.spent_by) > 0 do
            # Sort conflicting transactions by fee (higher fee first)
            sorted_tx_ids =
              box_info.spent_by
              |> Enum.map(&Map.get(tx_map, &1))
              |> Enum.filter(& &1)
              |> Enum.sort_by(fn tx -> String.to_integer(tx["fee"] || "0") end, :desc)
              |> Enum.map(& &1["id"])
    
            Enum.reduce(sorted_tx_ids, {chain, visited_boxes, visited_txs}, fn tx_id, {chain_acc, visited_boxes_acc, visited_txs_acc} ->
              if MapSet.member?(visited_txs_acc, tx_id) do
                {chain_acc, visited_boxes_acc, visited_txs_acc}
              else
                visited_txs_acc = MapSet.put(visited_txs_acc, tx_id)
                tx = Map.get(tx_map, tx_id)
    
                if tx do
                  is_main_branch = tx_id == List.first(sorted_tx_ids)
                  chain_acc = chain_acc ++ [%{type: "tx", tx: tx, isMainBranch: is_main_branch}]
    
                  Enum.reduce(tx["outputs"], {chain_acc, visited_boxes_acc, visited_txs_acc}, fn output, {chain_out, visited_boxes_out, visited_txs_out} ->
                    if Enum.any?(output["assets"] || [], fn asset -> asset["tokenId"] == @token_bank_nft end) do
                      traverse_bank_box_chain(output["boxId"], chain_out, visited_boxes_out, visited_txs_out, boxes, tx_map)
                    else
                      {chain_out, visited_boxes_out, visited_txs_out}
                    end
                  end)
                else
                  {chain_acc, visited_boxes_acc, visited_txs_acc}
                end
              end
            end)
          else
            {chain, visited_boxes, visited_txs}
          end
        end
      end
    end
    
  end
  