defmodule MempoolServerWeb.BlockchainController do
    use MempoolServerWeb, :controller
  
    def unspent_by_address(conn, %{"address" => address, "offset" => offset, "limit" => limit, "sortDirection" => sort_direction, "includeUnconfirmed" => include_unconfirmed, "excludeMempoolSpent" => exclude_mempool_spent}) do
      offset = String.to_integer(offset)
      limit = String.to_integer(limit)
      include_unconfirmed = String.downcase(include_unconfirmed) == "true"
      exclude_mempool_spent = String.downcase(exclude_mempool_spent) == "true"
  
      utxos = MempoolServer.Blockchain.get_unspent_by_address(address, offset, limit, sort_direction, include_unconfirmed, exclude_mempool_spent)
      json(conn, utxos)
    end
  
    def unspent_by_address(conn, %{"address" => address}) do
      utxos = MempoolServer.Blockchain.get_unspent_by_address(address)
      json(conn, utxos)
    end
  end