# lib/mempool_server_web/controllers/transaction_controller.ex

defmodule MempoolServerWeb.TransactionController do
  use MempoolServerWeb, :controller
  require Logger

  @node_url "http://213.239.193.208:9053"
  @max_limit 16_384
  @default_limit 100

  # Sigma Bank Address
  @sigma_bank_address "MUbV38YgqHy7XbsoXWF5z7EZm524Ybdwe5p9WDrbhruZRtehkRPT92imXer2eTkjwPDfboa1pR3zb3deVKVq3H7Xt98qcTqLuSBSbHb7izzo5jphEpcnqyKJ2xhmpNPVvmtbdJNdvdopPrHHDBbAGGeW7XYTQwEeoRfosXzcDtiGgw97b2aqjTsNFmZk7khBEQywjYfmoDc9nUCJMZ3vbSspnYo3LarLe55mh2Np8MNJqUN9APA6XkhZCrTTDRZb1B4krgFY1sVMswg2ceqguZRvC9pqt3tUUxmSnB24N6dowfVJKhLXwHPbrkHViBv1AKAJTmEaQW2DN1fRmD9ypXxZk8GXmYtxTtrj3BiunQ4qzUCu1eGzxSREjpkFSi2ATLSSDqUwxtRz639sHM6Lav4axoJNPCHbY8pvuBKUxgnGRex8LEGM8DeEJwaJCaoy8dBw9Lz49nq5mSsXLeoC4xpTUmp47Bh7GAZtwkaNreCu74m9rcZ8Di4w1cmdsiK1NWuDh9pJ2Bv7u3EfcurHFVqCkT3P86JUbKnXeNxCypfrWsFuYNKYqmjsix82g9vWcGMmAcu5nagxD4iET86iE2tMMfZZ5vqZNvntQswJyQqv2Wc6MTh4jQx1q2qJZCQe4QdEK63meTGbZNNKMctHQbp3gRkZYNrBtxQyVtNLR8xEY8zGp85GeQKbb37vqLXxRpGiigAdMe3XZA4hhYPmAAU5hpSMYaRAjtvvMT3bNiHRACGrfjvSsEG9G2zY5in2YWz5X9zXQLGTYRsQ4uNFkYoQRCBdjNxGv6R58Xq74zCgt19TxYZ87gPWxkXpWwTaHogG1eps8WXt8QzwJ9rVx6Vu9a5GjtcGsQxHovWmYixgBU8X9fPNJ9UQhYyAWbjtRSuVBtDAmoV1gCBEPwnYVP5GCGhCocbwoYhZkZjFZy6ws4uxVLid3FxuvhWvQrVEDYp7WRvGXbNdCbcSXnbeTrPMey1WPaXX"

  def index(conn, params) do
    address = Map.get(params, "address", "")
    offset = parse_integer_param(params["offset"], 0)
    limit = parse_integer_param(params["limit"], @default_limit)

    limit = min(limit, @max_limit)

    if address == "" do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Address parameter is required"})
    else
      case fetch_transactions(address, offset, limit) do
        {:ok, data} ->
          json(conn, data)

        {:error, reason} ->
          Logger.error("Error fetching transactions: #{inspect(reason)}")
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Failed to fetch transactions"})
      end
    end
  end

  def sigmausd_transactions(conn, params) do
    offset = parse_integer_param(params["offset"], 0)
    limit = parse_integer_param(params["limit"], @default_limit)

    limit = min(limit, @max_limit)

    case fetch_transactions(@sigma_bank_address, offset, limit) do
      {:ok, data} ->
        json(conn, data)

      {:error, reason} ->
        Logger.error("Error fetching SigmaUSD transactions: #{inspect(reason)}")
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to fetch SigmaUSD transactions"})
    end
  end

  defp parse_integer_param(nil, default), do: default

  defp parse_integer_param(value, default) do
    case Integer.parse(value) do
      {int_value, _} -> int_value
      :error -> default
    end
  end

  defp fetch_transactions(address, offset, limit) do
    url = "#{@node_url}/blockchain/transaction/byAddress?offset=#{offset}&limit=#{limit}"

    headers = [{"Content-Type", "application/json"}]
    body = Jason.encode!(address)

    case HTTPoison.post(url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, data} -> {:ok, data}
          error -> error
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        {:error, %{status_code: status_code, body: response_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end
end
