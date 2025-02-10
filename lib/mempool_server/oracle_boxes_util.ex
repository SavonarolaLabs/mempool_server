defmodule MempoolServer.OracleBoxesUtil do
    alias MempoolServer.BoxHistoryCache
    alias MempoolServer.TransactionsCache
    alias MempoolServer.Constants
  
    def oracle_boxes_payload do
      all_boxes = BoxHistoryCache.get_all_boxes()
      confirmed =
        Enum.reduce(all_boxes, %{}, fn {n, bs}, acc ->
          Map.put(acc, "confirmed_#{n}", bs)
        end)
      unconfirmed =
        Enum.reduce(Constants.boxes_by_token_id(), %{}, fn %{name: n, token_id: t}, acc ->
          txs = TransactionsCache.get_all_transactions()
          boxes =
            txs
            |> Enum.flat_map(fn x -> x["outputs"] || [] end)
            |> Enum.filter(fn o ->
              Enum.any?(o["assets"] || [], fn a -> a["tokenId"] == t end)
            end)
          Map.put(acc, "unconfirmed_#{n}", boxes)
        end)
      Map.merge(confirmed, unconfirmed)
    end
  end
  