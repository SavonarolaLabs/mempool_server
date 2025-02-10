defmodule MempoolServer.ErgoNode do
    require Logger
    alias MempoolServer.Constants
  
    @timeout_opts [hackney: [recv_timeout: 60000, connect_timeout: 60000]]
  
    def fetch_info do
      url = "#{Constants.node_url()}/info"
      case HTTPoison.get(url, [], @timeout_opts) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, data} -> {:ok, data}
            _ -> :error
          end
        _ -> :error
      end
    end
  
    def fetch_block_transactions(header_id) do
      url = "#{Constants.node_url()}/blocks/#{header_id}/transactions"
      case HTTPoison.get(url, [], @timeout_opts) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"transactions" => txs}} -> txs
            _ -> []
          end
        _ -> []
      end
    end
  
    def fetch_mempool_transactions(offset) do
      url = "#{Constants.node_url()}/transactions/unconfirmed?limit=10000&offset=#{offset}"
      case HTTPoison.get(url, [], @timeout_opts) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, data} -> {:ok, data}
            _ -> {:ok, []}
          end
        _ -> {:ok, []}
      end
    end
  
    def fetch_boxes_by_ids([]), do: []
    def fetch_boxes_by_ids(box_ids) do
      Enum.flat_map(Enum.chunk_every(box_ids, 100), fn chunk ->
        url = "#{Constants.node_url()}/utxo/withPool/byIds"
        headers = [{"Content-Type", "application/json"}, {"Accept", "application/json"}]
        body = Jason.encode!(chunk)
        case HTTPoison.post(url, body, headers, @timeout_opts) do
          {:ok, %HTTPoison.Response{status_code: 200, body: rb}} ->
            case Jason.decode(rb) do
              {:ok, boxes} -> boxes
              _ -> []
            end
          _ -> []
        end
      end)
    end
  
    def check_transaction(tx) do
      url = "#{Constants.node_url()}/transactions/check"
      headers = [{"Content-Type", "application/json"}, {"Accept", "application/json"}]
      body = Jason.encode!(tx)
      case HTTPoison.post(url, body, headers, []) do
        {:ok, %HTTPoison.Response{status_code: 200, body: rb}} ->
          case Jason.decode(rb) do
            {:ok, parsed} -> {:ok, parsed}
            _ -> {:error, "Invalid JSON response"}
          end
        {:ok, %HTTPoison.Response{status_code: c, body: b}} ->
          {:error, "Transaction check failed with status #{c}: #{b}"}
        {:error, %HTTPoison.Error{reason: r}} ->
          {:error, "HTTP request error: #{inspect(r)}"}
      end
    end
  
    def submit_transaction(tx) do
      url = "#{Constants.node_url()}/transactions"
      headers = [{"Content-Type", "application/json"}, {"Accept", "application/json"}]
      body = Jason.encode!(tx)
      case HTTPoison.post(url, body, headers, []) do
        {:ok, %HTTPoison.Response{status_code: 200, body: rb}} ->
          case Jason.decode(rb) do
            {:ok, parsed} -> {:ok, parsed}
            _ -> {:error, "Invalid JSON response"}
          end
        {:ok, %HTTPoison.Response{status_code: c, body: b}} ->
          {:error, "Transaction submission failed with status #{c}: #{b}"}
        {:error, %HTTPoison.Error{reason: r}} ->
          {:error, "HTTP request error: #{inspect(r)}"}
      end
    end
  end
  