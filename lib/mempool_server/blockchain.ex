defmodule MempoolServer.Blockchain do
require Logger
alias MempoolServer.Constants

def get_unspent_by_address(address, offset, limit, sort_direction, include_unconfirmed, exclude_mempool_spent) do
    base_url = Constants.node_url()
    url =
    "#{base_url}/blockchain/box/unspent/byAddress" <>
        "?offset=#{offset}" <>
        "&limit=#{limit}" <>
        "&sortDirection=#{sort_direction}" <>
        "&includeUnconfirmed=#{include_unconfirmed}" <>
        "&excludeMempoolSpent=#{exclude_mempool_spent}"

    case HTTPoison.post(url, Jason.encode!(address), [{"Content-Type", "application/json"}]) do
    {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
        {:ok, data} when is_list(data) -> data
        {:error, _} -> []
        end

    {:ok, %HTTPoison.Response{status_code: status_code, body: body}} when status_code >= 400 ->
        Logger.error("[box/unspent/byAddress] HTTP Error #{status_code}: #{body}")
        []

    {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("[box/unspent/byAddress] Request failed: #{inspect(reason)}")
        []
    end
end

def get_unspent_by_address(address) do
    offset = 0
    limit = 1000
    sort_direction = "desc"
    include_unconfirmed = "true"
    exclude_mempool_spent = "true"

    get_unspent_by_address(address, offset, limit, sort_direction, include_unconfirmed, exclude_mempool_spent)
end
end
  