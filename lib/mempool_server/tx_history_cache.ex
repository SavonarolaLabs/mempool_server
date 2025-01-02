defmodule MempoolServer.TxHistoryCache do
  @moduledoc """
  Cache that stores the last 10 most recent transactions by address.
  """

  use GenServer
  require Logger

  alias MempoolServer.Constants

  @table_name :tx_history_cache
  @timeout_opts [hackney: [recv_timeout: 60_000, connect_timeout: 60_000]]

  # ----------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Update the TxHistory for the given address name.
  Currently only supports "sigmausd_transactions".
  """
  def update_history("sigmausd_transactions") do
    address = Constants.sigma_bank_address()

    case fetch_transactions_for_address(address) do
      {:ok, new_txs} ->
        store_transactions(address, new_txs)
        :ok

      :error ->
        Logger.error("[TxHistoryCache] Failed to update history for sigmausd_transactions.")
        :error
    end
  end

  def update_history(_other), do: :ok

  @doc """
  Retrieve the recently cached transactions for a given address name.
  Currently only supports "sigmausd_transactions".
  """
  def get_recent("sigmausd_transactions") do
    address = Constants.sigma_bank_address()
    get_transactions(address)
  end

  def get_recent(_other), do: []

  # ----------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------

  def init(state) do
    # Create an ETS table for storing the transactions if it doesn't already exist
    :ets.new(@table_name, [
      :named_table,
      :set,
      :public,
      {:read_concurrency, true}
    ])

    {:ok, state}
  end

  # ----------------------------------------------------------------
  # Internal helpers
  # ----------------------------------------------------------------

  defp store_transactions(address, new_txs) when is_binary(address) and is_list(new_txs) do
    # If there is already something stored, fetch it
    existing = get_transactions(address)

    # We'll place new transactions *before* existing, then keep only up to 10
    updated = (new_txs ++ existing) |> Enum.take(10)

    :ets.insert(@table_name, {address, updated})
    :ok
  end

  defp get_transactions(address) do
    case :ets.lookup(@table_name, address) do
      [{^address, txs}] -> txs
      [] -> []
    end
  end

  defp fetch_transactions_for_address(address) do
    url = "https://ergfi.xyz:9443/blockchain/transaction/byAddress?offset=0&limit=10"
    headers = [
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]
    # The endpoint requires a POST with the address in JSON form
    body = Jason.encode!(address)

    case HTTPoison.post(url, body, headers, @timeout_opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          # Note: "items" is the array of transactions
          {:ok, %{"items" => items}} when is_list(items) ->
            {:ok, items}

          {:ok, other} ->
            Logger.error("""
            [TxHistoryCache] Unexpected JSON structure: #{inspect(other)}
            """)
            :error

          error ->
            Logger.error("[TxHistoryCache] Could not decode body: #{inspect(error)}")
            :error
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        Logger.error("[TxHistoryCache] HTTP #{status_code} => #{response_body}")
        :error

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("[TxHistoryCache] Request failed => #{inspect(reason)}")
        :error
    end
  end
end
